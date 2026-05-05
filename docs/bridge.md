# OCW Bridge

OCW Bridge exposes OpenCode Go models as a localhost OpenAI Responses-compatible
provider for Codex. Use it when you want Codex-native OSS subagents instead of
only shell-worker delegation.

The bundled runtime is derived from `goldtetsola/opencode-bridge` and is
included under Apache License 2.0 attribution in `bridge/opencode-bridge/`.

## Quick Start

```bash
ocw bridge install
ocw bridge agents sync
ocw bridge orchestration sync
ocw bridge codex-config --write --project
ocw bridge start
ocw bridge test
```

Set your OpenCode Go API key before live model calls:

```bash
export OPENCODE_GO_API_KEY=sk-...
```

Or edit the project-local env file:

```text
.codex/ocw-bridge/opencode-go.env
```

The health endpoint works without the upstream key, but `/v1/models` and
`/v1/responses` require `OPENCODE_GO_API_KEY`.

The bundled bridge runtime uses the upstream v3 streaming behavior: for
streaming Responses requests it sends `response.created` immediately, emits
heartbeat comments while the OpenCode Go call is pending, then sends the final
Responses items. This keeps long-running OSS subagent calls from looking idle
to Codex.

## Commands

```bash
ocw bridge install
ocw bridge start [--timeout SECONDS]
ocw bridge stop
ocw bridge status --json
ocw bridge doctor --json
ocw bridge test --json
ocw bridge test --live
ocw bridge codex-config
ocw bridge codex-config --write --project
ocw bridge agents sync
ocw bridge orchestration sync
```

## Codex Config

`ocw bridge codex-config` prints the model provider block:

```toml
[model_providers.opencode_bridge]
name = "OpenCode Bridge"
base_url = "http://127.0.0.1:4000/v1"
wire_api = "responses"
request_max_retries = 2
stream_max_retries = 2
stream_idle_timeout_ms = 900000

[model_providers.opencode_bridge.auth]
command = "sh"
args = ["-c", "printf %s \"${OCW_BRIDGE_KEY:-${PROXY_API_KEY:-${LITELLM_MASTER_KEY:-sk-local-codex-bridge}}}\""]
timeout_ms = 1000
```

Use `--write --project` to append it to `.codex/config.toml`, or `--write
--global` for `~/.codex/config.toml`.

For persistent custom proxy auth, set `OCW_BRIDGE_KEY` or `PROXY_API_KEY` in
the environment used by both Codex and `ocw bridge start`. The config generator
deliberately avoids writing custom bridge keys into project TOML.

## Agent Templates

`ocw bridge agents sync` installs these Codex agent templates into
`.codex/agents/`:

- `oss-deepseek-pro.toml`
- `oss-kimi-rapid.toml`
- `oss-flash-support.toml`

They route through the `opencode_bridge` model provider and keep Codex as the
orchestrator/final reviewer.

## Orchestration Pack

`ocw bridge orchestration sync` installs the bundled routing docs into
`.codex/ocw-bridge-orchestration/`:

- `AGENTS.md`
- `ROUTING.md`

These files capture the upstream bridge pattern in OCW terms: scout first for
ambiguous work, docs/flash for mechanical summaries, review workers for second
opinions, and isolated patch workers for bounded drafts. They explicitly keep
the frontier agent responsible for final review, tests, and user-facing
conclusions.

## Helper Scripts

`ocw bridge install` installs four generic helper scripts under
`.codex/ocw-bridge/bin/`:

```bash
.codex/ocw-bridge/bin/oss-scout --task .ai/tasks/map-auth.md
.codex/ocw-bridge/bin/oss-review --task .ai/tasks/review-risk.md
.codex/ocw-bridge/bin/oss-docs --task .ai/tasks/docs.md
.codex/ocw-bridge/bin/oss-patch --task .ai/tasks/fix-bug.md
```

Defaults:

- Task ids resolve to `.ai/tasks/<id>.md`.
- Reports are written to `.codex/ocw-bridge-results/`.
- Patch drafts run in `.codex/ocw-bridge-worktrees/` and emit
  `<task>.patch.diff` for inspection.
- The default env file is `.codex/ocw-bridge/opencode-go.env`.

The scripts accept `--tasks-dir`, `--results-dir`, `--dir`, `--env-file`,
`--opencode-bin`, `--model`, and `--auto-approve`. `oss-patch` also accepts
`--worktree-root` and `--keep-worktree`.

## Safety

- Bind the bridge to localhost only.
- `ocw bridge start` refuses non-loopback hosts unless
  `OCW_BRIDGE_ALLOW_NON_LOOPBACK=1` is set.
- Do not commit `.codex/ocw-bridge/opencode-go.env`.
- Do not commit `.codex/ocw-bridge-results/` or
  `.codex/ocw-bridge-worktrees/` unless your team deliberately archives worker
  artifacts.
- If you customize the local proxy key, put the same `LITELLM_MASTER_KEY`,
  `PROXY_API_KEY`, or `OCW_BRIDGE_KEY` value in the shell or env file used by
  `ocw bridge start`; `status`, `doctor`, and `test` read that env file too.
- Treat bridge model output as draft labor.
- Keep Codex responsible for final review, tests, and applying patches.
- Use `ocw audit`, `ocw policy check`, and `ocw apply --check` for artifact
  workflows even when bridge-native subagents are available.
