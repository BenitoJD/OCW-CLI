---
name: opencode-worker
description: Use ocw to delegate bounded repository exploration, scans, review passes, and patch drafts to OpenCode Go workers from Codex, Claude Code, or another coding agent.
---

# OpenCode Worker

Use this skill when a coding agent should spend less premium model time by delegating narrow worker tasks through `ocw`.

## Before Delegating

- Verify `ocw` exists with `ocw doctor` when setup is uncertain.
- Keep each worker request bounded: one repo area, one question, one review pass, or one patch draft.
- Treat worker output as draft labor. The primary agent remains responsible for final judgment, edits, tests, and user-facing explanation.

## Mode Selection

```bash
ocw cheap "Summarize this small config flow"
ocw explore "Find where auth errors are handled"
ocw scan "Map the billing flow across the repo"
ocw review "Review the current diff for regressions"
ocw --worktree patch "Draft the smallest safe validation fix"
```

Prefer read-only modes first:

- `cheap`: routine summaries and low-risk sanity checks
- `explore`: normal codebase exploration
- `scan`: broad or long-context mapping
- `review`: stronger second opinion on a diff or plan
- `--worktree patch`: isolated implementation draft

## Reading Results

Each run writes artifacts under `.codex/opencode-workers/<timestamp>-<mode>/`.

Use helper commands when available:

```bash
ocw last
ocw show latest --summary
ocw show latest --diff
```

Read in this order:

1. `summary.md`
2. Relevant source files identified by the worker
3. `diff.after.patch` and `status.after.txt` when files changed
4. `result.jsonl` only when the summary is incomplete

Never apply a worker patch blindly. Inspect the diff, keep only the parts that are correct, and run the relevant checks yourself.

For isolated patch drafts:

```bash
ocw --worktree patch "Draft the smallest safe fix"
ocw apply latest --check
ocw apply latest
```

## Safety Rules

- Use `ocw --worktree patch` for important repositories.
- Use `ocw apply latest --check` before applying any worker patch.
- Use `ocw --require-clean patch` only when direct edits are acceptable and the tree should be clean first.
- Do not commit `.codex/opencode-workers/` or `.codex/opencode-worktrees/`.
- If worker output conflicts with local evidence, trust the repo and verify manually.
