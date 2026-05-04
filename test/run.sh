#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OCW="$ROOT/bin/ocw"
MOCK_OPENCODE="$ROOT/test/fixtures/opencode"
MOCK_GH="$ROOT/test/fixtures/gh"
TMP_ROOT="$(mktemp -d)"
PASS=0
FAIL=0

trap 'rm -rf "$TMP_ROOT"' EXIT

say() {
  printf '%s\n' "$*"
}

fail() {
  say "FAIL: $*"
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "missing dir: $1"
}

assert_not_dir() {
  [[ ! -d "$1" ]] || fail "unexpected dir: $1"
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq "$expected" "$file" || {
    say "--- $file"
    sed -n '1,160p' "$file" || true
    fail "expected '$expected' in $file"
  }
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  ! grep -Fq "$unexpected" "$file" || fail "did not expect '$unexpected' in $file"
}

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    printf 'base\n' > tracked.txt
    printf 'attachment fixture\n' > attached.txt
    git add tracked.txt attached.txt
    git -c user.name='OCW Test' -c user.email='ocw-test@example.invalid' commit -q -m 'init'
  )
}

run_ocw() {
  OCW_OPENCODE_BIN="$MOCK_OPENCODE" \
    OCW_GH_BIN="$MOCK_GH" \
    OCW_OUTPUT_ROOT=".out" \
    OCW_MOCK_LOG="$PWD/mock.log" \
    OCW_MOCK_GH_LOG="$PWD/gh.log" \
    OCW_TEST_CREATED_AT="2026-01-01T00:00:00Z" \
    "$OCW" "$@"
}

run_test() {
  local name="$1"
  shift

  if "$@"; then
    PASS=$((PASS + 1))
    say "ok - $name"
  else
    FAIL=$((FAIL + 1))
    say "not ok - $name"
  fi
}

test_help_and_doctor() {
  local output
  "$OCW" --help >/dev/null
  output="$(OCW_OPENCODE_BIN="$MOCK_OPENCODE" "$OCW" doctor)"
  grep -Fq 'ocw 0.7.0-alpha' <<< "$output"
  output="$(OCW_OPENCODE_BIN="$MOCK_OPENCODE" OCW_OUTPUT_ROOT="$TMP_ROOT/doctor-out" "$OCW" doctor --deep)"
  grep -Fq 'doctor deep: ok' <<< "$output"
  grep -Fq 'opencode-go model count: 5' <<< "$output"
}

test_default_routing() {
  local repo="$TMP_ROOT/default-routing"
  make_repo "$repo"
  cd "$repo"

  OCW_TEST_STAMP="route-explore" run_ocw explore "route explore" >/dev/null
  OCW_TEST_STAMP="route-review" run_ocw review "route review" >/dev/null
  OCW_TEST_STAMP="route-patch" run_ocw patch "route patch" >/dev/null
  OCW_TEST_STAMP="route-scan" run_ocw scan "route scan" >/dev/null
  OCW_TEST_STAMP="route-cheap" run_ocw cheap "route cheap" >/dev/null

  assert_contains ".out/route-explore-explore/metadata.txt" "model=opencode-go/deepseek-v4-flash"
  assert_contains ".out/route-review-review/metadata.txt" "model=opencode-go/deepseek-v4-pro"
  assert_contains ".out/route-patch-patch/metadata.txt" "model=opencode-go/kimi-k2.6"
  assert_contains ".out/route-scan-scan/metadata.txt" "model=opencode-go/mimo-v2.5"
  assert_contains ".out/route-cheap-cheap/metadata.txt" "model=opencode-go/qwen3.5-plus"
}

test_overrides_and_summary() {
  local repo="$TMP_ROOT/overrides"
  make_repo "$repo"
  cd "$repo"

  OCW_TEST_STAMP="override" run_ocw \
    --model opencode-go/minimax-m2.7 \
    --agent build \
    --variant high \
    --file attached.txt \
    --auto-approve \
    cheap "override route" >/dev/null

  assert_contains ".out/override-cheap/metadata.txt" "model=opencode-go/minimax-m2.7"
  assert_contains ".out/override-cheap/metadata.txt" "agent=build"
  assert_contains ".out/override-cheap/metadata.txt" "variant=high"
  assert_contains ".out/override-cheap/metadata.txt" "auto_approve=1"
  assert_contains ".out/override-cheap/summary.md" "MOCK_OK model=opencode-go/minimax-m2.7"
  assert_contains "mock.log" "files=attached.txt"

  OCW_TEST_STAMP="mode-first" run_ocw \
    cheap \
    --model opencode-go/deepseek-v4-flash \
    --agent build \
    --variant low \
    --file attached.txt \
    --auto-approve \
    --out ".modeout" \
    "mode-first override route" >/dev/null

  assert_contains ".modeout/mode-first-cheap/metadata.txt" "model=opencode-go/deepseek-v4-flash"
  assert_contains ".modeout/mode-first-cheap/metadata.txt" "agent=build"
  assert_contains ".modeout/mode-first-cheap/metadata.txt" "variant=low"
  assert_contains ".modeout/mode-first-cheap/metadata.txt" "auto_approve=1"
}

