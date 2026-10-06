#!/usr/bin/env bash
# push.sh — push a previously built image using explicit values or saved defaults
# Usage: push.sh <image-name>
set -euo pipefail

IMAGE_NAME="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AC_DEFAULTS="${SCRIPT_DIR}/../../agent-swarm/.push-defaults"
if [[ -f "$AC_DEFAULTS" ]]; then
    DEFAULTS_FILE="$AC_DEFAULTS"
else
    DEFAULTS_FILE="${SCRIPT_DIR}/../.push-defaults"
fi

SAVED_REGISTRY=""
SAVED_IMAGE_TAG=""
if [[ -f "$DEFAULTS_FILE" ]]; then
    SAVED_REGISTRY=$(grep '^REGISTRY=' "$DEFAULTS_FILE" | cut -d= -f2- || true)
    SAVED_IMAGE_TAG=$(grep -m1 '^IMAGE_TAG=' "$DEFAULTS_FILE" | cut -d= -f2- || true)
fi
REGISTRY="${REGISTRY:-$SAVED_REGISTRY}"
IMAGE_TAG="${IMAGE_TAG:-${SAVED_IMAGE_TAG:-latest}}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

if [[ -z "$REGISTRY" ]]; then
    echo "Error: REGISTRY not set in .push-defaults. Run a build target first." >&2
    exit 1
fi

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "=== Push: ${IMAGE_NAME} ==="
echo "Pushing  ${FULL_IMAGE} ..."
if [[ -n "${PUSH_DIGEST_FILE:-}" ]]; then
    DIGEST_TMP=$(mktemp)
    trap 'rm -f "$DIGEST_TMP"' EXIT
    podman push --digestfile "${DIGEST_TMP}" "${FULL_IMAGE}"
    python3 "${SCRIPT_DIR}/image_release.py" record-push \
        "${PUSH_DIGEST_FILE}" "${DIGEST_TMP}" "${REGISTRY}" "${IMAGE_NAME}"
else
    podman push "${FULL_IMAGE}"
fi

if [[ "$IMAGE_TAG" != "latest" && "${PUSH_LATEST:-1}" != "0" ]]; then
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
