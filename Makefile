# Agent Containers — Build, Push, and Deploy
#
# .push-defaults is loaded if it exists (gitignored).
# Stores REGISTRY, IMAGE_TAG, IMAGE_PULL_SECRET, and NAMESPACE between sessions.
-include .push-defaults

IMAGES := opencode

# Toolchain versions — update all with: make update-deps
GO_VERSION       ?= 1.26.2
PYTHON_VERSION   ?= 3.14.4
PYTHON_BUILD     ?= 20260414
OPENCODE_VERSION ?= 1.14.29
GH_VERSION       ?= 2.92.0
FZF_VERSION      ?= 0.72.0
RG_VERSION       ?= 15.1.0

# --------------------------------------------------------------------------
# Per-image targets  (generated for each image in IMAGES)
#
#   build-<img>           — interactive build (prompts for registry)
#   build-fast-<img>      — non-interactive build (uses .push-defaults)
#   push-<img>            — push image
#   publish-<img>         — build-fast + push
#   redeploy-podman-<img> — rebuild, push, restart in podman
#   deploy-k8s-<img>      — deploy to Kubernetes
#   deploy-podman-<img>   — run with podman TUI
#   resume-podman-<img>   — resume last podman session
#   serve-podman-<img>    — start podman server on :4096
#   attach-podman-<img>   — attach TUI to running serve container
#   connect-<img>         — port-forward K8s pod to :4096
# --------------------------------------------------------------------------
define IMAGE_TARGETS

.PHONY: build-$(1) build-fast-$(1) push-$(1) publish-$(1)
build-$(1):
	@GO_VERSION=$(GO_VERSION) PYTHON_VERSION=$(PYTHON_VERSION) PYTHON_BUILD=$(PYTHON_BUILD) bash scripts/build.sh $(1) containerfiles/Containerfile.opencode
build-fast-$(1):
	podman build -f containerfiles/Containerfile.opencode \
	  --build-arg GH_VERSION=$(GH_VERSION) \
	  --build-arg GO_VERSION=$(GO_VERSION) \
	  --build-arg OPENCODE_VERSION=$(OPENCODE_VERSION) \
	  --build-arg PYTHON_VERSION=$(PYTHON_VERSION) \
	  --build-arg PYTHON_BUILD=$(PYTHON_BUILD) \
	  --build-arg FZF_VERSION=$(FZF_VERSION) \
	  --build-arg RG_VERSION=$(RG_VERSION) \
	  --target final -t $$(REGISTRY)/$(1):$$(IMAGE_TAG) .
push-$(1):
	@bash scripts/push.sh $(1)
publish-$(1): build-fast-$(1) push-$(1)

.PHONY: redeploy-podman-$(1) deploy-k8s-$(1) deploy-podman-$(1)
redeploy-podman-$(1): build-fast-$(1) push-$(1)
	-podman stop $(1) 2>/dev/null || true
	@bash scripts/podman-run.sh $(1) tui
deploy-k8s-$(1):
	@bash scripts/deploy.sh k8s/$(1).yaml k8s/secrets/opencode-secret.yaml.k8s
deploy-podman-$(1):
	@bash scripts/podman-run.sh $(1) tui

.PHONY: resume-podman-$(1) serve-podman-$(1) attach-podman-$(1) connect-$(1)
resume-podman-$(1):
	@bash scripts/podman-run.sh $(1) tui --continue
serve-podman-$(1):
	@bash scripts/podman-run.sh $(1) serve
attach-podman-$(1):
	opencode attach http://localhost:4096
connect-$(1):
	@bash scripts/connect.sh $(1)

endef

$(foreach img,$(IMAGES),$(eval $(call IMAGE_TARGETS,$(img))))

# --------------------------------------------------------------------------
# Aggregate targets
# --------------------------------------------------------------------------
.PHONY: build build-fast push publish
build:      $(addprefix build-,$(IMAGES))      ## Build all images (interactive)
build-fast: $(addprefix build-fast-,$(IMAGES))  ## Build all images (no prompts)
push:       $(addprefix push-,$(IMAGES))        ## Push all images
publish:    $(addprefix publish-,$(IMAGES))      ## Build + push all images

# --------------------------------------------------------------------------
# Secrets
# --------------------------------------------------------------------------
.PHONY: create-opencode-secret
create-opencode-secret:  ## Create Podman + K8s secrets.  Optional: CREDS_FILE=<path>
	@bash scripts/create-secrets.sh "$(CREDS_FILE)"