test_config_routing_and_attach() {
  local repo="$TMP_ROOT/config"
  make_repo "$repo"
  cd "$repo"

  cat > .ocw.toml <<'EOF'
[models]
cheap = "opencode-go/config-cheap"

[agents]
cheap = "build"

[defaults]
output_root = ".configured"
variant = "high"
attach = "http://localhost:4096"
EOF

  OCW_OPENCODE_BIN="$MOCK_OPENCODE" \
    OCW_MOCK_LOG="$PWD/mock.log" \
    OCW_TEST_CREATED_AT="2026-01-01T00:00:00Z" \
    OCW_TEST_STAMP="config" \
    "$OCW" cheap "config route" >/dev/null

  assert_contains ".configured/config-cheap/metadata.txt" "model=opencode-go/config-cheap"
  assert_contains ".configured/config-cheap/metadata.txt" "agent=build"
  assert_contains ".configured/config-cheap/metadata.txt" "variant=high"
  assert_contains ".configured/config-cheap/metadata.txt" "attach_url=http://localhost:4096"
  assert_contains ".configured/config-cheap/metadata.txt" "config_file="
  assert_contains ".configured/config-cheap/metadata.txt" ".ocw.toml"
  assert_contains "mock.log" "attach=http://localhost:4096"

  OCW_OPENCODE_BIN="$MOCK_OPENCODE" \
    OCW_CHEAP_MODEL="opencode-go/env-cheap" \
    OCW_MOCK_LOG="$PWD/mock.log" \
    OCW_TEST_CREATED_AT="2026-01-01T00:00:00Z" \
    OCW_TEST_STAMP="env" \
    "$OCW" cheap "env route" >/dev/null

  assert_contains ".configured/env-cheap/metadata.txt" "model=opencode-go/env-cheap"
}

test_diff_capture() {
  local repo="$TMP_ROOT/diff"
  make_repo "$repo"
  cd "$repo"

  OCW_TEST_STAMP="diff" run_ocw patch "OCW_MOCK_EDIT" >/dev/null

  assert_contains ".out/diff-patch/diff.after.patch" "mock edit from opencode-go/kimi-k2.6"
  assert_file ".out/diff-patch/status.before.txt"
  assert_contains ".out/diff-patch/status.after.txt" "M tracked.txt"
}

test_exit_code_capture() {
  local repo="$TMP_ROOT/fail"
  make_repo "$repo"
  cd "$repo"

  set +e
  OCW_TEST_STAMP="fail" run_ocw cheap "OCW_MOCK_FAIL" >/dev/null
  local status=$?
  set -e

  [[ "$status" -eq 7 ]] || fail "expected exit 7, got $status"
  assert_contains ".out/fail-cheap/metadata.txt" "status=7"
  assert_contains ".out/fail-cheap/summary.md" "MOCK_FAIL opencode-go/qwen3.5-plus"
}

test_output_collision() {
  local repo="$TMP_ROOT/collision"
  local i latest
  make_repo "$repo"
  cd "$repo"

  OCW_TEST_STAMP="same" run_ocw cheap "first" >/dev/null
  OCW_TEST_STAMP="same" run_ocw cheap "second" >/dev/null
  for i in $(seq 3 12); do
    OCW_TEST_STAMP="same" run_ocw cheap "collision $i" >/dev/null
  done

  assert_dir ".out/same-cheap"
  assert_dir ".out/same-cheap-1"
  assert_dir ".out/same-cheap-11"
  latest="$(OCW_OUTPUT_ROOT=".out" "$OCW" last cheap)"
  [[ "$(basename "$latest")" == "same-cheap-11" ]] || fail "unexpected collision latest: $latest"
}

test_worktree_patch_isolation() {
  local repo="$TMP_ROOT/worktree"
  make_repo "$repo"
  cd "$repo"

  OCW_TEST_STAMP="wt" run_ocw --worktree patch "OCW_MOCK_EDIT" >/dev/null

  assert_not_contains "tracked.txt" "mock edit from opencode-go/kimi-k2.6"
  assert_contains ".out/wt-patch/diff.after.patch" "mock edit from opencode-go/kimi-k2.6"
  assert_contains ".out/wt-patch/metadata.txt" "worktree=1"
  assert_contains ".out/wt-patch/metadata.txt" "run_dir=$repo/.codex/opencode-worktrees/wt-patch"
}

