# 2026-04-14 — Multi-mode K8s manifests (Job, Deployment, Pod)

## Problem

The original K8s manifests used bare `Pod` resources for all modes. A single Pod
abstraction doesn't fit three fundamentally different workload types: batch prompts
(finite), persistent servers (long-running), and interactive TUI sessions.

## Solution

Use the right K8s resource for each mode:

- **Job / CronJob** for prompt mode (`opencode run`) — batch semantics, TTL cleanup
- **Deployment + Service** for serve mode (`opencode serve`) — self-healing, rolling updates
- **Pod** for TUI mode (`sleep infinity` + `kubectl exec`) — interactive, stdin/tty

This mirrors kubeopencode's architecture (Deployment+Service for agents, Pod for tasks)
but uses Job/CronJob for prompts since we lack a controller for lifecycle management.

## Changes

| File | Action | Purpose |
|------|--------|---------|
| `k8s/job-opencode-golang.yaml` | Renamed from `opencode-golang.yaml` | Job for one-shot prompts |
| `k8s/job-opencode-python.yaml` | Renamed from `opencode-python.yaml` | Job for one-shot prompts |
| `k8s/cronjob-opencode-golang.yaml` | Added | CronJob for scheduled prompts |
| `k8s/cronjob-opencode-python.yaml` | Added | CronJob for scheduled prompts |
| `k8s/serve-opencode-golang.yaml` | Added | Deployment + Service for persistent server |
| `k8s/serve-opencode-python.yaml` | Added | Deployment + Service for persistent server |
| `k8s/tui-opencode-golang.yaml` | Added | Pod with stdin/tty for interactive use |
| `k8s/tui-opencode-python.yaml` | Added | Pod with stdin/tty for interactive use |
| `scripts/deploy.sh` | Modified | Smart apply: Deployments use apply, Jobs/Pods use delete-before-create |
| `scripts/connect.sh` | Modified | Label-based pod lookup for all modes |
| `Makefile` | Modified | Targets for all modes: job, cronjob, serve, tui |

---

## Implementation Summary

**Completed: 2026-04-14**

Implemented three K8s resource types matching each OpenCode usage mode:

**Job** (`job-opencode-*.yaml`): `backoffLimit: 0`, `ttlSecondsAfterFinished: 3600`,
runs `opencode run -m MODEL PROMPT`. Model and prompt configurable via env vars
substituted by `deploy.sh`.

**CronJob** (`cronjob-opencode-*.yaml`): Wraps Job template with `concurrencyPolicy: Forbid`,
configurable `CRONJOB_SCHEDULE`.

**Deployment + Service** (`serve-opencode-*.yaml`): `replicas: 1`, `strategy: Recreate`,
`restartPolicy: Always`. Runs `opencode serve --hostname 0.0.0.0`. Service exposes
ClusterIP on port 4096. Supports in-place `kubectl apply` updates.

**Pod** (`tui-opencode-*.yaml`): `stdin: true`, `tty: true`, `restartPolicy: Never`.
Runs `sleep infinity` — user connects via `kubectl exec -it`. Named with `-tui` suffix
to avoid conflicts with other modes.

`deploy.sh` detects Deployment manifests and skips delete-before-create (Deployments
support in-place updates; Jobs and Pods are immutable). `connect.sh` finds pods by
label selector (`-l app=<name>`) for all modes.

Validated all three modes on Kind: Job completes successfully, Deployment stays running
with Service endpoint routing, TUI Pod stays running with stdin/tty enabled.
Agent-swarm compatibility preserved — it builds its own pod specs programmatically
and only shares the container image.
