#!/usr/bin/env bash
# deploy.sh — render and deploy a k8s YAML with live substitution
# Usage: deploy.sh <yaml-file> kubectl [secret-yaml]
set -euo pipefail

YAML_FILE="$1"
EXTRA="${2:-}"   # optional secret yaml to apply first

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/../.push-defaults"

if [[ ! -f "$DEFAULTS_FILE" ]]; then
    echo "Error: .push-defaults not found. Run a build target first." >&2
    exit 1
fi

# ── Read saved values ────────────────────────────────────────────────────────
_get() { grep "^${1}=" "$DEFAULTS_FILE" | cut -d= -f2- || true; }

REGISTRY=$(           _get REGISTRY)
IMAGE_TAG=$(          _get IMAGE_TAG);  IMAGE_TAG="${IMAGE_TAG:-latest}"
SAVED_NAMESPACE=$(    _get NAMESPACE)
SAVED_PULL_SECRET=$(  _get IMAGE_PULL_SECRET)
SAVED_PULL_SECRET_FILE=$(_get IMAGE_PULL_SECRET_FILE)

if [[ -z "$REGISTRY" ]]; then
    echo "Error: REGISTRY not set in .push-defaults. Run a build target first." >&2
    exit 1
fi

echo ""
echo "=== Deploy: $(basename "$YAML_FILE") ==="
echo "    Registry : ${REGISTRY}"
echo "    IMAGE_TAG: ${IMAGE_TAG}"

# ── Prompt: namespace ────────────────────────────────────────────────────────
if [[ -n "$SAVED_NAMESPACE" ]]; then
    read -rp "Namespace             [${SAVED_NAMESPACE}] (Enter=keep, '-'=clear): " INPUT
    if [[ "$INPUT" == "-" ]]; then
        NAMESPACE=""
    else
        NAMESPACE="${INPUT:-$SAVED_NAMESPACE}"
    fi
else
    read -rp "Namespace             (Enter for cluster default): " NAMESPACE
fi

# ── Prompt: imagePullSecret name ─────────────────────────────────────────────
if [[ -n "$SAVED_PULL_SECRET" ]]; then
    read -rp "imagePullSecret name  [${SAVED_PULL_SECRET}] (Enter=keep, '-'=clear): " INPUT
    if [[ "$INPUT" == "-" ]]; then
        IMAGE_PULL_SECRET=""
    else
        IMAGE_PULL_SECRET="${INPUT:-$SAVED_PULL_SECRET}"
    fi
else
    read -rp "imagePullSecret name  (Enter to skip): " IMAGE_PULL_SECRET
fi

# ── Prompt: imagePullSecret file ─────────────────────────────────────────────
if [[ -n "$SAVED_PULL_SECRET_FILE" ]]; then
    read -rp "imagePullSecret file  [${SAVED_PULL_SECRET_FILE}] (Enter=keep, '-'=clear): " INPUT
    if [[ "$INPUT" == "-" ]]; then
        IMAGE_PULL_SECRET_FILE=""
    else
        IMAGE_PULL_SECRET_FILE="${INPUT:-$SAVED_PULL_SECRET_FILE}"
    fi
else
    read -rp "imagePullSecret file  (Enter to skip): " IMAGE_PULL_SECRET_FILE
fi

# ── Persist updated defaults ─────────────────────────────────────────────────
{
    grep -v '^IMAGE_PULL_SECRET=' "$DEFAULTS_FILE" \
        | grep -v '^IMAGE_PULL_SECRET_FILE=' \
        | grep -v '^NAMESPACE=' || true
    [[ -n "$NAMESPACE"            ]] && echo "NAMESPACE=${NAMESPACE}"
    [[ -n "$IMAGE_PULL_SECRET"    ]] && echo "IMAGE_PULL_SECRET=${IMAGE_PULL_SECRET}"
    [[ -n "$IMAGE_PULL_SECRET_FILE" ]] && echo "IMAGE_PULL_SECRET_FILE=${IMAGE_PULL_SECRET_FILE}"
} > "${DEFAULTS_FILE}.tmp" && mv "${DEFAULTS_FILE}.tmp" "$DEFAULTS_FILE"

# ── Render YAML ──────────────────────────────────────────────────────────────
render() {
    local pull_block=""
    if [[ -n "$IMAGE_PULL_SECRET" ]]; then
        pull_block="  imagePullSecrets:\n    - name: ${IMAGE_PULL_SECRET}"
    fi

    if [[ -n "$IMAGE_PULL_SECRET" ]]; then
        sed \
            -e "s|REGISTRY|${REGISTRY}|g" \
            -e "s|IMAGE_TAG|${IMAGE_TAG}|g" \
            -e "s|  IMAGE_PULL_SECRET_BLOCK|${pull_block}|" \
            "$YAML_FILE"
    else
        sed \
            -e "s|REGISTRY|${REGISTRY}|g" \
            -e "s|IMAGE_TAG|${IMAGE_TAG}|g" \
            -e "/  IMAGE_PULL_SECRET_BLOCK/d" \
            "$YAML_FILE"
    fi
}

# ── Deploy ───────────────────────────────────────────────────────────────────
NS_FLAG=()
[[ -n "$NAMESPACE" ]] && NS_FLAG=(-n "$NAMESPACE")

[[ -n "$IMAGE_PULL_SECRET_FILE" ]] && kubectl apply "${NS_FLAG[@]}" -f "$IMAGE_PULL_SECRET_FILE"
[[ -n "$EXTRA" ]] && kubectl apply "${NS_FLAG[@]}" -f "$EXTRA"
render | kubectl apply "${NS_FLAG[@]}" -f -
