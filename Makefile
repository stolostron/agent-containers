# Agent Containers — Build, Push, and Deploy
#
# .push-defaults is loaded if it exists (gitignored).
# It stores REGISTRY, IMAGE_TAG, IMAGE_PULL_SECRET, and NAMESPACE between sessions.
-include .push-defaults

# --------------------------------------------------------------------------
# Publish  (build + push; prompts once for registry/image_tag, saves to .push-defaults)
# --------------------------------------------------------------------------
.PHONY: publish-claude
publish-claude:  ## Build and push both Claude Code images (golang + python)
	@bash scripts/publish.sh claude

.PHONY: publish-gemini
publish-gemini:  ## Build and push both Gemini CLI images (golang + python)
	@bash scripts/publish.sh gemini

# --------------------------------------------------------------------------
# Exec prompt  (interactive: select AI, language, and enter a prompt)
# --------------------------------------------------------------------------
.PHONY: exec-prompt
exec-prompt:  ## Launch a one-shot AI agent pod (select AI + language interactively, or: AI=claude LANG=golang PROMPT="...")
	@bash scripts/exec_prompt.sh "$(AI)" "$(LANG)" "$(PROMPT)"

# --------------------------------------------------------------------------
# Secrets  (generates gitignored k8s/secrets/*.yaml — no kubectl required)
# --------------------------------------------------------------------------
.PHONY: setup-github
setup-github:  ## Generate ephemeral SSH key, store as secret, register as GitHub deploy key.  Requires: REPO=owner/repo  Optional: READ_ONLY=false
	@if [ -z "$(REPO)" ]; then echo "Error: REPO=owner/repo is required" >&2; exit 1; fi
	@bash scripts/setup-github.sh "$(REPO)" "$(or $(READ_ONLY),false)"

# --------------------------------------------------------------------------
# Cleanup  (remove completed/failed agent pods and containers)
# --------------------------------------------------------------------------
.PHONY: clean-agents-k8s
clean-agents-k8s:  ## Delete completed and failed agent pods in K8s
	kubectl delete pods -l agent-container=true \
	    --field-selector='status.phase!=Running' \
	    $(if $(NAMESPACE),-n $(NAMESPACE),)

.PHONY: clean-agents-podman
clean-agents-podman:  ## Remove stopped agent containers in podman
	podman rm --filter label=agent-container=true

.PHONY: create-gemini-secret
create-gemini-secret:  ## Generate Gemini secret YAML.  Requires: GEMINI_API_KEY=<key>
	@bash scripts/create-secrets.sh gemini "$(GEMINI_API_KEY)"

.PHONY: create-claude-vertex-secret
create-claude-vertex-secret:  ## Generate Claude Vertex secret YAML.  Requires: PROJECT_ID=<id> REGION=<region>  Optional: CREDS_FILE=<path> (default: ~/.config/gcloud/application_default_credentials.json)
	@bash scripts/create-secrets.sh claude "$(PROJECT_ID)" "$(REGION)" "$(CREDS_FILE)"

# --------------------------------------------------------------------------
# K8s deploy  (publish + deploy in one command; prompts once for all details)
# --------------------------------------------------------------------------
.PHONY: deploy-k8s-claude-golang
deploy-k8s-claude-golang: publish-claude  ## Publish and deploy Claude Code golang to K8s
	@bash scripts/deploy.sh k8s/claude-golang.yaml k8s/secrets/claude-vertex-secret.yaml k8s/secrets/github-secret.yaml

.PHONY: deploy-k8s-claude-python
deploy-k8s-claude-python: publish-claude  ## Publish and deploy Claude Code python to K8s
	@bash scripts/deploy.sh k8s/claude-python.yaml k8s/secrets/claude-vertex-secret.yaml k8s/secrets/github-secret.yaml

.PHONY: deploy-k8s-gemini-golang
deploy-k8s-gemini-golang: publish-gemini  ## Publish and deploy Gemini CLI golang to K8s
	@bash scripts/deploy.sh k8s/gemini-golang.yaml k8s/secrets/gemini-secret.yaml

.PHONY: deploy-k8s-gemini-python
deploy-k8s-gemini-python: publish-gemini  ## Publish and deploy Gemini CLI python to K8s
	@bash scripts/deploy.sh k8s/gemini-python.yaml k8s/secrets/gemini-secret.yaml

# --------------------------------------------------------------------------
# Podman deploy  (publish + run in one command)
# --------------------------------------------------------------------------
.PHONY: deploy-podman-claude-golang
deploy-podman-claude-golang: publish-claude  ## Publish and run Claude Code golang with podman
	@bash scripts/podman-run.sh claude-golang

.PHONY: deploy-podman-claude-python
deploy-podman-claude-python: publish-claude  ## Publish and run Claude Code python with podman
	@bash scripts/podman-run.sh claude-python

.PHONY: deploy-podman-gemini-golang
deploy-podman-gemini-golang: publish-gemini  ## Publish and run Gemini CLI golang with podman
	@bash scripts/podman-run.sh gemini-golang

.PHONY: deploy-podman-gemini-python
deploy-podman-gemini-python: publish-gemini  ## Publish and run Gemini CLI python with podman
	@bash scripts/podman-run.sh gemini-python

# --------------------------------------------------------------------------
# Help
# --------------------------------------------------------------------------
.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' Makefile \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-36s\033[0m %s\n", $$1, $$2}' \
	  | sort

.DEFAULT_GOAL := help
