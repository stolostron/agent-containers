# Agent Containers — Build, Push, and Deploy
#
# .push-defaults is loaded if it exists (gitignored).
# It stores REGISTRY, IMAGE_TAG, IMAGE_PULL_SECRET, and NAMESPACE between sessions.
-include .push-defaults

# --------------------------------------------------------------------------
# Build  (prompts for registry/image_tag, saves to .push-defaults)
# --------------------------------------------------------------------------
.PHONY: build-opencode-golang
build-opencode-golang:  ## Build OpenCode + Golang + Git image
	@bash scripts/build.sh opencode-golang containerfiles/Containerfile.opencode golang

.PHONY: build-opencode-python
build-opencode-python:  ## Build OpenCode + Python3 + Git image
	@bash scripts/build.sh opencode-python containerfiles/Containerfile.opencode python

.PHONY: build-all
build-all: build-opencode-golang build-opencode-python  ## Build both OpenCode images (golang + python)

# --------------------------------------------------------------------------
# Build fast  (non-interactive — uses saved .push-defaults, no prompts)
# --------------------------------------------------------------------------
.PHONY: build-fast-opencode-golang
build-fast-opencode-golang:  ## Build opencode-golang (no prompts, uses .push-defaults)
	podman build -f containerfiles/Containerfile.opencode --build-arg LANG=golang --target final -t $(REGISTRY)/opencode-golang:$(IMAGE_TAG) .

.PHONY: build-fast-opencode-python
build-fast-opencode-python:  ## Build opencode-python (no prompts, uses .push-defaults)
	podman build -f containerfiles/Containerfile.opencode --build-arg LANG=python --target final -t $(REGISTRY)/opencode-python:$(IMAGE_TAG) .

# --------------------------------------------------------------------------
# Push  (reads registry/image_tag from .push-defaults — no prompts)
# --------------------------------------------------------------------------
.PHONY: push-opencode-golang
push-opencode-golang:  ## Push opencode-golang (uses .push-defaults)
	@bash scripts/push.sh opencode-golang

.PHONY: push-opencode-python
push-opencode-python:  ## Push opencode-python (uses .push-defaults)
	@bash scripts/push.sh opencode-python

.PHONY: podman-push
podman-push: push-opencode-golang push-opencode-python  ## Push both OpenCode images (also tags :latest)

# --------------------------------------------------------------------------
# Redeploy  (build + push + restart container in one shot)
# --------------------------------------------------------------------------
.PHONY: redeploy-podman-opencode-golang
redeploy-podman-opencode-golang: build-fast-opencode-golang push-opencode-golang  ## Rebuild, push, and restart opencode-golang in podman
	-podman stop opencode-golang 2>/dev/null || true
	@bash scripts/podman-run.sh opencode-golang tui

.PHONY: redeploy-podman-opencode-python
redeploy-podman-opencode-python: build-fast-opencode-python push-opencode-python  ## Rebuild, push, and restart opencode-python in podman
	-podman stop opencode-python 2>/dev/null || true
	@bash scripts/podman-run.sh opencode-python tui

# --------------------------------------------------------------------------
# Secrets  (generates gitignored k8s/secrets/*.yaml — no kubectl required)
# --------------------------------------------------------------------------
.PHONY: create-opencode-secret
create-opencode-secret:  ## Create Podman + K8s secrets from k8s/secrets/opencode-secret.yaml.  Optional: CREDS_FILE=<path>
	@bash scripts/create-secrets.sh "$(CREDS_FILE)"

# --------------------------------------------------------------------------
# K8s deploy  (prompts for imagePullSecret + namespace, substitutes image refs)
# --------------------------------------------------------------------------
.PHONY: deploy-k8s-opencode-golang
deploy-k8s-opencode-golang:  ## Deploy opencode-golang to K8s
	@bash scripts/deploy.sh k8s/opencode-golang.yaml k8s/secrets/opencode-secret.yaml.k8s

.PHONY: deploy-k8s-opencode-python
deploy-k8s-opencode-python:  ## Deploy opencode-python to K8s
	@bash scripts/deploy.sh k8s/opencode-python.yaml k8s/secrets/opencode-secret.yaml.k8s

# --------------------------------------------------------------------------
# Podman deploy  (native podman run — reads secrets from podman secret store)
# --------------------------------------------------------------------------
.PHONY: deploy-podman-opencode-golang
deploy-podman-opencode-golang:  ## Run opencode-golang container with podman (interactive TUI)
	@bash scripts/podman-run.sh opencode-golang tui

.PHONY: deploy-podman-opencode-python
deploy-podman-opencode-python:  ## Run opencode-python container with podman (interactive TUI)
	@bash scripts/podman-run.sh opencode-python tui

.PHONY: resume-podman-opencode-golang
resume-podman-opencode-golang:  ## Resume last opencode-golang session in podman
	@bash scripts/podman-run.sh opencode-golang tui --continue

.PHONY: resume-podman-opencode-python
resume-podman-opencode-python:  ## Resume last opencode-python session in podman
	@bash scripts/podman-run.sh opencode-python tui --continue

.PHONY: serve-podman-opencode-golang
serve-podman-opencode-golang:  ## Start opencode-golang server on localhost:4096 (background)
	@bash scripts/podman-run.sh opencode-golang serve

.PHONY: serve-podman-opencode-python
serve-podman-opencode-python:  ## Start opencode-python server on localhost:4096 (background)
	@bash scripts/podman-run.sh opencode-python serve

# --------------------------------------------------------------------------
# Podman attach  (connect a local TUI to a running serve container)
# --------------------------------------------------------------------------
.PHONY: attach-podman-opencode-golang
attach-podman-opencode-golang:  ## Attach TUI to running opencode-golang serve container
	opencode attach http://localhost:4096

.PHONY: attach-podman-opencode-python
attach-podman-opencode-python:  ## Attach TUI to running opencode-python serve container
	opencode attach http://localhost:4096

# --------------------------------------------------------------------------
# K8s connect  (port-forward pod to localhost:4096)
# --------------------------------------------------------------------------
.PHONY: connect-opencode-golang
connect-opencode-golang:  ## Port-forward opencode-golang pod to localhost:4096
	@bash scripts/connect.sh opencode-golang

.PHONY: connect-opencode-python
connect-opencode-python:  ## Port-forward opencode-python pod to localhost:4096
	@bash scripts/connect.sh opencode-python

# --------------------------------------------------------------------------
# Help
# --------------------------------------------------------------------------
.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' Makefile \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-36s\033[0m %s\n", $$1, $$2}' \
	  | sort

.DEFAULT_GOAL := help
