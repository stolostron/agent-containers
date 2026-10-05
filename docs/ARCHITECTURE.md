# Project Architecture & Structure

- **`Makefile`**: Central entrypoint for all operations. It dynamically generates per-image targets for images defined in `IMAGES` (`opencode`).
- **`Containerfile.agents`**: Multi-stage build containing:
  - `base-tools`: Core OS utilities (git, curl, fzf, rg, gh, jq) on a `nodejs-24` base.
  - `base-runtimes`: Language runtimes (Go, Python), LSPs (gopls, pyright), preinstalled CVE scanners (`pip-audit`, `govulncheck`), MCP servers, and GitHub App auth scripts.
  - Target-specific stage: `opencode`.
- **`scripts/`**: Shell scripts wrapped by the Makefile (e.g., `build.sh`, `push.sh`, `deploy.sh`).
- **`scripts/github-app/`**: GitHub App IAT generation, token caching, `gh` wrapper, and git credential helper (from kubeopencode/devbox / server-foundation-agent). Wired in `base-runtimes` so the agent image gets transparent auth when `/etc/github-app/` is mounted or `GH_APP_*` env vars are set. If `GH_TOKEN` is already set (e.g. agent-swarm session PAT), the wrapper uses it instead.
- **`.push-defaults`**: A gitignored file that persists your registry and image tag preferences across builds. Sourced from `../agent-swarm/.push-defaults` if available.

## Automated image releases

`.github/workflows/publish-image.yml` serializes pushes to `main` and uses the
tracked `IMAGE_PUBLISH_STATE` SHA as a catch-up cursor. `scripts/image_release.py`
walks first-parent commits after that cursor and uses GitHub's commit-to-PR
association to select squash merges. Direct pushes and release metadata commits
are skipped. Each selected source gets the next patch version from `VERSION`.

`scripts/publish_image.py --stage publish` builds each source revision with
explicit `REGISTRY` and `IMAGE_TAG` Make overrides, pushes its candidate tag,
records `IMAGE_DIGEST`, and prepares local metadata commits. Build subprocesses
receive an allowlisted environment without GitHub or Quay credentials; registry
authentication is isolated in a temporary Podman authfile. By default,
`scripts/build.sh` installs the pinned Agent Swarm MCP release rather than using
an implicitly discovered sibling checkout. `AGENT_SWARM_MCP_SOURCE` is an
explicit local-only override.

Every pushed digest passes `scripts/e2e_container.py` (runtime identity and
permissions, pinned tools/MCP startup, and the OpenCode `/global/health`
endpoint) and `scripts/e2e_kind_pod.py` (registry pull and workload execution
under a non-root security context). Only after all candidates pass does the
promotion stage tag the final candidate as `latest`, compare registry digests,
and push the prepared version/digest/cursor commits to `main`. The cursor only
advances in those commits, so failed candidates are eligible for a later
catch-up run. The workflow requires a Quay push robot secret, read access to
the public Quay image for E2E, GitHub `contents: write` and
`pull-requests: read`, and permission for the Actions bot to update `main`.

Release contracts and failure/promotion behavior are covered by
`tests/test_image_release.py` (`pytest -q tests/test_image_release.py`).

## CVE Scanner Runtime

`pip-audit` and `govulncheck` are pinned in `Makefile`, installed into the shared image runtime, and validated during the image build. They are available to both non-root runtime users through `/usr/local/bin`. Scanner binaries are updated independently from live advisory data; normal scans query their upstream advisory services and do not require an image rebuild.

The image deliberately keeps the `gopls` build output under `/home/node/go` and
does not configure its runtime cache paths under `/tmp`. OpenCode treats paths
outside the workspace, including `/tmp`, as external directories that require
permission approval; automated sessions may reject those requests. Build-only
temporary directories are safe when removed in the same image layer, but paths
needed by the running agent must remain in the user home directories.

The image provides Node/npm for native Node audits. Corepack may be enabled by the audit workflow for an existing pnpm or Yarn project, but audits must not install dependencies or mutate manifests and lockfiles. The audit workflow must record the scanner version, target, timestamp, advisory source, live/cache status, and distinguish clean, findings, partial, and infrastructure-failure outcomes. DNS, authentication, rate-limit, and advisory-service failures are not clean scans.
