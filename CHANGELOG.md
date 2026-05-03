# Changelog

All notable changes to `ocw` are documented here.

## 0.2.0-alpha

- Add `ocw init` for project bootstrap, `.ocw.toml`, `.gitignore`, project instructions, and skill installation.
- Add `.ocw.toml` routing for models, agents, defaults, worktree behavior, and attach URLs.
- Add `ocw last`, `ocw show`, and `ocw clean` for worker artifact management.
- Add `ocw apply` with `git apply --check` validation for isolated worktree patch drafts.
- Add `ocw stats`, `ocw serve`, and worker `--attach` support for OpenCode server/cost workflows.
- Add Claude Code plugin packaging for the `opencode-worker` skill.
- Expand mocked tests across init, config, attach, artifacts, apply, stats, serve, skills, and plugin assets.

## 0.1.0-alpha

- Add `explore`, `review`, `patch`, `scan`, and `cheap` worker modes.
- Route default modes to OpenCode Go models.
- Capture `summary.md`, raw JSONL, metadata, status, and before/after diffs.
- Add `--worktree` patch isolation and `--require-clean`.
- Add model, agent, variant, attachment, and auto-approve overrides.
- Add `doctor`, `models`, and `version` commands.
- Add deterministic mocked tests and release packaging.
- Add Codex and Claude Code integration docs and project instruction templates.
- Add shared `opencode-worker` skill and installer for Codex and Claude Code.
- Add README About section for GitHub project positioning.
