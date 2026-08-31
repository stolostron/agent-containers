#!/usr/bin/env bash
# Verify standalone secret generation supports each provider independently.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

MOCK_BIN="${TMP_ROOT}/bin"
OUTPUT_DIR="${TMP_ROOT}/output"
mkdir -p "$MOCK_BIN" "$OUTPUT_DIR"

cat > "${MOCK_BIN}/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "secret" && "${2:-}" == "rm" ]]; then
    exit 0
fi
if [[ "${1:-}" == "secret" && "${2:-}" == "create" ]]; then
    cat > "${PODMAN_OUTPUT:?}"
    exit 0
fi
if [[ "${1:-}" == "secret" && "${2:-}" == "inspect" ]]; then
    exit 0
fi
if [[ "${1:-}" == "run" ]]; then
    printf '%s\n' "$@" > "${PODMAN_RUN_OUTPUT:?}"
    exit 0
fi
echo "unexpected podman invocation" >&2
exit 1
EOF
chmod +x "${MOCK_BIN}/podman"

run_generator() {
    local name="$1" yaml_content="$2" creds_file="${3:-${TMP_ROOT}/missing-creds.json}"
    local secrets_dir="${TMP_ROOT}/${name}-secrets"
    local output_dir="${TMP_ROOT}/${name}-output"
    local yaml_file="${secrets_dir}/opencode-secret.yaml"
    local podman_output="${output_dir}/podman.json"
    mkdir -p "$secrets_dir" "$output_dir"
    printf '%s\n' "$yaml_content" > "$yaml_file"

    SECRETS_DIR="$secrets_dir" \
    YAML_FILE="$yaml_file" \
    OUTPUT_DIR="$output_dir" \
    PODMAN_OUTPUT="$podman_output" \
    PATH="${MOCK_BIN}:${PATH}" \
        "$REPO_ROOT/scripts/create-secrets.sh" "$creds_file"

    jq empty "$podman_output"
    [[ -s "${output_dir}/opencode-secret.yaml.k8s" ]]
}

assert_json_value() {
    local file="$1" key="$2" expected="$3"
    [[ "$(jq -r --arg key "$key" '.[$key] // empty' "$file")" == "$expected" ]]
}

assert_json_missing() {
    local file="$1" key="$2"
    ! jq -e --arg key "$key" 'has($key)' "$file" >/dev/null
}

OPENAI_OUTPUT="${TMP_ROOT}/openai-only-output/podman.json"
run_generator openai-only '
apiVersion: v1
kind: Secret
metadata:
  name: opencode-secret
stringData:
  GOOGLE_CLOUD_PROJECT: ""
  VERTEX_LOCATION: ""
  GOOGLE_API_KEY: ""
  OPENAI_API_KEY: "openai-test-key"
  GITHUB_PAT: ""
'
assert_json_value "$OPENAI_OUTPUT" OPENAI_API_KEY openai-test-key
assert_json_missing "$OPENAI_OUTPUT" GOOGLE_API_KEY
assert_json_missing "$OPENAI_OUTPUT" application_default_credentials.json

RUNTIME_DATA="${TMP_ROOT}/runtime-data"
mkdir -p "${RUNTIME_DATA}/containers/storage/secrets/filedriver"
printf '%s' '{"secrets":[{"name":"opencode-secret","id":"test-id"}]}' \
    > "${RUNTIME_DATA}/containers/storage/secrets/secrets.json"
SECRET_B64=$(base64 -w 0 "$OPENAI_OUTPUT")
printf '{"test-id":"%s"}' "$SECRET_B64" \
    > "${RUNTIME_DATA}/containers/storage/secrets/filedriver/secretsdata.json"
RUNTIME_DEFAULTS="${TMP_ROOT}/runtime-defaults"
printf '%s\n' 'REGISTRY=registry.example' 'IMAGE_TAG=test' > "$RUNTIME_DEFAULTS"
PODMAN_RUN_OUTPUT="${TMP_ROOT}/podman-run-args"
DEFAULTS_FILE="$RUNTIME_DEFAULTS" \
XDG_DATA_HOME="$RUNTIME_DATA" \
PODMAN_RUN_OUTPUT="$PODMAN_RUN_OUTPUT" \
PATH="${MOCK_BIN}:${PATH}" \
    bash "$REPO_ROOT/scripts/podman-run.sh" opencode tui
