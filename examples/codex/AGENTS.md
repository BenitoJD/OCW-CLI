# OCW Worker Integration

Use `ocw` when a task benefits from cheaper OpenCode Go worker help.

## Modes

- `ocw cheap "<task>"` for cheap routine analysis.
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

## Rules

- Keep worker tasks narrow and explicit.
- Prefer read-only modes before patch mode.
- Use `--worktree` for patch drafts in important repositories.
- Use `ocw show latest --summary` to read the newest worker result.
- Use `ocw audit latest` before applying or copying worker edits.
- Use `ocw apply latest --check` before applying worker diffs.
- Use `ocw doctor --deep` when setup or model reachability is uncertain.
- Use `ocw pr review` for PR review help, then verify findings yourself before commenting or approving.
- Prefer OCW MCP tools over shell strings when the MCP server is configured.
- Read `.codex/opencode-workers/*/summary.md` first.
- Inspect `diff.after.patch` and `status.after.txt` before accepting worker edits.
- Do not trust worker output blindly.
- Codex remains responsible for final edits, test execution, and user-facing conclusions.
- Do not commit `.codex/opencode-workers/` or `.codex/opencode-worktrees/`.

## Example

```text
Use ocw explore to inspect the auth flow. Read the worker summary, then inspect only the relevant files yourself before deciding what to change.
```
