#!/usr/bin/env bash
# build.sh — build a container image, optionally prompting for registry/tag
# Usage: build.sh <image-name> <containerfile>
# Set NOPROMPT=1 to skip interactive prompts and use saved defaults.
set -euo pipefail

IMAGE_NAME="$1"
CONTAINERFILE="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
AC_DEFAULTS="${REPO_ROOT}/../agent-swarm/.push-defaults"
if [[ -f "$AC_DEFAULTS" ]]; then
    DEFAULTS_FILE="$AC_DEFAULTS"
else
    DEFAULTS_FILE="${REPO_ROOT}/.push-defaults"
fi

SAVED_REGISTRY=""
SAVED_IMAGE_TAG="latest"
if [[ -f "$DEFAULTS_FILE" ]]; then
    SAVED_REGISTRY=$(grep '^REGISTRY=' "$DEFAULTS_FILE" | cut -d= -f2- || true)
    SAVED_IMAGE_TAG=$(grep '^IMAGE_TAG=' "$DEFAULTS_FILE" | cut -d= -f2- || true)
    SAVED_IMAGE_TAG="${SAVED_IMAGE_TAG:-latest}"
fi

echo ""
echo "=== Build: ${IMAGE_NAME} ==="

if [[ "${NOPROMPT:-}" == "1" ]]; then
    REGISTRY="$SAVED_REGISTRY"
    IMAGE_TAG="$SAVED_IMAGE_TAG"
else
    if [[ -n "$SAVED_REGISTRY" ]]; then
        read -rp "Registry  [${SAVED_REGISTRY}]: " REGISTRY
    else
        read -rp "Registry: " REGISTRY
    fi
    REGISTRY="${REGISTRY:-$SAVED_REGISTRY}"
    read -rp "IMAGE_TAG [${SAVED_IMAGE_TAG}]: " IMAGE_TAG
    IMAGE_TAG="${IMAGE_TAG:-$SAVED_IMAGE_TAG}"
fi

if [[ -z "$REGISTRY" ]]; then
    echo "Error: registry cannot be empty." >&2
    exit 1
fi

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Persist REGISTRY + IMAGE_TAG to defaults file
{
    grep -v '^REGISTRY=' "$DEFAULTS_FILE" 2>/dev/null \
        | grep -v '^IMAGE_TAG=' || true
    echo "REGISTRY=${REGISTRY}"
    echo "IMAGE_TAG=${IMAGE_TAG}"
} > "${DEFAULTS_FILE}.tmp" && mv "${DEFAULTS_FILE}.tmp" "$DEFAULTS_FILE"

echo ""
echo "Building ${FULL_IMAGE} ..."
podman build \
  -f "${REPO_ROOT}/${CONTAINERFILE}" \
  --build-arg GH_VERSION="${GH_VERSION:-2.92.0}" \
  --build-arg GO_VERSION="${GO_VERSION:-1.26.2}" \
  --build-arg OPENCODE_VERSION="${OPENCODE_VERSION:-1.14.29}" \
  --build-arg CRUSH_VERSION="${CRUSH_VERSION:-0.65.3}" \
  --build-arg PYTHON_VERSION="${PYTHON_VERSION:-3.14.4}" \
  --build-arg PYTHON_BUILD="${PYTHON_BUILD:-20260414}" \
  --build-arg FZF_VERSION="${FZF_VERSION:-0.72.0}" \
  --build-arg RG_VERSION="${RG_VERSION:-15.1.0}" \
  --build-arg JIRA_MCP_VERSION="${JIRA_MCP_VERSION:-0.1.0}" \
  --build-arg GOPLS_VERSION="${GOPLS_VERSION:-0.22.0}" \
  --build-arg PYRIGHT_VERSION="${PYRIGHT_VERSION:-1.1.409}" \
  --build-arg MAKE_LS_VERSION="${MAKE_LS_VERSION:-0.1.9}" \
  --target "${IMAGE_NAME}" \
  -t "${FULL_IMAGE}" \
  "${REPO_ROOT}"

echo ""
echo "Built:   ${FULL_IMAGE}"
echo "Defaults saved to ${DEFAULTS_FILE}"
