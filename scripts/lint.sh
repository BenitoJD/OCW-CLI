#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

files=(
  "$ROOT/bin/ocw"
  "$ROOT/install.sh"
  "$ROOT/test/run.sh"
  "$ROOT/test/fixtures/opencode"
  "$ROOT/test/fixtures/gh"
  "$ROOT/scripts/lint.sh"
  "$ROOT/scripts/install-skills.sh"
  "$ROOT/scripts/package.sh"
  "$ROOT/scripts/release-check.sh"
)

for file in "${files[@]}"; do
  bash -n "$file"
done

if [[ "${OCW_SKIP_SHELLCHECK:-0}" != "1" ]]; then
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${files[@]}"
  else
    printf 'shellcheck not found; skipping shellcheck\n' >&2
  fi
fi

"$ROOT/test/run.sh"
