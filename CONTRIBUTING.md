# Contributing

Thanks for helping improve `ocw`.

## Development

Run the full local check:

```bash
make lint
```

That runs Bash syntax checks, ShellCheck when available, and the deterministic mocked test suite.

Run only tests:

```bash
make test
```

Build a release archive:

```bash
make package
```

## Design Principles

- Keep the CLI small and scriptable.
- Prefer safe defaults over surprising behavior.
- Keep OpenCode workers bounded; Codex or the user remains the final reviewer.
- Use deterministic tests with the mocked OpenCode binary for behavior changes.
- Do not add network-dependent tests to the default suite.

## Pull Requests

Before opening a PR:

1. Run `make lint`.
2. Update `README.md` for user-facing behavior.
3. Update `CHANGELOG.md` for notable changes.
4. Add or update tests in `test/run.sh`.

## Release Process

1. Update `VERSION` in `bin/ocw`.
2. Update `CHANGELOG.md`.
3. Run `make release-check`.
4. Create a signed tag:

```bash
git tag -s v0.1.0-alpha -m "v0.1.0-alpha"
git push origin v0.1.0-alpha
```

The GitHub release workflow builds the tarball and SHA-256 checksum.
