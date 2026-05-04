#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="$("$ROOT/bin/ocw" version | awk '{print $2}')"

grep -Fq "## $VERSION" "$ROOT/CHANGELOG.md" || {
  printf 'CHANGELOG.md is missing heading: ## %s\n' "$VERSION" >&2
  exit 1
}

"$ROOT/scripts/lint.sh"
"$ROOT/scripts/package.sh"
OCW_GAUNTLET_SKIP_PACKAGE=1 "$ROOT/scripts/gauntlet.sh"

printf 'Release check passed for %s\n' "$VERSION"
