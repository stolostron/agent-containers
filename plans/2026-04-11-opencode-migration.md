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
