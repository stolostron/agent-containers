# Development Guidelines

## Process Flow

### 1. Plan
- Write a plan file to `./plans/YYYY-MM-DD-<short-description>.md`
- Use Claude or Gemini in planning mode to draft the plan
- The plan becomes the **Jira/GitHub issue description or comment**

### 2. Implement
- Implement the plan and any associated tests

### 3. Document
- Append an **Implementation Summary** section to the plan file
- The implementation summary becomes the **Pull Request description**

## Plan File Format

```markdown
# YYYY-MM-DD — <Title>

## Problem
<What is broken or missing, and why it matters>

## Solution
<Approach chosen and key design decisions>

## Changes
<Files added, deleted, modified — with purpose>

---

## Implementation Summary

**Completed: YYYY-MM-DD**

<What was actually built, any deviations from the plan, and notable tradeoffs>
```

## Artifacts → Destinations

| Artifact | Destination |
|----------|-------------|
| Plan (`## Problem` + `## Solution`) | Jira or GitHub issue description / comment |
| Implementation Summary | Pull Request description |
