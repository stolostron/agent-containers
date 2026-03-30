#!/usr/bin/env bash
# push.sh — push a previously built image using saved registry/image_tag
# Usage: push.sh <image-name>
set -euo pipefail

IMAGE_NAME="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/../.push-defaults"

if [[ ! -f "$DEFAULTS_FILE" ]]; then
    echo "Error: .push-defaults not found. Run a build target first." >&2
    exit 1
fi

REGISTRY=$(grep '^REGISTRY=' "$DEFAULTS_FILE" | cut -d= -f2- || true)
IMAGE_TAG=$(grep '^IMAGE_TAG=' "$DEFAULTS_FILE" | cut -d= -f2- || true)
IMAGE_TAG="${IMAGE_TAG:-latest}"

if [[ -z "$REGISTRY" ]]; then
    echo "Error: REGISTRY not set in .push-defaults. Run a build target first." >&2
    exit 1
fi

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "=== Push: ${IMAGE_NAME} ==="
echo "Pushing  ${FULL_IMAGE} ..."
podman push "${FULL_IMAGE}"

if [[ "$IMAGE_TAG" != "latest" ]]; then
    LATEST_IMAGE="${REGISTRY}/${IMAGE_NAME}:latest"
    echo "Tagging  ${FULL_IMAGE} -> ${LATEST_IMAGE}"
    podman tag "${FULL_IMAGE}" "${LATEST_IMAGE}"
    echo "Pushing  ${LATEST_IMAGE} ..."
    podman push "${LATEST_IMAGE}"
fi

echo ""
echo "Pushed:  ${FULL_IMAGE}"
if [[ "$IMAGE_TAG" != "latest" ]]; then
    echo "Pushed:  ${REGISTRY}/${IMAGE_NAME}:latest"
fi
