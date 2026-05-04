#!/usr/bin/env bash
set -euo pipefail

REPO="${OCW_REPO:-BenitoJD/OCW-CLI}"
VERSION="${OCW_VERSION:-latest}"
INSTALL_DIR="${OCW_INSTALL_DIR:-$HOME/.local/bin}"
VERIFY=1
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: install-release.sh [--repo OWNER/REPO] [--version VERSION] [--install-dir DIR] [--no-verify] [--dry-run]

Downloads an OCW release archive from GitHub Releases, verifies the SHA-256 file,
and runs the packaged installer.

Environment:
  OCW_REPO         Default GitHub repo, owner/name
  OCW_VERSION      Release tag or version. Defaults to latest
  OCW_INSTALL_DIR  Install directory. Defaults to ~/.local/bin
EOF
}

die() {
  printf 'install-release: %s\n' "$*" >&2
  exit 2
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  have_command "$1" || die "required command not found: $1"
}

sha256_check() {
  local checksum_file="$1"

  if have_command shasum; then
    shasum -a 256 -c "$checksum_file"
  elif have_command sha256sum; then
    sha256sum -c "$checksum_file"
  else
    die "shasum or sha256sum is required for checksum verification"
  fi
}

resolve_latest_version() {
  local repo="$1"
  local latest_url

  latest_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")"
  latest_url="${latest_url%/}"
  [[ "$latest_url" == *"/"* ]] || die "could not resolve latest release for $repo"
  printf '%s\n' "${latest_url##*/}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      REPO="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || die "--version requires a value"
      VERSION="$2"
      shift 2
      ;;
    --install-dir)
      [[ $# -ge 2 ]] || die "--install-dir requires a value"
      INSTALL_DIR="$2"
      shift 2
      ;;
    --no-verify)
      VERIFY=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

require_command curl
require_command tar

if [[ "$VERSION" == "latest" ]]; then
  VERSION="$(resolve_latest_version "$REPO")"
fi

ASSET_VERSION="${VERSION#v}"
ARCHIVE="ocw-$ASSET_VERSION.tar.gz"
CHECKSUM="$ARCHIVE.sha256"
BASE_URL="https://github.com/$REPO/releases/download/$VERSION"

printf 'OCW release installer\n'
printf 'repo: %s\n' "$REPO"
printf 'version: %s\n' "$VERSION"
printf 'asset: %s\n' "$ARCHIVE"
printf 'install_dir: %s\n' "$INSTALL_DIR"

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'dry run: would download %s/%s\n' "$BASE_URL" "$ARCHIVE"
  [[ "$VERIFY" -eq 1 ]] && printf 'dry run: would verify %s/%s\n' "$BASE_URL" "$CHECKSUM"
  printf 'dry run: would run packaged install.sh\n'
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ocw-install-release.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

curl -fsSL "$BASE_URL/$ARCHIVE" -o "$TMP_DIR/$ARCHIVE"
if [[ "$VERIFY" -eq 1 ]]; then
  curl -fsSL "$BASE_URL/$CHECKSUM" -o "$TMP_DIR/$CHECKSUM"
  (
    cd "$TMP_DIR"
    sha256_check "$CHECKSUM"
  )
fi

tar -xzf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR"
OCW_INSTALL_DIR="$INSTALL_DIR" "$TMP_DIR/ocw-$ASSET_VERSION/install.sh"

printf 'Installed OCW %s\n' "$ASSET_VERSION"
