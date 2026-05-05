# OCW Bridge Orchestration

This pack adapts the `opencode-bridge` orchestration model for OCW projects.
Use it as routing guidance for Codex, Claude Code, OpenCode, or another
frontier orchestrator that wants cheaper OpenCode Go workers for bounded work.

## Operating Model

- The frontier agent remains accountable for final decisions, edits, tests, and
  user-facing conclusions.
- OpenCode Go workers are draft labor. Use them for exploration, review,
  documentation, and isolated implementation drafts.
- Keep worker prompts narrow. Name the repo area, files, expected output, and
  what the worker must not change.
- Prefer read-only workers before patch workers.
- Use isolated worktrees for patch drafts in important repositories.
- Validate every worker report before applying changes or repeating findings to
  a user.

## Routing

- Scout/exploration: `oss-kimi-rapid` or `bin/oss-scout`
- Review/risk pass: `oss-kimi-rapid` or `bin/oss-review`
- Docs/mechanical summary: `oss-flash-support` or `bin/oss-docs`
- Bounded implementation draft: `oss-deepseek-pro` or `bin/oss-patch`

When a task is ambiguous, run a scout first and let the primary agent decide
the implementation plan.

## Do Not Delegate

Keep these with the frontier orchestrator unless a human explicitly narrows the
scope and accepts the risk:

- Authentication, authorization, secrets, and data recovery paths
- Persistence/schema migrations and irreversible data changes
- CI/release gates, billing, compliance, and security policy decisions
- Cross-module invariants where a worker cannot inspect the full blast radius
- User-facing final review, approval, or merge decisions

## Worker Contract

Every worker result should include:

- Task interpreted
- Files inspected
- Findings or changes
- Verification performed
- Confidence
- Caveats
- Escalation recommendation

If a worker cannot inspect the needed files, it should say so instead of
guessing.

## Concurrency

- Run at most two read-only OSS workers in parallel unless the repository owner
  has configured a higher limit.
- Do not run multiple write-capable OSS workers against the same write surface.
- If a patch worker is active, keep other workers read-only and in disjoint
  repo areas.

## Final Review Gate

Before accepting any OSS worker output:

1. Read the worker report.
2. Inspect the cited files yourself.
3. For patch drafts, inspect the diff and run `git apply --check` or
   `ocw apply --check`.
4. Run the relevant test or lint target.
5. Keep the final conclusion in the frontier agent.
