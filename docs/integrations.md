# Integrations

`ocw` is intentionally just a CLI. Any coding agent that can run shell commands can use it.

The integration pattern is:

1. Install `ocw` globally.
2. Add a short project instruction file for your agent.
3. Ask the agent to delegate bounded work through `ocw`.
4. Have the agent read `summary.md` first, then inspect `diff.after.patch` only when needed.
5. Keep the main agent responsible for final judgment and tests.

## Setup

Install:

```bash
./install.sh
```

Verify:

```bash
ocw quickstart
ocw doctor
ocw doctor --deep
ocw models
```

Bootstrap a project:

```bash
ocw init
ocw hooks install all
ocw setup all
ocw mcp-config all
ocw bridge doctor
```

This installs `.ocw.toml`, `.gitignore` entries, `AGENTS.md`, `CLAUDE.md`, and personal/global skills for Codex, Claude Code, OpenCode, and Agent Skills-compatible clients. Use `ocw init --no-skills` when you only want project files.

`ocw hooks install all` adds project-local helper files for Codex-style post-task audits, Claude Code hooks, GitHub Copilot custom instructions/prompts/agents, and OpenCode commands. Existing files are kept unless you pass `--force`.

Install project-local skills too:

```bash
ocw init --project-skills
```

This writes `.opencode/skills`, `.claude/skills`, and `.agents/skills` copies for projects that want portable agent instructions committed with the repo.

## OCW Bridge

Use OCW Bridge when Codex should spawn OpenCode Go backed native subagents via
a local Responses-compatible provider:

```bash
ocw bridge install
ocw bridge agents sync
ocw bridge codex-config --write --project
ocw bridge start
ocw bridge test
```

Set `OPENCODE_GO_API_KEY` in the shell or in `.codex/ocw-bridge/opencode-go.env`
before live model calls. The generated `.codex/agents/*.toml` files use the
`opencode_bridge` provider and keep the primary agent responsible for final
review.

Install the reusable agent skill:

```bash
./scripts/install-skills.sh both
```

In every project that uses `ocw`, add:

```gitignore
.codex/opencode-workers/
.codex/opencode-worktrees/
```

`ocw init` handles those entries automatically.

## Reusable Skill

`skills/opencode-worker/SKILL.md` is a shared Agent Skill for Codex and Claude Code. It teaches the orchestrator when to call `ocw`, which mode to choose, and how to inspect worker artifacts safely.

Install for Codex:

```bash
./scripts/install-skills.sh codex
```

Install for Claude Code:

```bash
./scripts/install-skills.sh claude
```

Install for both:

```bash
./scripts/install-skills.sh both
```

Install for OpenCode:

```bash
./scripts/install-skills.sh opencode
```

Install for Agent Skills-compatible clients:

```bash
./scripts/install-skills.sh agents
```

Install everywhere:

```bash
./scripts/install-skills.sh all
```

Install project-local OpenCode, Claude-compatible, and Agents-compatible skills:

```bash
./scripts/install-skills.sh project
```

The installer copies the same skill to:

```text
~/.codex/skills/opencode-worker/SKILL.md
~/.claude/skills/opencode-worker/SKILL.md
~/.config/opencode/skills/opencode-worker/SKILL.md
~/.agents/skills/opencode-worker/SKILL.md
```

You can override the target directories:

```bash
OCW_CODEX_SKILLS_DIR=/path/to/codex/skills ./scripts/install-skills.sh codex
OCW_CLAUDE_SKILLS_DIR=/path/to/claude/skills ./scripts/install-skills.sh claude
OCW_OPENCODE_SKILLS_DIR=/path/to/opencode/skills ./scripts/install-skills.sh opencode
OCW_AGENTS_SKILLS_DIR=/path/to/agents/skills ./scripts/install-skills.sh agents
```

After installation, ask your agent to use the `opencode-worker` skill when it should delegate cheap worker tasks through OpenCode Go.

Claude Code can also use the plugin package in:

```text
plugins/claude/ocw
```

For local plugin testing:

```bash
claude --plugin-dir plugins/claude/ocw
```

Codex prompt:

```text
Use the opencode-worker skill to run ocw explore for this repo area, then inspect the worker summary before deciding what to edit.
```

Claude Code direct invocation:

```text
/opencode-worker Run ocw scan for this repo area, then inspect summary.md before continuing.
```

## Codex

Use `ocw` from Codex when a task has cheap worker-shaped subtasks:

- broad repo exploration
- long-context scans
- second-pass review
- bounded patch drafts
- test ideas and risk mapping

### Quick Prompt

```text
Use ocw explore to inspect the auth flow. Read the worker summary, then inspect only the files you think matter before deciding what to change.
```

For patch drafts:

```text
Use ocw --worktree patch to draft the smallest safe fix. Then run ocw apply latest --check, read summary.md and diff.after.patch, review the patch yourself, and only apply the parts that are correct.
```

### Project Instructions

If your Codex setup reads project instruction files, copy or merge:

```text
examples/codex/AGENTS.md
```

If it does not, paste the same rules into your Codex project/profile instructions.