test_require_clean() {
  local repo="$TMP_ROOT/require-clean"
  make_repo "$repo"
  cd "$repo"
  printf 'dirty\n' >> tracked.txt

  set +e
  run_ocw --require-clean cheap "should fail" >/dev/null 2>err.log
  local status=$?
  set -e

  [[ "$status" -eq 2 ]] || fail "expected exit 2, got $status"
  assert_contains "err.log" "git worktree is not clean"
}

test_init_project() {
  local repo="$TMP_ROOT/init"
  local codex_skills="$TMP_ROOT/init-codex-skills"
  local claude_skills="$TMP_ROOT/init-claude-skills"
  local opencode_skills="$TMP_ROOT/init-opencode-skills"
  local agents_skills="$TMP_ROOT/init-agents-skills"
  make_repo "$repo"
  cd "$repo"

  OCW_CODEX_SKILLS_DIR="$codex_skills" \
    OCW_CLAUDE_SKILLS_DIR="$claude_skills" \
    OCW_OPENCODE_SKILLS_DIR="$opencode_skills" \
    OCW_AGENTS_SKILLS_DIR="$agents_skills" \
    "$OCW" init >/dev/null

  assert_file ".gitignore"
  assert_file ".ocw.toml"
  assert_file "AGENTS.md"
  assert_file "CLAUDE.md"
  assert_contains ".gitignore" ".codex/opencode-workers/"
  assert_contains ".gitignore" ".codex/opencode-worktrees/"
  assert_contains ".ocw.toml" "[models]"
  assert_contains ".ocw.toml" "worktree = true"
  assert_file "$codex_skills/opencode-worker/SKILL.md"
  assert_file "$claude_skills/opencode-worker/SKILL.md"
  assert_file "$opencode_skills/opencode-worker/SKILL.md"
  assert_file "$agents_skills/opencode-worker/SKILL.md"

  "$OCW" init --project-skills >/dev/null
  assert_file ".opencode/skills/opencode-worker/SKILL.md"
  assert_file ".claude/skills/opencode-worker/SKILL.md"
  assert_file ".agents/skills/opencode-worker/SKILL.md"
}

test_uninstall_command() {
  local repo="$TMP_ROOT/uninstall"
  local install_dir="$TMP_ROOT/uninstall-bin"
  local codex_skills="$TMP_ROOT/uninstall-codex-skills"
  local claude_skills="$TMP_ROOT/uninstall-claude-skills"
  local opencode_skills="$TMP_ROOT/uninstall-opencode-skills"
  local agents_skills="$TMP_ROOT/uninstall-agents-skills"
  local dry_run output
  make_repo "$repo"
  cd "$repo"

  OCW_INSTALL_DIR="$install_dir" "$ROOT/install.sh" >/dev/null
  assert_file "$install_dir/ocw"

  OCW_CODEX_SKILLS_DIR="$codex_skills" \
    OCW_CLAUDE_SKILLS_DIR="$claude_skills" \
    OCW_OPENCODE_SKILLS_DIR="$opencode_skills" \
    OCW_AGENTS_SKILLS_DIR="$agents_skills" \
    "$OCW" init --project-skills >/dev/null
  "$OCW" agent-pack install >/dev/null

  dry_run="$TMP_ROOT/uninstall-dry-run.txt"
  OCW_INSTALL_DIR="$install_dir" \
    OCW_CODEX_SKILLS_DIR="$codex_skills" \
    OCW_CLAUDE_SKILLS_DIR="$claude_skills" \
    OCW_OPENCODE_SKILLS_DIR="$opencode_skills" \
    OCW_AGENTS_SKILLS_DIR="$agents_skills" \
    "$OCW" uninstall --all --dry-run > "$dry_run"
  assert_contains "$dry_run" "Would remove binary"
  assert_file "$install_dir/ocw"
  assert_file ".ocw.toml"

  output="$TMP_ROOT/uninstall-output.txt"
  OCW_INSTALL_DIR="$install_dir" \
    OCW_CODEX_SKILLS_DIR="$codex_skills" \
    OCW_CLAUDE_SKILLS_DIR="$claude_skills" \
    OCW_OPENCODE_SKILLS_DIR="$opencode_skills" \
    OCW_AGENTS_SKILLS_DIR="$agents_skills" \
    "$OCW" uninstall --all --yes > "$output"
  assert_contains "$output" "OCW uninstall complete"

  [[ ! -e "$install_dir/ocw" ]] || fail "expected binary uninstall"
  [[ ! -d "$codex_skills/opencode-worker" ]] || fail "expected Codex skill uninstall"
  [[ ! -d "$claude_skills/opencode-worker" ]] || fail "expected Claude skill uninstall"
  [[ ! -d "$opencode_skills/opencode-worker" ]] || fail "expected OpenCode skill uninstall"
  [[ ! -d "$agents_skills/opencode-worker" ]] || fail "expected Agents skill uninstall"
  [[ ! -e ".ocw.toml" ]] || fail "expected config uninstall"
  [[ ! -e "AGENTS.md" ]] || fail "expected AGENTS uninstall"
  [[ ! -e "CLAUDE.md" ]] || fail "expected CLAUDE uninstall"
  [[ ! -d ".opencode/skills/opencode-worker" ]] || fail "expected project OpenCode skill uninstall"
  [[ ! -d ".claude/skills/opencode-worker" ]] || fail "expected project Claude skill uninstall"
  [[ ! -d ".agents/skills/opencode-worker" ]] || fail "expected project Agents skill uninstall"
  [[ ! -e ".opencode/agents/ocw-explorer.md" ]] || fail "expected OpenCode agent uninstall"
  assert_not_contains ".gitignore" ".codex/opencode-workers/"
  assert_not_contains ".gitignore" ".codex/opencode-worktrees/"
}

