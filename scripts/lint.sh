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
  "$ROOT/scripts/gauntlet.sh"
  "$ROOT/scripts/install-release.sh"
)

js_files=(
  "$ROOT/mcp/ocw-mcp.js"
  "$ROOT/test/mcp-smoke.js"
)

for file in "${files[@]}"; do
  bash -n "$file"
done

if command -v node >/dev/null 2>&1; then
  for file in "${js_files[@]}"; do
    node --check "$file"
  done
else
  printf 'node not found; skipping MCP JavaScript syntax checks\n' >&2
fi

if [[ "${OCW_SKIP_SHELLCHECK:-0}" != "1" ]]; then
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${files[@]}"
  else
    printf 'shellcheck not found; skipping shellcheck\n' >&2
  fi
fi

if command -v actionlint >/dev/null 2>&1; then
  actionlint "$ROOT/.github/workflows/"*.yml
else
  printf 'actionlint not found; skipping workflow lint\n' >&2
fi

"$ROOT/test/run.sh"
