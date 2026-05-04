# Release Verification

Use the release installer for normal installs:

```bash
curl -fsSL https://raw.githubusercontent.com/BenitoJD/OCW-CLI/main/scripts/install-release.sh | bash
```

Require GitHub artifact attestation verification when `gh` is available:

```bash
curl -fsSL https://raw.githubusercontent.com/BenitoJD/OCW-CLI/main/scripts/install-release.sh | bash -s -- --require-attestation
```

Manual verification:

```bash
VERSION=0.8.0-alpha
curl -fsSLO "https://github.com/BenitoJD/OCW-CLI/releases/download/v$VERSION/ocw-$VERSION.tar.gz"
curl -fsSLO "https://github.com/BenitoJD/OCW-CLI/releases/download/v$VERSION/ocw-$VERSION.tar.gz.sha256"
shasum -a 256 -c "ocw-$VERSION.tar.gz.sha256"
gh attestation verify "ocw-$VERSION.tar.gz" --repo BenitoJD/OCW-CLI
```

After install:

```bash
ocw version
ocw doctor --deep
ocw mcp audit
```