test_last_show_clean() {
  local repo="$TMP_ROOT/artifacts"
  local latest summary clean_list
  make_repo "$repo"
  cd "$repo"

  OCW_TEST_STAMP="a" run_ocw cheap "first" >/dev/null
  OCW_TEST_STAMP="b" run_ocw review "second" >/dev/null

  latest="$(OCW_OUTPUT_ROOT=".out" "$OCW" last)"
  [[ "$(basename "$latest")" == "b-review" ]] || fail "unexpected latest: $latest"

  latest="$(OCW_OUTPUT_ROOT=".out" "$OCW" last cheap)"
  [[ "$(basename "$latest")" == "a-cheap" ]] || fail "unexpected latest cheap: $latest"

  summary="$TMP_ROOT/show-summary.txt"
  OCW_OUTPUT_ROOT=".out" "$OCW" show latest --summary > "$summary"
  assert_contains "$summary" "MOCK_OK model=opencode-go/deepseek-v4-pro"

  OCW_TEST_STAMP="c" run_ocw pr review 123 --repo owner/repo >/dev/null
  latest="$(OCW_OUTPUT_ROOT=".out" "$OCW" last)"
  [[ "$(basename "$latest")" == "c-pr-review" ]] || fail "unexpected latest after pr review: $latest"

  latest="$(OCW_OUTPUT_ROOT=".out" "$OCW" last review)"
  [[ "$(basename "$latest")" == "b-review" ]] || fail "expected worker review latest, got $latest"

  clean_list="$TMP_ROOT/clean-list.txt"
  OCW_OUTPUT_ROOT=".out" "$OCW" clean --all --dry-run > "$clean_list"
  assert_contains "$clean_list" "$repo/.out/a-cheap"
  assert_contains "$clean_list" "$repo/.out/b-review"

  OCW_OUTPUT_ROOT=".out" "$OCW" clean --all --yes >/dev/null
  assert_not_dir ".out/a-cheap"
  assert_not_dir ".out/b-review"
}

