# Agent Containers

Build and deploy containerized AI code agents with language-specific tooling.

This repository builds container images for [OpenCode](https://opencode.ai) — an AI coding agent that supports **Claude** (via Vertex AI) and **Gemini** as selectable providers. Images are available with **Go** or **Python 3** toolchains and can be deployed locally with Podman or to Kubernetes.

## Available Images

- `opencode-golang` — OpenCode with Go
- `opencode-python` — OpenCode with Python 3

Each image includes:
- Node.js 20 (slim base) with OpenCode CLI (`opencode-ai`) pre-installed
- Language runtime (Go or Python 3 + pip/venv)
- Git and development tools (fzf, ripgrep, jq, vim, nano, zsh, less)
- Provider config restricting to Claude and Gemini models only

## Prerequisites

- **Docker** or **Podman** (for building images)
- **Make**
- **kubectl** + **kind** (for Kubernetes deployments)
- API credentials (at least one):
  - **Gemini**: API key from [Google AI Studio](https://aistudio.google.com/apikey)
  - **Claude via Vertex AI**: GCP project, region, and ADC credentials

## Kubernetes Deployment Modes

Each mode uses the right K8s resource for the job:

| Mode | K8s Resource | Command | Use Case |
|------|-------------|---------|----------|
| **Job** | `batch/v1 Job` | `opencode run -m MODEL PROMPT` | One-shot prompt execution |
| **CronJob** | `batch/v1 CronJob` | `opencode run -m MODEL PROMPT` | Scheduled/periodic prompts |
| **Serve** | `apps/v1 Deployment` + `Service` | `opencode serve` | Persistent server on port 4096 |
| **TUI** | `v1 Pod` | `sleep infinity` + `kubectl exec` | Interactive terminal session |

## Quick Start (Kind Cluster)

### 1. Build the image

```bash
# With Docker
docker build -f containerfiles/Containerfile.opencode \
  --build-arg LANG=golang --target final \
  -t opencode-golang:latest .

# Or with Podman
make build-opencode-golang
```

### 2. Create a Kind cluster and load the image

```bash
kind create cluster --name opencode
kind load docker-image opencode-golang:latest --name opencode
```

### 3. Create secrets

Copy the template and fill in your credentials:

```bash
cp k8s/secrets/opencode-secret.yaml.template k8s/secrets/opencode-secret.yaml
```

Edit `k8s/secrets/opencode-secret.yaml` with your values:

```yaml
stringData:
  GOOGLE_CLOUD_PROJECT: "your-gcp-project-id"
  VERTEX_LOCATION: "us-east5"
  GOOGLE_API_KEY: "your-gemini-api-key"
  GITHUB_PAT: ""  # optional
```

Then generate the K8s secret:

```bash
make create-opencode-secret
```

Or create the secret directly with kubectl:

```bash
kubectl create secret generic opencode-secret \
  --from-literal=GOOGLE_CLOUD_PROJECT=your-project \
  --from-literal=VERTEX_LOCATION=us-east5 \
  --from-literal=GOOGLE_API_KEY=your-gemini-key \
  --from-literal=application_default_credentials.json='{}' \
  --context kind-opencode
```

### 4. Deploy

Pick a mode and render the manifest with `sed`, then apply:

**Job (one-shot prompt):**
```bash
sed -e 's|REGISTRY|opencode-golang|g' \
    -e 's|/opencode-golang||g' \
    -e 's|IMAGE_TAG|latest|g' \
    -e 's|OPENCODE_MODEL_VALUE|google/gemini-2.5-pro|g' \
    -e 's|OPENCODE_PROMPT_VALUE|explain what kubernetes is in one sentence|g' \
    -e '/IMAGE_PULL_SECRET_BLOCK/d' \
    k8s/job-opencode-golang.yaml | kubectl apply -f -
```

**Serve (persistent server):**
```bash
sed -e 's|REGISTRY|opencode-golang|g' \
    -e 's|/opencode-golang||g' \
    -e 's|IMAGE_TAG|latest|g' \
    -e '/IMAGE_PULL_SECRET_BLOCK/d' \
    k8s/serve-opencode-golang.yaml | kubectl apply -f -
```

**TUI (interactive pod):**
```bash
sed -e 's|REGISTRY|opencode-golang|g' \
    -e 's|/opencode-golang||g' \
    -e 's|IMAGE_TAG|latest|g' \
    -e '/IMAGE_PULL_SECRET_BLOCK/d' \
    k8s/tui-opencode-golang.yaml | kubectl apply -f -
```

### 5. Check status and connect

```bash
# See all resources
kubectl get jobs,deployments,services,pods

# Job — check logs
kubectl logs -l app=opencode-golang

# Serve — port-forward and attach
kubectl port-forward svc/opencode-golang 4096:4096
# then: opencode attach http://localhost:4096
# or open http://localhost:4096 in a browser

# TUI — exec into the pod
kubectl exec -it opencode-golang-tui -- opencode
```

## Getting API Credentials

### Gemini API Key (simplest)

1. Go to [Google AI Studio](https://aistudio.google.com/apikey)
2. Click **Create API Key**
3. Copy the key — use it as `GOOGLE_API_KEY`

### Claude via Vertex AI

1. Create or select a GCP project at [console.cloud.google.com](https://console.cloud.google.com)
2. Enable the **Vertex AI API** in your project
3. Request access to Claude models through the [Model Garden](https://console.cloud.google.com/vertex-ai/model-garden)
4. Authenticate locally:
   ```bash
   gcloud auth application-default login
   ```
5. Note your project ID and region (e.g. `us-east5`) — use as `GOOGLE_CLOUD_PROJECT` and `VERTEX_LOCATION`
6. The ADC credentials file at `~/.config/gcloud/application_default_credentials.json` is used by `create-secrets.sh`

### GitHub PAT (optional)

For private repo access inside agent containers:

1. Go to [github.com/settings/tokens](https://github.com/settings/tokens)
2. Create a fine-grained token with **Contents: Read** on the repos you need
3. Use it as `GITHUB_PAT` in the secret

## Makefile Targets

### Build

```bash
make build-opencode-golang       # Build OpenCode + Go image (prompts for registry/tag)
make build-opencode-python       # Build OpenCode + Python image
make build-all                   # Build both
make build-fast-opencode-golang  # Build without prompts (uses saved .push-defaults)
```

### Push

```bash
make push-opencode-golang        # Push golang image to registry
make push-opencode-python        # Push python image to registry
make podman-push                 # Push both (also tags :latest)
```

### Kubernetes Deploy

```bash
# Job (one-shot prompt)
make deploy-k8s-job-opencode-golang
make deploy-k8s-job-opencode-python

# CronJob (scheduled prompt)
make deploy-k8s-cronjob-opencode-golang
make deploy-k8s-cronjob-opencode-python

# Serve (Deployment + Service)
make deploy-k8s-serve-opencode-golang
make deploy-k8s-serve-opencode-python

# TUI (interactive Pod)
make deploy-k8s-tui-opencode-golang
make deploy-k8s-tui-opencode-python

# Port-forward to a running pod
make connect-opencode-golang
```

Job and CronJob targets accept optional environment variables:

```bash
OPENCODE_MODEL="google/gemini-2.5-flash" \
OPENCODE_PROMPT="refactor this function" \
  make deploy-k8s-job-opencode-golang

CRONJOB_SCHEDULE="0 */6 * * *" \
OPENCODE_PROMPT="run daily checks" \
  make deploy-k8s-cronjob-opencode-golang
```

### Podman (local)

```bash
make deploy-podman-opencode-golang   # Interactive TUI
make serve-podman-opencode-golang    # Background server on localhost:4096
make attach-podman-opencode-golang   # Attach TUI to running server
make resume-podman-opencode-golang   # Resume last session
```

### Secrets

```bash
make create-opencode-secret          # Generate K8s + Podman secrets
make create-opencode-secret CREDS_FILE=/path/to/adc.json
```

### Help

```bash
make help                            # Show all targets
```

## Directory Structure

```text
.
├── Makefile                              # Build, push, deploy targets
├── README.md
├── CLAUDE.md                             # AI assistant guidelines
├── .push-defaults                        # Saved registry/tag/namespace (gitignored)
├── containerfiles/
│   ├── Containerfile.opencode            # Multi-stage image definition
│   ├── entrypoint.sh                     # Runtime credential setup
│   └── opencode.json                     # Provider allowlist
├── k8s/
│   ├── job-opencode-golang.yaml          # Job — one-shot prompt
│   ├── job-opencode-python.yaml
│   ├── cronjob-opencode-golang.yaml      # CronJob — scheduled prompt
│   ├── cronjob-opencode-python.yaml
│   ├── serve-opencode-golang.yaml        # Deployment + Service — persistent server
│   ├── serve-opencode-python.yaml
│   ├── tui-opencode-golang.yaml          # Pod — interactive TUI
│   ├── tui-opencode-python.yaml
│   └── secrets/
│       ├── opencode-secret.yaml.template # Template (committed)
│       └── opencode-secret.yaml          # Your values (gitignored)
├── scripts/
│   ├── build.sh                          # Build with registry/tag prompts
│   ├── push.sh                           # Push to registry
│   ├── deploy.sh                         # Render + deploy to K8s
│   ├── connect.sh                        # Port-forward to pod
│   ├── podman-run.sh                     # Run locally with Podman
│   └── create-secrets.sh                 # Generate secret files
└── plans/                                # Design documents
```

## Configuration

### .push-defaults

Saved after each build (gitignored):

```dotenv
REGISTRY=docker.io/myuser
IMAGE_TAG=0.3
NAMESPACE=opencode
```

### Provider Config

Baked into the image at `/workspace/opencode.json`:

```json
{
  "enabled_providers": ["google-vertex-anthropic", "google"]
}
```

- `google-vertex-anthropic` — Claude via Vertex AI (requires GCP ADC + project)
- `google` — Gemini via API key

### Resource Limits

All manifests use:

```yaml
requests:
  memory: "512Mi"
  cpu: "500m"
limits:
  memory: "2Gi"
  cpu: "2000m"
```

Edit the YAML files under `k8s/` to customize.

## Selecting a Provider at Runtime

```bash
# Inside the container — interactive model picker
opencode

# Non-interactive
opencode run --model google/gemini-2.5-pro "explain this code"
opencode run --model google-vertex-anthropic/claude-sonnet-4-20250514 "review this PR"

# List available models
opencode models
```

## Security Notes

- Secrets are gitignored — never commit `k8s/secrets/*.yaml` (only the `.template` is tracked)
- Credentials are mounted at runtime via K8s Secrets or Podman secret store
- Images run as non-root `node` user
- The entrypoint writes `GITHUB_PAT` to `~/.git-credentials` and `GOOGLE_API_KEY` to OpenCode's `auth.json` at startup only

## Troubleshooting

**Job completes but no output:**
```bash
kubectl logs -l app=opencode-golang
```

**Pod stuck in Pending:**
```bash
kubectl describe pod -l app=opencode-golang
```

**Auth errors (API key not valid):**
- Verify your `GOOGLE_API_KEY` in the secret
- Check that the Gemini API is enabled in your GCP project
- Run `opencode models` inside the container to test connectivity

**Image not found in Kind:**
```bash
kind load docker-image opencode-golang:latest --name opencode
```

**Secret not found:**
```bash
kubectl get secrets
# Recreate if missing:
kubectl create secret generic opencode-secret --from-literal=...
```

## License

See LICENSE file for details.
