# 2026-04-13 — Add Development Guidelines

## Problem

There were no documented development conventions for this repo. Contributors (human or AI) had no shared understanding of how work should be planned, implemented, or recorded — making it hard to trace decisions back to intent and harder to produce consistent PR descriptions or issue comments.

## Solution

Add a `CLAUDE.md` at the repo root that codifies the three-step workflow:

1. **Plan** — write a dated plan file under `./plans/` before touching code. Use an AI in planning mode to draft it. The plan content (Problem + Solution) is what goes into the Jira issue or GitHub issue description.
2. **Implement** — build what the plan describes, including any tests.
3. **Document** — append an Implementation Summary to the plan file. That summary is what goes into the Pull Request description.

`CLAUDE.md` is picked up automatically by Claude Code and serves as the project-level instruction file, so the workflow is enforced at the tooling level without any additional configuration.

## Changes

| File | Change |
|------|--------|
| `CLAUDE.md` | New — documents process flow, plan file format, and artifact destinations |
| `plans/2026-04-13-development-guidelines.md` | New — this file, serving as the first example of the workflow |

---

## Implementation Summary

**Completed: 2026-04-13**

Created `CLAUDE.md` at the repo root with:
- Three-step process flow (Plan → Implement → Document)
- Plan file template matching the existing `plans/2026-04-11-opencode-migration.md` style
- Artifact-to-destination table (plan → issue, impl summary → PR)

No deviations from the plan. The plan file itself (`plans/2026-04-13-development-guidelines.md`) doubles as the first working example of the format.
