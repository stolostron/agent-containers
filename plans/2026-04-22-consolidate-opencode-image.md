# Plan: Consolidate to Single opencode Image
**Date:** 2026-04-22
**Branch:** main

## Context
Currently the repo builds two separate images — `opencode-golang` and `opencode-python` — using a `LANG` build-arg to select the final stage in a multi-stage Containerfile. This means separate build/push/deploy cycles for workloads that only differ by language runtime. Consolidating into one image (`opencode`) containing both Go and Python simplifies operations and reduces image sprawl, while leaving room to add a third image later for Console/NPM/Patternfly.

## Approach

### 1. `containerfiles/Containerfile.opencode`
- Remove `ARG LANG` and the `FROM lang-${LANG} AS final` selection stage.
- Collapse `lang-golang` and `lang-python` into a single final build stage:
  - Start from `base-common`
  - Install Go (as the current `lang-golang` stage does)
  - Then install Python (`python3-pip python3-venv`) on top
  - Name the result stage `final` (or just leave it as the terminal `FROM`)
- Keep all `ARG` declarations for version pins (`GO_VERSION`, `GH_VERSION`, `OPENCODE_VERSION`).

### 2. `Makefile`
- Change `IMAGES := opencode-golang opencode-python` → `IMAGES := opencode`
- Remove `LANG_opencode-golang` and `LANG_opencode-python` variable lines
- In the `IMAGE_TARGETS` macro, remove `--build-arg LANG=$(LANG_$(1))` from `build-fast-$(1)` and remove `--target final` (the Containerfile's final stage will be the natural last stage)
- Update `build-$(1)` (calls `build.sh`) to stop passing the lang arg (was `$(LANG_$(1))`)
- The `update-deps`, `help`, and aggregate targets need no changes other than picking up the new `IMAGES` value automatically

### 3. `scripts/build.sh`
- Remove `LANG="$3"` and the `--build-arg LANG="${LANG}"` line from the `podman build` call
- The script currently takes 3 positional args; drop the third

### 4. K8s manifests
- Delete `k8s/opencode-golang.yaml` and `k8s/opencode-python.yaml`
- Create `k8s/opencode.yaml` — single Pod manifest:
  - `name: opencode`, `app: opencode` label, no `lang:` label
  - `image: REGISTRY/opencode:IMAGE_TAG`
  - Same env vars and volume mounts as the current manifests (opencode-secret refs, gcloud creds)
  - Same resource requests/limits (1Gi req / 2Gi limit, 500m / 2000m CPU)

## Files to Change
- `containerfiles/Containerfile.opencode` — merge lang stages, remove LANG arg
- `Makefile` — single IMAGES entry, remove LANG vars, clean up macro
- `scripts/build.sh` — remove LANG positional arg and build-arg pass-through
- `k8s/opencode-golang.yaml` — delete
- `k8s/opencode-python.yaml` — delete
- `k8s/opencode.yaml` — create (new single manifest)

## Verification
```bash
# Build the unified image
make build-fast-opencode

# Confirm both runtimes are present
podman run --rm <registry>/opencode:<tag> go version
podman run --rm <registry>/opencode:<tag> python3 --version

# Confirm opencode still starts
podman run --rm <registry>/opencode:<tag> opencode --version

# Dry-run the K8s manifest render (no cluster needed)
REGISTRY=myregistry IMAGE_TAG=test \
  sed -e 's|REGISTRY|myregistry|g' -e 's|IMAGE_TAG|test|g' \
      -e '/IMAGE_PULL_SECRET_BLOCK/d' k8s/opencode.yaml

# Full deploy (if cluster available)
make deploy-k8s-opencode
```

---
## Implementation Summary
> To be filled in by /finish-work after work is complete.
