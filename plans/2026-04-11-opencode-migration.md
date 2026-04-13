# 2026-04-11 — Migrate from Claude/Gemini Containers to OpenCode

## Problem

The original setup maintained two separate container images and two separate secrets configurations — one for Claude Code (using Vertex AI) and one for Gemini CLI (using a Gemini API key). This meant:

- 4 images to build and maintain (`claude-code-golang`, `claude-code-python`, `gemini-cli-golang`, `gemini-cli-python`)
- 2 separate secret configurations (`claude-vertex-secret`, `gemini-secret`)
- Duplicate Makefile targets and scripts per agent type
- No way to switch AI providers without switching containers

## Solution

Replace both agent-specific containers with a single **OpenCode** container that supports multiple providers. OpenCode (`opencode-ai` on npm) is a terminal AI coding agent supporting 75+ LLM providers including Anthropic Claude and Google Gemini.

Key capabilities used:
- **Provider allowlist** via `opencode.json` — restricts UI to only Claude and Gemini models
- **Claude via Vertex AI** — `google-vertex-anthropic` provider using existing GCP credentials
- **Gemini** — `google` provider using `GOOGLE_API_KEY`
- **Non-interactive mode** — `opencode run --model <provider/model> "prompt"`
- **Session management** — `opencode session list`, `opencode -c`, `opencode -s <id>`

## Changes Made

### New Files
| File | Purpose |
|------|---------|
| `containerfiles/Containerfile.opencode` | Multi-stage build: shared base (Node + tools + opencode) + golang/python layers |
| `containerfiles/opencode.json` | Provider allowlist baked into image |
| `k8s/opencode-golang.yaml` | Pod manifest (Vertex creds + optional API keys) |
| `k8s/opencode-python.yaml` | Pod manifest (Vertex creds + optional API keys) |
| `k8s/secrets/opencode-secret.yaml.template` | Secret template (one secret for all providers) |
| `plans/2026-04-11-opencode-migration.md` | This document |

### Deleted Files
| File | Reason |
|------|--------|
| `containerfiles/Containerfile.claude` | Replaced by Containerfile.opencode |
| `containerfiles/Containerfile.gemini` | Replaced by Containerfile.opencode |
| `k8s/claude-golang.yaml` | Replaced by opencode-golang.yaml |
| `k8s/claude-python.yaml` | Replaced by opencode-python.yaml |
| `k8s/gemini-golang.yaml` | Replaced by opencode-golang.yaml |
| `k8s/gemini-python.yaml` | Replaced by opencode-python.yaml |
| `k8s/secrets/claude-vertex-secret.yaml.template` | Replaced by opencode-secret.yaml.template |
| `k8s/secrets/gemini-secret.yaml.template` | Replaced by opencode-secret.yaml.template |

### Modified Files
| File | Change |
|------|--------|
| `Makefile` | Replaced claude/gemini targets with opencode targets |
| `scripts/create-secrets.sh` | Single `opencode` mode replacing `gemini` and `claude` modes |
| `scripts/podman-run.sh` | Single `opencode-*` case replacing two agent cases |
| `README.md` | Full rewrite for OpenCode |

## Architecture: Multi-Stage Containerfile

```
node:20-slim
    └── base-common  (git, tools, opencode-ai npm package, opencode.json)
            ├── lang-golang  (+ golang-go)  →  final (CMD opencode)
            └── lang-python  (+ python3)    →  final (CMD opencode)
```

The `base-common` layer is shared and cached — rebuilding after a Go version bump only rebuilds `lang-golang`, not the OpenCode install layer.

## Secret Structure

Single `opencode-secret` replaces the two previous secrets:

| Key | Required | Purpose |
|-----|----------|---------|
| `GOOGLE_CLOUD_PROJECT` | Yes | GCP project for Vertex AI |
| `VERTEX_LOCATION` | Yes | GCP region (e.g. `us-east5`) |
| `application_default_credentials.json` | Yes | ADC JSON from `gcloud auth application-default login` |
| `GOOGLE_API_KEY` | Yes | Gemini via Google AI Studio |

## Provider Selection at Runtime

