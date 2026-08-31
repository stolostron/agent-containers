#!/usr/bin/env bash
# podman-run.sh — run an opencode container natively with podman
# Usage: podman-run.sh <opencode> [tui|serve]
#
#   tui   (default) — interactive TUI, attached to terminal
#   serve           — headless server on port 4096, runs in background
set -euo pipefail

TYPE="$1"
MODE="${2:-tui}"
shift 2 || true
EXTRA_ARGS=("$@")  # any remaining args passed to opencode (e.g. --continue)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AC_DEFAULTS="${SCRIPT_DIR}/../../agent-swarm/.push-defaults"
if [[ -n "${DEFAULTS_FILE:-}" ]]; then
    :
elif [[ -f "$AC_DEFAULTS" ]]; then
    DEFAULTS_FILE="$AC_DEFAULTS"
else
    DEFAULTS_FILE="${SCRIPT_DIR}/../.push-defaults"
fi

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

# Extract a key that may be absent — returns empty string instead of error
optional_secret_val() {
    local secret_name="$1" key="$2"
    local secrets_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/containers/storage/secrets"
    local id
    id=$(jq -r --arg n "$secret_name" \
        '.secrets[] | select(.name == $n) | .id' \
        "${secrets_dir}/secrets.json")
    jq -r --arg id "$id" '.[$id]' \
        "${secrets_dir}/filedriver/secretsdata.json" \
        | base64 -d | jq -r ".\"${key}\" // empty" 2>/dev/null || true
}

case "$TYPE" in

opencode)
    SECRET="opencode-secret"
    IMAGE="${REGISTRY}/opencode:${IMAGE_TAG}"

    if ! podman secret inspect "$SECRET" &>/dev/null; then
        echo "Error: podman secret '${SECRET}' not found." >&2
        echo "" >&2
        echo "Available secrets:" >&2
        podman secret ls >&2
        echo "" >&2
        echo "To create '${SECRET}': copy the secret template, fill in its values, and run make create-opencode-secret" >&2
        exit 1
    fi

    PROJECT_ID=$(    optional_secret_val "$SECRET" GOOGLE_CLOUD_PROJECT)
    REGION=$(        optional_secret_val "$SECRET" VERTEX_LOCATION)
    CREDS=$(         optional_secret_val "$SECRET" "application_default_credentials.json")
    GOOGLE_API_KEY=$(optional_secret_val "$SECRET" GOOGLE_API_KEY)
    OPENAI_API_KEY=$(optional_secret_val "$SECRET" OPENAI_API_KEY)
    GITHUB_PAT=$(    optional_secret_val "$SECRET" GITHUB_PAT)

    if [[ -n "$PROJECT_ID$REGION$CREDS" ]]; then
        if [[ -z "$PROJECT_ID" || -z "$REGION" || -z "$CREDS" ]]; then
            echo "Error: Vertex AI requires GOOGLE_CLOUD_PROJECT, VERTEX_LOCATION, and ADC credentials." >&2
            exit 1
        fi
    fi

    if [[ -z "$PROJECT_ID$REGION$CREDS$GOOGLE_API_KEY$OPENAI_API_KEY" ]]; then
        echo "Error: no provider credentials found in '${SECRET}'." >&2
        echo "Configure Vertex AI, GOOGLE_API_KEY, or OPENAI_API_KEY." >&2
        exit 1
    fi

    COMMON_ARGS=(
        --name "$TYPE"
        -v "opencode-local:/home/node/.local:Z,U"
    )
    if [[ -n "$CREDS" ]]; then
        # Write Vertex credentials to a temporary file mounted into the container.
        TMPDIR=$(mktemp -d)
        trap 'rm -rf "$TMPDIR"' EXIT
        printf '%s' "$CREDS" > "${TMPDIR}/credentials.json"
        COMMON_ARGS+=(
            -e "GOOGLE_CLOUD_PROJECT=${PROJECT_ID}"
            -e "VERTEX_LOCATION=${REGION}"
            -e GOOGLE_APPLICATION_CREDENTIALS=/app/gcloud/credentials.json
            -v "${TMPDIR}/credentials.json:/app/gcloud/credentials.json:ro,Z"
        )
    fi
    [[ -n "$GOOGLE_API_KEY" ]] && COMMON_ARGS+=(-e "GOOGLE_API_KEY=${GOOGLE_API_KEY}")
    [[ -n "$OPENAI_API_KEY" ]] && COMMON_ARGS+=(-e "OPENAI_API_KEY=${OPENAI_API_KEY}")
    [[ -n "$GITHUB_PAT" ]] && COMMON_ARGS+=(-e "GITHUB_PAT=${GITHUB_PAT}")

    echo ""
    echo "=== Run: ${IMAGE} (${MODE}) ==="

    case "$MODE" in
    tui)
        podman run --rm -it \
            "${COMMON_ARGS[@]}" \
            "$IMAGE" opencode "${EXTRA_ARGS[@]}"
        ;;
    serve)
        podman run --rm -d \
            "${COMMON_ARGS[@]}" \
            -p 4096:4096 \
            "$IMAGE" opencode serve --hostname 0.0.0.0
        echo "OpenCode server started — connect at http://localhost:4096"
        echo "Stop with: podman stop ${TYPE}"
        ;;
    *)
        echo "Error: unknown mode '${MODE}'. Expected: tui | serve" >&2
        exit 1
        ;;
    esac
    ;;

*)
    echo "Error: unknown type '${TYPE}'." >&2
    echo "Expected: opencode" >&2
    exit 1
    ;;
esac
