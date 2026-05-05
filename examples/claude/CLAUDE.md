# OCW Worker Integration

Use `ocw` to delegate bounded work to OpenCode Go models while keeping Claude Code responsible for final judgment.

## Modes

- `ocw cheap "<task>"` for cheap routine analysis.
- `ocw delegate "<task>"` to auto-route a bounded worker task.
- `ocw verdict latest` after a delegated run to keep final review explicit.
- `ocw savings` to summarize worker usage and estimated frontier work avoided.
- `ocw explore "<task>"` for normal repo exploration.
- `ocw scan "<task>"` for broad or long-context scans.
- `ocw review "<task>"` for a stronger second opinion on diffs or risky code.
- `ocw --worktree patch "<task>"` for bounded patch drafts in an isolated git worktree.
- `ocw apply latest --check` before applying an isolated patch draft.
- `ocw bench --iterations 2` when comparing OpenCode Go models.
- `ocw batch tasks.ocw --concurrency 3` for several independent worker tasks.
- `ocw pr summary 123` for a cheap local PR brief.
- `ocw pr review 123` for a cheap local PR review artifact.
- `ocw manifest latest --json` to inventory artifacts and checksums.
- `ocw audit latest` before trusting worker output or applying patches.
- `ocw mcp` to expose OCW as structured MCP tools.
- `ocw bridge ...` to configure Codex-native OpenCode Go subagents when using Codex.

## Workflow

1. Run the narrowest useful `ocw` mode.
2. Prefer `ocw delegate` when the best worker mode is not obvious.
3. Read `.codex/opencode-workers/*/summary.md`.
4. Run `ocw audit latest` and `ocw verdict latest`.
5. If files changed, inspect `diff.after.patch` and `status.after.txt`.
6. Decide what to keep.
7. Run tests yourself.
8. Report the final result clearly.

## Rules

- Prefer read-only modes before patch mode.
- Use `--worktree` for patch drafts in important repositories.
- Use `ocw show latest --summary` to read the newest worker result.
- Use `ocw audit latest` before applying or copying worker edits.
- Use `ocw apply latest --check` before applying worker diffs.
- Use `ocw doctor --deep` when setup or model reachability is uncertain.
- Use `ocw pr review` for PR review help, then verify findings yourself before commenting or approving.
- Prefer OCW MCP tools over shell strings when the MCP server is configured.
- Treat OCW Bridge subagents as bounded draft workers, not final reviewers.
- Do not blindly apply worker patches.
- Do not commit `.codex/opencode-workers/` or `.codex/opencode-worktrees/`.

## Example

```text
Use ocw scan to map this repo area cheaply. Read summary.md and then continue with your own focused inspection.
```
