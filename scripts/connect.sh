#!/usr/bin/env bash
# connect.sh — port-forward an opencode K8s pod to localhost:4096
# Usage: connect.sh <opencode-golang|opencode-python>
#
# Finds the pod by label selector (Job pods have random name suffixes).
set -euo pipefail

APP="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/../.push-defaults"

if [[ ! -f "$DEFAULTS_FILE" ]]; then
    echo "Error: .push-defaults not found. Run a build target first." >&2
    exit 1
fi

NAMESPACE=$(grep '^NAMESPACE=' "$DEFAULTS_FILE" | cut -d= -f2- || true)

NS_FLAG=()
[[ -n "$NAMESPACE" ]] && NS_FLAG=(-n "$NAMESPACE")

POD=$(kubectl get pods "${NS_FLAG[@]}" -l "app=${APP}" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "$POD" ]]; then
    echo "Error: no running pod found with label app=${APP}" >&2
    echo "" >&2
    echo "Current pods:" >&2
    kubectl get pods "${NS_FLAG[@]}" -l "app=${APP}" 2>&1 >&2 || true
    exit 1
fi

echo ""
echo "=== Connect: ${APP} ==="
[[ -n "$NAMESPACE" ]] && echo "    Namespace: ${NAMESPACE}"
echo "    Found pod: ${POD}"
echo "    Forwarding -> localhost:4096"
echo "    Press Ctrl+C to stop"
echo ""

kubectl port-forward "${NS_FLAG[@]}" "pod/${POD}" 4096:4096
