#!/usr/bin/env bash
# create-secrets.sh — generate K8s Secret YAMLs and create Podman secrets.
#
# K8s secrets:  consumed by `kubectl apply`
# Podman secrets: created via `podman secret create` so that `podman play kube`
#                 can resolve secretKeyRef (podman play kube cannot consume Kind:Secret YAML).
#                 Secret data is stored as JSON so individual keys can be extracted.
#
# Usage:
#   create-secrets.sh gemini <API_KEY>
#   create-secrets.sh claude <PROJECT_ID> <REGION> [CREDS_FILE]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/../k8s/secrets"

b64() { printf '%s' "$1" | base64 -w 0; }

# Write a Podman secret from stdin only if podman is available.
podman_secret() {
    local name="$1"
    if ! command -v podman &>/dev/null; then
        echo "  (podman not found — skipping Podman secret)"
        cat > /dev/null   # drain stdin
        return
    fi
    podman secret rm "$name" 2>/dev/null || true
    podman secret create "$name" -
    echo "Created Podman secret: ${name}"
}

MODE="${1:-}"

case "$MODE" in

github)
    KEY_FILE="${2:-}"
    if [[ -z "$KEY_FILE" ]]; then
        echo "Usage: create-secrets.sh github <SSH_PRIVATE_KEY_FILE>" >&2
        exit 1
    fi
    if [[ ! -f "$KEY_FILE" ]]; then
        echo "Error: SSH key file not found: ${KEY_FILE}" >&2
        exit 1
    fi

    KEY_B64=$(base64 -w 0 < "$KEY_FILE")

    # K8s Secret YAML
    cat > "${SECRETS_DIR}/github-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: github-secret
type: Opaque
data:
  ssh_private_key: ${KEY_B64}
EOF
    echo "Generated ${SECRETS_DIR}/github-secret.yaml"

    jq -n --rawfile key "$KEY_FILE" '{"ssh_private_key":$key}' \
        | podman_secret github-secret
    ;;

gemini)
    API_KEY="${2:-}"
    if [[ -z "$API_KEY" ]]; then
        echo "Usage: create-secrets.sh gemini <GEMINI_API_KEY>" >&2
        exit 1
    fi

    # K8s Secret YAML
    cat > "${SECRETS_DIR}/gemini-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gemini-secret
type: Opaque
data:
  GEMINI_API_KEY: $(b64 "$API_KEY")
EOF
    echo "Generated ${SECRETS_DIR}/gemini-secret.yaml"

    printf '{"GEMINI_API_KEY":"%s"}' "$API_KEY" \
        | podman_secret gemini-secret
    ;;

claude)
    PROJECT_ID="${2:-}"
    REGION="${3:-}"
    CREDS_FILE="${4:-${HOME}/.config/gcloud/application_default_credentials.json}"

    if [[ -z "$PROJECT_ID" || -z "$REGION" ]]; then
        echo "Usage: make create-claude-vertex-secret PROJECT_ID=<id> REGION=<region> [CREDS_FILE=<path>]" >&2
        echo "  CREDS_FILE defaults to ~/.config/gcloud/application_default_credentials.json" >&2
        exit 1
    fi

    if [[ ! -f "$CREDS_FILE" ]]; then
        echo "Error: credentials file not found: ${CREDS_FILE}" >&2
        echo "Run: gcloud auth application-default login" >&2
        exit 1
    fi

    CREDS_B64=$(base64 -w 0 < "$CREDS_FILE")

    # K8s Secret YAML
    cat > "${SECRETS_DIR}/claude-vertex-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: claude-vertex-secret
type: Opaque
data:
  ANTHROPIC_VERTEX_PROJECT_ID: $(b64 "$PROJECT_ID")
  CLOUD_ML_REGION: $(b64 "$REGION")
  application_default_credentials.json: ${CREDS_B64}
EOF
    echo "Generated ${SECRETS_DIR}/claude-vertex-secret.yaml"

    jq -n \
        --arg pid "$PROJECT_ID" \
        --arg reg "$REGION" \
        --rawfile creds "$CREDS_FILE" \
        '{"ANTHROPIC_VERTEX_PROJECT_ID":$pid,"CLOUD_ML_REGION":$reg,"application_default_credentials.json":$creds}' \
        | podman_secret claude-vertex-secret
    ;;

*)
    echo "Usage: create-secrets.sh <gemini|claude> ..." >&2
    exit 1
    ;;
esac
