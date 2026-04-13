# Agent Containers

Build and deploy containerized AI code agents with language-specific tooling.

This repository builds container images for **Claude Code** and **Gemini CLI**, each available with **Go** or **Python 3** support. Deploy locally with Podman or to Kubernetes.

## Available Images

- `gemini-cli-golang` - Gemini CLI with Go 1.x
- `gemini-cli-python` - Gemini CLI with Python 3
- `claude-code-golang` - Claude Code with Go 1.x  
- `claude-code-python` - Claude Code with Python 3

Each image includes:
- Git and essential development tools
- Node.js 20 (slim base)
- AI agent CLI pre-installed
- Language runtime (Go or Python)
- Development utilities (fzf, ripgrep, jq, vim, nano, zsh, less)

## Prerequisites

- **Podman** or **Docker** (for building)
- **Make** (for running build/deploy targets)
- **Git**
- **kubectl** (for Kubernetes deployments only)
- API credentials:
  - **Gemini**: API key from [Google AI Studio](https://aistudio.google.com/apikey)
  - **Claude**: GCP Vertex AI credentials (Project ID, region, service account)

## Quick Start

### 1. Build an Image

```bash
make build-claude-golang
```

The build script will prompt for:
- **Registry**: Container registry (e.g., `docker.io`, `ghcr.io`, `zot.paxlab.cc`)
- **Image Tag**: Version tag (default: `latest`)

These defaults are saved to `.push-defaults` (gitignored) for future builds.

### 2. Create Secrets

For **Gemini**:
```bash
make create-gemini-secret GEMINI_API_KEY=your-api-key-here
```

For **Claude** (Vertex AI):
```bash
make create-claude-vertex-secret \
  PROJECT_ID=your-gcp-project-id \
  REGION=us-east5 \
  CREDS_FILE=~/.config/gcloud/application_default_credentials.json
```

Get GCP credentials with:
```bash
gcloud auth application-default login
```

### 3. Deploy

**Locally with Podman:**
```bash
make deploy-podman-claude-golang
```

**To Kubernetes:**
```bash
make deploy-k8s-claude-golang
```

The deploy script will prompt for:
- **Image Pull Secret** (name of existing K8s secret)
- **Namespace** (K8s namespace to deploy to)

## Usage

### Build Targets

Build individual images or all at once:

```bash
make build-gemini-golang      # Gemini + Go
make build-gemini-python      # Gemini + Python
make build-claude-golang      # Claude + Go
make build-claude-python      # Claude + Python
make build-all                # All four images
```

### Push Targets

Push images to registry (reads defaults from `.push-defaults`):

```bash
make push-claude-golang       # Build and push
make podman-push              # Build and push all four images
```

### Secret Management

```bash
# Create Gemini secret
make create-gemini-secret GEMINI_API_KEY=xyz

# Create Claude Vertex secret (with optional CREDS_FILE path)
make create-claude-vertex-secret PROJECT_ID=xyz REGION=us-east5
```

Secrets are stored as gitignored YAML files in `k8s/secrets/`.

### Deployment

**Podman (local container runtime):**
```bash
make deploy-podman-gemini-golang
make deploy-podman-claude-python
```

**Kubernetes:**
```bash
make deploy-k8s-gemini-golang
make deploy-k8s-claude-python
```

### View Help

```bash
make help
```

Displays all available targets with descriptions.

## Directory Structure

```
.
├── Makefile                      # Build, push, deploy targets
├── .push-defaults               # Session defaults (gitignored)
├── README.md                    # This file
├── containerfiles/
│   ├── Containerfile.claude     # Claude Code image definition
│   └── Containerfile.gemini     # Gemini CLI image definition
├── k8s/
│   ├── claude-golang.yaml       # Claude + Go Pod template
│   ├── claude-python.yaml       # Claude + Python Pod template
│   ├── gemini-golang.yaml       # Gemini + Go Pod template
│   ├── gemini-python.yaml       # Gemini + Python Pod template
│   └── secrets/
│       ├── gemini-secret.yaml.template         # Template (not committed)
│       ├── claude-vertex-secret.yaml.template  # Template (not committed)
│       ├── gemini-secret.yaml                  # Generated (gitignored)
│       └── claude-vertex-secret.yaml           # Generated (gitignored)
└── scripts/
    ├── build.sh                 # Build image with registry/tag prompts
    ├── push.sh                  # Push image to registry
    ├── deploy.sh                # Deploy to Kubernetes
    ├── podman-run.sh            # Run container locally
    └── create-secrets.sh        # Generate secret YAML
```

## Configuration

### .push-defaults

Session defaults saved after each build (gitignored):

```
REGISTRY=zot.paxlab.cc
IMAGE_TAG=0.2
IMAGE_PULL_SECRET=zot-pull-secret
NAMESPACE=gemini
```

Edit or delete to reset defaults.

### Container Environment

**Claude images** set:
- `CLAUDE_CODE_USE_VERTEX=1` - Use Vertex AI API
- `GOOGLE_APPLICATION_CREDENTIALS=/app/gcloud/credentials.json`

**Gemini images** set:
- `GEMINI_API_KEY` - Loaded from K8s secret at runtime

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

# 2. Create secrets (one-time setup)
make create-gemini-secret GEMINI_API_KEY=sk-...
make create-claude-vertex-secret PROJECT_ID=my-project REGION=us-east5

# 3. Push all to registry
make podman-push

# 4. Deploy to K8s
make deploy-k8s-gemini-golang
make deploy-k8s-claude-golang
```

### Running Locally

```bash
# 1. Create secrets
make create-gemini-secret GEMINI_API_KEY=sk-...

# 2. Build image
make build-gemini-golang

# 3. Run container
make deploy-podman-gemini-golang
```

## GitHub Access

Agents authenticate to GitHub via an **SSH deploy key** scoped to a single repository. Setup requires a one-time GitHub Personal Access Token (PAT) to register the key — the PAT is not stored anywhere.

### Setting up GitHub access for a repo

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN=<your-pat>
make setup-github REPO=owner/repo
```

This generates an ephemeral RSA key pair, stores the private key as a secret, registers the public key as a deploy key on the repo, then wipes the key files. The PAT is used only for this step.

### Required PAT permissions

Generate a PAT at [github.com/settings/tokens](https://github.com/settings/tokens).

| PAT type | Required permission |
|----------|-------------------|
| **Fine-grained** (recommended) | `Administration` → Read and write (on the target repo) |
| **Classic** | `repo` scope (or `public_repo` for public repos only) |

The PAT does not need any other scopes. It is read from `GITHUB_PERSONAL_ACCESS_TOKEN` in your environment, with `GITHUB_TOKEN` as a fallback.

### Granting write access

By default, deploy keys are registered with write access (`read_only=false`). To register as read-only:

```bash
make setup-github REPO=owner/repo READ_ONLY=true
```

### Cleanup

```bash
# Remove completed/failed agent pods from K8s
make clean-agents-k8s

# Remove stopped agent containers from Podman
make clean-agents-podman
```

## Security Notes

- **Secrets are gitignored**: Never commit `k8s/secrets/*.yaml` (non-template files)
- **Credentials in environment**: Mounted via K8s secrets or Podman secret store at runtime
- **Non-root user**: Images run as `node` user (non-root for security)
- **Template files**: `.yaml.template` files are committed; generated `.yaml` files are not

## Troubleshooting

**Build fails with permission denied:**
```bash
# Ensure podman is available and running
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
- Regenerate if needed: `make create-gemini-secret GEMINI_API_KEY=...`
- Ensure namespace matches in K8s deployment

## Development

To modify image definitions, edit the Containerfiles:

- `containerfiles/Containerfile.claude` - Claude Code base image
- `containerfiles/Containerfile.gemini` - Gemini CLI base image

Build arguments:
- `LANG` - Language variant: `golang` or `python`
- `--target final` - Build final stage only

## License

See LICENSE file for details.
