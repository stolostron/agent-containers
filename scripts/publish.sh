#!/usr/bin/env bash
# publish.sh — build and push all images for a given agent (prompts once)
# Usage: publish.sh <agent>   where agent is "claude" or "gemini"
set -euo pipefail

AGENT="$1"  # claude | gemini

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
DEFAULTS_FILE="${REPO_ROOT}/.push-defaults"

case "$AGENT" in
    claude)
        IMAGES=("claude-code-golang" "claude-code-python")
        CONTAINERFILE="containerfiles/Containerfile.claude"
        ;;
    gemini)
        IMAGES=("gemini-cli-golang" "gemini-cli-python")
        CONTAINERFILE="containerfiles/Containerfile.gemini"
        ;;
    *)
        echo "Error: unknown agent '${AGENT}'. Use 'claude' or 'gemini'." >&2
        exit 1
        ;;
esac

# Load saved defaults
SAVED_REGISTRY=""
SAVED_IMAGE_TAG="latest"
if [[ -f "$DEFAULTS_FILE" ]]; then
    SAVED_REGISTRY=$(grep '^REGISTRY=' "$DEFAULTS_FILE" | cut -d= -f2- || true)
    SAVED_IMAGE_TAG=$(grep '^IMAGE_TAG=' "$DEFAULTS_FILE" | cut -d= -f2- || true)
    SAVED_IMAGE_TAG="${SAVED_IMAGE_TAG:-latest}"
fi

# Prompt once
echo ""
echo "=== Publish: ${AGENT} ==="

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

read -rp "Image tag [${SAVED_IMAGE_TAG}]: " IMAGE_TAG
IMAGE_TAG="${IMAGE_TAG:-$SAVED_IMAGE_TAG}"

# Save defaults (preserve IMAGE_PULL_SECRET and NAMESPACE if set)
{
    grep -v '^REGISTRY=' "$DEFAULTS_FILE" 2>/dev/null \
        | grep -v '^IMAGE_TAG=' || true
    echo "REGISTRY=${REGISTRY}"
    echo "IMAGE_TAG=${IMAGE_TAG}"
} > "${DEFAULTS_FILE}.tmp" && mv "${DEFAULTS_FILE}.tmp" "$DEFAULTS_FILE"

# Build all
for IMAGE_NAME in "${IMAGES[@]}"; do
    [[ "$IMAGE_NAME" == *golang ]] && LANG=golang || LANG=python
    FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    echo "Building ${FULL_IMAGE} ..."
    podman build \
      -f "${REPO_ROOT}/${CONTAINERFILE}" \
      --build-arg LANG="${LANG}" \
      --target final \
      -t "${FULL_IMAGE}" \
      "${REPO_ROOT}"
    echo "Built:   ${FULL_IMAGE}"
done

# Push all
for IMAGE_NAME in "${IMAGES[@]}"; do
    FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    echo "Pushing  ${FULL_IMAGE} ..."
    podman push "${FULL_IMAGE}"
    if [[ "$IMAGE_TAG" != "latest" ]]; then
        LATEST_IMAGE="${REGISTRY}/${IMAGE_NAME}:latest"
        echo "Tagging  ${FULL_IMAGE} -> ${LATEST_IMAGE}"
        podman tag "${FULL_IMAGE}" "${LATEST_IMAGE}"
        echo "Pushing  ${LATEST_IMAGE} ..."
        podman push "${LATEST_IMAGE}"
    fi
done

echo ""
echo "Done. Defaults saved to .push-defaults"