test_manifest_audit_and_cli_helpers() {
  local repo="$TMP_ROOT/audit"
  local manifest audit_output audit_json completion config fail_status
  make_repo "$repo"
  cd "$repo"

  OCW_OPENCODE_BIN="$MOCK_OPENCODE" \
    OCW_OUTPUT_ROOT=".out" \
    OCW_MOCK_LOG="$PWD/.out/mock.log" \
    OCW_TEST_CREATED_AT="2026-01-01T00:00:00Z" \
    OCW_TEST_STAMP="audit-ok" \
    "$OCW" cheap "audit ok" >/dev/null

  manifest="$TMP_ROOT/manifest.json"
  OCW_OUTPUT_ROOT=".out" "$OCW" manifest latest --json > "$manifest"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$manifest"
  assert_contains "$manifest" '"schema_version": "ocw.manifest.v1"'
  assert_contains "$manifest" '"summary.md"'
  assert_contains "$manifest" '"sha256"'

  audit_output="$TMP_ROOT/audit.txt"
  OCW_OUTPUT_ROOT=".out" "$OCW" audit latest > "$audit_output"
  assert_contains "$audit_output" "overall: ok"
  assert_contains "$audit_output" "summary.md is present"

  printf 'pre-existing\n' > local-note.txt
  OCW_OPENCODE_BIN="$MOCK_OPENCODE" \
    OCW_OUTPUT_ROOT=".out" \
    OCW_MOCK_LOG="$PWD/.out/mock.log" \
    OCW_TEST_CREATED_AT="2026-01-01T00:00:00Z" \
    OCW_TEST_STAMP="audit-preexisting-dirty" \
    "$OCW" cheap "audit preexisting dirty" >/dev/null

  OCW_OUTPUT_ROOT=".out" "$OCW" audit latest > "$audit_output"
  assert_contains "$audit_output" "overall: ok"
  assert_contains "$audit_output" "no unexpected git status changes"

  OCW_OPENCODE_BIN="$MOCK_OPENCODE" \
    OCW_OUTPUT_ROOT=".out" \
    OCW_MOCK_LOG="$PWD/.out/mock.log" \
    OCW_TEST_CREATED_AT="2026-01-01T00:00:00Z" \
    OCW_TEST_STAMP="audit-readonly-change" \
    "$OCW" cheap "OCW_MOCK_EDIT" >/dev/null

  OCW_OUTPUT_ROOT=".out" "$OCW" audit latest > "$audit_output"
  assert_contains "$audit_output" "overall: warn"
  assert_contains "$audit_output" "read-only mode left unexpected git status changes"

  completion="$TMP_ROOT/completion.txt"
  "$OCW" completions bash > "$completion"
  assert_contains "$completion" "_ocw()"
  assert_contains "$completion" "manifest audit"
  "$OCW" completions zsh > "$completion"
  assert_contains "$completion" "#compdef ocw"
  "$OCW" completions fish > "$completion"
  assert_contains "$completion" "complete -c ocw"

  config="$TMP_ROOT/mcp-config.txt"
  "$OCW" mcp-config codex > "$config"
  assert_contains "$config" "codex mcp add ocw -- ocw mcp"
  assert_contains "$config" "[mcp_servers.ocw]"
  "$OCW" mcp-config claude > "$config"
  assert_contains "$config" "claude mcp add --transport stdio ocw -- ocw mcp"
  "$OCW" mcp-config opencode > "$config"
  assert_contains "$config" '"command": ["ocw", "mcp"]'

  set +e
  OCW_OPENCODE_BIN="$MOCK_OPENCODE" \
    OCW_OUTPUT_ROOT=".out" \
    OCW_MOCK_LOG="$PWD/.out/mock.log" \
    OCW_TEST_CREATED_AT="2026-01-01T00:00:00Z" \
    OCW_TEST_STAMP="audit-fail" \
    "$OCW" cheap "OCW_MOCK_FAIL" >/dev/null
  fail_status=$?
  set -e
  [[ "$fail_status" -eq 7 ]] || fail "expected worker failure 7, got $fail_status"

  audit_json="$TMP_ROOT/audit-fail.json"
  set +e
  OCW_OUTPUT_ROOT=".out" "$OCW" audit audit-fail-cheap --json > "$audit_json"
  fail_status=$?
  set -e
  [[ "$fail_status" -eq 1 ]] || fail "expected audit failure 1, got $fail_status"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$audit_json"
  assert_contains "$audit_json" '"overall": "fail"'
  assert_contains "$audit_json" '"worker exited 7"'
}

test_apply_worktree_patch() {
  local repo="$TMP_ROOT/apply"
  local check_output apply_output
  make_repo "$repo"
  cd "$repo"

  OCW_OPENCODE_BIN="$MOCK_OPENCODE" \
    OCW_OUTPUT_ROOT=".out" \
    OCW_MOCK_LOG="$PWD/.out/mock.log" \
    OCW_TEST_CREATED_AT="2026-01-01T00:00:00Z" \
    OCW_TEST_STAMP="apply" \
    "$OCW" --worktree patch "OCW_MOCK_EDIT" >/dev/null

  assert_not_contains "tracked.txt" "mock edit from opencode-go/kimi-k2.6"

  check_output="$TMP_ROOT/apply-check.txt"
  OCW_OUTPUT_ROOT=".out" "$OCW" apply --check latest > "$check_output"
  assert_contains "$check_output" "Patch can be applied"

  apply_output="$TMP_ROOT/apply-output.txt"
  OCW_OUTPUT_ROOT=".out" "$OCW" apply latest > "$apply_output"
  assert_contains "$apply_output" "Applied patch"
  assert_contains "tracked.txt" "mock edit from opencode-go/kimi-k2.6"
}

