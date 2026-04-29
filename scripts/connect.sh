#!/usr/bin/env bash
# connect.sh — port-forward an opencode K8s pod to localhost:4096
# Usage: connect.sh <opencode>
set -euo pipefail

POD="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/../.push-defaults"

if [[ ! -f "$DEFAULTS_FILE" ]]; then
    echo "Error: .push-defaults not found. Run a build target first." >&2
    exit 1
fi

NAMESPACE=$(grep '^NAMESPACE=' "$DEFAULTS_FILE" | cut -d= -f2- || true)

NS_FLAG=()
[[ -n "$NAMESPACE" ]] && NS_FLAG=(-n "$NAMESPACE")

echo ""
echo "=== Connect: ${POD} ==="
[[ -n "$NAMESPACE" ]] && echo "    Namespace: ${NAMESPACE}"
echo "    Forwarding pod/${POD} -> localhost:4096"
echo "    Press Ctrl+C to stop"
echo ""

kubectl port-forward "pod/${POD}" 4096:4096 "${NS_FLAG[@]}"
