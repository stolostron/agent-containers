#!/usr/bin/env bash
# test_lsp_version_pinning.sh — verify LSP version pinning is correctly wired
# across Containerfile.agents, Makefile, and scripts/build.sh.
#
# Run: bash tests/test_lsp_version_pinning.sh
# Exit 0 on all pass; non-zero on any failure.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINERFILE="${REPO_ROOT}/containerfiles/Containerfile.agents"
MAKEFILE="${REPO_ROOT}/Makefile"
BUILD_SH="${REPO_ROOT}/scripts/build.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1"; ((FAIL++)) || true; }

echo ""
echo "=== LSP version-pinning wiring tests ==="
echo ""

# --------------------------------------------------------------------------
# Containerfile.agents checks
# --------------------------------------------------------------------------
echo "-- Containerfile.agents --"

if grep -qP '^ARG GOPLS_VERSION' "$CONTAINERFILE"; then
    pass "ARG GOPLS_VERSION declared"
else
    fail "ARG GOPLS_VERSION not declared"
fi

if grep -qP '^ARG PYRIGHT_VERSION' "$CONTAINERFILE"; then
    pass "ARG PYRIGHT_VERSION declared"
else
    fail "ARG PYRIGHT_VERSION not declared"
fi

if grep -qF 'gopls@v${GOPLS_VERSION}' "$CONTAINERFILE" || grep -qF 'gopls@${GOPLS_VERSION}' "$CONTAINERFILE"; then
    pass "gopls install uses \${GOPLS_VERSION}"
else
    fail "gopls install does not reference \${GOPLS_VERSION}"
fi

if grep -qF 'pyright==${PYRIGHT_VERSION}' "$CONTAINERFILE"; then
    pass "pyright install uses \${PYRIGHT_VERSION}"
else
    fail "pyright install does not reference \${PYRIGHT_VERSION}"
fi

# ARG must be re-declared inside base-runtimes stage (between FROM base-runtimes and next FROM)
_base_runtimes_args=$(awk '/^FROM.*AS base-runtimes/{found=1; next} found && /^FROM /{exit} found{print}' "$CONTAINERFILE")

if echo "$_base_runtimes_args" | grep -qP '^ARG GOPLS_VERSION'; then
    pass "GOPLS_VERSION ARG re-declared in base-runtimes stage"
else
    fail "GOPLS_VERSION ARG not re-declared in base-runtimes stage"
fi

if echo "$_base_runtimes_args" | grep -qP '^ARG PYRIGHT_VERSION'; then
    pass "PYRIGHT_VERSION ARG re-declared in base-runtimes stage"
else
    fail "PYRIGHT_VERSION ARG not re-declared in base-runtimes stage"
fi

for scanner in PIP_AUDIT GOVULNCHECK; do
    if echo "$_base_runtimes_args" | grep -qP "^ARG ${scanner}_VERSION"; then
        pass "${scanner}_VERSION ARG re-declared in base-runtimes stage"
    else
        fail "${scanner}_VERSION ARG not re-declared in base-runtimes stage"
    fi
done

# Default values must be set (version pinned)
if grep -qP '^ARG GOPLS_VERSION=\d' "$CONTAINERFILE"; then
    pass "GOPLS_VERSION has a default value pinned"
else
    fail "GOPLS_VERSION has no default value (not pinned)"
fi

if grep -qP '^ARG PYRIGHT_VERSION=\d' "$CONTAINERFILE"; then
    pass "PYRIGHT_VERSION has a default value pinned"
else
    fail "PYRIGHT_VERSION has no default value (not pinned)"
fi

for scanner in PIP_AUDIT GOVULNCHECK; do
    if grep -qP "^ARG ${scanner}_VERSION=" "$CONTAINERFILE"; then
        pass "${scanner}_VERSION has a default value pinned"
    else
        fail "${scanner}_VERSION has no Containerfile pin"
    fi
done

if grep -qF 'govulncheck@v${GOVULNCHECK_VERSION}' "$CONTAINERFILE" && grep -qF '/usr/local/bin/govulncheck -version' "$CONTAINERFILE"; then
    pass "govulncheck install and build-time validation are pinned"
