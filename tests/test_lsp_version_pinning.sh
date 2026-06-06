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

if grep -qP '^ARG MAKE_LS_VERSION' "$CONTAINERFILE"; then
    pass "ARG MAKE_LS_VERSION declared"
else
    fail "ARG MAKE_LS_VERSION not declared"
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

if grep -qF 'make-ls@v${MAKE_LS_VERSION}' "$CONTAINERFILE"; then
    pass "make-ls install uses \${MAKE_LS_VERSION}"
else
    fail "make-ls install does not reference \${MAKE_LS_VERSION}"
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

if echo "$_base_runtimes_args" | grep -qP '^ARG MAKE_LS_VERSION'; then
    pass "MAKE_LS_VERSION ARG re-declared in base-runtimes stage"
else
    fail "MAKE_LS_VERSION ARG not re-declared in base-runtimes stage"
fi

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

if grep -qP '^ARG MAKE_LS_VERSION=\d' "$CONTAINERFILE"; then
    pass "MAKE_LS_VERSION has a default value pinned"
else
    fail "MAKE_LS_VERSION has no default value (not pinned)"
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

if grep -qP '^MAKE_LS_VERSION\s+\?=' "$MAKEFILE"; then
    pass "MAKE_LS_VERSION variable declared in Makefile"
else
    fail "MAKE_LS_VERSION variable not declared in Makefile"
fi

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

if grep -qP 'MAKE_LS_VERSION=\$\(MAKE_LS_VERSION\)' "$MAKEFILE"; then
    pass "MAKE_LS_VERSION passed to build.sh in Makefile"
else
    fail "MAKE_LS_VERSION not passed to build.sh in Makefile"
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

# update-deps fetches make-ls latest
if grep -qP 'LATEST_MAKE_LS\s*:=' "$MAKEFILE"; then
    pass "update-deps fetches LATEST_MAKE_LS"
else
    fail "update-deps does not fetch LATEST_MAKE_LS"
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

# update-deps sed-updates MAKE_LS_VERSION in Makefile
if grep -qP "sed.*MAKE_LS_VERSION.*LATEST_MAKE_LS" "$MAKEFILE"; then
    pass "update-deps sed-updates MAKE_LS_VERSION in Makefile"
else
    fail "update-deps does not sed-update MAKE_LS_VERSION"
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

if grep -qP '\-\-build-arg MAKE_LS_VERSION=' "$BUILD_SH"; then
    pass "--build-arg MAKE_LS_VERSION= present in build.sh"
else
    fail "--build-arg MAKE_LS_VERSION= not in build.sh"
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

if grep -q 'build-arg MAKE_LS_VERSION="${MAKE_LS_VERSION' "$BUILD_SH"; then
    pass "--build-arg MAKE_LS_VERSION uses \${MAKE_LS_VERSION:-...} in build.sh"
else
    fail "--build-arg MAKE_LS_VERSION does not use \${MAKE_LS_VERSION:-...} in build.sh"
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