grep -Fxq 'OPENAI_API_KEY=openai-test-key' "$PODMAN_RUN_OUTPUT"
! grep -Eq 'GOOGLE_|credentials.json' "$PODMAN_RUN_OUTPUT"

GEMINI_OUTPUT="${TMP_ROOT}/gemini-only-output/podman.json"
run_generator gemini-only '
apiVersion: v1
kind: Secret
metadata:
  name: opencode-secret
stringData:
  GOOGLE_CLOUD_PROJECT: ""
  VERTEX_LOCATION: ""
  GOOGLE_API_KEY: "gemini-test-key"
  OPENAI_API_KEY: ""
  GITHUB_PAT: ""
'
assert_json_value "$GEMINI_OUTPUT" GOOGLE_API_KEY gemini-test-key
assert_json_missing "$GEMINI_OUTPUT" OPENAI_API_KEY
assert_json_missing "$GEMINI_OUTPUT" application_default_credentials.json

VERTEX_CREDS="${TMP_ROOT}/vertex-credentials.json"
printf '%s\n' '{"type":"authorized_user"}' > "$VERTEX_CREDS"
VERTEX_OUTPUT="${TMP_ROOT}/vertex-only-output/podman.json"
run_generator vertex-only '
apiVersion: v1
kind: Secret
metadata:
  name: opencode-secret
stringData:
  GOOGLE_CLOUD_PROJECT: "test-project"
  VERTEX_LOCATION: "us-east5"
  GOOGLE_API_KEY: ""
  OPENAI_API_KEY: ""
  GITHUB_PAT: ""
' "$VERTEX_CREDS"
assert_json_value "$VERTEX_OUTPUT" GOOGLE_CLOUD_PROJECT test-project
assert_json_value "$VERTEX_OUTPUT" VERTEX_LOCATION us-east5
assert_json_value "$VERTEX_OUTPUT" application_default_credentials.json '{"type":"authorized_user"}'
assert_json_missing "$VERTEX_OUTPUT" OPENAI_API_KEY

PARTIAL_YAML="${TMP_ROOT}/partial.yaml"
printf '%s\n' '
apiVersion: v1
kind: Secret
metadata:
  name: opencode-secret
stringData:
  GOOGLE_CLOUD_PROJECT: "test-project"
  VERTEX_LOCATION: ""
  GOOGLE_API_KEY: ""
  OPENAI_API_KEY: ""
' > "$PARTIAL_YAML"
if SECRETS_DIR="${TMP_ROOT}/partial-secrets" YAML_FILE="$PARTIAL_YAML" OUTPUT_DIR="${TMP_ROOT}/partial-output" PATH="${MOCK_BIN}:${PATH}" \
    "$REPO_ROOT/scripts/create-secrets.sh" "${TMP_ROOT}/missing-creds.json"; then
    echo "FAIL: partial Vertex configuration was accepted" >&2
    exit 1
fi

NO_PROVIDER_YAML="${TMP_ROOT}/none.yaml"
printf '%s\n' '
apiVersion: v1
kind: Secret
metadata:
  name: opencode-secret
stringData:
  GOOGLE_CLOUD_PROJECT: ""
  VERTEX_LOCATION: ""
  GOOGLE_API_KEY: ""
  OPENAI_API_KEY: ""
' > "$NO_PROVIDER_YAML"
if SECRETS_DIR="${TMP_ROOT}/none-secrets" YAML_FILE="$NO_PROVIDER_YAML" OUTPUT_DIR="${TMP_ROOT}/none-output" PATH="${MOCK_BIN}:${PATH}" \
    "$REPO_ROOT/scripts/create-secrets.sh" "${TMP_ROOT}/missing-creds.json"; then
    echo "FAIL: no-provider configuration was accepted" >&2
    exit 1
fi

echo "All standalone provider secret tests passed"