test_stats_and_serve() {
  local output

  output="$(OCW_OPENCODE_BIN="$MOCK_OPENCODE" "$OCW" stats --days 7 --models 5)"
  grep -Fq "MOCK_STATS --days 7 --models 5" <<< "$output"

  output="$(OCW_OPENCODE_BIN="$MOCK_OPENCODE" "$OCW" serve --port 4096 --hostname 127.0.0.1)"
  grep -Fq "MOCK_SERVE --port 4096 --hostname 127.0.0.1" <<< "$output"
}

test_skill_assets() {
  assert_file "$ROOT/skills/opencode-worker/SKILL.md"
  assert_contains "$ROOT/skills/opencode-worker/SKILL.md" "name: opencode-worker"
  assert_contains "$ROOT/skills/opencode-worker/SKILL.md" "description: Use ocw"
}

test_plugin_assets() {
  assert_file "$ROOT/plugins/claude/ocw/.claude-plugin/plugin.json"
  assert_file "$ROOT/plugins/claude/ocw/skills/opencode-worker/SKILL.md"
  assert_contains "$ROOT/plugins/claude/ocw/.claude-plugin/plugin.json" '"name": "ocw"'
  cmp -s "$ROOT/skills/opencode-worker/SKILL.md" "$ROOT/plugins/claude/ocw/skills/opencode-worker/SKILL.md" \
    || fail "Claude plugin skill differs from shared skill"
}

test_skill_installer() {
  local codex_skills="$TMP_ROOT/codex-skills"
  local claude_skills="$TMP_ROOT/claude-skills"
  local opencode_skills="$TMP_ROOT/opencode-skills"
  local agents_skills="$TMP_ROOT/agents-skills"

  OCW_CODEX_SKILLS_DIR="$codex_skills" \
    OCW_CLAUDE_SKILLS_DIR="$claude_skills" \
    OCW_OPENCODE_SKILLS_DIR="$opencode_skills" \
    OCW_AGENTS_SKILLS_DIR="$agents_skills" \
    "$ROOT/scripts/install-skills.sh" all >/dev/null

  assert_file "$codex_skills/opencode-worker/SKILL.md"
  assert_file "$claude_skills/opencode-worker/SKILL.md"
  assert_file "$opencode_skills/opencode-worker/SKILL.md"
  assert_file "$agents_skills/opencode-worker/SKILL.md"
  assert_contains "$codex_skills/opencode-worker/SKILL.md" "name: opencode-worker"
  assert_contains "$claude_skills/opencode-worker/SKILL.md" "name: opencode-worker"
  assert_contains "$opencode_skills/opencode-worker/SKILL.md" "name: opencode-worker"
  assert_contains "$agents_skills/opencode-worker/SKILL.md" "name: opencode-worker"
}

test_agent_pack_install() {
  local repo="$TMP_ROOT/agent-pack"
  make_repo "$repo"
  cd "$repo"

  "$OCW" agent-pack install >/dev/null

  assert_file ".opencode/agents/ocw-explorer.md"
  assert_file ".opencode/agents/ocw-reviewer.md"
  assert_file ".opencode/agents/ocw-patcher.md"
  assert_file ".opencode/agents/ocw-triage.md"
  assert_contains ".opencode/agents/ocw-explorer.md" "model: opencode-go/deepseek-v4-flash"
  assert_contains ".opencode/agents/ocw-patcher.md" "edit: allow"
}

test_bench_command() {
  local repo="$TMP_ROOT/bench"
  make_repo "$repo"
  cd "$repo"

  OCW_TEST_STAMP="bench" run_ocw bench \
    --models opencode-go/qwen3.5-plus,opencode-go/deepseek-v4-flash \
    --iterations 2 >/dev/null

  assert_file ".out/bench-bench/bench.md"
  assert_file ".out/bench-bench/bench.tsv"
  assert_contains ".out/bench-bench/bench.md" "opencode-go/qwen3.5-plus"
  assert_contains ".out/bench-bench/bench.tsv" "opencode-go/deepseek-v4-flash"
}

