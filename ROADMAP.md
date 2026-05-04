# OCW Roadmap

OCW is alpha software. The roadmap is intentionally biased toward reliability, integration ergonomics, and cheap-worker safety.

## Now

- Keep install, uninstall, release, and Homebrew paths boring and repeatable.
- Keep CI green on Linux and macOS.
- Preserve deterministic mocked tests and the packaged CLI gauntlet.
- Treat worker output, PR diffs, and repository content as untrusted data.
- Make Codex, Claude Code, and OpenCode setup obvious for first-time users.

## Next

- Publish signed GitHub releases with checksums and artifact attestations.
- Publish and maintain the `BenitoJD/homebrew-ocw` tap.
- Collect feedback from 5-10 external users using `docs/feedback.md`.
- Add short demo recordings for install, PR review, MCP setup, and patch review flows.
- Expand prompt-injection and untrusted-content evals beyond the current smoke set.
- Add more MCP tools only when they remove real shell-string friction.

## Later

- Turn `docs/site` into a richer docs site if adoption justifies it.
- Add package-manager support beyond Homebrew when users ask for it.
- Add compatibility tests for more agent clients.
- Add optional telemetry-free local diagnostics for support bundles.
- Publish a small corpus of anonymized workflow examples and expected artifacts.

## Non-goals

- OCW should not replace the orchestrator agent.
- OCW should not auto-apply worker output without explicit checks.
- OCW should not hide OpenCode behavior or usage costs from the user.
