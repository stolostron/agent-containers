# Agent Containers — Build, Push, and Deploy
#
# .push-defaults is loaded if it exists (gitignored).
# It stores REGISTRY, IMAGE_TAG, IMAGE_PULL_SECRET, and NAMESPACE between sessions.
-include .push-defaults

# --------------------------------------------------------------------------
# Build  (prompts for registry/image_tag, saves to .push-defaults)
# --------------------------------------------------------------------------
.PHONY: build-gemini-golang
build-gemini-golang:  ## Build Gemini CLI + Golang + Git image
	@bash scripts/build.sh gemini-cli-golang containerfiles/Containerfile.gemini golang

.PHONY: build-gemini-python
build-gemini-python:  ## Build Gemini CLI + Python3 + Git image
	@bash scripts/build.sh gemini-cli-python containerfiles/Containerfile.gemini python

.PHONY: build-claude-golang
build-claude-golang:  ## Build Claude Code + Golang + Git image
	@bash scripts/build.sh claude-code-golang containerfiles/Containerfile.claude golang

.PHONY: build-claude-python
build-claude-python:  ## Build Claude Code + Python3 + Git image
	@bash scripts/build.sh claude-code-python containerfiles/Containerfile.claude python

.PHONY: build-claude
build-claude: build-claude-golang build-claude-python  ## Build both Claude Code images (golang + python)

.PHONY: build-gemini
build-gemini: build-gemini-golang build-gemini-python  ## Build both Gemini CLI images (golang + python)

.PHONY: build-all
build-all: build-claude build-gemini  ## Build all four images

# --------------------------------------------------------------------------
# Push  (reads registry/image_tag from .push-defaults — no prompts)
# --------------------------------------------------------------------------
.PHONY: push-gemini-golang
push-gemini-golang:  ## Push gemini-cli-golang (uses .push-defaults)
	@bash scripts/push.sh gemini-cli-golang

.PHONY: push-gemini-python
push-gemini-python:  ## Push gemini-cli-python (uses .push-defaults)
	@bash scripts/push.sh gemini-cli-python

.PHONY: push-claude-golang
push-claude-golang:  ## Push claude-code-golang (uses .push-defaults)
	@bash scripts/push.sh claude-code-golang

.PHONY: push-claude-python
push-claude-python:  ## Push claude-code-python (uses .push-defaults)
	@bash scripts/push.sh claude-code-python

.PHONY: push-claude
push-claude: push-claude-golang push-claude-python  ## Build and push both Claude Code images

.PHONY: push-gemini
push-gemini: push-gemini-golang push-gemini-python  ## Build and push both Gemini CLI images

.PHONY: podman-push
podman-push: push-claude push-gemini  ## Build and push all four images (also tags :latest)

# --------------------------------------------------------------------------
# Secrets  (generates gitignored k8s/secrets/*.yaml — no kubectl required)
# --------------------------------------------------------------------------
.PHONY: create-gemini-secret
create-gemini-secret:  ## Generate Gemini secret YAML.  Requires: GEMINI_API_KEY=<key>
	@bash scripts/create-secrets.sh gemini "$(GEMINI_API_KEY)"

.PHONY: create-claude-vertex-secret
create-claude-vertex-secret:  ## Generate Claude Vertex secret YAML.  Requires: PROJECT_ID=<id> REGION=<region>  Optional: CREDS_FILE=<path> (default: ~/.config/gcloud/application_default_credentials.json)
	@bash scripts/create-secrets.sh claude "$(PROJECT_ID)" "$(REGION)" "$(CREDS_FILE)"

# --------------------------------------------------------------------------
# K8s deploy  (prompts for imagePullSecret + namespace, substitutes image refs)
# --------------------------------------------------------------------------
.PHONY: deploy-k8s-gemini-golang
deploy-k8s-gemini-golang:  ## Deploy gemini-golang to K8s
	@bash scripts/deploy.sh k8s/gemini-golang.yaml k8s/secrets/gemini-secret.yaml

.PHONY: deploy-k8s-gemini-python
deploy-k8s-gemini-python:  ## Deploy gemini-python to K8s
	@bash scripts/deploy.sh k8s/gemini-python.yaml k8s/secrets/gemini-secret.yaml

.PHONY: deploy-k8s-claude-golang
deploy-k8s-claude-golang:  ## Deploy claude-golang to K8s
	@bash scripts/deploy.sh k8s/claude-golang.yaml k8s/secrets/claude-vertex-secret.yaml

.PHONY: deploy-k8s-claude-python
deploy-k8s-claude-python:  ## Deploy claude-python to K8s
	@bash scripts/deploy.sh k8s/claude-python.yaml k8s/secrets/claude-vertex-secret.yaml

# --------------------------------------------------------------------------
# Podman deploy  (native podman run — reads secrets from podman secret store)
# --------------------------------------------------------------------------
.PHONY: deploy-podman-gemini-golang
deploy-podman-gemini-golang:  ## Run gemini-golang container with podman (run create-gemini-secret first)
	@bash scripts/podman-run.sh gemini-golang

.PHONY: deploy-podman-gemini-python
deploy-podman-gemini-python:  ## Run gemini-python container with podman (run create-gemini-secret first)
	@bash scripts/podman-run.sh gemini-python

.PHONY: deploy-podman-claude-golang
deploy-podman-claude-golang:  ## Run claude-golang container with podman (run create-claude-vertex-secret first)
	@bash scripts/podman-run.sh claude-golang

.PHONY: deploy-podman-claude-python
deploy-podman-claude-python:  ## Run claude-python container with podman (run create-claude-vertex-secret first)
	@bash scripts/podman-run.sh claude-python

# --------------------------------------------------------------------------
# Help
# --------------------------------------------------------------------------
.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' Makefile \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-36s\033[0m %s\n", $$1, $$2}' \
	  | sort

.DEFAULT_GOAL := help