# --------------------------------------------------------------------------
# Version updates
# --------------------------------------------------------------------------
.PHONY: update-deps
update-deps:  ## Fetch latest versions of all dependencies and update Makefile
	$(eval LATEST_GO := $(shell curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '.[0].version' | sed 's/go//'))
	$(eval LATEST_BUILD := $(shell curl -fsSL 'https://api.github.com/repos/indygreg/python-build-standalone/releases/latest' | jq -r '.tag_name'))
	$(eval LATEST_PY := $(shell curl -fsSL 'https://api.github.com/repos/indygreg/python-build-standalone/releases/tags/$(LATEST_BUILD)' | jq -r '.assets[].name' | grep -oP 'cpython-\K[0-9]+\.[0-9]+\.[0-9]+(?=\+.*x86_64-unknown-linux-gnu-install_only\.tar\.gz)' | sort -V | tail -1))
	$(eval LATEST_OC := $(shell npm view opencode-ai version))
	$(eval LATEST_GH := $(shell curl -fsSL 'https://api.github.com/repos/cli/cli/releases/latest' | jq -r '.tag_name | ltrimstr("v")'))
	$(eval LATEST_FZF := $(shell curl -fsSL 'https://api.github.com/repos/junegunn/fzf/releases/latest' | jq -r '.tag_name | ltrimstr("v")'))
	$(eval LATEST_RG := $(shell curl -fsSL 'https://api.github.com/repos/BurntSushi/ripgrep/releases/latest' | jq -r '.tag_name'))
	@echo "Go: $(LATEST_GO)  Python: $(LATEST_PY) (build: $(LATEST_BUILD))  opencode: $(LATEST_OC)  gh: $(LATEST_GH)  fzf: $(LATEST_FZF)  rg: $(LATEST_RG)"
	@sed -i 's/^GO_VERSION\s*?= .*/GO_VERSION       ?= $(LATEST_GO)/' Makefile
	@sed -i 's/^PYTHON_VERSION\s*?= .*/PYTHON_VERSION   ?= $(LATEST_PY)/' Makefile
	@sed -i 's/^PYTHON_BUILD\s*?= .*/PYTHON_BUILD     ?= $(LATEST_BUILD)/' Makefile
	@sed -i 's/^OPENCODE_VERSION\s*?= .*/OPENCODE_VERSION ?= $(LATEST_OC)/' Makefile
	@sed -i 's/^GH_VERSION\s*?= .*/GH_VERSION       ?= $(LATEST_GH)/' Makefile
	@sed -i 's/^FZF_VERSION\s*?= .*/FZF_VERSION      ?= $(LATEST_FZF)/' Makefile
	@sed -i 's/^RG_VERSION\s*?= .*/RG_VERSION       ?= $(LATEST_RG)/' Makefile

.PHONY: set-image-tag
set-image-tag:  ## Set IMAGE_TAG in .push-defaults (usage: make set-image-tag IMAGE_TAG=0.3.2)
	@if [ -z "$(IMAGE_TAG)" ]; then echo "Usage: make set-image-tag IMAGE_TAG=<tag>" >&2; exit 1; fi; \
	sed -i '/^IMAGE_TAG=/d' .push-defaults; \
	echo "IMAGE_TAG=$(IMAGE_TAG)" >> .push-defaults; \
	echo "IMAGE_TAG set to $(IMAGE_TAG) in .push-defaults"

.PHONY: update-and-rebuild
update-and-rebuild: update-deps publish  ## Update all dependencies, rebuild + push all

# --------------------------------------------------------------------------
# Help
# --------------------------------------------------------------------------
.PHONY: help
help:  ## Show this help
	@echo ""
	@echo "Aggregate targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' Makefile \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-36s\033[0m %s\n", $$1, $$2}' \
	  | sort
	@echo ""
	@echo "Per-image targets (replace <img> with: $(IMAGES)):"
	@echo "  \033[36mbuild-<img>\033[0m                        Build (interactive, prompts for registry)"
	@echo "  \033[36mbuild-fast-<img>\033[0m                   Build (no prompts, uses .push-defaults)"
	@echo "  \033[36mpush-<img>\033[0m                         Push image"
	@echo "  \033[36mpublish-<img>\033[0m                      Build + push"
	@echo "  \033[36mredeploy-podman-<img>\033[0m              Rebuild, push, restart in podman"
	@echo "  \033[36mdeploy-k8s-<img>\033[0m                   Deploy to Kubernetes"
	@echo "  \033[36mdeploy-podman-<img>\033[0m                Run with podman (TUI)"
	@echo "  \033[36mresume-podman-<img>\033[0m                Resume last podman session"
	@echo "  \033[36mserve-podman-<img>\033[0m                 Start server on localhost:4096"
	@echo "  \033[36mattach-podman-<img>\033[0m                Attach TUI to running server"
	@echo "  \033[36mconnect-<img>\033[0m                      Port-forward K8s pod to localhost:4096"
	@echo ""

.DEFAULT_GOAL := help
