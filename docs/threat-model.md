# OCW Threat Model

OCW delegates work to external model providers through OpenCode. Treat every worker answer, PR diff, issue body, model output, and MCP client input as untrusted.

## Assets

- Source code in the current repository
- Secrets in environment variables, config files, shell history, and local credential stores
- OpenCode API keys stored through `ocw keys`, `ocw bridge key`, local
  credential stores, or passed through environment variables
- GitHub PR metadata and diffs fetched with `gh`
- OCW artifacts under `.codex/opencode-workers/`
- MCP tool access exposed by `ocw mcp`

## Primary Risks

- Prompt injection in PR titles, issue bodies, diffs, docs, or worker summaries
- Unsafe patch application from worker output
- Accidental secret disclosure into model prompts or support bundles
- Running OCW in the wrong repository or output root
- MCP clients invoking write-capable tools without an orchestrator review step
- Supply-chain tampering in release archives or install scripts

## Controls

- Prefer read-only modes first: `cheap`, `explore`, `scan`, `review`
- Use `ocw --worktree patch` for patch drafts
- Run `ocw audit latest` before trusting an artifact
- Run `ocw apply latest --check` before applying a patch
- Keep `.codex/opencode-workers/` and `.codex/opencode-worktrees/` out of git
- Keep `.codex/ocw-keys.tsv` out of git, prefer `ocw keys set --stdin`, and run `ocw keys doctor`
- Prefer `ocw bridge key set --stdin` for the OpenCode Go bridge key; use
  `.codex/ocw-bridge/opencode-go.env` only for intentional project overrides
- Use `ocw support bundle` instead of manually sharing artifacts; it redacts config and excludes summaries by default
- Verify releases with SHA-256 and GitHub artifact attestations
- Use `ocw mcp audit --write-baseline` for MCP server baseline checks in sensitive environments

## Non-Goals

OCW does not sandbox OpenCode itself, replace code review, prove model output correctness, or guarantee that a provider will not log prompts. The orchestrator and repository tests remain the final authority.
