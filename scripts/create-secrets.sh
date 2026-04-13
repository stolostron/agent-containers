#!/usr/bin/env bash
# create-secrets.sh — read opencode-secret.yaml and create K8s + Podman secrets.
#
# Values are read from k8s/secrets/opencode-secret.yaml (stringData section).
# Copy opencode-secret.yaml.template to opencode-secret.yaml and fill in values.
#
# K8s secret:    consumed by `kubectl apply` (generated with base64 data)
# Podman secret: created via `podman secret create` for local container runs.
#                Stored as JSON so individual keys can be extracted by name.
#
# Usage:
#   create-secrets.sh [CREDS_FILE]
#   CREDS_FILE defaults to ~/.config/gcloud/application_default_credentials.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/../k8s/secrets"
YAML_FILE="${SECRETS_DIR}/opencode-secret.yaml"
CREDS_FILE="${1:-${HOME}/.config/gcloud/application_default_credentials.json}"

b64() { printf '%s' "$1" | base64 -w 0; }

if [[ ! -f "$YAML_FILE" ]]; then
    echo "Error: ${YAML_FILE} not found." >&2
    echo "Copy the template and fill in your values:" >&2
    echo "  cp k8s/secrets/opencode-secret.yaml.template k8s/secrets/opencode-secret.yaml" >&2
    exit 1
fi

# Parse a value from the YAML — handles both data: (base64) and stringData: (plaintext)
yaml_val() {
    local raw
    raw=$(grep "^  ${1}:" "$YAML_FILE" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '"' | tr -d "'")
    if grep -q '^data:' "$YAML_FILE"; then
        printf '%s' "$raw" | base64 -d 2>/dev/null || printf '%s' "$raw"
    else
        printf '%s' "$raw"
    fi
}

GOOGLE_CLOUD_PROJECT=$(yaml_val GOOGLE_CLOUD_PROJECT)
VERTEX_LOCATION=$(yaml_val VERTEX_LOCATION)
GOOGLE_API_KEY=$(yaml_val GOOGLE_API_KEY)
GITHUB_PAT=$(yaml_val GITHUB_PAT)

if [[ -z "$GOOGLE_CLOUD_PROJECT" || -z "$VERTEX_LOCATION" || -z "$GOOGLE_API_KEY" ]]; then
    echo "Error: GOOGLE_CLOUD_PROJECT, VERTEX_LOCATION, and GOOGLE_API_KEY must be set in ${YAML_FILE}" >&2
    exit 1
fi

if [[ ! -f "$CREDS_FILE" ]]; then
    echo "Error: GCP credentials file not found: ${CREDS_FILE}" >&2
    echo "Run: gcloud auth application-default login" >&2
    echo "Or specify a path: make create-opencode-secret CREDS_FILE=<path>" >&2
    exit 1
fi

CREDS_B64=$(base64 -w 0 < "$CREDS_FILE")

# K8s Secret YAML — base64-encode all values for kubectl apply
{
    cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: opencode-secret
type: Opaque
data:
  GOOGLE_CLOUD_PROJECT: $(b64 "$GOOGLE_CLOUD_PROJECT")
  VERTEX_LOCATION: $(b64 "$VERTEX_LOCATION")
  application_default_credentials.json: ${CREDS_B64}
  GOOGLE_API_KEY: $(b64 "$GOOGLE_API_KEY")
EOF
    [[ -n "$GITHUB_PAT" ]] && echo "  GITHUB_PAT: $(b64 "$GITHUB_PAT")"
} > "${SECRETS_DIR}/opencode-secret.yaml.k8s"
echo "Generated ${SECRETS_DIR}/opencode-secret.yaml.k8s"

# Podman secret — JSON so individual keys can be extracted by name
SECRET_JSON=$(jq -n \
    --arg pid "$GOOGLE_CLOUD_PROJECT" \
    --arg reg "$VERTEX_LOCATION" \
    --arg gak "$GOOGLE_API_KEY" \
    --arg pat "$GITHUB_PAT" \
    --rawfile creds "$CREDS_FILE" \
    '{
        GOOGLE_CLOUD_PROJECT: $pid,
        VERTEX_LOCATION: $reg,
        "application_default_credentials.json": $creds,
        GOOGLE_API_KEY: $gak
    }
    + (if $pat != "" then {GITHUB_PAT: $pat} else {} end)')

podman secret rm opencode-secret 2>/dev/null || true
printf '%s' "$SECRET_JSON" | podman secret create opencode-secret -
echo "Created Podman secret: opencode-secret"
