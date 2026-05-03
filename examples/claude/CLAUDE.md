# OCW Worker Integration

Use `ocw` to delegate bounded work to OpenCode Go models while keeping Claude Code responsible for final judgment.

## Modes

- `ocw cheap "<task>"` for cheap routine analysis.
- `ocw explore "<task>"` for normal repo exploration.
- `ocw scan "<task>"` for broad or long-context scans.
- `ocw review "<task>"` for a stronger second opinion on diffs or risky code.
- `ocw --worktree patch "<task>"` for bounded patch drafts in an isolated git worktree.

## Workflow

1. Run the narrowest useful `ocw` mode.
2. Read `.codex/opencode-workers/*/summary.md`.
3. If files changed, inspect `diff.after.patch` and `status.after.txt`.
4. Decide what to keep.
5. Run tests yourself.
6. Report the final result clearly.

## Rules

- Prefer read-only modes before patch mode.
- Use `--worktree` for patch drafts in important repositories.
- Do not blindly apply worker patches.
- Do not commit `.codex/opencode-workers/` or `.codex/opencode-worktrees/`.

## Example

```text
Use ocw scan to map this repo area cheaply. Read summary.md and then continue with your own focused inspection.
```