test_batch_command() {
  local repo="$TMP_ROOT/batch"
  local latest audit_output
  make_repo "$repo"
  cd "$repo"

  cat > tasks.ocw <<'EOF'
# mode|task
cheap|Summarize tracked.txt
review|Review the current diff
EOF

  OCW_TEST_STAMP="batch" run_ocw batch tasks.ocw --concurrency 2 >/dev/null

  assert_file ".out/batch-batch/batch.tsv"
  assert_contains ".out/batch-batch/batch.tsv" "cheap"
  assert_contains ".out/batch-batch/batch.tsv" "review"
  assert_dir ".out/batch-batch-1-cheap"
  assert_dir ".out/batch-batch-2-review"
  latest="$(OCW_OUTPUT_ROOT=".out" "$OCW" last)"
  [[ "$(basename "$latest")" == "batch-batch" ]] || fail "expected latest batch aggregate, got $latest"
  audit_output="$TMP_ROOT/batch-audit.txt"
  OCW_OUTPUT_ROOT=".out" "$OCW" audit latest > "$audit_output"
  assert_contains "$audit_output" "overall: ok"
  assert_contains "$audit_output" "all batch workers exited 0"
}

test_extended_cli_features() {
  local repo="$TMP_ROOT/extended"
  local codex_skills="$TMP_ROOT/extended-codex-skills"
  local claude_skills="$TMP_ROOT/extended-claude-skills"
  local opencode_skills="$TMP_ROOT/extended-opencode-skills"
  local agents_skills="$TMP_ROOT/extended-agents-skills"
  local doctor_json audit_output policy_output gh_dir
  make_repo "$repo"
  cd "$repo"

  doctor_json="$TMP_ROOT/doctor.json"
  OCW_OPENCODE_BIN="$MOCK_OPENCODE" \
    OCW_OUTPUT_ROOT=".out" \
    OCW_CODEX_SKILLS_DIR="$codex_skills" \
    OCW_CLAUDE_SKILLS_DIR="$claude_skills" \
    OCW_OPENCODE_SKILLS_DIR="$opencode_skills" \
    OCW_AGENTS_SKILLS_DIR="$agents_skills" \
    "$OCW" doctor --deep --json --fix > "$doctor_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$doctor_json"
  assert_contains "$doctor_json" '"schema_version": "ocw.doctor.v1"'
  assert_file "$codex_skills/opencode-worker/SKILL.md"

  OCW_TEST_STAMP="extended-cheap" run_ocw cheap "extended report" >/dev/null
  OCW_OUTPUT_ROOT=".out" "$OCW" report latest --json --out reports/report.json >/dev/null
  OCW_OUTPUT_ROOT=".out" "$OCW" report latest --html --out reports/report.html >/dev/null
  OCW_OUTPUT_ROOT=".out" "$OCW" report latest --junit --out reports/report.xml >/dev/null
  OCW_OUTPUT_ROOT=".out" "$OCW" report latest --sarif --out reports/report.sarif >/dev/null
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" reports/report.json
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" reports/report.sarif
  assert_contains reports/report.json '"schema_version": "ocw.report.v1"'
  assert_contains reports/report.html "<h1>OCW report"
  assert_contains reports/report.xml '<testsuite name="ocw"'

  cat > eval.ocw <<'EOF'
cheap|Return MOCK_OK for eval|MOCK_OK
review|Return MOCK_OK for review eval|MOCK_OK
EOF
  OCW_TEST_STAMP="extended-eval" run_ocw eval eval.ocw --iterations 1 >/dev/null
  assert_file ".out/extended-eval-eval/eval.md"
  assert_file ".out/extended-eval-eval/eval.tsv"
  assert_contains ".out/extended-eval-eval/eval.tsv" "MOCK_OK"
  audit_output="$TMP_ROOT/eval-audit.txt"
  OCW_OUTPUT_ROOT=".out" "$OCW" audit latest > "$audit_output"
  assert_contains "$audit_output" "overall: ok"
  assert_contains "$audit_output" "all eval expectations are present"

  "$OCW" agents sync --force >/dev/null
  "$OCW" agents doctor >/dev/null
  "$OCW" agents diff >/dev/null
  assert_file ".opencode/agents/ocw-patcher.md"

  "$OCW" policy init strict --force >/dev/null
  policy_output="$TMP_ROOT/policy.txt"
  "$OCW" policy show > "$policy_output"
  assert_contains "$policy_output" 'profile = "strict"'
  OCW_OUTPUT_ROOT=".out" "$OCW" policy check latest > "$policy_output"
  assert_contains "$policy_output" "policy: ok"

  gh_dir="$TMP_ROOT/gh-ext"
  "$OCW" gh-extension install --dir "$gh_dir" >/dev/null
  assert_file "$gh_dir/gh-ocw"
  assert_contains "$gh_dir/gh-ocw" 'exec ocw "$@"'

  "$OCW" security policy > "$TMP_ROOT/security-policy.txt"
  assert_contains "$TMP_ROOT/security-policy.txt" "Scorecard"
  "$OCW" security init --force >/dev/null
  assert_file ".github/workflows/scorecard.yml"
  assert_contains ".github/workflows/scorecard.yml" "ossf/scorecard-action"
  assert_contains ".github/workflows/scorecard.yml" "actions/checkout@v6"
}

