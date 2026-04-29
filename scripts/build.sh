#!/usr/bin/env bash
# build.sh — prompt for registry/image_tag, build, save defaults
# Usage: build.sh <image-name> <containerfile>
set -euo pipefail

IMAGE_NAME="$1"    # e.g. opencode
CONTAINERFILE="$2" # e.g. containerfiles/Containerfile.opencode

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
DEFAULTS_FILE="${REPO_ROOT}/.push-defaults"

# Load saved defaults
SAVED_REGISTRY=""
SAVED_IMAGE_TAG="latest"
if [[ -f "$DEFAULTS_FILE" ]]; then
    SAVED_REGISTRY=$(grep '^REGISTRY=' "$DEFAULTS_FILE" | cut -d= -f2- || true)
    SAVED_IMAGE_TAG=$(grep '^IMAGE_TAG=' "$DEFAULTS_FILE" | cut -d= -f2- || true)
    SAVED_IMAGE_TAG="${SAVED_IMAGE_TAG:-latest}"
fi

echo ""
echo "=== Build: ${IMAGE_NAME} ==="

if [[ -n "$SAVED_REGISTRY" ]]; then
    read -rp "Registry  [${SAVED_REGISTRY}]: " REGISTRY
else
    read -rp "Registry: " REGISTRY
fi
REGISTRY="${REGISTRY:-$SAVED_REGISTRY}"

if [[ -z "$REGISTRY" ]]; then
    echo "Error: registry cannot be empty." >&2
    exit 1
fi

read -rp "IMAGE_TAG [${SAVED_IMAGE_TAG}]: " IMAGE_TAG
IMAGE_TAG="${IMAGE_TAG:-$SAVED_IMAGE_TAG}"

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Persist defaults before building (preserve IMAGE_PULL_SECRET and NAMESPACE if set)
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
  --build-arg GH_VERSION="${GH_VERSION:-2.74.0}" \
  --build-arg GO_VERSION="${GO_VERSION:-1.26.2}" \
  --build-arg OPENCODE_VERSION="${OPENCODE_VERSION:-1.14.20}" \
  --build-arg PYTHON_VERSION="${PYTHON_VERSION:-3.13.13}" \
  --build-arg PYTHON_BUILD="${PYTHON_BUILD:-20260414}" \
  -t "${FULL_IMAGE}" \
  "${REPO_ROOT}"

echo ""
echo "Built:   ${FULL_IMAGE}"
echo "Defaults saved to .push-defaults"
