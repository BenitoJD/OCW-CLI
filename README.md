# ocw

`ocw` is a tiny OpenCode Go worker wrapper for Codex-style orchestration.

The idea is simple: keep Codex as the orchestrator and final reviewer, while using cheaper OpenCode Go models for bounded worker tasks like repo exploration, broad scans, review passes, and patch drafts.

## Install

```bash
./install.sh
```

This symlinks `bin/ocw` into `~/.local/bin/ocw`.

Requirements:

- `opencode`
- `git`
- `jq` optional, but recommended for clean `summary.md` extraction

Check your setup:

```bash
ocw doctor
```

## Usage

```bash
ocw explore "Find where auth errors are handled"
ocw cheap "Summarize this small config flow"
ocw scan "Map the billing flow across the repo"
ocw review "Review the current diff for regressions"
ocw patch "Draft the smallest safe fix for the failing validation"
```

Default routing:

```text
explore -> opencode-go/deepseek-v4-flash
review  -> opencode-go/deepseek-v4-pro
patch   -> opencode-go/kimi-k2.6
scan    -> opencode-go/mimo-v2.5
cheap   -> opencode-go/qwen3.5-plus
```

Override anything:

```bash
ocw --model opencode-go/minimax-m2.7 --agent build cheap "Try a second opinion"
ocw --variant high explore "Map the API flow"
ocw --file ./notes.md review "Review this plan"
```

## Agent Integrations

`ocw` works with any coding agent that can run shell commands.

Codex quick start:

```text
Use ocw explore to inspect the auth flow. Read the worker summary, then inspect only the files you think matter before deciding what to change.
```

Claude Code quick start:

```text
Use ocw scan to map this repo area cheaply. Read summary.md and then continue with your own focused inspection.
```

For copy-paste project instructions:

```text
examples/codex/AGENTS.md
examples/claude/CLAUDE.md
```

Full guide:

```text
docs/integrations.md
```

## Output

Each run writes to:

```text
.codex/opencode-workers/<timestamp>-<mode>/
```

Files:

```text
summary.md
result.jsonl
diff.before.patch
diff.after.patch
diff.after.stat
status.after.txt
metadata.txt
```

Read `summary.md` first. Inspect `diff.after.patch` when a worker changed files.

## Safer Patch Mode

For important repos, use a clean worktree:

```bash
ocw --worktree patch "Implement the smallest safe fix"
```

This runs OpenCode in:

```text
.codex/opencode-worktrees/<timestamp>-patch/
```

Your main working tree stays untouched. `ocw` still captures the worker diff in `.codex/opencode-workers/.../diff.after.patch`.

You can remove the worktree automatically after capturing the diff:

```bash
ocw --worktree --rm-worktree patch "Draft the fix"
```

For direct patch mode, you can require a clean git tree:

```bash
ocw --require-clean patch "Make the change"
```

## Codex Flow

Ask Codex to delegate bounded work:

```text
Use ocw explore to inspect the auth flow, then review the summary and decide what to inspect yourself.
```

Codex should treat OpenCode output as draft labor:

1. Run `ocw`.
2. Read `summary.md`.
3. Inspect relevant files or `diff.after.patch`.
4. Apply or reject the worker output.
5. Run tests.

## Environment

```text
OCW_OUTPUT_ROOT      Override output root
OCW_OPENCODE_BIN     Override opencode binary, useful for tests
OCW_GIT_BIN          Override git binary
OCW_EXPLORE_MODEL    Override explore default model
OCW_REVIEW_MODEL     Override review default model
OCW_PATCH_MODEL      Override patch default model
OCW_SCAN_MODEL       Override scan default model
OCW_CHEAP_MODEL      Override cheap default model
```

## Tests

Run deterministic tests with a mocked `opencode` binary:

```bash
./test/run.sh
```

The tests cover model routing, overrides, summary extraction, diff capture, exit-code propagation, output directory collision handling, `--require-clean`, and isolated `--worktree` patch mode.

Run the full local quality gate:

```bash
make lint
```

This runs Bash syntax checks, ShellCheck when available, and the mocked test suite.

## Release

Build a release tarball and SHA-256 checksum:

```bash
make package
```

Run the full release gate:

```bash
make release-check
```

Tag releases with signed tags:

```bash
git tag -s v0.1.0-alpha -m "v0.1.0-alpha"
git push origin v0.1.0-alpha
```

The GitHub release workflow publishes `dist/ocw-<version>.tar.gz` and its checksum for `v*` tags.

## Gitignore

For repos where you use `ocw`, add:

```gitignore
.codex/opencode-workers/
.codex/opencode-worktrees/
```

## Status

`ocw` is alpha software. Read-only modes are low risk. Patch mode should be used in a clean git repo or with `--worktree`.