test_pr_summary_command() {
  local repo="$TMP_ROOT/pr-summary"
  make_repo "$repo"
  cd "$repo"

  OCW_TEST_STAMP="prsum" run_ocw pr summary 123 --repo owner/repo >/dev/null

  assert_file ".out/prsum-pr-summary/pr.txt"
  assert_file ".out/prsum-pr-summary/pr.diff.patch"
  assert_file ".out/prsum-pr-summary/pr.files.txt"
  assert_file ".out/prsum-pr-summary/workers.tsv"
  assert_file ".out/prsum-pr-summary/summary.md"
  assert_file ".out/prsum-pr-summary/metadata.txt"
  assert_contains ".out/prsum-pr-summary/pr.txt" "Mock PR 123"
  assert_contains ".out/prsum-pr-summary/pr.diff.patch" "diff --git"
  assert_contains ".out/prsum-pr-summary/pr.files.txt" "src/example.go"
  assert_contains ".out/prsum-pr-summary/workers.tsv" "summary"
  assert_contains ".out/prsum-pr-summary/summary.md" "OCW PR summary"
  assert_contains ".out/prsum-pr-summary/metadata.txt" "mode=pr-summary"
  assert_contains ".out/prsum-pr-summary/metadata.txt" "repo=owner/repo"
  assert_dir ".out/prsum-pr-summary/workers/summary-cheap"
  assert_contains "mock.log" "files="
  assert_contains "mock.log" "pr.txt"
  assert_contains "mock.log" "pr.diff.patch"
  assert_contains "mock.log" "pr.files.txt"
  assert_contains "gh.log" "mode=patch"
}

test_pr_review_command() {
  local repo="$TMP_ROOT/pr-review"
  make_repo "$repo"
  cd "$repo"

  OCW_TEST_STAMP="prrev" run_ocw pr review 123 --repo owner/repo >/dev/null

  assert_file ".out/prrev-pr-review/pr.txt"
  assert_file ".out/prrev-pr-review/pr.diff.patch"
  assert_file ".out/prrev-pr-review/pr.files.txt"
  assert_file ".out/prrev-pr-review/workers.tsv"
  assert_file ".out/prrev-pr-review/review.md"
  assert_file ".out/prrev-pr-review/summary.md"
  assert_file ".out/prrev-pr-review/metadata.txt"
  assert_contains ".out/prrev-pr-review/workers.tsv" "findings"
  assert_contains ".out/prrev-pr-review/workers.tsv" "risk-tests"
  assert_contains ".out/prrev-pr-review/review.md" "OCW PR review"
  assert_contains ".out/prrev-pr-review/review.md" "Findings worker"
  assert_contains ".out/prrev-pr-review/review.md" "Risk and tests worker"
  assert_contains ".out/prrev-pr-review/metadata.txt" "mode=pr-review"
  assert_dir ".out/prrev-pr-review/workers/findings-cheap"
  assert_dir ".out/prrev-pr-review/workers/risk-tests-cheap"
}

test_mcp_server() {
  node "$ROOT/test/mcp-smoke.js"
}

run_test "help and doctor" test_help_and_doctor
run_test "default routing" test_default_routing
run_test "overrides and summary" test_overrides_and_summary
run_test "config routing and attach" test_config_routing_and_attach
run_test "diff capture" test_diff_capture
run_test "exit code capture" test_exit_code_capture
run_test "output collision" test_output_collision
run_test "worktree patch isolation" test_worktree_patch_isolation
run_test "require clean" test_require_clean
run_test "init project" test_init_project
run_test "uninstall command" test_uninstall_command
run_test "last show clean" test_last_show_clean
run_test "manifest audit and cli helpers" test_manifest_audit_and_cli_helpers
run_test "apply worktree patch" test_apply_worktree_patch
run_test "stats and serve" test_stats_and_serve
run_test "skill assets" test_skill_assets
run_test "plugin assets" test_plugin_assets
run_test "skill installer" test_skill_installer
run_test "agent pack install" test_agent_pack_install
run_test "bench command" test_bench_command
run_test "batch command" test_batch_command
run_test "extended cli features" test_extended_cli_features
run_test "pr summary command" test_pr_summary_command
run_test "pr review command" test_pr_review_command
run_test "mcp server" test_mcp_server

say "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
