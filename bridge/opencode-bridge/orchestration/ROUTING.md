# OCW Bridge Routing

Use this routing sheet when deciding whether to use OCW shell workers, bridge
native agents, or the bundled `bin/oss-*` helper scripts.

## Decision Flow

```text
Need broad repo map?
  -> scout/read-only worker

Need bug or risk review?
  -> review worker, then frontier agent verifies findings

Need docs, changelog, migration notes, or mechanical summarization?
  -> docs/flash worker

Need a bounded implementation draft?
  -> patch worker in an isolated git worktree

Need final merge, production safety, auth, data, schema, or release judgment?
  -> frontier agent only
```

## Command Matrix

| Need | OCW CLI | Bridge Agent | Helper Script |
|---|---|---|---|
| Fast repo reconnaissance | `ocw explore` | `oss-kimi-rapid` | `bin/oss-scout` |
| Cheap scan or summary | `ocw scan` | `oss-flash-support` | `bin/oss-docs` |
| Review findings | `ocw review` | `oss-kimi-rapid` | `bin/oss-review` |
| Isolated patch draft | `ocw --worktree patch` | `oss-deepseek-pro` | `bin/oss-patch` |
| PR artifact | `ocw pr review 123` | n/a | n/a |
| Structured agent tooling | `ocw mcp` | n/a | n/a |

## Helper Script Defaults

The helper scripts are installed by `ocw bridge install` into
`.codex/ocw-bridge/bin/`.

```bash
.codex/ocw-bridge/bin/oss-scout --task .ai/tasks/map-auth.md
.codex/ocw-bridge/bin/oss-review --task .ai/tasks/review-pr.md
.codex/ocw-bridge/bin/oss-docs --task .ai/tasks/docs.md
.codex/ocw-bridge/bin/oss-patch --task .ai/tasks/fix-bug.md
```

Defaults:

- Tasks: `.ai/tasks/<task>.md`
- Reports: `.codex/ocw-bridge-results/`
- Patch worktrees: `.codex/ocw-bridge-worktrees/`
- Env file: `.codex/ocw-bridge/opencode-go.env`

The scripts can also be pointed at custom locations with `--tasks-dir`,
`--results-dir`, `--worktree-root`, `--env-file`, and `--dir`.

## Safety Checklist

- Keep task files small and explicit.
- Use `--auto-approve` only inside trusted repos or isolated worktrees.
- Do not commit `.codex/ocw-bridge-results/` or
  `.codex/ocw-bridge-worktrees/` unless your team has decided to retain worker
  artifacts.
- Treat every report as evidence to verify, not as a final answer.
