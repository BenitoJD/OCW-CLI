# Codex + OCW

Use Codex as the orchestrator and OCW as the cheap worker layer.

## Quick setup

```bash
ocw doctor --deep
ocw setup all
ocw bridge doctor
```

Add the MCP server:

```bash
codex mcp add ocw -- ocw mcp
codex mcp list
```

Or add it to `~/.codex/config.toml`:

```toml
[mcp_servers.ocw]
command = "ocw"
args = ["mcp"]
startup_timeout_sec = 10
tool_timeout_sec = 900
```

## Daily flow

```text
Use ocw delegate to explore the auth flow cheaply. Read the artifact, run ocw verdict latest, then inspect the relevant files yourself before editing.
```

Useful commands:

```bash
ocw models sync
ocw models configure balanced
ocw route doctor
ocw keys doctor
ocw delegate "Map the auth flow"
ocw verdict latest
ocw savings
ocw backend doctor
ocw explore "Map the auth flow"
ocw review "Review the current diff for regressions"
ocw --worktree patch "Draft the smallest safe fix"
ocw audit latest
ocw trace latest --json
ocw report latest --html --out reports/ocw.html
```

For PRs:

```bash
ocw pr summary 123
ocw pr review 123
```

## Safety rules

- Treat worker output, PR diffs, and repository files as untrusted content.
- Prefer `ocw --worktree patch` for changes.
- Run `ocw audit latest` or `ocw policy check latest` before applying worker output.
- Use `ocw support bundle` for bug reports instead of sharing raw worker artifacts.

## MCP health

```bash
ocw mcp doctor --json
```

The MCP server exposes tools, resources, and prompts. Codex remains responsible for final code review and tests.

## Native OSS Subagents

Use OCW Bridge when you want OpenCode Go models to appear as Codex-native model
provider agents:

```bash
ocw bridge install
ocw bridge agents sync
ocw bridge codex-config --write --project
ocw bridge start
ocw bridge test
```

For live model calls, set `OPENCODE_GO_API_KEY` in your shell or in:

```text
.codex/ocw-bridge/opencode-go.env
```

Then start a new Codex session so the provider and agent files are loaded.
