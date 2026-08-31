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
SECRETS_DIR="${SECRETS_DIR:-${SCRIPT_DIR}/../k8s/secrets}"
YAML_FILE="${YAML_FILE:-${SECRETS_DIR}/opencode-secret.yaml}"
OUTPUT_DIR="${OUTPUT_DIR:-${SECRETS_DIR}}"
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
    raw=$(grep "^  ${1}:" "$YAML_FILE" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '"' | tr -d "'" || true)
    if grep -q '^data:' "$YAML_FILE"; then
        printf '%s' "$raw" | base64 -d 2>/dev/null || printf '%s' "$raw"
    else
        printf '%s' "$raw"
    fi
}

GOOGLE_CLOUD_PROJECT=$(yaml_val GOOGLE_CLOUD_PROJECT)
VERTEX_LOCATION=$(yaml_val VERTEX_LOCATION)
GOOGLE_API_KEY=$(yaml_val GOOGLE_API_KEY)
OPENAI_API_KEY=$(yaml_val OPENAI_API_KEY)
GITHUB_PAT=$(yaml_val GITHUB_PAT)

VERTEX_VALUES_SET=0
[[ -n "$GOOGLE_CLOUD_PROJECT$VERTEX_LOCATION" ]] && VERTEX_VALUES_SET=1
VERTEX_CONFIGURED=0
if [[ "$VERTEX_VALUES_SET" == "1" ]]; then
    if [[ -z "$GOOGLE_CLOUD_PROJECT" || -z "$VERTEX_LOCATION" ]]; then
        echo "Error: GOOGLE_CLOUD_PROJECT and VERTEX_LOCATION must both be set for Vertex AI" >&2
        exit 1
    fi
    if [[ ! -f "$CREDS_FILE" ]]; then
        echo "Error: GCP credentials file not found: ${CREDS_FILE}" >&2
        echo "Run: gcloud auth application-default login" >&2
        echo "Or specify a path: make create-opencode-secret CREDS_FILE=<path>" >&2
        exit 1
    fi
    VERTEX_CONFIGURED=1
fi

if [[ "$VERTEX_CONFIGURED" == "0" && -z "$GOOGLE_API_KEY" && -z "$OPENAI_API_KEY" ]]; then
    echo "Error: configure at least one provider in ${YAML_FILE}: Vertex AI, GOOGLE_API_KEY, or OPENAI_API_KEY" >&2
    exit 1
fi

CREDS_B64=""
CREDS=""
if [[ "$VERTEX_CONFIGURED" == "1" ]]; then
    CREDS_B64=$(base64 -w 0 < "$CREDS_FILE")
    CREDS=$(<"$CREDS_FILE")
fi

# K8s Secret YAML — base64-encode all values for kubectl apply
{
    cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: opencode-secret
type: Opaque
data:
EOF
    [[ -n "$GOOGLE_CLOUD_PROJECT" ]] && echo "  GOOGLE_CLOUD_PROJECT: $(b64 "$GOOGLE_CLOUD_PROJECT")"
    [[ -n "$VERTEX_LOCATION" ]] && echo "  VERTEX_LOCATION: $(b64 "$VERTEX_LOCATION")"
    [[ -n "$CREDS_B64" ]] && echo "  application_default_credentials.json: ${CREDS_B64}"
    [[ -n "$GOOGLE_API_KEY" ]] && echo "  GOOGLE_API_KEY: $(b64 "$GOOGLE_API_KEY")"
    [[ -n "$OPENAI_API_KEY" ]] && echo "  OPENAI_API_KEY: $(b64 "$OPENAI_API_KEY")"
    [[ -n "$GITHUB_PAT" ]] && echo "  GITHUB_PAT: $(b64 "$GITHUB_PAT")"
} > "${OUTPUT_DIR}/opencode-secret.yaml.k8s"
echo "Generated ${OUTPUT_DIR}/opencode-secret.yaml.k8s"

# Podman secret — JSON so individual keys can be extracted by name
SECRET_JSON=$(jq -n \
    --arg pid "$GOOGLE_CLOUD_PROJECT" \
    --arg reg "$VERTEX_LOCATION" \
    --arg creds "$CREDS" \
    --arg gak "$GOOGLE_API_KEY" \
    --arg oai "$OPENAI_API_KEY" \
    --arg pat "$GITHUB_PAT" \
    '{}
    + (if $pid != "" then {GOOGLE_CLOUD_PROJECT: $pid} else {} end)
    + (if $reg != "" then {VERTEX_LOCATION: $reg} else {} end)
    + (if $creds != "" then {"application_default_credentials.json": $creds} else {} end)
    + (if $gak != "" then {GOOGLE_API_KEY: $gak} else {} end)
    + (if $oai != "" then {OPENAI_API_KEY: $oai} else {} end)
    + (if $pat != "" then {GITHUB_PAT: $pat} else {} end)')

podman secret rm opencode-secret 2>/dev/null || true
printf '%s' "$SECRET_JSON" | podman secret create opencode-secret -
echo "Created Podman secret: opencode-secret"
