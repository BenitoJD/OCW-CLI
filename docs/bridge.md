# OCW Bridge

OCW Bridge exposes OpenCode Go models as a localhost OpenAI Responses-compatible
provider for Codex. Use it when you want Codex-native OSS subagents instead of
only shell-worker delegation.

The bundled runtime is derived from `goldtetsola/opencode-bridge` and is
included under Apache License 2.0 attribution in `bridge/opencode-bridge/`.

## Quick Start

Save your OpenCode Go API key once on the machine, then set up the bridge in
any project:

```bash
ocw bridge key set --stdin
ocw bridge setup --force
ocw bridge start
ocw bridge test --live
```

`ocw bridge key set --stdin` uses macOS Keychain when available and a chmod-600
user config file elsewhere. If `OPENCODE_GO_API_KEY` is already available in
your shell, one command can also set up, start, and verify the bridge:

```bash
ocw bridge setup --force --live
```

Project-specific override:

```bash
printf 'OPENCODE_GO_API_KEY=sk-...\n' > .codex/ocw-bridge/opencode-go.env
```

The health endpoint works without the upstream key, but `/v1/models` and
`/v1/responses` require `OPENCODE_GO_API_KEY`.

The bridge accepts every current OpenCode Go catalog model with three naming
styles:

- Bridge alias: `ocg-qwen3.6-plus`
- OpenCode alias: `opencode-go/qwen3.6-plus`
- Raw upstream ID: `qwen3.6-plus`

`/v1/models` returns upstream IDs plus the `ocg-*` and `opencode-go/*` aliases
so Codex and other clients can discover the bridge-native names.

The bundled bridge runtime uses the upstream v3 streaming behavior: for
streaming Responses requests it sends `response.created` immediately, emits
heartbeat comments while the OpenCode Go call is pending, then sends the final
Responses items. This keeps long-running OSS subagent calls from looking idle
to Codex.

## Commands

```bash
ocw bridge setup
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
ocw bridge workers sync
ocw bridge workers doctor
ocw bridge orchestration sync
```

`ocw bridge setup --force` is the preferred project setup command. It runs
`install`, `agents sync`, `workers sync`, `orchestration sync`,
`codex-config --write --project`, `workers doctor`, and `bridge doctor` in the
right order.

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

## Built-In Worker Overrides

`ocw bridge workers sync` installs opt-in Codex built-in overrides into
`.codex/agents/`:

- `worker.toml`: bounded implementation worker using `ocg-deepseek-v4-pro`
- `explorer.toml`: read-only codebase explorer using `ocg-kimi-k2.6`

Codex supports project-scoped custom agents in `.codex/agents/`; if a custom
agent uses the same name as a built-in agent such as `worker` or `explorer`,
the custom agent takes precedence. That means this command lets Codex spawn its
normal worker/explorer roles while routing those spawned sessions through the
local OpenCode Go bridge.

This is intentionally separate from `ocw bridge agents sync` because it changes
the behavior of built-in Codex roles:

```bash
ocw bridge workers sync --force
ocw bridge workers doctor
ocw bridge workers diff
```

After syncing, start a new Codex session in the project so the new agent files
and provider config are loaded.

## Current Model Catalog

OCW Bridge supports the current OpenCode Go catalog:

- `deepseek-v4-flash`
- `deepseek-v4-pro`
- `glm-5`
- `glm-5.1`
- `kimi-k2.5`
- `kimi-k2.6`
- `mimo-v2-omni`
- `mimo-v2-pro`
- `mimo-v2.5`
- `mimo-v2.5-pro`
- `minimax-m2.5`
- `minimax-m2.7`
- `qwen3.5-plus`
- `qwen3.6-plus`

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
- The default project override env file is `.codex/ocw-bridge/opencode-go.env`.
- The preferred shared bridge key is managed by `ocw bridge key set --stdin`.

The scripts accept `--tasks-dir`, `--results-dir`, `--dir`, `--env-file`,
`--opencode-bin`, `--model`, and `--auto-approve`. `oss-patch` also accepts
`--worktree-root` and `--keep-worktree`.

## Safety

- Bind the bridge to localhost only.
- `ocw bridge start` refuses non-loopback hosts unless
  `OCW_BRIDGE_ALLOW_NON_LOOPBACK=1` is set.
- Prefer `ocw bridge key set --stdin` for the OpenCode Go upstream key so users
  are not asked again in every project.
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
