# 2026-04-21 — Build Pipeline and Ops Improvements

## Planning

### Problems Identified

**1. opencode version not pinned in image builds**
`npm install -g opencode-ai` in the Containerfile had no version pin. Docker layer caching meant rebuilds reused the cached layer, so the python image was stuck on `1.4.11` while the golang image had picked up `1.14.20` from a prior uncached build. `OPENCODE_VERSION` existed in the Makefile but was never wired into the build as a `--build-arg`.

**2. No way to set IMAGE_TAG without editing `.push-defaults` manually**
Deploying a specific tag required hand-editing `.push-defaults`. Prefixing `IMAGE_TAG=x make deploy-*` silently had no effect because the `-include .push-defaults` assignment overrides environment variable prefixes in Make.

**3. `.push-defaults` could accumulate duplicate `IMAGE_TAG` lines**
A failed `set-image-tag` run (from a shell-compatibility bug) left the original line in place; the next successful run appended a second line. `grep | cut` in `push.sh` then produced a newline-embedded value, causing `Error: invalid reference format` from podman.

**4. Container memory limits too high**
Both k8s manifests had a 4Gi memory limit and the image baked `NODE_OPTIONS=--max-old-space-size=3072`, which reserved most of that headroom for Node alone.

---

### Planned Changes

| Area | Change |
|------|--------|
| `Containerfile.opencode` | Add `ARG OPENCODE_VERSION` and pin `npm install -g opencode-ai@${OPENCODE_VERSION}` |
| `Makefile` (build target) | Pass `--build-arg OPENCODE_VERSION=$(OPENCODE_VERSION)` in `build-fast-<img>` |
| `Makefile` (new target) | `set-image-tag` — updates `IMAGE_TAG` in `.push-defaults` without prompts |
| `scripts/push.sh` | Use `grep -m1` to guard against duplicate key lines |
| `k8s/opencode-golang.yaml` | Reduce memory limit from `4Gi` → `2Gi` |
| `k8s/opencode-python.yaml` | Reduce memory limit from `4Gi` → `2Gi` |
| `Containerfile.opencode` | Reduce `NODE_OPTIONS` heap from `3072` → `1536` MB |

---

## Implementation

**Completed: 2026-04-21**

### `containerfiles/Containerfile.opencode`
- Added `ARG OPENCODE_VERSION=1.14.20` at the top alongside `GH_VERSION` and `GO_VERSION`
- Changed `npm install -g opencode-ai` → `npm install -g opencode-ai@${OPENCODE_VERSION}` so the version pin busts the Docker layer cache on upgrade
- Reduced `NODE_OPTIONS=--max-old-space-size=1536` (down from 3072), proportional to the new 2Gi container limit

### `Makefile`
- Added `--build-arg OPENCODE_VERSION=$(OPENCODE_VERSION)` to `build-fast-<img>` target so `make update-deps` → `make publish` propagates the new version end-to-end
- Added `set-image-tag` target: removes all existing `IMAGE_TAG=` lines then appends the new value, preventing duplicates. Usage: `make set-image-tag IMAGE_TAG=0.3.2` (Make argument form, not env prefix, due to `-include .push-defaults` precedence)

### `scripts/push.sh`
- Changed `grep` to `grep -m1` when reading `IMAGE_TAG` from `.push-defaults` so a duplicate line can never embed a newline in the image reference

### `k8s/opencode-golang.yaml` and `k8s/opencode-python.yaml`
- Memory limit reduced from `4Gi` → `2Gi`; requests unchanged at `1Gi`
