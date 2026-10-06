# Agent Containers

Build and deploy containerized AI code agents with language-specific tooling.

This repository builds a container image for **OpenCode** — an AI coding agent that supports **Claude** via Vertex AI, **Gemini**, and **OpenAI** as selectable providers. The image includes Node.js, Go, and Python 3 and can be run locally with Podman.

## Available Images

- `opencode` - OpenCode with Node.js, Go, and Python 3

Each image includes:
- Git and essential development tools
- Node.js 24 (Red Hat UBI10 base)
- OpenCode CLI pre-installed (`opencode-ai`)
- Provider config for Claude, Gemini, and OpenAI
- Go and Python 3 runtimes
- Development utilities (fzf, ripgrep, jq, vim, nano, zsh, less)

## Prerequisites

- **Podman** or **Docker** (for building)
- **Make** (for running build/deploy targets)
- **Git**

Credentials are not required to build the image. API credentials are required only when running OpenCode with a provider:
  - **Claude via Vertex AI**: GCP project ID, region, and ADC credentials (`gcloud auth application-default login`)
  - **Gemini**: API key from [Google AI Studio](https://aistudio.google.com/apikey)
  - **OpenAI**: API key from [OpenAI](https://platform.openai.com/api-keys)

## Quick Start

### 1. Build an Image

```bash
make build-opencode
```

The build script will prompt for:
- **Registry**: Container registry (e.g., `docker.io`, `ghcr.io`, `zot.paxlab.cc`)
- **Image Tag**: Version tag (default: `latest`)

These defaults are saved to `.push-defaults` (gitignored) for future builds.

### 2. Create Secrets

Copy the secret template and fill in the credentials for at least one provider. OpenAI-only runs need only `OPENAI_API_KEY`:

```bash
cp k8s/secrets/opencode-secret.yaml.template k8s/secrets/opencode-secret.yaml
make create-opencode-secret
```

For an OpenAI-only setup, leave the Google/Vertex fields blank and set the OpenAI key:

```yaml
stringData:
  OPENAI_API_KEY: "sk-your-key"
```

For Vertex AI, get GCP credentials with:
```bash
gcloud auth application-default login
```

`CREDS_FILE` defaults to `~/.config/gcloud/application_default_credentials.json`. Use `make create-opencode-secret CREDS_FILE=<path>` to specify another ADC file.

### 3. Run

**Locally with Podman:**
```bash
make deploy-podman-opencode
```

The image is run locally with the Podman targets below.

## Connecting to OpenCode

### Podman — Interactive TUI

Starts OpenCode directly in your terminal:

```bash
make deploy-podman-opencode
```

### Podman — Server Mode

Starts OpenCode as a background server on `localhost:4096`:

```bash
make serve-podman-opencode
```

Then connect from your local machine:

```bash
opencode          # TUI connected to the server
# or open http://localhost:4096 in a browser
```

Stop the server with:
```bash
podman stop opencode
```

---

## Usage

### Build Targets

```bash
make build-opencode           # Build the OpenCode image
make build                    # Same target
```

### Push Targets

Push images to registry (reads defaults from `.push-defaults`):

```bash
make push-opencode            # Push the OpenCode image
make push                     # Same target
make publish-opencode         # Build and push without prompts
make publish                  # Same target
```

### Secret Management

```bash
cp k8s/secrets/opencode-secret.yaml.template k8s/secrets/opencode-secret.yaml
# Fill in the required values and any optional provider keys, then run:
make create-opencode-secret
```

Secrets are stored as gitignored YAML files in `k8s/secrets/`.

### Deployment

**Podman (local container runtime):**
```bash
make deploy-podman-opencode
make redeploy-podman-opencode
make resume-podman-opencode
make serve-podman-opencode
make attach-podman-opencode
```

### View Help

```bash
make help
```

## Selecting a Provider at Runtime

OpenCode is configured to show Claude, Gemini, and OpenAI models. Select a provider when running a prompt:

```bash
# Claude via Vertex AI (interactive TUI — select model in UI)
opencode

# Non-interactive with a specific model
opencode run --model google-vertex-anthropic/claude-sonnet-4-20250514 "explain this code"
opencode run --model google/gemini-2.5-pro "refactor this function"
opencode run --model openai/gpt-4o "write tests for this function"

# List available models
opencode models
```

### Session Management

**Interactive** (inside the container TUI):
- `Ctrl+A` — open session picker to browse and resume previous sessions
- `/sessions` slash command — same as above

**CLI**:
```bash
opencode session list                     # list all sessions (ID, title, timestamp)
opencode session list --format json       # JSON output for scripting
opencode -c                               # resume last session
opencode -s <session-id>                  # resume a specific session
opencode run -c "follow-up prompt"        # non-interactive continuation of last session
```

## Directory Structure

```
.
├── Makefile                           # Build, push, and Podman targets
├── .push-defaults                     # Session defaults (gitignored)
├── README.md                          # This file
├── plans/                             # Implementation plan documents
├── containerfiles/
│   ├── Containerfile.agents           # OpenCode image definition (shared base + runtimes)
│   └── opencode.json                  # Provider allowlist (Claude + Gemini + OpenAI)
├── k8s/
│   ├── opencode.yaml                  # OpenCode Pod template
│   └── secrets/
│       ├── opencode-secret.yaml.template   # Template (committed)
│       └── opencode-secret.yaml            # Generated (gitignored)
└── scripts/
    ├── build.sh                       # Build image with registry/tag prompts
    ├── push.sh                        # Push image to registry
    ├── podman-run.sh                  # Run container locally
    └── create-secrets.sh              # Generate secret YAML
```

## Configuration

### .push-defaults

Session defaults saved after each build (gitignored):

```
REGISTRY=zot.paxlab.cc
IMAGE_TAG=0.2
IMAGE_PULL_SECRET=zot-pull-secret
NAMESPACE=agent-coordinator
```

Edit or delete to reset defaults.

### Automated image releases

Pull requests to `main` run the Python and shell test suites. The image-build
smoke check runs only for same-repository PR branches (the trusted-PR boundary)
and builds locally without pushing. Standalone container and KinD E2E remain in
the release workflow and run only after changes reach `main`. Semgrep Python
SAST and dependency review run in a separate security workflow; `pip-audit`
checks installed image dependencies on trusted builds and release candidates.

Every push to `main` runs the serialized image release workflow. For each
unprocessed PR squash merge, in first-parent order, it builds a new patch
SemVer candidate from that merge commit and pushes it to Quay. The workflow
records the immutable image digest, runs standalone Podman and KinD Pod E2E
checks and a `pip-audit` SCA scan against that digest, signs each candidate,
and only then moves `latest` and commits `VERSION`, `IMAGE_DIGEST`, and
`IMAGE_PUBLISH_STATE` to `main`.

Configure these repository Actions settings:

- Variable `QUAY_REPOSITORY_PATH`: Quay namespace, such as `quay.io/jpacker`
  (do not include `/opencode` or a tag).
- Variable `QUAY_ROBOT_USERNAME`: the Quay robot account username.
- Secret `QUAY_PUSH_TOKEN`: a robot token with push access to the OpenCode
  image repository. Candidate SemVer tags must be replaceable so failed
  candidates can be retried from the unchanged release cursor.
- The Quay repository must allow anonymous pulls so Podman and KinD can test
  each candidate by digest. The workflow's GitHub token requires
  `contents: write`, `pull-requests: read`, and `id-token: write` for keyless
  candidate signing. Permit the Actions bot to push release metadata commits to
  protected `main` if branch protection is enabled.

Candidate builds fetch the pinned Agent Swarm commit in
`AGENT_SWARM_MCP_REVISION` and stage only its tracked `mcp-server` package; they
do not build or run the full `agent-swarm` application. CI registry and tag
values override local defaults without modifying `.push-defaults`.

If a build or either E2E gate fails, `latest` and committed release metadata
remain unchanged. The candidate tag is retained for diagnosis. A later push to
`main` catches up from `IMAGE_PUBLISH_STATE`, so failed and coalesced merges are
retried in order. Logs include candidate groups, and KinD failures report Pods,
events, descriptions, and workload logs before cluster cleanup.

Run the helper tests locally with `pytest -q tests/test_image_release.py` and
lint with `make lint` (Ruff at the pinned `RUFF_VERSION` is required).
The E2E scripts can be invoked against an already-pushed candidate digest:

```bash
python3 scripts/e2e_container.py --image-ref quay.io/<namespace>/opencode@sha256:<digest>
python3 scripts/e2e_kind_pod.py --image-ref quay.io/<namespace>/opencode@sha256:<digest>
```

For local build/push use, explicit values take precedence over saved defaults:

```bash
make build-opencode REGISTRY=quay.io/<namespace> IMAGE_TAG=0.5.3 NOPROMPT=1
make push-opencode REGISTRY=quay.io/<namespace> IMAGE_TAG=0.5.3
```

### Provider Config (opencode.json)

Baked into the image at `/sandbox/opencode.json`. Restricts available providers to:

```json
{
  "enabled_providers": ["google-vertex-anthropic", "google", "openai"]
}
```

- `google-vertex-anthropic` — Claude via Google Vertex AI (GCP credentials)
- `google` — Gemini via Google API key
- `openai` — OpenAI via `OPENAI_API_KEY`

### Container Environment

The image sets:
- `GOOGLE_APPLICATION_CREDENTIALS=/app/gcloud/credentials.json` (path for Vertex AI creds)
- `DEVCONTAINER=true`
- `EDITOR=nano`

At runtime, provider-specific env vars are injected from the secret:
- `GOOGLE_CLOUD_PROJECT` — GCP project ID (Vertex AI, optional)
- `VERTEX_LOCATION` — GCP region (Vertex AI, optional)
- `GOOGLE_API_KEY` — Gemini API key (optional)
- `OPENAI_API_KEY` — OpenAI API key (optional)

At least one provider must be configured. OpenAI-only runs do not require Google credentials or an ADC file.

## Workflow Example

### Building and Publishing

```bash
# 1. Build the image
make build-opencode

# 2. Create secret (one-time setup)
make create-opencode-secret

# 3. Push to the registry
make push-opencode
```

### Running Locally

```bash
# 1. Create the secret from the template
cp k8s/secrets/opencode-secret.yaml.template k8s/secrets/opencode-secret.yaml
# Fill in the provider credentials, including OPENAI_API_KEY when needed.
make create-opencode-secret

# 2. Build image
make build-opencode

# 3. Run container
make deploy-podman-opencode
```

## Security Notes

- **Secrets are gitignored**: Never commit `k8s/secrets/*.yaml` (non-template files)
- **Credentials at runtime**: Mounted via K8s secrets or Podman secret store
- **Non-root user**: Images run as `node` user (non-root for security)
- **Template files**: `.yaml.template` files are committed; generated `.yaml` files are not

## Troubleshooting

**Build fails with permission denied:**
```bash
podman version
```

**Container exits immediately:**
- Check logs: `podman logs opencode`
- Verify secrets are mounted correctly

**Secrets not found:**
- Verify secret YAML was created: `ls -la k8s/secrets/*.yaml`
- Regenerate if needed: `make create-opencode-secret`

**No models listed / auth errors:**
- Verify the selected provider's API key is set in `k8s/secrets/opencode-secret.yaml`
- For Vertex AI, verify `GOOGLE_CLOUD_PROJECT`, `VERTEX_LOCATION`, and the ADC file
- Run `opencode models` inside the container to diagnose provider connectivity

## Development

To modify the image definition, edit:

- `containerfiles/Containerfile.agents` — image build definition
- `containerfiles/opencode.json` — provider allowlist

The build passes pinned toolchain versions as build arguments and targets the `opencode` stage.

## License

See LICENSE file for details.
