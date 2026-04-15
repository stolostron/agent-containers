#!/usr/bin/env bash
# deploy.sh — render and deploy a k8s YAML with live substitution
# Usage: deploy.sh <yaml-file> [secret-yaml] [secret-yaml-2]
#
# Environment variables (optional):
#   OPENCODE_MODEL   — model to use (default: google/gemini-2.5-pro)
#   OPENCODE_PROMPT  — prompt text (default: "hello world")
#   CRONJOB_SCHEDULE — cron schedule for CronJob manifests (default: "0 * * * *")
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

# ── Configurable model/prompt/schedule ────────────────────────────────────────
OPENCODE_MODEL="${OPENCODE_MODEL:-google/gemini-2.5-pro}"
OPENCODE_PROMPT="${OPENCODE_PROMPT:-hello world}"
CRONJOB_SCHEDULE="${CRONJOB_SCHEDULE:-0 * * * *}"

echo ""
echo "=== Deploy: $(basename "$YAML_FILE") ==="
echo "    Registry : ${REGISTRY}"
echo "    IMAGE_TAG: ${IMAGE_TAG}"
echo "    Model    : ${OPENCODE_MODEL}"
echo "    Prompt   : ${OPENCODE_PROMPT}"

# Show schedule for CronJob manifests
if grep -q 'kind: CronJob' "$YAML_FILE" 2>/dev/null; then
    echo "    Schedule : ${CRONJOB_SCHEDULE}"
fi

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

    local sed_args=(
        -e "s|REGISTRY|${REGISTRY}|g"
        -e "s|IMAGE_TAG|${IMAGE_TAG}|g"
        -e "s|OPENCODE_MODEL_VALUE|${OPENCODE_MODEL}|g"
        -e "s|OPENCODE_PROMPT_VALUE|${OPENCODE_PROMPT}|g"
        -e "s|CRONJOB_SCHEDULE|${CRONJOB_SCHEDULE}|g"
    )

    if [[ -n "$IMAGE_PULL_SECRET" ]]; then
        sed "${sed_args[@]}" \
            -e "s|  IMAGE_PULL_SECRET_BLOCK|${pull_block}|" \
            "$YAML_FILE"
    else
        sed "${sed_args[@]}" \
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

# Deployments support in-place updates; Jobs and Pods are immutable.
if grep -q 'kind: Deployment' "$YAML_FILE" 2>/dev/null; then
    render | kubectl apply "${NS_FLAG[@]}" -f -
else
    render | kubectl delete "${NS_FLAG[@]}" -f - --ignore-not-found
    render | kubectl apply "${NS_FLAG[@]}" -f -
fi
