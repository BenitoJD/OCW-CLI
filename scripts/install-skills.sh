#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SKILL_NAME="opencode-worker"
SOURCE="$ROOT/skills/$SKILL_NAME/SKILL.md"

usage() {
  cat <<'USAGE'
Usage: scripts/install-skills.sh [codex|claude|opencode|agents|both|all|project]

Installs the opencode-worker skill for Codex, Claude Code, OpenCode, Agent Skills-compatible agents, or project-local agent skill directories.

Environment overrides:
  OCW_CODEX_SKILLS_DIR    Target Codex skills directory
  OCW_CLAUDE_SKILLS_DIR   Target Claude Code skills directory
  OCW_OPENCODE_SKILLS_DIR Target OpenCode skills directory
  OCW_AGENTS_SKILLS_DIR   Target Agent Skills-compatible directory
  CODEX_HOME              Codex home, default: ~/.codex
  CLAUDE_HOME             Claude home, default: ~/.claude
  OPENCODE_CONFIG_HOME    OpenCode config home, default: ~/.config/opencode
  AGENTS_HOME             Agent Skills home, default: ~/.agents
USAGE
}

install_skill() {
  local label="$1"
  local skills_dir="$2"
  local target="$skills_dir/$SKILL_NAME"

  mkdir -p "$target"
  cp "$SOURCE" "$target/SKILL.md"
  printf 'Installed %s skill: %s\n' "$label" "$target"
}

main() {
  local target="${1:-both}"
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local claude_home="${CLAUDE_HOME:-$HOME/.claude}"
  local opencode_home="${OPENCODE_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
  local agents_home="${AGENTS_HOME:-$HOME/.agents}"
  local codex_skills_dir="${OCW_CODEX_SKILLS_DIR:-$codex_home/skills}"
  local claude_skills_dir="${OCW_CLAUDE_SKILLS_DIR:-$claude_home/skills}"
  local opencode_skills_dir="${OCW_OPENCODE_SKILLS_DIR:-$opencode_home/skills}"
  local agents_skills_dir="${OCW_AGENTS_SKILLS_DIR:-$agents_home/skills}"

  [[ -f "$SOURCE" ]] || {
    printf 'missing skill source: %s\n' "$SOURCE" >&2
    exit 1
  }

  case "$target" in
    codex)
      install_skill "Codex" "$codex_skills_dir"
      ;;
    claude)
      install_skill "Claude Code" "$claude_skills_dir"
      ;;
    both)
      install_skill "Codex" "$codex_skills_dir"
      install_skill "Claude Code" "$claude_skills_dir"
      ;;
    opencode)
      install_skill "OpenCode" "$opencode_skills_dir"
      ;;
    agents)
      install_skill "Agents" "$agents_skills_dir"
      ;;
    all)
      install_skill "Codex" "$codex_skills_dir"
      install_skill "Claude Code" "$claude_skills_dir"
      install_skill "OpenCode" "$opencode_skills_dir"
      install_skill "Agents" "$agents_skills_dir"
      ;;
    project)
      install_skill "project OpenCode" ".opencode/skills"
      install_skill "project Claude Code" ".claude/skills"
      install_skill "project Agents" ".agents/skills"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
