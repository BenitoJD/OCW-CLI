# Codex + OCW

Use Codex as the orchestrator and OCW as the cheap worker layer.

## Paste into Codex

Open Codex in the target repository and paste this:

```text
Set up OCW in this project so Codex can use my OpenCode Go subscription for cheaper worker tasks.

Goal:
- Keep Codex as the orchestrator and final reviewer.
- Install/configure OCW with no manual steps from me except providing my OpenCode Go API key.
- Enable both OCW shell/MCP workers and Codex-native OpenCode Go bridge models.
- Do not commit secrets or generated worker artifacts.

Steps:
1. Check whether `ocw` is available with `command -v ocw` and `ocw version`.
2. If `ocw` is missing, install it from GitHub:
   `curl -fsSL https://raw.githubusercontent.com/BenitoJD/OCW-CLI/main/scripts/install-release.sh | bash`
   Then make sure the installed `ocw` is on PATH.
3. Run `ocw doctor --deep`.
4. Run `ocw setup codex --force`.
5. Run `ocw bridge setup --force`.
6. Run `ocw bridge key status`.
7. If no bridge key is configured, ask me for my OpenCode Go API key once and
   save it with `ocw bridge key set --stdin`.
8. Confirm `.codex/ocw-keys.tsv`, `.codex/ocw-bridge/`, `.codex/opencode-workers/`, `.codex/opencode-worktrees/`, `.codex/ocw-bridge-results/`, and `.codex/ocw-bridge-worktrees/` are gitignored.
9. Install or restart the always-on bridge service with `ocw bridge bootstrap --live --timeout 60`.
10. Run `ocw bridge test --live`.
11. Run `ocw bridge workers doctor`.
12. Show me the ready provider name, the ready `ocg-*` models, and two examples:
    - one command that uses OCW CLI workers
    - one Codex instruction that asks Codex to spawn a worker or explorer backed by `opencode_bridge`
    - whether I need to restart Codex for the new provider config to be picked up
13. If `opencode_bridge` is not visible in this Codex session, tell me to start a
    new Codex session in this same project.

Rules:
- Do not print my API key back to me.
- Prefer the global bridge key store. Use `.codex/ocw-bridge/opencode-go.env`
  only when this project intentionally needs an override.
- Do not commit `.codex/ocw-bridge/opencode-go.env`.
- Treat OpenCode Go worker output as draft labor; Codex still does final review and tests.
- If a command fails, find and fix the root cause instead of bypassing the check.
```

## Quick setup

For the live bridge test, save your OpenCode Go key once with
`ocw bridge key set --stdin` first.

```bash
ocw doctor --deep
ocw setup all
ocw bridge key set --stdin
ocw bridge bootstrap --live
ocw bridge setup --force
ocw bridge test --live
ocw bridge service status
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
ocw bridge key set --stdin
ocw bridge bootstrap --live
ocw bridge setup --force
ocw bridge test --live
```

For live model calls, save the OpenCode Go key once:

```bash
ocw bridge key set --stdin
ocw bridge key status
```

That stores the key once for every project. A project-specific override can
still live in `.codex/ocw-bridge/opencode-go.env`.

`ocw bridge bootstrap --live` keeps the proxy running as an OS-native user
service: launchd on macOS, `systemd --user` on Linux, and Task Scheduler on
Windows. Use `ocw bridge service status` and `ocw bridge service logs` when you
need to inspect it.

Then start a new Codex session so the provider and agent files are loaded.

With `ocw bridge workers sync`, Codex's built-in `worker` and `explorer` roles
are replaced by project-local custom agents that use the `opencode_bridge`
provider. Ask Codex explicitly:

```text
Spawn an explorer to map the auth flow, then summarize the evidence before any edits.
```

or:

```text
Spawn a worker to draft the smallest test-only fix for this bug, then have Codex review the diff before applying it.
```
