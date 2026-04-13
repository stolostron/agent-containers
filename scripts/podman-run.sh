#!/usr/bin/env bash
# podman-run.sh — run an agent container natively with podman
# Usage: podman-run.sh <gemini-golang|gemini-python|claude-golang|claude-python>
set -euo pipefail

TYPE="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/../.push-defaults"
SECRETS_DIR="${SCRIPT_DIR}/../k8s/secrets"

if [[ ! -f "$DEFAULTS_FILE" ]]; then
    echo "Error: .push-defaults not found. Run a build target first." >&2
    exit 1
fi

_get() { grep "^${1}=" "$DEFAULTS_FILE" | cut -d= -f2- || true; }

REGISTRY=$(  _get REGISTRY)
IMAGE_TAG=$( _get IMAGE_TAG); IMAGE_TAG="${IMAGE_TAG:-latest}"

if [[ -z "$REGISTRY" ]]; then
    echo "Error: REGISTRY not set in .push-defaults. Run a build target first." >&2
    exit 1
fi

# Extract a key from a JSON podman secret
secret_val() {
    local secret_name="$1" key="$2"
    podman secret inspect --showsecret "$secret_name" \
        | jq -r ".[0].SecretData | fromjson | .\"${key}\""
}

case "$TYPE" in

gemini-golang|gemini-python)
    SECRET="gemini-secret"
    IMAGE="${REGISTRY}/gemini-cli-${TYPE#gemini-}:${IMAGE_TAG}"

    if ! podman secret inspect "$SECRET" &>/dev/null; then
        echo "Error: podman secret '${SECRET}' not found." >&2
        echo "Run: make create-gemini-secret GEMINI_API_KEY=xxx" >&2
        exit 1
    fi

    GEMINI_API_KEY=$(secret_val "$SECRET" GEMINI_API_KEY)

    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
    ssh_mount_args=()
    if podman secret inspect github-secret &>/dev/null; then
        secret_val github-secret ssh_private_key > "${TMPDIR}/id_rsa"
        chmod 600 "${TMPDIR}/id_rsa"
        ssh_mount_args=(-v "${TMPDIR}/id_rsa:/home/node/.ssh/id_rsa:ro,Z")
    fi

    echo ""
    echo "=== Run: ${IMAGE} ==="
    podman run --rm -it \
        --name "$TYPE" \
        --label agent-container=true \
        -e "GEMINI_API_KEY=${GEMINI_API_KEY}" \
        -e "GIT_SSH_COMMAND=ssh -i /home/node/.ssh/id_rsa -o StrictHostKeyChecking=accept-new" \
        "${ssh_mount_args[@]}" \
        "$IMAGE"
    ;;

claude-golang|claude-python)
    SECRET="claude-vertex-secret"
    IMAGE="${REGISTRY}/claude-code-${TYPE#claude-}:${IMAGE_TAG}"

    if ! podman secret inspect "$SECRET" &>/dev/null; then
        echo "Error: podman secret '${SECRET}' not found." >&2
        echo "Run: make create-claude-vertex-secret PROJECT_ID=xxx REGION=xxx" >&2
        exit 1
    fi

    PROJECT_ID=$(secret_val "$SECRET" ANTHROPIC_VERTEX_PROJECT_ID)
    REGION=$(    secret_val "$SECRET" CLOUD_ML_REGION)
    CREDS=$(     secret_val "$SECRET" "application_default_credentials.json")

    # Write credentials to a temp file mounted into the container
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
    printf '%s' "$CREDS" > "${TMPDIR}/credentials.json"

    ssh_mount_args=()
    if podman secret inspect github-secret &>/dev/null; then
        secret_val github-secret ssh_private_key > "${TMPDIR}/id_rsa"
        chmod 600 "${TMPDIR}/id_rsa"
        ssh_mount_args=(-v "${TMPDIR}/id_rsa:/home/node/.ssh/id_rsa:ro,Z")
    fi

    # Resolve MCP config: honour MCP_CONFIG env var, fall back to ./claude.json
    MCP_MOUNT=()
    _mcp_file="${MCP_CONFIG:-}"
    if [[ -z "$_mcp_file" && -f "./claude.json" ]]; then
        _mcp_file="./claude.json"
    fi
    if [[ -n "$_mcp_file" ]]; then
        echo "    MCP config: ${_mcp_file}"
        MCP_MOUNT=(-v "$(realpath "$_mcp_file"):/home/node/.claude.json:ro,Z")
    fi

    echo ""
    echo "=== Run: ${IMAGE} ==="
    podman run --rm -it \
        --name "$TYPE" \
        --label agent-container=true \
        -e CLAUDE_CODE_USE_VERTEX=1 \
        -e "ANTHROPIC_VERTEX_PROJECT_ID=${PROJECT_ID}" \
        -e "CLOUD_ML_REGION=${REGION}" \
        -e GOOGLE_APPLICATION_CREDENTIALS=/app/gcloud/credentials.json \
        -e "GIT_SSH_COMMAND=ssh -i /home/node/.ssh/id_rsa -o StrictHostKeyChecking=accept-new" \
        -v "${TMPDIR}/credentials.json:/app/gcloud/credentials.json:ro,Z" \
        "${ssh_mount_args[@]}" \
        "${MCP_MOUNT[@]}" \
        "$IMAGE"
    ;;

*)
    echo "Error: unknown type '${TYPE}'." >&2
    echo "Expected: gemini-golang | gemini-python | claude-golang | claude-python" >&2
    exit 1
    ;;
esac
