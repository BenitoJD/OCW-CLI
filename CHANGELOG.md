# Changelog

All notable changes to `ocw` are documented here.

## 0.4.0-alpha

- Add `ocw pr summary` and `ocw pr review` for GitHub PR artifacts powered by `gh` and cheap OpenCode Go workers.
- Capture PR metadata, changed files, patch diff, worker outputs, combined review/summary reports, and metadata in local artifact directories.
- Add `OCW_GH_BIN` for deterministic tests and custom GitHub CLI paths.
- Add mocked `gh` tests for PR summary and review flows.

## 0.3.0-alpha

- Add `ocw doctor --deep` for provider reachability, model list, output root, git state, and skill installation diagnostics.
- Extend skill installation to OpenCode and Agent Skills-compatible directories, with `all` and `project` installer targets.
- Add `ocw agent-pack install` for OpenCode markdown agents: `ocw-explorer`, `ocw-reviewer`, `ocw-patcher`, and `ocw-triage`.
- Add `ocw bench` to compare OpenCode Go models with saved JSONL, summaries, Markdown, TSV, and metadata.
- Add `ocw batch` for concurrent worker task files with per-task stdout/stderr and artifact tracking.
- Expand docs and skill guidance for Codex, Claude Code, OpenCode, and portable project-local skills.
- Add deterministic tests for deep doctor, expanded installers, agent pack generation, benchmarks, and batch execution.

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
