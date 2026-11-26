# Dependency Update Plan — 2026-11-26

**Jira:** [ACM-51101](https://redhat.atlassian.net/browse/ACM-51101)\
**Repository:** `stolostron/agent-containers`\
**Baseline:** `main` at `b32ed4f4a8206e5b411c7b961730ed4ecc0b2ec9`\
**Existing topic branch / PR:** `ACM-51101/update-dependency-pins-nov-2026` / [PR #29](https://github.com/stolostron/agent-containers/pull/29)

---

## Comparison with the last recorded update

The most recent merged dependency update remains PR [#28](https://github.com/stolostron/agent-containers/pull/28), linked to ACM-49186 and merged 2026-10-26. The November update is already tracked by ACM-51101 and open PR #29, created from the clean `main` baseline. To avoid duplicate task or PR work, this run extends that open branch and PR.

Compared with the update recorded in `plans/2026-11-23-dependency-update.md`, the updater now proposes OpenCode 2.4.2 instead of 2.4.1, GitHub CLI 2.106.0 instead of 2.105.0, and Python build artifact 20261124 instead of 20261110. The other pins in PR #29 are unchanged by this run.

---

## Changes from this run

All updater changes are in `Makefile`.

| Dependency/tool | Category | Previous | Proposed | Files |
|---|---|---:|---:|---|
| Python build artifact | Other tool / runtime build | 20261110 | 20261124 | `Makefile` |
| OpenCode CLI | OpenCode | 2.4.1 | 2.4.2 | `Makefile` |
| GitHub CLI (`gh`) | Other tool | 2.105.0 | 2.106.0 | `Makefile` |

No LSP version changed in this run: gopls remains 0.24.0 and pyright remains 1.1.414. The updater also reported Go 1.27.4, Python 3.15.2, fzf 0.75.0, ripgrep 16.0.0, yq 4.54.3, Jira MCP 0.3.0, Agent Swarm MCP revision `d1f15f419a560494496d6e80b1f4aea6857c7014`, pip-audit 2.10.1, govulncheck 1.10.0, and Ruff 0.17.6; these are unchanged from the open PR branch.

---

## CVE review

No new LSP or CVE fix was identified in the three-value delta from PR #29. The existing PR's Go 1.27.3 → 1.27.4 change is independently confirmed to fix 12 CVEs and remains part of the combined PR:

| CVE | OSV / Go vulnerability record | Affected / fixed Go 1.27 versions |
|---|---|---|
| CVE-2026-97033 | [GO-2026-6858](https://api.osv.dev/v1/vulns/GO-2026-6858) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97034 | [GO-2026-6857](https://api.osv.dev/v1/vulns/GO-2026-6857) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97035 | [GO-2026-6856](https://api.osv.dev/v1/vulns/GO-2026-6856) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97036 | [GO-2026-6855](https://api.osv.dev/v1/vulns/GO-2026-6855) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97037 | [GO-2026-6854](https://api.osv.dev/v1/vulns/GO-2026-6854) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97038 | [GO-2026-6853](https://api.osv.dev/v1/vulns/GO-2026-6853) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97039 | [GO-2026-6852](https://api.osv.dev/v1/vulns/GO-2026-6852) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97040 | [GO-2026-6851](https://api.osv.dev/v1/vulns/GO-2026-6851) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97041 | [GO-2026-6850](https://api.osv.dev/v1/vulns/GO-2026-6850) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97042 | [GO-2026-6849](https://api.osv.dev/v1/vulns/GO-2026-6849) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97043 | [GO-2026-6848](https://api.osv.dev/v1/vulns/GO-2026-6848) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |
| CVE-2026-97054 | [GO-2026-6859](https://api.osv.dev/v1/vulns/GO-2026-6859) | 1.27.0-0 through before 1.27.4; fixed in 1.27.4 |

The Go 1.27.4 release history is documented at [go.dev](https://go.dev/doc/devel/release#go1.27.4). The original November plan records additional advisory checks and their sources.

---

## PR threshold

The batch meets the PR threshold because OpenCode changes from 2.1.4 on `main` to 2.4.2. The existing PR also contains multiple tool updates and the Go 1.27.4 security fixes noted above. The qualifying work is added to ACM-51101 / PR #29 rather than duplicated.

---

## Implementation and validation

1. Reuse Jira task ACM-51101 and existing branch `ACM-51101/update-dependency-pins-nov-2026`.
2. Run `make update-deps`; review the complete diff and confirm only intended version pins and this plan are included.
3. Run `bash tests/test_lsp_version_pinning.sh`, `bash tests/test_standalone_provider_secrets.sh`, `make lint`, `make -n build-opencode`, shell syntax checks for `scripts/*.sh` and `tests/*.sh`, and `git diff --check`.
4. Commit and push the update to the existing branch, then verify PR #29 still targets `main` and points at the pushed head. Do not merge the PR.
5. Record the verified commit and PR URL in ACM-51101 and request an agent review.

## Validation results

- `make update-deps` — passed; returned the versions listed above.
- `bash tests/test_lsp_version_pinning.sh` — passed (41 passed, 0 failed).
- `bash tests/test_standalone_provider_secrets.sh` — passed.
- `PATH=/tmp/opencode/ruff-0.17.6/bin:$PATH make lint` — passed; Ruff reported all checks passed and the shell syntax loop completed.
- `make -n build-opencode` — passed; the dry run propagated the updated OpenCode, Go, and Python build pins.
- Explicit `bash -n` checks for `scripts/*.sh` and `tests/*.sh` — passed.
- `git diff --check` — passed.