For a reusable Codex skill instead of per-project instructions:

```bash
./scripts/install-skills.sh codex
```

For structured tools instead of shell strings:

```bash
ocw mcp-config codex
ocw mcp audit
```

### Recommended Codex Rules

- Prefer `ocw explore`, `ocw cheap`, `ocw scan`, and `ocw review` before `ocw patch`.
- Use `ocw --worktree patch` for important repos.
- Use `ocw apply latest --check` before applying an isolated worker patch.
- Read `.codex/opencode-workers/*/summary.md` before reading raw JSONL.
- Read `diff.after.patch` and `status.after.txt` before accepting worker edits.
- Codex remains responsible for final edits, tests, and the user-facing answer.

## OpenCode

Install the OpenCode-native agent pack:

```bash
ocw agent-pack install
ocw hooks install opencode
```

This creates markdown agents in `.opencode/agents/`:

```text
ocw-explorer.md
ocw-reviewer.md
ocw-patcher.md
ocw-triage.md
```

Use them directly from OpenCode with `@ocw-explorer`, `@ocw-reviewer`, `@ocw-patcher`, or `@ocw-triage`, or configure `.ocw.toml` to route OCW modes to those agent names.

The generated agents follow OpenCode's markdown agent format: YAML frontmatter declares `description`, `mode`, `model`, `temperature`, and `permission`; the body contains the agent instructions.

## Claude Code

Claude Code can use `ocw` the same way: call it from the shell, inspect the saved output, and treat OpenCode worker output as draft material.

Install Claude Code helpers:

```bash
ocw hooks install claude
ocw mcp-config claude
```

## GitHub Copilot

Install Copilot custom instructions, prompt, and agent files:

```bash
ocw copilot install
ocw copilot doctor
```

This writes:

```text
.github/copilot-instructions.md
.github/prompts/ocw-pr-review.prompt.md
.github/agents/ocw-reviewer.agent.md
```

Use the generated prompt when you want Copilot to run `ocw pr review <PR>` and inspect the local artifact before writing a final review.

## MCP Tools

Start the MCP server with:

```bash
ocw mcp
```

Audit and baseline the server:

```bash
ocw mcp audit
ocw mcp audit --write-baseline .codex/ocw-mcp.sha256
ocw mcp audit --baseline .codex/ocw-mcp.sha256
```

Available tools include:

```text
ocw_run
ocw_last
ocw_show
ocw_manifest
ocw_audit
ocw_report
ocw_eval
ocw_doctor
ocw_apply_check
ocw_apply
ocw_stats
ocw_models
ocw_route
ocw_tournament
ocw_memory
ocw_dashboard
ocw_mcp_audit
```

### Quick Prompt

```text
Use ocw scan to map this repo area cheaply. Read summary.md and then continue with your own focused inspection.
```

For patch drafts:

```text
Use ocw --worktree patch to draft this change. Run ocw apply latest --check, inspect diff.after.patch, decide what to keep, and run tests.
```

### Project Instructions

Copy or merge:

```text
examples/claude/CLAUDE.md
```

into your project `CLAUDE.md`.

For a reusable Claude Code skill instead of per-project instructions:

```bash
./scripts/install-skills.sh claude
```

### Recommended Claude Code Rules

- Use `ocw cheap` for routine summaries and sanity checks.
- Use `ocw explore` for normal codebase exploration.
- Use `ocw scan` for broad or long-context scans.
- Use `ocw review` for a stronger second opinion on diffs.
- Use `ocw --worktree patch` for implementation drafts.
- Use `ocw apply latest --check` before applying worker patches.
- Never commit `.codex/opencode-workers/` or `.codex/opencode-worktrees/`.

## Mode Cheat Sheet

```text
ocw cheap "Summarize this config flow"
ocw explore "Find where auth errors are handled"
ocw scan "Map the billing flow across the repo"
ocw review "Review the current diff for regressions"
ocw --worktree patch "Draft the smallest safe validation fix"
ocw apply latest --check
ocw apply latest
ocw bench --iterations 2
ocw batch tasks.ocw --concurrency 3
ocw pr summary 123
ocw pr review 123
ocw mcp
```

Default models:

```text
cheap   -> opencode-go/qwen3.5-plus
explore -> opencode-go/deepseek-v4-flash
scan    -> opencode-go/mimo-v2.5
review  -> opencode-go/deepseek-v4-pro
patch   -> opencode-go/kimi-k2.6
```

## Safety Pattern

For risky work, use this loop:

```bash
ocw --worktree patch "Draft the change"
```

Then inspect:

```bash
ls .codex/opencode-workers/*-patch
sed -n '1,160p' .codex/opencode-workers/*-patch/summary.md
sed -n '1,220p' .codex/opencode-workers/*-patch/diff.after.patch
```

Apply only the parts you trust.

## Artifact Commands

```bash
ocw last
ocw last patch
ocw show latest --summary
ocw show latest --diff
ocw show latest --metadata
ocw clean --days 14 --dry-run
ocw clean --days 14 --yes
```

`ocw clean` prints candidates by default. It removes runs only when `--yes` is present.

