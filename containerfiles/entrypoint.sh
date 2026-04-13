#!/bin/sh
# entrypoint.sh — configure runtime credentials then hand off to CMD
set -e

# Configure git to use GITHUB_PAT for HTTPS authentication if provided.
# PAT is used as the token in: https://x-access-token:<PAT>@github.com
if [ -n "${GITHUB_PAT:-}" ]; then
    git config --global credential.helper store
    printf 'https://x-access-token:%s@github.com\n' "$GITHUB_PAT" \
        > "${HOME}/.git-credentials"
    chmod 600 "${HOME}/.git-credentials"
fi

# Write OpenCode auth.json for API-key-based providers.
# OpenCode does not read API keys from env vars — it requires auth.json.
# Format: {"<provider>": {"type": "api", "key": "<key>"}}
AUTH_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/opencode"
mkdir -p "$AUTH_DIR"
jq -n \
    --arg gak "${GOOGLE_API_KEY:-}" \
    '{
        google: (if $gak != "" then {"type": "api", "key": $gak} else empty end)
    }
    | with_entries(select(.value != null))' \
    > "${AUTH_DIR}/auth.json"

exec "$@"
