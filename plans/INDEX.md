# Plans Index

Parent epic: [ACM-32892](https://redhat.atlassian.net/browse/ACM-32892) — Implement an Agentic SDLC platform, similar to Ambient and KubeOpenCode

## Sessions

---
- date: "2026-04-22"
  title: "Consolidate to single opencode image (Go + Python)"
  jira: "ACM-33183"
  jira_url: "https://redhat.atlassian.net/browse/ACM-33183"
  status: "Closed"
  pr: "https://github.com/jnpacker/agent-containers/pull/2"
  summary: "Merged Go+Python into single opencode image via python-build-standalone; dropped LANG build-arg, per-lang k8s manifests, and legacy publish.sh"

# ──────────────────────────────────────────────────────────
- date: "2026-04-29"
  title: "Switch container base image to UBI 10 / Node.js 24 for enterprise compliance and size optimization"
  jira: "ACM-33426"
  jira_url: "https://redhat.atlassian.net/browse/ACM-33426"
  status: "Done"
  pr: "https://github.com/jnpacker/agent-containers/pull/3"
  summary: "Replace node:20-slim with ubi10/nodejs-24; dnf with passwordless sudo for agent package installs; binary-pin fzf+ripgrep; bump opencode/gh/Python; fix arch detection"

# ──────────────────────────────────────────────────────────
- date: "2026-05-06"
  title: "Add Crush container image with shared Containerfile"
  jira: "ACM-33677"
  jira_url: "https://redhat.atlassian.net/browse/ACM-33677"
  status: "Done"
  pr: "https://github.com/jnpacker/agent-containers/pull/4"
  summary: "Restructure Containerfile into multi-target build (base-tools → base-runtimes → opencode/crush); both images share Go/Python/tools layers, differing only in AI client"

## Feature Plans

| Plan | Summary | Jira | PR |
|------|---------|------|-----|
| [2026-04-11-opencode-migration.md](2026-04-11-opencode-migration.md) | Migrate from Claude/Gemini containers to OpenCode | — | — |
| [2026-04-21-build-and-ops-improvements.md](2026-04-21-build-and-ops-improvements.md) | Pin opencode version, set-image-tag target, right-size memory limits | [ACM-33121](https://redhat.atlassian.net/browse/ACM-33121) | [#1](https://github.com/jnpacker/agent-containers/pull/1) |
| [2026-04-22-consolidate-opencode-image.md](2026-04-22-consolidate-opencode-image.md) | Merge Go+Python into single opencode image | [ACM-33183](https://redhat.atlassian.net/browse/ACM-33183) | [#2](https://github.com/jnpacker/agent-containers/pull/2) |
