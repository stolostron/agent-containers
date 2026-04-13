#!/usr/bin/env bash
# setup-github.sh — generate an ephemeral SSH key pair, register it as a
# deploy key on a GitHub repo, and store the private key as a secret.
# The key files exist only in a temp directory and are wiped on exit.
#
# Usage: setup-github.sh <owner/repo> [read_only=false]
set -euo pipefail

REPO="${1:-}"
READ_ONLY="${2:-false}"

if [[ -z "$REPO" ]]; then
    echo "Usage: setup-github.sh <owner/repo> [read_only=false]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

KEY_FILE="${TMPDIR}/id_rsa"
COMMENT="agent-container/${REPO}/$(date +%Y%m%d)"

echo "Generating ephemeral SSH key pair..."
ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N "" -C "$COMMENT" -q

echo "Storing private key as secret..."
bash "${SCRIPT_DIR}/create-secrets.sh" github "$KEY_FILE"

GH_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$GH_TOKEN" ]]; then
    echo "Error: GITHUB_PERSONAL_ACCESS_TOKEN or GITHUB_TOKEN must be set" >&2
    exit 1
fi

echo "Registering public key as deploy key on ${REPO}..."
RESPONSE=$(curl -sf -X POST \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO}/keys" \
    -d "{\"title\":\"agent-container/${REPO}\",\"key\":\"$(cat "${KEY_FILE}.pub")\",\"read_only\":${READ_ONLY}}")
echo "  Deploy key id=$(echo "$RESPONSE" | jq -r '.id')  read_only=$(echo "$RESPONSE" | jq -r '.read_only')"

echo "Private key wiped. Secret and deploy key are ready."