else
    fail "govulncheck install or build-time validation is not pinned"
fi

if grep -qF 'pip-audit==${PIP_AUDIT_VERSION}' "$CONTAINERFILE" && grep -qF 'pip-audit --version' "$CONTAINERFILE"; then
    pass "pip-audit install and build-time validation are pinned"
else
    fail "pip-audit install or build-time validation is not pinned"
fi

echo ""

# --------------------------------------------------------------------------
# Makefile checks
# --------------------------------------------------------------------------
echo "-- Makefile --"

if grep -qP '^GOPLS_VERSION\s+\?=' "$MAKEFILE"; then
    pass "GOPLS_VERSION variable declared in Makefile"
else
    fail "GOPLS_VERSION variable not declared in Makefile"
fi

if grep -qP '^PYRIGHT_VERSION\s+\?=' "$MAKEFILE"; then
    pass "PYRIGHT_VERSION variable declared in Makefile"
else
    fail "PYRIGHT_VERSION variable not declared in Makefile"
fi

for scanner in PIP_AUDIT GOVULNCHECK; do
    if grep -qP "^${scanner}_VERSION\s+\?=" "$MAKEFILE"; then
        pass "${scanner}_VERSION variable declared in Makefile"
    else
        fail "${scanner}_VERSION variable not declared in Makefile"
    fi
    if grep -qF "${scanner}_VERSION=\$(${scanner}_VERSION)" "$MAKEFILE"; then
        pass "${scanner}_VERSION passed to build.sh in Makefile"
    else
        fail "${scanner}_VERSION not passed to build.sh in Makefile"
    fi
done

# GOPLS_VERSION passed to build.sh invocation
if grep -qP 'GOPLS_VERSION=\$\(GOPLS_VERSION\)' "$MAKEFILE"; then
    pass "GOPLS_VERSION passed to build.sh in Makefile"
else
    fail "GOPLS_VERSION not passed to build.sh in Makefile"
fi

if grep -qP 'PYRIGHT_VERSION=\$\(PYRIGHT_VERSION\)' "$MAKEFILE"; then
    pass "PYRIGHT_VERSION passed to build.sh in Makefile"
else
    fail "PYRIGHT_VERSION not passed to build.sh in Makefile"
fi

# update-deps fetches gopls latest
if grep -qP 'LATEST_GOPLS' "$MAKEFILE" || grep -qP 'gopls' "$MAKEFILE"; then
    if grep -qP 'LATEST_GOPLS\s*:=' "$MAKEFILE"; then
        pass "update-deps fetches LATEST_GOPLS"
    else
        fail "update-deps does not fetch LATEST_GOPLS"
    fi
else
    fail "update-deps has no gopls fetch"
fi

# update-deps fetches pyright latest
if grep -qP 'LATEST_PYRIGHT\s*:=' "$MAKEFILE"; then
    pass "update-deps fetches LATEST_PYRIGHT"
else
    fail "update-deps does not fetch LATEST_PYRIGHT"
fi

# update-deps sed-updates GOPLS_VERSION in Makefile
if grep -qP "GOPLS_VERSION" "$MAKEFILE" && grep -qP "sed.*GOPLS_VERSION.*LATEST_GOPLS" "$MAKEFILE"; then
    pass "update-deps sed-updates GOPLS_VERSION in Makefile"
else
    fail "update-deps does not sed-update GOPLS_VERSION"
fi

# update-deps sed-updates PYRIGHT_VERSION in Makefile
if grep -qP "sed.*PYRIGHT_VERSION.*LATEST_PYRIGHT" "$MAKEFILE"; then
    pass "update-deps sed-updates PYRIGHT_VERSION in Makefile"
else
    fail "update-deps does not sed-update PYRIGHT_VERSION"
fi

