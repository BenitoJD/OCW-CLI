# Security

`ocw` shells out to `opencode` and may capture prompts, paths, summaries, diffs, and metadata under `.codex/opencode-workers/`.

## Reporting Vulnerabilities

Do not open a public issue for a sensitive vulnerability. Report privately through GitHub Security Advisories after the repository is published.

Until then, contact the maintainer directly.

## Data Handling

`ocw` writes local artifacts:

```text
.codex/opencode-workers/
.codex/opencode-worktrees/
```

These files can include source snippets, paths, command output, and model responses. Add them to `.gitignore` in downstream projects.

## Safe Usage

- Prefer read-only modes for exploration and review.
- Use `--worktree` for patch drafts in important repositories.
- Use `--require-clean` before direct patch mode.
- Review `diff.after.patch` before applying or keeping worker changes.
- Do not paste secrets into worker prompts.
