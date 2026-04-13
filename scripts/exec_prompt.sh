#!/usr/bin/env bash
# exec_prompt.sh — launch a one-shot k8s pod to run an AI agent with a given prompt
# Usage: exec_prompt.sh [claude|gemini] [golang|python] ["prompt text"]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/../.push-defaults"

if [[ ! -f "$DEFAULTS_FILE" ]]; then
    echo "Error: .push-defaults not found. Run a build target first." >&2
    exit 1
fi

_get() { grep "^${1}=" "$DEFAULTS_FILE" | cut -d= -f2- || true; }

REGISTRY=$(              _get REGISTRY)
IMAGE_TAG=$(             _get IMAGE_TAG); IMAGE_TAG="${IMAGE_TAG:-latest}"
NAMESPACE=$(             _get NAMESPACE)
IMAGE_PULL_SECRET=$(     _get IMAGE_PULL_SECRET)
IMAGE_PULL_SECRET_FILE=$(_get IMAGE_PULL_SECRET_FILE)

if [[ -z "$REGISTRY" ]]; then
    echo "Error: REGISTRY not set in .push-defaults." >&2
    exit 1
fi

NS_FLAG=()
[[ -n "$NAMESPACE" ]] && NS_FLAG=(-n "$NAMESPACE")

# Derive pull secret name from the file if not stored directly
if [[ -z "$IMAGE_PULL_SECRET" && -n "$IMAGE_PULL_SECRET_FILE" && -f "$IMAGE_PULL_SECRET_FILE" ]]; then
    IMAGE_PULL_SECRET=$(grep "^\s*name:" "$IMAGE_PULL_SECRET_FILE" | head -1 | awk '{print $2}')
fi

# Build imagePullSecrets block if a pull secret is configured
PULL_SECRET_BLOCK=""
if [[ -n "$IMAGE_PULL_SECRET" ]]; then
    PULL_SECRET_BLOCK="  imagePullSecrets:
    - name: ${IMAGE_PULL_SECRET}"
fi

# ── Select AI ────────────────────────────────────────────────────────────────
AI="${1:-}"
if [[ -z "$AI" ]]; then
    echo "Select AI:"
    echo "  1) claude"
    echo "  2) gemini"
    read -rp "Choice [1]: " INPUT
    case "${INPUT:-1}" in
        1|claude) AI="claude" ;;
        2|gemini) AI="gemini" ;;
        *) echo "Error: invalid choice." >&2; exit 1 ;;
    esac
fi

# ── Select language ───────────────────────────────────────────────────────────
LANG="${2:-}"
if [[ -z "$LANG" ]]; then
    echo "Select language:"
    echo "  1) golang"
    echo "  2) python"
    read -rp "Choice [1]: " INPUT
    case "${INPUT:-1}" in
        1|golang) LANG="golang" ;;
        2|python) LANG="python" ;;
        *) echo "Error: invalid choice." >&2; exit 1 ;;
    esac
fi

# ── Prompt text ───────────────────────────────────────────────────────────────
PROMPT="${3:-}"
if [[ -z "$PROMPT" ]]; then
    read -rp "Prompt: " PROMPT
fi
if [[ -z "$PROMPT" ]]; then
    echo "Error: prompt cannot be empty." >&2
    exit 1
fi

