# User Feedback Plan

Use this when asking early users to test OCW. The goal is to find installation friction, confusing commands, unsafe defaults, and missing integration docs.

## Target users

Ask 5-10 developers who already use at least one of:

- Codex
- Claude Code
- OpenCode
- GitHub CLI

Prefer users with different repo sizes: one small CLI, one frontend app, one backend/API, one monorepo, and one active PR-heavy repo.

## Test script

Ask each user to start from a clean shell and run:

```bash
ocw doctor --deep
ocw init
ocw cheap "Summarize this repository"
ocw review "Review the current diff for regressions"
ocw mcp doctor --json
```

For GitHub-heavy users:

```bash
ocw pr summary 123
ocw pr review 123
```

For patch-mode users:

```bash
ocw --worktree patch "Draft the smallest safe fix for one failing test"
ocw apply latest --check
```

## Questions

- What command or output confused you first?
- Did install or uninstall behave exactly as expected?
- Did `ocw doctor --deep` give enough information to fix setup problems?
- Did worker summaries contain enough signal to be useful?
- Did any command feel unsafe or too magical?
- Which integration docs did you use: Codex, Claude Code, OpenCode, MCP, or PR review?
- What should be one command shorter?

## Capture

Ask users to attach:

- `ocw version`
- `ocw doctor --deep`
- install method
- operating system
- OpenCode version
- sanitized `ocw support bundle --out ocw-support.tgz`

Do not ask users to share raw `.codex/opencode-workers` artifacts unless they explicitly opt in.
