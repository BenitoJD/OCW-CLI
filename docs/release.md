# Release Hardening

OCW release artifacts are built by GitHub Actions from a tag.

## Tag

```bash
git tag -s v0.7.0-alpha -m "v0.7.0-alpha"
git push origin v0.7.0-alpha
```

The release workflow runs `scripts/release-check.sh`, publishes the tarball and checksum, and creates GitHub artifact attestations.

## Verify

```bash
gh release download v0.7.0-alpha -R BenitoJD/OCW-CLI -p 'ocw-0.7.0-alpha.tar.gz*'
shasum -a 256 -c ocw-0.7.0-alpha.tar.gz.sha256
gh attestation verify ocw-0.7.0-alpha.tar.gz --repo BenitoJD/OCW-CLI
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/BenitoJD/OCW-CLI/main/scripts/install-release.sh | bash
```

Require attestation verification:

```bash
curl -fsSL https://raw.githubusercontent.com/BenitoJD/OCW-CLI/main/scripts/install-release.sh | bash -s -- --require-attestation
```

## Homebrew tap

Generate a formula after packaging:

```bash
make package
ocw homebrew formula --out Formula/ocw.rb
```

Then publish `Formula/ocw.rb` from a `homebrew-ocw` tap repository.

Users install from the tap with:

```bash
brew install BenitoJD/ocw/ocw
```

## Docs site

The static docs site source lives in `docs/site`.

The Pages workflow is manual by design:

```bash
gh workflow run pages.yml -R BenitoJD/OCW-CLI
```

Before first deployment, configure the repository Pages source to GitHub Actions in repository settings.