```bash
# Interactive TUI (default CMD)
opencode

# Non-interactive
opencode run --model google-vertex-anthropic/claude-sonnet-4-20250514 "prompt"
opencode run --model google/gemini-2.5-pro "prompt"
opencode run -c "follow-up on last session"

# Session management
opencode session list
opencode session list --format json
opencode -s <session-id>
```

## Tradeoffs / Known Limitations

- `opencode run -s <session-id>` (non-interactive resume of a specific session) has a known upstream bug and may not work reliably — use `opencode run -c` for last-session continuation instead.
- Provider filtering is at the provider level only; individual model filtering is not yet supported by OpenCode.
- The `opencode.json` is placed in `/workspace` (the WORKDIR), so it applies as a project-level config automatically on startup.

---

## Implementation Summary

**Completed: 2026-04-13**

The full migration from Claude Code + Gemini CLI containers to a unified OpenCode container was implemented and staged. Here is a summary of what was built:

### Containerfile (`containerfiles/Containerfile.opencode`)
- Renamed from `Containerfile.claude`, updated to install `opencode-ai` (npm) instead of `@anthropic-ai/claude-code`
- Bakes in `opencode.json` (provider allowlist) and `entrypoint.sh` at build time
- Drops `CLAUDE_CODE_USE_VERTEX=1`; retains `GOOGLE_APPLICATION_CREDENTIALS` path
- `ENTRYPOINT` changed to `entrypoint.sh`; `CMD` is `["opencode"]`

### Entrypoint (`containerfiles/entrypoint.sh`)
- Writes `~/.local/share/opencode/auth.json` at startup from `GOOGLE_API_KEY` (OpenCode reads API keys from auth.json, not env vars)
- Optionally configures git credential store from `GITHUB_PAT`
- Hands off to `exec "$@"` so both `tui` and `serve` modes work

### Provider config (`containerfiles/opencode.json`)
- `{"enabled_providers": ["google-vertex-anthropic", "google"]}` baked into image

### K8s manifests (`k8s/opencode-golang.yaml`, `k8s/opencode-python.yaml`)
- Single `opencode-secret` provides all credentials: `GOOGLE_CLOUD_PROJECT`, `VERTEX_LOCATION`, `GOOGLE_API_KEY`, optional `GITHUB_PAT`, and ADC JSON file
- Mounts ADC JSON as a volume at `/app/gcloud/credentials.json`

### Secret template (`k8s/secrets/opencode-secret.yaml.template`)
- Uses `stringData:` (plaintext) for ease of editing; script converts to base64 for the `.k8s` output file
- `.gitignore` updated to also ignore `*.yaml.k8s`

### `scripts/create-secrets.sh`
- Rewritten to read from `opencode-secret.yaml` (copied from template) rather than accepting CLI args
- Generates `opencode-secret.yaml.k8s` (base64-encoded, for `kubectl apply`)
- Creates `opencode-secret` Podman secret as JSON for key-by-name extraction

### `scripts/podman-run.sh`
- Unified `opencode-golang|opencode-python` case replacing four agent-specific cases
- Added `tui` mode (interactive, default) and `serve` mode (background server on port 4096)
- Mounts a named volume `<type>-opencode-local` at `/home/node/.local` to persist OpenCode sessions across runs
- `optional_secret_val` helper for `GITHUB_PAT` (absent key returns empty string instead of error)
- Fixed Podman secret reading to use raw filesystem paths (compatible with Podman < 4.7 which lacks `--showsecret`)

### `scripts/connect.sh` (new)
- `kubectl port-forward pod/<name> 4096:4096` using namespace from `.push-defaults`

### `Makefile`
- Replaced all `build-gemini-*`, `build-claude-*`, `push-gemini-*`, `push-claude-*`, `deploy-podman-*`, `deploy-k8s-*` targets with `opencode-*` equivalents
- Added `build-fast-opencode-*` targets (non-interactive, reads `.push-defaults` directly)
- Added `redeploy-podman-opencode-*` targets (build + push + restart in one step)
- Added `resume-podman-opencode-*` and `serve-podman-opencode-*` targets
- Added `attach-podman-opencode-*` and `connect-opencode-*` targets

### `README.md`
- Full rewrite documenting OpenCode, provider selection, session management, server/attach workflow, and updated directory structure
