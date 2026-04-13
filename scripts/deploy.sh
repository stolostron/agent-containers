#!/usr/bin/env bash
# deploy.sh — render and deploy a k8s YAML with live substitution
# Usage: deploy.sh <yaml-file> [secret-yaml] [secret-yaml-2]
set -euo pipefail

YAML_FILE="$1"
EXTRA="${2:-}"       # optional secret yaml to apply first
EXTRA2="${3:-}"      # optional second secret yaml to apply first

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/../.push-defaults"

if [[ ! -f "$DEFAULTS_FILE" ]]; then
    echo "Error: .push-defaults not found. Run a build target first." >&2
    exit 1
fi

# ── Read saved values ────────────────────────────────────────────────────────
_get() { grep "^${1}=" "$DEFAULTS_FILE" | cut -d= -f2- || true; }

REGISTRY=$(              _get REGISTRY)
IMAGE_TAG=$(             _get IMAGE_TAG);  IMAGE_TAG="${IMAGE_TAG:-latest}"
SAVED_NAMESPACE=$(       _get NAMESPACE)
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
# Skip prompts when DEPLOY_NO_PROMPT=1 (used when chaining multiple deploys)
if [[ "${DEPLOY_NO_PROMPT:-0}" == "1" ]]; then
    NAMESPACE="${SAVED_NAMESPACE}"
    IMAGE_PULL_SECRET_FILE="${SAVED_PULL_SECRET_FILE}"
    echo "    Namespace: ${NAMESPACE:-<cluster default>}"
    echo "    imagePullSecret file: ${IMAGE_PULL_SECRET_FILE:-<none>}"
else
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
fi

# ── Extract pull secret name from file ───────────────────────────────────────
IMAGE_PULL_SECRET=""
if [[ -n "$IMAGE_PULL_SECRET_FILE" && -f "$IMAGE_PULL_SECRET_FILE" ]]; then
    IMAGE_PULL_SECRET=$(grep -A5 '^metadata:' "$IMAGE_PULL_SECRET_FILE" | grep '^\s*name:' | head -1 | awk '{print $2}')
fi

# ── Persist updated defaults ─────────────────────────────────────────────────
{
    grep -v '^IMAGE_PULL_SECRET_FILE=' "$DEFAULTS_FILE" \
        | grep -v '^NAMESPACE=' || true
    [[ -n "$NAMESPACE"               ]] && echo "NAMESPACE=${NAMESPACE}"
    [[ -n "$IMAGE_PULL_SECRET_FILE"  ]] && echo "IMAGE_PULL_SECRET_FILE=${IMAGE_PULL_SECRET_FILE}"
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
if [[ -n "$NAMESPACE" ]]; then
    NS_FLAG=(-n "$NAMESPACE")
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        echo "    Creating namespace: ${NAMESPACE}"
        kubectl create namespace "$NAMESPACE"
    fi
fi

[[ -n "$IMAGE_PULL_SECRET_FILE" ]] && kubectl apply "${NS_FLAG[@]}" -f "$IMAGE_PULL_SECRET_FILE"
[[ -n "$EXTRA"  ]] && kubectl apply "${NS_FLAG[@]}" -f "$EXTRA"
[[ -n "$EXTRA2" ]] && kubectl apply "${NS_FLAG[@]}" -f "$EXTRA2"
render | kubectl apply "${NS_FLAG[@]}" -f -
