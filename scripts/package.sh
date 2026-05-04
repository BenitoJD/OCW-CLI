#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="$("$ROOT/bin/ocw" version | awk '{print $2}')"
DIST="$ROOT/dist"
PKG="ocw-$VERSION"
PKG_DIR="$DIST/$PKG"

rm -rf "$DIST"
mkdir -p "$PKG_DIR"

mkdir -p "$PKG_DIR/bin" "$PKG_DIR/docs" "$PKG_DIR/examples/codex" "$PKG_DIR/examples/claude" "$PKG_DIR/mcp" "$PKG_DIR/skills/opencode-worker" "$PKG_DIR/plugins/claude/ocw/.claude-plugin" "$PKG_DIR/plugins/claude/ocw/skills/opencode-worker" "$PKG_DIR/test/fixtures" "$PKG_DIR/scripts"

cp "$ROOT/bin/ocw" "$PKG_DIR/bin/ocw"
cp "$ROOT/install.sh" "$PKG_DIR/install.sh"
cp "$ROOT/README.md" "$PKG_DIR/README.md"
cp "$ROOT/LICENSE" "$PKG_DIR/LICENSE"
cp "$ROOT/CHANGELOG.md" "$PKG_DIR/CHANGELOG.md"
cp "$ROOT/CODE_OF_CONDUCT.md" "$PKG_DIR/CODE_OF_CONDUCT.md"
cp "$ROOT/CONTRIBUTING.md" "$PKG_DIR/CONTRIBUTING.md"
cp "$ROOT/SECURITY.md" "$PKG_DIR/SECURITY.md"
cp "$ROOT/Makefile" "$PKG_DIR/Makefile"
cp "$ROOT/docs/integrations.md" "$PKG_DIR/docs/integrations.md"
cp "$ROOT/examples/codex/AGENTS.md" "$PKG_DIR/examples/codex/AGENTS.md"
cp "$ROOT/examples/claude/CLAUDE.md" "$PKG_DIR/examples/claude/CLAUDE.md"
cp "$ROOT/mcp/ocw-mcp.js" "$PKG_DIR/mcp/ocw-mcp.js"
cp "$ROOT/skills/opencode-worker/SKILL.md" "$PKG_DIR/skills/opencode-worker/SKILL.md"
cp "$ROOT/plugins/claude/ocw/.claude-plugin/plugin.json" "$PKG_DIR/plugins/claude/ocw/.claude-plugin/plugin.json"
cp "$ROOT/plugins/claude/ocw/skills/opencode-worker/SKILL.md" "$PKG_DIR/plugins/claude/ocw/skills/opencode-worker/SKILL.md"
cp "$ROOT/test/run.sh" "$PKG_DIR/test/run.sh"
cp "$ROOT/test/mcp-smoke.js" "$PKG_DIR/test/mcp-smoke.js"
cp "$ROOT/test/fixtures/opencode" "$PKG_DIR/test/fixtures/opencode"
cp "$ROOT/test/fixtures/gh" "$PKG_DIR/test/fixtures/gh"
cp "$ROOT/scripts/lint.sh" "$PKG_DIR/scripts/lint.sh"
cp "$ROOT/scripts/install-skills.sh" "$PKG_DIR/scripts/install-skills.sh"
cp "$ROOT/scripts/package.sh" "$PKG_DIR/scripts/package.sh"
cp "$ROOT/scripts/release-check.sh" "$PKG_DIR/scripts/release-check.sh"
cp "$ROOT/scripts/gauntlet.sh" "$PKG_DIR/scripts/gauntlet.sh"

chmod +x "$PKG_DIR/bin/ocw" "$PKG_DIR/install.sh" "$PKG_DIR/mcp/ocw-mcp.js" "$PKG_DIR/test/run.sh" "$PKG_DIR/test/mcp-smoke.js" "$PKG_DIR/test/fixtures/opencode" "$PKG_DIR/test/fixtures/gh" "$PKG_DIR/scripts/"*.sh

tar -czf "$DIST/$PKG.tar.gz" -C "$DIST" "$PKG"

(
  cd "$DIST"
  shasum -a 256 "$PKG.tar.gz" > "$PKG.tar.gz.sha256"
)

printf 'Created %s\n' "$DIST/$PKG.tar.gz"
printf 'Created %s\n' "$DIST/$PKG.tar.gz.sha256"
