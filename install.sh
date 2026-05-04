#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET_DIR="${OCW_INSTALL_DIR:-$HOME/.local/bin}"
TARGET="$TARGET_DIR/ocw"

mkdir -p "$TARGET_DIR"
ln -sf "$ROOT/bin/ocw" "$TARGET"

printf 'Installed ocw -> %s\n' "$TARGET"
printf 'Uninstall with: ocw uninstall --yes\n'

case ":$PATH:" in
  *":$TARGET_DIR:"*) ;;
  *)
    printf 'Note: %s is not on PATH in this shell.\n' "$TARGET_DIR"
    ;;
esac
