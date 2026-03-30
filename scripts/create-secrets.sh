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

MODE="${1:-}"

case "$MODE" in

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

    # Podman secret (JSON so secretKeyRef can extract individual keys)
    printf '{"GEMINI_API_KEY":"%s"}' "$API_KEY" \
        | podman secret create --replace gemini-secret - 2>/dev/null \
        || printf '{"GEMINI_API_KEY":"%s"}' "$API_KEY" \
        | podman secret create gemini-secret -
    echo "Created Podman secret: gemini-secret"
    ;;

claude)
    PROJECT_ID="${2:-}"
    REGION="${3:-}"
    CREDS_FILE="${4:-${HOME}/.config/gcloud/application_default_credentials.json}"

    if [[ -z "$PROJECT_ID" || -z "$REGION" ]]; then
        echo "Usage: create-secrets.sh claude <PROJECT_ID> <REGION> [CREDS_FILE]" >&2
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

    # Podman secret (JSON so secretKeyRef can extract individual keys).
    # jq safely handles the credentials JSON which may contain quotes/newlines.
    jq -n \
        --arg pid "$PROJECT_ID" \
        --arg reg "$REGION" \
        --rawfile creds "$CREDS_FILE" \
        '{"ANTHROPIC_VERTEX_PROJECT_ID":$pid,"CLOUD_ML_REGION":$reg,"application_default_credentials.json":$creds}' \
        | podman secret create --replace claude-vertex-secret - 2>/dev/null \
        || jq -n \
            --arg pid "$PROJECT_ID" \
            --arg reg "$REGION" \
            --rawfile creds "$CREDS_FILE" \
            '{"ANTHROPIC_VERTEX_PROJECT_ID":$pid,"CLOUD_ML_REGION":$reg,"application_default_credentials.json":$creds}' \
        | podman secret create claude-vertex-secret -
    echo "Created Podman secret: claude-vertex-secret"
    ;;

*)
    echo "Usage: create-secrets.sh <gemini|claude> ..." >&2
    exit 1
    ;;
esac
