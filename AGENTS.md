# Agent Instructions (AGENTS.md)

This repository is for building, pushing, and deploying containerized AI code agents (OpenCode and Crush).

## Project Architecture & Structure

For system architecture, data flows, and module layout, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Important Commands

- **Build**: `make build` (builds all) or `make build-opencode` / `make build-crush`. 
  - *Note: It prompts for Registry/Tag interactively. Pass `NOPROMPT=1` to use saved defaults.*
- **Push**: `make push` or `make push-<image>`.
- **Publish**: `make publish-<image>` (builds and pushes without prompts).
- **Run locally**: `make deploy-podman-<image>` (runs the container using the TUI).
- **Update Dependencies**: `make update-deps` (Fetches latest upstream versions using `curl`/`jq` and updates the `Makefile`).
- **Update and Rebuild**: `make update-and-rebuild` (Updates deps, builds, and pushes all images).

## Toolchain Version Pinning (Important Gotcha)

Versions for tools (Go, Python, gh, rg, fzf, gopls, pyright, etc.) are strictly managed and pinned.
If you need to add or update a versioned dependency, it MUST follow this flow:
1. Define it as a variable in the `Makefile` (e.g., `GOPLS_VERSION ?= 0.22.0`).
2. Add a `curl`/`jq` fetch step in the `update-deps` target of the `Makefile` to automatically discover the latest version.
3. Pass the variable into `scripts/build.sh` within the `build-$(1)` target in the `Makefile`.
4. Add it as a `--build-arg` in `scripts/build.sh`.
5. Declare it as an `ARG` at the top of `containerfiles/Containerfile.agents`.
6. **Crucially**: Re-declare the `ARG` immediately after the `FROM ... AS ...` line in the specific build stage where it is used (e.g., `base-runtimes`).

## Testing

Always run `bash tests/test_lsp_version_pinning.sh` after modifying any version wiring in the `Makefile`, `scripts/build.sh`, or `Containerfile.agents`. This script explicitly tests the wiring of variables from end-to-end to ensure no breaks.

## Conventions & Gotchas

- **Secrets**: Running `make create-opencode-secret` generates gitignored `.yaml` files from templates in `k8s/secrets/`. Do not commit generated secrets.
- **User Permissions in Containerfile**: The container base uses a non-root `node` user. When installing system packages, explicitly switch to `USER root`, install, and then switch back to `USER node`.
- **Markdown Plans**: When editing files in `plans/` (like `INDEX.md`), use `---` for separators. Do not use `# ──` heading separators.
- **Opencode Configuration**: Models are restricted to Claude and Gemini via `containerfiles/opencode.json`.