# Encode prompt as a safe JSON string for embedding in YAML
PROMPT_JSON=$(printf '%s' "$PROMPT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# ── Pod name ──────────────────────────────────────────────────────────────────
POD_NAME="${AI}-${LANG}-$(date +%s)"

echo ""
echo "=== Launching pod: ${POD_NAME} ==="
echo "    AI      : ${AI}"
echo "    Language: ${LANG}"
echo "    Registry: ${REGISTRY}:${IMAGE_TAG}"
echo ""

# ── Build and apply pod YAML ──────────────────────────────────────────────────
if [[ "$AI" == "claude" ]]; then
    IMAGE="${REGISTRY}/claude-code-${LANG}:${IMAGE_TAG}"
    kubectl apply "${NS_FLAG[@]}" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  labels:
    app: ${POD_NAME}
    tool: claude-code
    lang: ${LANG}
    agent-container: "true"
spec:
${PULL_SECRET_BLOCK}
  containers:
    - name: ${POD_NAME}
      image: ${IMAGE}
      args:
        - "claude"
        - "-p"
        - ${PROMPT_JSON}
        - "--dangerously-skip-permissions"
      env:
        - name: CLAUDE_CODE_USE_VERTEX
          value: "1"
        - name: ANTHROPIC_VERTEX_PROJECT_ID
          valueFrom:
            secretKeyRef:
              name: claude-vertex-secret
              key: ANTHROPIC_VERTEX_PROJECT_ID
        - name: CLOUD_ML_REGION
          valueFrom:
            secretKeyRef:
              name: claude-vertex-secret
              key: CLOUD_ML_REGION
        - name: GOOGLE_APPLICATION_CREDENTIALS
          value: /app/gcloud/credentials.json
        - name: GIT_SSH_COMMAND
          value: "ssh -i /home/node/.ssh/id_rsa -o StrictHostKeyChecking=accept-new"
      volumeMounts:
        - name: gcloud-creds
          mountPath: /app/gcloud
          readOnly: true
        - name: github-ssh
          mountPath: /run/secrets/github
          readOnly: true
      resources:
        requests:
          memory: "512Mi"
          cpu: "500m"
        limits:
          memory: "2Gi"
          cpu: "2000m"
  volumes:
    - name: gcloud-creds
      secret:
        secretName: claude-vertex-secret
        items:
          - key: application_default_credentials.json
            path: credentials.json
    - name: github-ssh
      secret:
        secretName: github-secret
        defaultMode: 0444
        items:
          - key: ssh_private_key
            path: id_rsa
  restartPolicy: Never
EOF

elif [[ "$AI" == "gemini" ]]; then
    IMAGE="${REGISTRY}/gemini-cli-${LANG}:${IMAGE_TAG}"
    kubectl apply "${NS_FLAG[@]}" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  labels:
    app: ${POD_NAME}
    tool: gemini-cli
    lang: ${LANG}
    agent-container: "true"
spec:
${PULL_SECRET_BLOCK}
  containers:
    - name: ${POD_NAME}
      image: ${IMAGE}
      args:
        - "gemini"
        - "-p"
        - ${PROMPT_JSON}
        - "--dangerously-skip-permissions"
      env:
        - name: GEMINI_API_KEY
          valueFrom:
            secretKeyRef:
              name: gemini-secret
              key: GEMINI_API_KEY
        - name: GIT_SSH_COMMAND
          value: "ssh -i /home/node/.ssh/id_rsa -o StrictHostKeyChecking=accept-new"
      volumeMounts:
        - name: github-ssh
          mountPath: /run/secrets/github
          readOnly: true
      resources:
        requests:
          memory: "256Mi"
          cpu: "250m"
        limits:
          memory: "1Gi"
          cpu: "1000m"
  volumes:
    - name: github-ssh
      secret:
        secretName: github-secret
        defaultMode: 0444
        items:
          - key: ssh_private_key
            path: id_rsa
  restartPolicy: Never
EOF

else
    echo "Error: unknown AI '${AI}'. Expected: claude | gemini" >&2
    exit 1
fi

# ── Wait for pod to leave Pending, then stream logs ───────────────────────────
echo "Waiting for pod to start..."
while true; do
    PHASE=$(kubectl get pod "${POD_NAME}" "${NS_FLAG[@]}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" != "Pending" && -n "$PHASE" ]] && break
    sleep 2
done

echo "Streaming logs..."
echo ""
kubectl logs "${NS_FLAG[@]}" -f "${POD_NAME}" || true

# ── Final status ──────────────────────────────────────────────────────────────
PHASE=$(kubectl get pod "${POD_NAME}" "${NS_FLAG[@]}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
echo ""
echo "=== Pod ${POD_NAME} finished: ${PHASE} ==="
