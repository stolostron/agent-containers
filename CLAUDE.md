# Agent Containers

## Commands

- **Build**: `make build` (all), `make build-opencode`, `make build-crush`
- **Push**: `make push`, `make push-<image>`
- **Publish**: `make publish-<image>`
- **Run locally**: `make deploy-podman-<image>`
- **Update Dependencies**: `make update-deps`
- **Update & Rebuild**: `make update-and-rebuild`
- **Test**: `bash tests/test_lsp_version_pinning.sh`

## Notes

- **Unavailable CLIs**: The `gh` and `jira` CLIs are not installed. Do not attempt to use them. Prefer MCP tools for GitHub and Jira operations.

## Architecture

For system architecture, data flows, and module layout, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Personal configuration

Read `.claude/user.local.md` at the start of any task that needs an assignee, email, or project key.
If the file does not exist, fall back to Claude memory (`user-config`), then placeholders.
Run `make personalize` to generate it (if this repo uses Fleet Engineering tooling).

## Fleet Engineering Skills

Fetch and apply the relevant skill when the task matches its domain.

| Skill | When to use |
|---|---|
| [jira/bug-specialist](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/jira/bug-specialist/SKILL.md) | Bug triage, reproduction steps, fix planning |
| [jira/epic-specialist](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/jira/epic-specialist/SKILL.md) | Multi-sprint epics with outcomes |
| [jira/feature-specialist](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/jira/feature-specialist/SKILL.md) | Large customer-facing capabilities |
| [jira/initiative-specialist](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/jira/initiative-specialist/SKILL.md) | Multi-team strategic programs |
| [jira/jira-create](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/jira/jira-create/SKILL.md) | Interactive issue creation with specialist delegation |
| [jira/jira-specialist](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/jira/jira-specialist/SKILL.md) | General triage, search, linking, transitions |
| [jira/outcome-specialist](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/jira/outcome-specialist/SKILL.md) | Strategic outcomes tied to OKRs |
| [jira/spike-specialist](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/jira/spike-specialist/SKILL.md) | Time-boxed research and PoC |
| [jira/story-specialist](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/jira/story-specialist/SKILL.md) | User stories with acceptance criteria |
| [jira/task-specialist](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/jira/task-specialist/SKILL.md) | Internal technical tasks |
| [sdlc/agent-memory-setup](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/sdlc/agent-memory-setup/SKILL.md) | Initialize or update CLAUDE.md / AGENTS.md for a repo |
| [sdlc/finish-work](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/sdlc/finish-work/SKILL.md) | Commit, push, open PR, update Jira |
| [sdlc/pr-fix](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/sdlc/pr-fix/SKILL.md) | Fix blocked PRs: merge conflicts, CI failures, review comments |
| [sdlc/pr-review](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/sdlc/pr-review/SKILL.md) | GitHub PR review with worktree isolation and inline comments |
| [sdlc/repo-content-audit](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/sdlc/repo-content-audit/SKILL.md) | Scan for unlinked or orphaned content — catalog gaps, dead links, missing cross-references |
| [sdlc/start-work](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/sdlc/start-work/SKILL.md) | Create a Jira sub-task |
| [meetings/f2f-daily-summary](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/meetings/f2f-daily-summary/SKILL.md) | Capture daily F2F meeting notes as Jira sub-tasks |
| [meetings/f2f-epic-specialist](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/meetings/f2f-epic-specialist/SKILL.md) | Create and manage F2F meeting Epics |
| [meetings/presentation-task](https://raw.githubusercontent.com/OpenShift-Fleet/agentic-sdlc/main/skills/meetings/presentation-task/SKILL.md) | Log a delivered presentation as a closed Jira sub-task with time and materials |
