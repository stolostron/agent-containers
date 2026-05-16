# Agent Containers — Build, Push, and Deploy
#
# Local .push-defaults: machine-specific settings (NAMESPACE, IMAGE_PULL_SECRET, etc.) — gitignored.
# ../agent-swarm/.push-defaults: REGISTRY + IMAGE_TAG (source of truth) — checked in.
-include .push-defaults
AC_DEFAULTS := $(firstword $(wildcard ../agent-swarm/.push-defaults) .push-defaults)
-include $(AC_DEFAULTS)

IMAGES := opencode crush

# Toolchain versions — update all with: make update-deps
GO_VERSION       ?= 1.26.3
PYTHON_VERSION   ?= 3.13.13
PYTHON_BUILD     ?= 20260504
OPENCODE_VERSION ?= 1.14.41
CRUSH_VERSION    ?= 0.66.0
GH_VERSION       ?= 2.92.0
FZF_VERSION      ?= 0.72.0
RG_VERSION       ?= 15.1.0
JIRA_MCP_VERSION ?= 0.1.0
GOPLS_VERSION    ?= 0.21.1
PYRIGHT_VERSION  ?= 1.1.409

# Per-image build targets
TARGET_opencode := opencode
TARGET_crush    := crush
CONTAINERFILE   := containerfiles/Containerfile.agents

# Pass NOPROMPT=1 to skip interactive prompts (e.g. make build NOPROMPT=1)
NOPROMPT ?=

# --------------------------------------------------------------------------
# Per-image targets  (generated for each image in IMAGES)
#
#   build-<img>           — build image (NOPROMPT=1 to skip prompts)
#   push-<img>            — push image
#   publish-<img>         — build + push (no prompts)
#   redeploy-podman-<img> — rebuild, push, restart in podman (no prompts)
#   deploy-podman-<img>   — run with podman TUI
#   resume-podman-<img>   — resume last podman session
#   serve-podman-<img>    — start podman server on :4096
#   attach-podman-<img>   — attach TUI to running serve container
# --------------------------------------------------------------------------
define IMAGE_TARGETS

.PHONY: build-$(1) push-$(1) publish-$(1)
build-$(1):
	@GO_VERSION=$(GO_VERSION) PYTHON_VERSION=$(PYTHON_VERSION) PYTHON_BUILD=$(PYTHON_BUILD) CRUSH_VERSION=$(CRUSH_VERSION) OPENCODE_VERSION=$(OPENCODE_VERSION) JIRA_MCP_VERSION=$(JIRA_MCP_VERSION) GOPLS_VERSION=$(GOPLS_VERSION) PYRIGHT_VERSION=$(PYRIGHT_VERSION) NOPROMPT=$(NOPROMPT) bash scripts/build.sh $(1) $(CONTAINERFILE)
push-$(1):
	@bash scripts/push.sh $(1)
publish-$(1):
	@$(MAKE) build-$(1) NOPROMPT=1
	@$(MAKE) push-$(1)

.PHONY: redeploy-podman-$(1) deploy-podman-$(1)
redeploy-podman-$(1):
	@$(MAKE) build-$(1) NOPROMPT=1
	@$(MAKE) push-$(1)
	-podman stop $(1) 2>/dev/null || true
	@bash scripts/podman-run.sh $(1) tui
deploy-podman-$(1):
	@bash scripts/podman-run.sh $(1) tui

.PHONY: resume-podman-$(1) serve-podman-$(1) attach-podman-$(1)
resume-podman-$(1):
	@bash scripts/podman-run.sh $(1) tui --continue
serve-podman-$(1):
	@bash scripts/podman-run.sh $(1) serve
attach-podman-$(1):
	$(1) attach http://localhost:4096

endef

$(foreach img,$(IMAGES),$(eval $(call IMAGE_TARGETS,$(img))))

# --------------------------------------------------------------------------
# Aggregate targets
# --------------------------------------------------------------------------
.PHONY: build push publish
build:  ## Build all images (first image prompts for registry/tag, rest reuse saved values)
	@$(MAKE) build-$(firstword $(IMAGES)) NOPROMPT=$(NOPROMPT)
	@for img in $(wordlist 2,$(words $(IMAGES)),$(IMAGES)); do \
	    $(MAKE) build-$$img NOPROMPT=1; \
	done