for scanner in PIP_AUDIT GOVULNCHECK; do
    latest="LATEST_${scanner}"
    if grep -qP "${latest}\s*:=" "$MAKEFILE"; then
        pass "update-deps fetches ${latest}"
    else
        fail "update-deps does not fetch ${latest}"
    fi
    if grep -qP "sed.*${scanner}_VERSION.*${latest}" "$MAKEFILE"; then
        pass "update-deps sed-updates ${scanner}_VERSION in Makefile"
    else
        fail "update-deps does not sed-update ${scanner}_VERSION"
    fi
done

if grep -qF 'mktemp Makefile.' "$MAKEFILE" && grep -qF 'mv "$$tmpfile" Makefile' "$MAKEFILE"; then
    pass "update-deps applies substitutions through an atomic temporary file"
else
    fail "update-deps does not use an atomic temporary file"
fi

echo ""

# --------------------------------------------------------------------------
# build.sh checks
# --------------------------------------------------------------------------
echo "-- scripts/build.sh --"

if grep -qP '\-\-build-arg GOPLS_VERSION=' "$BUILD_SH"; then
    pass "--build-arg GOPLS_VERSION= present in build.sh"
else
    fail "--build-arg GOPLS_VERSION= not in build.sh"
fi

if grep -qP '\-\-build-arg PYRIGHT_VERSION=' "$BUILD_SH"; then
    pass "--build-arg PYRIGHT_VERSION= present in build.sh"
else
    fail "--build-arg PYRIGHT_VERSION= not in build.sh"
fi

# build.sh should use the env variable (not a hardcoded version)
if grep -q 'build-arg GOPLS_VERSION="${GOPLS_VERSION' "$BUILD_SH"; then
    pass "--build-arg GOPLS_VERSION uses \${GOPLS_VERSION:-...} in build.sh"
else
    fail "--build-arg GOPLS_VERSION does not use \${GOPLS_VERSION:-...} in build.sh"
fi

if grep -q 'build-arg PYRIGHT_VERSION="${PYRIGHT_VERSION' "$BUILD_SH"; then
    pass "--build-arg PYRIGHT_VERSION uses \${PYRIGHT_VERSION:-...} in build.sh"
else
    fail "--build-arg PYRIGHT_VERSION does not use \${PYRIGHT_VERSION:-...} in build.sh"
fi

for scanner in PIP_AUDIT GOVULNCHECK; do
    if grep -qP "\-\-build-arg ${scanner}_VERSION=" "$BUILD_SH" && grep -q "build-arg ${scanner}_VERSION=\"\${${scanner}_VERSION" "$BUILD_SH"; then
        pass "build.sh passes ${scanner}_VERSION from the environment"
    else
        fail "build.sh does not pass ${scanner}_VERSION from the environment"
    fi
done

echo ""

# --------------------------------------------------------------------------
# Runtime availability checks
# --------------------------------------------------------------------------
echo "-- Runtime availability --"

if grep -qF 'GOBIN=/usr/local/bin' "$CONTAINERFILE" && grep -qF '/usr/local/bin/govulncheck' "$CONTAINERFILE"; then
    pass "govulncheck is installed in a shared system executable path"
else
    fail "govulncheck is not installed in a shared system executable path"
fi

if ! grep -qF 'ENV GOPATH=' "$CONTAINERFILE" && grep -qF 'GOPATH=/home/node/go' "$CONTAINERFILE"; then
    pass "runtime Go caches use per-user defaults and gopls remains on its persistent path"
else
    fail "runtime Go cache configuration uses a shared GOPATH"
fi

if grep -qF 'usable by both `node` and' "${REPO_ROOT}/docs/CVE_SCANNERS.md"; then
    pass "scanner availability for node and sandbox is documented"
else
    fail "scanner availability for node and sandbox is not documented"
fi

echo ""

# --------------------------------------------------------------------------
# plans/INDEX.md separator check
# --------------------------------------------------------------------------
echo "-- plans/INDEX.md --"

INDEX="${REPO_ROOT}/plans/INDEX.md"
if grep -qP '^# ──' "$INDEX"; then
    fail "plans/INDEX.md still contains # ── heading separators (should use ---)"
else
    pass "plans/INDEX.md uses --- separators (no # ── headings)"
fi

echo ""

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo "Results: ${PASS} passed, ${FAIL} failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
    exit 0
fi
