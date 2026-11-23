# Dependency Update Plan — 2026-11-23

**Jira:** [ACM-51101](https://redhat.atlassian.net/browse/ACM-51101)
**Repository:** `stolostron/agent-containers`
**Baseline:** `main` at `b32ed4f4a8206e5b411c7b961730ed4ecc0b2ec9`
**Topic branch:** `ACM-51101/update-dependency-pins-nov-2026`

---

## Comparison with the last recorded update

The most recent merged dependency update is PR [#28](https://github.com/stolostron/agent-containers/pull/28), commit `0d8e49d075b34ddc70a1e1a01e6f91869e5ccbee`, linked to ACM-49186 and merged 2026-10-26. No open dependency-update PR exists.

The open task ACM-51101 records a 2026-11-19 update attempt based on that same main baseline. Its proposed OpenCode version was 2.3.2; it did not include ripgrep. Validation stopped before a PR because Ruff 0.17.6 was unavailable. This run reuses ACM-51101 and reruns the updater from a clean `main` baseline; OpenCode is now 2.4.1 and ripgrep is newly included.

---

## Dependency changes

All changes below are in `Makefile`; no build wiring or other files were changed by the updater.

| Dependency/tool | Category | Previous | Proposed | Files |
|---|---|---:|---:|---|
| Go | Other tool / compiler toolchain | 1.27.3 | 1.27.4 | `Makefile` |
| Python build artifact | Other tool / runtime build | 20261026 | 20261110 | `Makefile` |
| Python | Other tool / runtime | 3.15.2 | 3.15.2 (unchanged) | `Makefile` |
| OpenCode CLI | OpenCode | 2.1.4 | 2.4.1 | `Makefile` |
| GitHub CLI (`gh`) | Other tool | 2.103.3 | 2.105.0 | `Makefile` |
| fzf | Other tool | 0.74.5 | 0.75.0 | `Makefile` |
| ripgrep | Other tool | 15.2.0 | 16.0.0 | `Makefile` |
| yq | Other tool | 4.54.1 | 4.54.3 | `Makefile` |
| govulncheck | Other tool | 1.9.0 | 1.10.0 | `Makefile` |
| Ruff | Other tool | 0.17.2 | 0.17.6 | `Makefile` |

Unchanged pins include gopls 0.24.0, pyright 1.1.414, Jira MCP 0.3.0, Agent Swarm MCP revision `d1f15f419a560494496d6e80b1f4aea6857c7014`, and pip-audit 2.10.1.

---

## Confirmed CVEs

The Go Vulnerability Database records each issue as affecting Go 1.27.0-0 through versions before 1.27.4 (the prior 1.27.3 pin is in the affected range); the fixed version for the Go 1.27 branch is 1.27.4. The same records list 1.26.11 as the fix for the 1.26 branch. Each linked OSV record is authoritative source evidence for its affected range and fixed versions; the matching NVD record is also linked.

| CVE | Go vulnerability record | Advisory/source |
|---|---|---|
| CVE-2026-97033 | [GO-2026-6858](https://api.osv.dev/v1/vulns/GO-2026-6858) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97033) |
| CVE-2026-97034 | [GO-2026-6857](https://api.osv.dev/v1/vulns/GO-2026-6857) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97034) |
| CVE-2026-97035 | [GO-2026-6856](https://api.osv.dev/v1/vulns/GO-2026-6856) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97035) |
| CVE-2026-97036 | [GO-2026-6855](https://api.osv.dev/v1/vulns/GO-2026-6855) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97036) |
| CVE-2026-97037 | [GO-2026-6854](https://api.osv.dev/v1/vulns/GO-2026-6854) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97037) |
| CVE-2026-97038 | [GO-2026-6853](https://api.osv.dev/v1/vulns/GO-2026-6853) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97038) |
| CVE-2026-97039 | [GO-2026-6852](https://api.osv.dev/v1/vulns/GO-2026-97039) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97039) |
| CVE-2026-97040 | [GO-2026-6851](https://api.osv.dev/v1/vulns/GO-2026-6851) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97040) |
| CVE-2026-97041 | [GO-2026-6850](https://api.osv.dev/v1/vulns/GO-2026-6850) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97041) |
| CVE-2026-97042 | [GO-2026-6849](https://api.osv.dev/v1/vulns/GO-2026-6849) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97042) |
| CVE-2026-97043 | [GO-2026-6848](https://api.osv.dev/v1/vulns/GO-2026-6848) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97043) |
| CVE-2026-97054 | [GO-2026-6859](https://api.osv.dev/v1/vulns/GO-2026-6859) | [NVD](https://nvd.nist.gov/vuln/detail/CVE-2026-97054) |

Other advisory checks:

- GitHub CLI CVE-2026-72924 ([GHSA-vfhh-p7hm-pxfh](https://github.com/cli/cli/security/advisories/GHSA-vfhh-p7hm-pxfh)) lists v2.98.0 as patched; the existing v2.103.3 baseline is already beyond that fix.
- fzf CVE-2026-121716 ([GHSA-w6x2-f5m4-xw82](https://github.com/junegunn/fzf/security/advisories/GHSA-w6x2-f5m4-xw82)) and CVE-2026-121717 ([GHSA-7rj6-7pqx-v7rm](https://github.com/junegunn/fzf/security/advisories/GHSA-7rj6-7pqx-v7rm)) affect versions through 0.74.4 and are fixed in 0.74.5; the baseline is already fixed, so these are not attributed to this update.
- yq advisories [GHSA-h2cv-65fq-jgrp](https://github.com/mikefarah/yq/security/advisories/GHSA-h2cv-65fq-jgrp) (4.54.1 fixed in 4.54.2) and [GHSA-c3cc-5w96-mw9r](https://github.com/mikefarah/yq/security/advisories/GHSA-c3cc-5w96-mw9r) (versions through 4.54.1 fixed in 4.54.3) have no CVE identifiers. The yq update addresses these advisories, but they are not counted as CVEs.
- No CVE fix was confirmed for the ripgrep, govulncheck, or Ruff version changes in the reviewed repository advisories.

Go release notes document the Go 1.27.4 security fixes: [Go 1.27.4 release history](https://go.dev/doc/devel/release#go1.27.4).

---

## PR threshold

The PR threshold is met because OpenCode changes from 2.1.4 to 2.4.1, eight distinct non-OpenCode dependencies/tools have version or build-artifact changes, and Go 1.27.4 is documented as fixing 12 CVEs that affect the pinned Go 1.27.3. The yq advisories provide additional security context but do not count toward the CVE criterion because neither has an assigned CVE.

---

## Implementation and validation

1. Reuse Jira task ACM-51101; keep the updater output and this plan as the only intended changes.
2. Create topic branch `ACM-51101/update-dependency-pins-nov-2026`.
3. Review the full diff for scope, versions, accidental downgrades, and generated files.
4. Run `bash tests/test_lsp_version_pinning.sh`, `bash tests/test_standalone_provider_secrets.sh`, `make lint`, `make -n build-opencode`, shell syntax checks for `scripts/*.sh` and `tests/*.sh`, and `git diff --check`.
5. Resolve any safely fixable failures and rerun the relevant checks; do not push or open a PR if required validation remains blocked.
6. Commit with ACM-51101 in the branch/commit context, push, and open (never merge) a PR against `main`.

---

## Validation results

- `make update-deps` — passed; updater returned the versions recorded above.
- `bash tests/test_lsp_version_pinning.sh` — passed (41 passed, 0 failed).
- `bash tests/test_standalone_provider_secrets.sh` — passed.
- `make lint` — passed with Ruff 0.17.6 installed in an isolated `/tmp/opencode` prefix; `ruff check scripts tests` reported all checks passed, and the target's shell syntax loop completed.
- `make -n build-opencode` — passed; dry run propagated the updated versions to `scripts/build.sh`.
- Explicit `bash -n` checks for `scripts/*.sh` and `tests/*.sh` — passed.
- `git diff --check` — passed.