## Pull Requests

Use `ocw pr summary` for a cheap local PR brief:

```bash
ocw pr summary 123
ocw pr summary 123 --repo owner/repo
```

Use `ocw pr review` for a cheap two-worker review pass:

```bash
ocw pr review 123
ocw pr review 123 --repo owner/repo
```

The command uses `gh pr view`, `gh pr diff --name-only`, and `gh pr diff --patch` to create local files, then runs OpenCode Go workers against those files. It does not post comments or submit a GitHub review.

Review artifacts include:

```text
pr.txt
pr.diff.patch
pr.files.txt
workers.tsv
review.md
summary.md
metadata.txt
```

Read `review.md` or `summary.md` first, then inspect `pr.diff.patch` and individual worker outputs under `workers/` when needed.

## MCP Server

Start the local stdio MCP server:

```bash
ocw mcp
```

It exposes these structured tools:

```text
ocw_run
ocw_last
ocw_show
ocw_manifest
ocw_audit
ocw_report
ocw_eval
ocw_doctor
ocw_apply_check
ocw_apply
ocw_stats
```

The tools accept structured arguments such as `cwd`, `output_root`, `mode`, `task`, `ref`, and `view`, then return text plus structured command status, stdout, stderr, and artifact paths. Use `ocw_manifest` to inventory artifacts and checksums, `ocw_audit` before trusting worker output or applying patches, `ocw_report` for review artifacts, and `ocw_eval` to compare worker behavior.

It also exposes resources and prompt templates:

```text
ocw://latest/summary
ocw://latest/metadata
ocw://latest/manifest
ocw://latest/audit

ocw-review-diff
ocw-patch-small
ocw-pr-review
ocw-eval
```

For easy project setup across Codex, Claude Code, OpenCode, and Agent Skills-compatible clients:

```bash
ocw agents sync
ocw agents doctor
ocw agents diff
```

For repeatable config validation and support diagnostics:

```bash
ocw config validate --json
ocw support bundle --out ocw-support.tgz
```

`ocw support bundle` redacts likely credential keys and excludes worker summaries unless `--include-summary` is explicitly passed.

Print client-specific setup snippets:

```bash
ocw mcp-config codex
ocw mcp-config claude
ocw mcp-config opencode
```

Codex CLI:

```bash
codex mcp add ocw -- ocw mcp
```

Codex `config.toml`:

```toml
[mcp_servers.ocw]
command = "ocw"
args = ["mcp"]
startup_timeout_sec = 10
tool_timeout_sec = 900
```

Claude Code:

```bash
claude mcp add --transport stdio ocw -- ocw mcp
```

OpenCode `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "ocw": {
      "type": "local",
      "command": ["ocw", "mcp"],
      "enabled": true
    }
  }
}
```

For repo-local development without installing `ocw`, use:

```json
{
  "mcp": {
    "ocw": {
      "type": "local",
      "command": ["node", "/absolute/path/to/OCW-CLI/mcp/ocw-mcp.js"],
      "enabled": true
    }
  }
}
```

`ocw_apply` can modify the working tree. Prefer `ocw_apply_check` first and keep the primary agent responsible for final review and tests.

## Project Config

`.ocw.toml` supports the routing knobs teams usually need:

```toml
[models]
cheap = "opencode-go/qwen3.5-plus"
explore = "opencode-go/deepseek-v4-flash"
scan = "opencode-go/mimo-v2.5"
review = "opencode-go/deepseek-v4-pro"
patch = "opencode-go/kimi-k2.6"

[agents]
cheap = "plan"
explore = "plan"
scan = "plan"
review = "plan"
patch = "build"

[defaults]
output_root = ".codex/opencode-workers"
worktree = true
rm_worktree = false
require_clean = false
auto_approve = false
# attach = "http://localhost:4096"
```

Precedence is: CLI flags, environment variables, `.ocw.toml`, built-in defaults.

## OpenCode Server

OpenCode supports a warm backend with `opencode serve` and `opencode run --attach`. `ocw` exposes both:

```bash
ocw serve --port 4096
ocw --attach http://localhost:4096 scan "Map this repo area"
```

Use this when repeated worker calls are paying cold-start cost for MCP servers or provider setup.

## Cost Stats

OpenCode exposes token and cost statistics. `ocw` passes that through:

```bash
ocw stats --days 7 --models 10
```

## Benchmarks

Use `ocw bench` to compare the OpenCode Go models available in your account:

```bash
ocw bench --models opencode-go/qwen3.5-plus,opencode-go/deepseek-v4-flash --iterations 2
```

The benchmark is intentionally small and read-only. It records status, elapsed seconds, marker detection, JSONL output, and extracted summaries in a benchmark artifact directory.

## Batch Workers

Create a task file:

```text
cheap|Summarize package scripts
scan|Map the authentication flow
review|Review the current diff
patch|Draft the smallest safe validation fix
```

Run it:

```bash
ocw batch tasks.ocw --concurrency 3
```

For patch tasks, prefer isolated worktrees:

```bash
ocw batch tasks.ocw --concurrency 2 --worktree-patches
```
