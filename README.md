# Agent Containers

Build and deploy containerized AI code agents with language-specific tooling.

This repository builds container images for **OpenCode** — an AI coding agent that supports both **Claude** (via Vertex AI or direct API) and **Gemini** as selectable providers. Images are available with **Go** or **Python 3** support and can be deployed locally with Podman or to Kubernetes.

## Available Images

- `opencode-golang` - OpenCode with Go 1.x
- `opencode-python` - OpenCode with Python 3

Each image includes:
- Git and essential development tools
- Node.js 20 (slim base)
- OpenCode CLI pre-installed (`opencode-ai`)
- Provider config restricting to Claude and Gemini models only
- Language runtime (Go or Python)
- Development utilities (fzf, ripgrep, jq, vim, nano, zsh, less)

## Prerequisites

- **Podman** or **Docker** (for building)
- **Make** (for running build/deploy targets)
- **Git**
- **kubectl** (for Kubernetes deployments only)
- API credentials:
  - **Claude via Vertex AI**: GCP project ID, region, and ADC credentials (`gcloud auth application-default login`)
  - **Gemini**: API key from [Google AI Studio](https://aistudio.google.com/apikey)

## Quick Start

### 1. Build an Image

```bash
make build-opencode-golang
```

The build script will prompt for:
- **Registry**: Container registry (e.g., `docker.io`, `ghcr.io`, `zot.paxlab.cc`)
- **Image Tag**: Version tag (default: `latest`)

These defaults are saved to `.push-defaults` (gitignored) for future builds.

### 2. Create Secrets

```bash
make create-opencode-secret \
  PROJECT_ID=your-gcp-project-id \
  REGION=us-east5 \
  GOOGLE_API_KEY=your-gemini-api-key
```

Get GCP credentials with:
```bash
gcloud auth application-default login
```

`CREDS_FILE` defaults to `~/.config/gcloud/application_default_credentials.json`.

### 3. Deploy

**Locally with Podman:**
```bash
make deploy-podman-opencode-golang
```

**To Kubernetes:**
```bash
make deploy-k8s-opencode-golang
```

The deploy script will prompt for:
- **Image Pull Secret** (name of existing K8s secret)
- **Namespace** (K8s namespace to deploy to)

## Connecting to OpenCode

### Podman — Interactive TUI

Starts OpenCode directly in your terminal:

```bash
make deploy-podman-opencode-golang
```

### Podman — Server Mode

Starts OpenCode as a background server on `localhost:4096`:

```bash
make serve-podman-opencode-golang
```

Then connect from your local machine:

```bash
opencode          # TUI connected to the server
# or open http://localhost:4096 in a browser
```

Stop the server with:
```bash
podman stop opencode-golang
```

### Kubernetes — Port-Forward

After deploying to K8s, forward the pod's port to your local machine:

```bash
make connect-opencode-golang
```

Then connect at `localhost:4096` the same way as above. Press `Ctrl+C` to stop forwarding.

---

## Usage

### Build Targets

```bash
make build-opencode-golang    # OpenCode + Go
make build-opencode-python    # OpenCode + Python
make build-all                # Both images
```

### Push Targets

Push images to registry (reads defaults from `.push-defaults`):

```bash
make push-opencode-golang     # Push golang image
make push-opencode-python     # Push python image
make podman-push              # Push both images (also tags :latest)
```

### Secret Management

```bash
make create-opencode-secret \
  PROJECT_ID=my-project \
  REGION=us-east5 \
  GOOGLE_API_KEY=xyz
```

Secrets are stored as gitignored YAML files in `k8s/secrets/`.

### Deployment

**Podman (local container runtime):**
```bash
make deploy-podman-opencode-golang
make deploy-podman-opencode-python
```

**Kubernetes:**
```bash
make deploy-k8s-opencode-golang
make deploy-k8s-opencode-python
```

### View Help

```bash
make help
```

## Selecting a Provider at Runtime

OpenCode is configured to show only Claude and Gemini models. Select a provider when running a prompt:

```bash
# Claude via Vertex AI (interactive TUI — select model in UI)
opencode

# Non-interactive with a specific model
opencode run --model google-vertex-anthropic/claude-sonnet-4-20250514 "explain this code"
opencode run --model google/gemini-2.5-pro "refactor this function"

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
├── Makefile                           # Build, push, deploy targets
├── .push-defaults                     # Session defaults (gitignored)
├── README.md                          # This file
├── plans/                             # Implementation plan documents
├── containerfiles/
│   ├── Containerfile.opencode         # OpenCode image definition (shared base + lang layers)
│   └── opencode.json                  # Provider allowlist (Claude + Gemini only)
├── k8s/
│   ├── opencode-golang.yaml           # OpenCode + Go Pod template
│   ├── opencode-python.yaml           # OpenCode + Python Pod template
│   └── secrets/
│       ├── opencode-secret.yaml.template   # Template (committed)
│       └── opencode-secret.yaml            # Generated (gitignored)
└── scripts/
    ├── build.sh                       # Build image with registry/tag prompts
    ├── push.sh                        # Push image to registry
    ├── deploy.sh                      # Deploy to Kubernetes
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

### Provider Config (opencode.json)

Baked into the image at `/workspace/opencode.json`. Restricts available providers to:

```json
{
  "enabled_providers": ["google-vertex-anthropic", "google"]
}
```

- `google-vertex-anthropic` — Claude via Google Vertex AI (GCP credentials)
- `google` — Gemini via Google API key

### Container Environment

The image sets:
- `GOOGLE_APPLICATION_CREDENTIALS=/app/gcloud/credentials.json` (path for Vertex AI creds)
- `DEVCONTAINER=true`
- `EDITOR=nano`

At runtime, the following env vars are injected from the secret:
- `GOOGLE_CLOUD_PROJECT` — GCP project ID (Vertex AI)
- `VERTEX_LOCATION` — GCP region (Vertex AI)
- `GOOGLE_API_KEY` — Gemini API key

### Resource Limits

Default Kubernetes resource requests/limits:

```yaml
requests:
  memory: "512Mi"
  cpu: "500m"
limits:
  memory: "2Gi"
  cpu: "2000m"
```

Edit K8s YAML files to customize.

## Workflow Example

### Building and Deploying to K8s

```bash
# 1. Build all images
make build-all

# 2. Create secret (one-time setup)
make create-opencode-secret \
  PROJECT_ID=my-project \
  REGION=us-east5 \
  GOOGLE_API_KEY=your-gemini-api-key

# 3. Push all to registry
make podman-push

# 4. Deploy to K8s
make deploy-k8s-opencode-golang
```

### Running Locally

```bash
# 1. Create secret
make create-opencode-secret PROJECT_ID=my-project REGION=us-east5

# 2. Build image
make build-opencode-golang

# 3. Run container
make deploy-podman-opencode-golang
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

**K8s deployment fails to pull image:**
- Verify image push succeeded: `podman images`
- Check image pull secret exists: `kubectl get secrets -n <namespace>`
- Verify registry URL in `.push-defaults`

**Container exits immediately:**
- Check logs: `kubectl logs <pod-name> -n <namespace>`
- For Podman: `podman logs <container-id>`
- Verify secrets are mounted correctly

**Secrets not found:**
- Verify secret YAML was created: `ls -la k8s/secrets/*.yaml`
- Regenerate if needed: `make create-opencode-secret PROJECT_ID=... REGION=...`
- Ensure namespace matches in K8s deployment

**No models listed / auth errors:**
- Verify `GOOGLE_CLOUD_PROJECT` and `VERTEX_LOCATION` are set correctly
- Check `GOOGLE_APPLICATION_CREDENTIALS` points to a valid credentials file
- Run `opencode models` inside the container to diagnose provider connectivity

## Development

To modify the image definition, edit:

- `containerfiles/Containerfile.opencode` — image build definition
- `containerfiles/opencode.json` — provider allowlist

Build arguments:
- `LANG` — Language variant: `golang` or `python`
- `--target final` — Build final stage only

## License

See LICENSE file for details.
