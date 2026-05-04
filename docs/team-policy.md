# Team Policy Examples

Strict local policy:

```bash
ocw policy init strict
ocw policy check latest
```

Recommended team defaults:

```toml
[defaults]
worktree = true
rm_worktree = false
require_clean = false
auto_approve = false
```

Recommended review flow:

```bash
ocw pr review 123 --repo owner/repo
ocw audit latest
ocw report latest --html --out reports/ocw-pr-123.html
```

Recommended patch flow:

```bash
ocw --worktree patch "Draft the smallest safe fix"
ocw audit latest
ocw apply latest --check
```

Do not commit `.codex/opencode-workers/`, `.codex/opencode-worktrees/`, support bundles, or generated reports unless your team explicitly wants them as review artifacts.