push:       $(addprefix push-,$(IMAGES))        ## Push all images
publish:    $(addprefix publish-,$(IMAGES))      ## Build + push all images (no prompts)

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
	$(eval LATEST_CRUSH := $(shell curl -fsSL 'https://api.github.com/repos/charmbracelet/crush/releases/latest' | jq -r '.tag_name | ltrimstr("v")'))
	$(eval LATEST_GH := $(shell curl -fsSL 'https://api.github.com/repos/cli/cli/releases/latest' | jq -r '.tag_name | ltrimstr("v")'))
	$(eval LATEST_FZF := $(shell curl -fsSL 'https://api.github.com/repos/junegunn/fzf/releases/latest' | jq -r '.tag_name | ltrimstr("v")'))
	$(eval LATEST_RG := $(shell curl -fsSL 'https://api.github.com/repos/BurntSushi/ripgrep/releases/latest' | jq -r '.tag_name'))
	$(eval LATEST_JIRA_MCP := $(shell curl -fsSL 'https://api.github.com/repos/stolostron/jira-mcp-server/releases/latest' | jq -r '.tag_name | ltrimstr("v")'))
	$(eval LATEST_GOPLS := $(shell curl -fsSL 'https://api.github.com/repos/golang/tools/releases' | jq -r '[.[] | select(.tag_name | startswith("gopls/"))][0].tag_name | ltrimstr("gopls/v")'))
	$(eval LATEST_PYRIGHT := $(shell curl -fsSL 'https://pypi.org/pypi/pyright/json' | jq -r '.info.version'))
	@echo "Go: $(LATEST_GO)  Python: $(LATEST_PY) (build: $(LATEST_BUILD))  opencode: $(LATEST_OC)  crush: $(LATEST_CRUSH)  gh: $(LATEST_GH)  fzf: $(LATEST_FZF)  rg: $(LATEST_RG)  jira-mcp: $(LATEST_JIRA_MCP)  gopls: $(LATEST_GOPLS)  pyright: $(LATEST_PYRIGHT)"
	@sed -i 's/^GO_VERSION\s*?= .*/GO_VERSION       ?= $(LATEST_GO)/' Makefile
	@sed -i 's/^PYTHON_VERSION\s*?= .*/PYTHON_VERSION   ?= $(LATEST_PY)/' Makefile
	@sed -i 's/^PYTHON_BUILD\s*?= .*/PYTHON_BUILD     ?= $(LATEST_BUILD)/' Makefile
	@sed -i 's/^OPENCODE_VERSION\s*?= .*/OPENCODE_VERSION ?= $(LATEST_OC)/' Makefile
	@sed -i 's/^CRUSH_VERSION\s*?= .*/CRUSH_VERSION    ?= $(LATEST_CRUSH)/' Makefile
	@sed -i 's/^GH_VERSION\s*?= .*/GH_VERSION       ?= $(LATEST_GH)/' Makefile
	@sed -i 's/^FZF_VERSION\s*?= .*/FZF_VERSION      ?= $(LATEST_FZF)/' Makefile
	@sed -i 's/^RG_VERSION\s*?= .*/RG_VERSION       ?= $(LATEST_RG)/' Makefile
	@sed -i 's/^JIRA_MCP_VERSION\s*?= .*/JIRA_MCP_VERSION ?= $(LATEST_JIRA_MCP)/' Makefile
	@sed -i 's/^GOPLS_VERSION\s*?= .*/GOPLS_VERSION    ?= $(LATEST_GOPLS)/' Makefile
	@sed -i 's/^PYRIGHT_VERSION\s*?= .*/PYRIGHT_VERSION  ?= $(LATEST_PYRIGHT)/' Makefile

.PHONY: set-image-tag
set-image-tag:  ## Set IMAGE_TAG in $(AC_DEFAULTS) (usage: make set-image-tag IMAGE_TAG=0.3.2)
	@if [ -z "$(IMAGE_TAG)" ]; then echo "Usage: make set-image-tag IMAGE_TAG=<tag>" >&2; exit 1; fi; \
	sed -i '/^IMAGE_TAG=/d' $(AC_DEFAULTS); \
	echo "IMAGE_TAG=$(IMAGE_TAG)" >> $(AC_DEFAULTS); \
	echo "IMAGE_TAG set to $(IMAGE_TAG) in $(AC_DEFAULTS)"

.PHONY: update-and-rebuild
update-and-rebuild: update-deps  ## Update all dependencies, rebuild + push all
	@$(MAKE) build NOPROMPT=$(NOPROMPT)
	@$(MAKE) push

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
	@echo "  \033[36mbuild-<img>\033[0m                        Build (NOPROMPT=1 to skip prompts)"
	@echo "  \033[36mpush-<img>\033[0m                         Push image"
	@echo "  \033[36mpublish-<img>\033[0m                      Build + push (no prompts)"
	@echo "  \033[36mredeploy-podman-<img>\033[0m              Rebuild, push, restart in podman"
	@echo "  \033[36mdeploy-podman-<img>\033[0m                Run with podman (TUI)"
	@echo "  \033[36mresume-podman-<img>\033[0m                Resume last podman session"
	@echo "  \033[36mserve-podman-<img>\033[0m                 Start server on localhost:4096"
	@echo "  \033[36mattach-podman-<img>\033[0m                Attach TUI to running server"
	@echo ""

.DEFAULT_GOAL := help
