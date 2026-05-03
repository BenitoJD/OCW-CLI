#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OCW="$ROOT/bin/ocw"
MOCK_OPENCODE="$ROOT/test/fixtures/opencode"
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
    OCW_OUTPUT_ROOT=".out" \
    OCW_MOCK_LOG="$PWD/mock.log" \
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
  grep -Fq 'ocw 0.2.0-alpha' <<< "$output"
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
  make_repo "$repo"
  cd "$repo"

  OCW_TEST_STAMP="same" run_ocw cheap "first" >/dev/null
  OCW_TEST_STAMP="same" run_ocw cheap "second" >/dev/null

  assert_dir ".out/same-cheap"
  assert_dir ".out/same-cheap-1"
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
  make_repo "$repo"
  cd "$repo"

  OCW_CODEX_SKILLS_DIR="$codex_skills" \
    OCW_CLAUDE_SKILLS_DIR="$claude_skills" \
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

  clean_list="$TMP_ROOT/clean-list.txt"
  OCW_OUTPUT_ROOT=".out" "$OCW" clean --all --dry-run > "$clean_list"
  assert_contains "$clean_list" "$repo/.out/a-cheap"
  assert_contains "$clean_list" "$repo/.out/b-review"

  OCW_OUTPUT_ROOT=".out" "$OCW" clean --all --yes >/dev/null
  assert_not_dir ".out/a-cheap"
  assert_not_dir ".out/b-review"
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

  OCW_CODEX_SKILLS_DIR="$codex_skills" \
    OCW_CLAUDE_SKILLS_DIR="$claude_skills" \
    "$ROOT/scripts/install-skills.sh" both >/dev/null

  assert_file "$codex_skills/opencode-worker/SKILL.md"
  assert_file "$claude_skills/opencode-worker/SKILL.md"
  assert_contains "$codex_skills/opencode-worker/SKILL.md" "name: opencode-worker"
  assert_contains "$claude_skills/opencode-worker/SKILL.md" "name: opencode-worker"
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
run_test "last show clean" test_last_show_clean
run_test "apply worktree patch" test_apply_worktree_patch
run_test "stats and serve" test_stats_and_serve
run_test "skill assets" test_skill_assets
run_test "plugin assets" test_plugin_assets
run_test "skill installer" test_skill_installer

say "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
