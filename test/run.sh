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
unset OCW_API_KEYS OCW_KEYS_FILE OCW_API_KEY_ENV OCW_KEY_ROTATION OCW_KEY_MAX_ATTEMPTS OPENCODE_API_KEY CUSTOM_OCW_KEY

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

assert_absent() {
  [[ ! -e "$1" ]] || fail "unexpected path: $1"
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || {
    say "--- $file"
    sed -n '1,160p' "$file" || true
    fail "expected '$expected' in $file"
  }
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  ! grep -Fq -- "$unexpected" "$file" || fail "did not expect '$unexpected' in $file"
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
  local output status
  "$OCW" --help >/dev/null
  "$OCW" help config >/dev/null
  "$OCW" help mcp >/dev/null
  output="$(OCW_OPENCODE_BIN="$MOCK_OPENCODE" "$OCW" doctor)"
  grep -Fq 'ocw 0.8.0-alpha' <<< "$output"
  output="$(OCW_OPENCODE_BIN="$MOCK_OPENCODE" OCW_OUTPUT_ROOT="$TMP_ROOT/doctor-out" "$OCW" doctor --deep)"
  grep -Fq 'doctor deep: ok' <<< "$output"
  grep -Fq 'opencode-go model count: 5' <<< "$output"

  set +e
  "$OCW" suport > "$TMP_ROOT/help-suggest.out" 2> "$TMP_ROOT/help-suggest.err"
  status=$?
  set -e
  [[ "$status" -eq 2 ]] || fail "expected unknown command status 2, got $status"
  assert_contains "$TMP_ROOT/help-suggest.err" "Did you mean: ocw support"
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

test_key_management_and_rotation() {
  local repo="$TMP_ROOT/keys"
  local keys_json doctor_json status
  make_repo "$repo"
  cd "$repo"

  "$OCW" keys set primary --value fail-key --env OPENCODE_API_KEY --activate >/dev/null
  assert_contains ".gitignore" ".codex/ocw-keys.tsv"
  "$OCW" keys set backup --value good-key --env OPENCODE_API_KEY --force >/dev/null
  "$OCW" keys list --json > "$TMP_ROOT/keys-list.json"
  node -e "const data = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (data.keys.length !== 2 || data.keys[0].name !== 'primary' || data.keys[0].fingerprint.includes('fail-key')) process.exit(1)" "$TMP_ROOT/keys-list.json"

  set +e
  OCW_TEST_STAMP="keys-rotate" run_ocw cheap "key rotation" > "$TMP_ROOT/keys-rotate.out" 2> "$TMP_ROOT/keys-rotate.err"
  status=$?
  set -e
  [[ "$status" -eq 0 ]] || fail "expected key rotation success, got $status"
  assert_contains "$TMP_ROOT/keys-rotate.err" "trying next key"
  assert_contains ".out/keys-rotate-cheap/metadata.txt" "key_name=backup"
  assert_contains ".out/keys-rotate-cheap/metadata.txt" "key_attempts=2"
  assert_contains ".out/keys-rotate-cheap/result.key-attempts.tsv" "primary"
  assert_contains ".out/keys-rotate-cheap/result.key-attempts.tsv" "auth_or_quota"
  assert_contains "mock.log" "api_key=fail-key"
  assert_contains "mock.log" "api_key=good-key"
  assert_not_contains ".out/keys-rotate-cheap/metadata.txt" "good-key"
  assert_not_contains "$TMP_ROOT/keys-rotate.err" "fail-key"
  assert_not_contains ".out/keys-rotate-cheap/result.attempt-1.jsonl" "fail-key"
  assert_not_contains ".out/keys-rotate-cheap/stderr.attempt-1.txt" "fail-key"

  "$OCW" keys set custom --value custom-good --env CUSTOM_OCW_KEY --activate --force >/dev/null
  OCW_TEST_STAMP="keys-custom" run_ocw cheap "custom key env" >/dev/null
  assert_contains ".out/keys-custom-cheap/metadata.txt" "key_name=custom"
  assert_contains ".out/keys-custom-cheap/metadata.txt" "key_env=CUSTOM_OCW_KEY"
  assert_contains "mock.log" "api_key=custom-good"

  "$OCW" keys use backup >/dev/null
  keys_json="$TMP_ROOT/keys-use.json"
  "$OCW" keys list --json > "$keys_json"
  node -e "const data = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (data.keys[0].name !== 'backup' || !data.keys[0].active) process.exit(1)" "$keys_json"
  "$OCW" keys remove primary >/dev/null
  "$OCW" keys doctor --json > "$TMP_ROOT/keys-doctor.json"
  doctor_json="$TMP_ROOT/keys-doctor.json"
  node -e "const data = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (data.count !== 2 || data.severity !== 'ok') process.exit(1)" "$doctor_json"

  OCW_API_KEYS="fail-env,good-env" OCW_TEST_STAMP="keys-env" run_ocw cheap "env key rotation" >/dev/null 2> "$TMP_ROOT/keys-env.err"
  assert_contains ".out/keys-env-cheap/metadata.txt" "key_name=env-2"
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
  assert_contains ".gitignore" ".codex/ocw-keys.tsv"
  assert_contains ".gitignore" ".codex/ocw-bridge/"
  assert_contains ".gitignore" ".codex/ocw-bridge-results/"
  assert_contains ".gitignore" ".codex/ocw-bridge-worktrees/"
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
  assert_not_contains ".gitignore" ".codex/ocw-keys.tsv"
  assert_not_contains ".gitignore" ".codex/ocw-bridge/"
  assert_not_contains ".gitignore" ".codex/ocw-bridge-results/"
  assert_not_contains ".gitignore" ".codex/ocw-bridge-worktrees/"
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

test_world_class_workflows() {
  local repo="$TMP_ROOT/world-class"
  local models_json models_out route_json memory_json dashboard_json audit_json audit_output eval_file
  make_repo "$repo"
  cd "$repo"

  cat > models.json <<'EOF'
{
  "models": [
    { "id": "opencode-go/test-a" },
    { "model": "opencode-go/test-b" },
    { "id": "test-c", "owned_by": "opencode" }
  ]
}
EOF

  models_json="$TMP_ROOT/models-sync.json"
  "$OCW" models sync --url "file://$PWD/models.json" --out ".codex/models.json" --json > "$models_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$models_json"
  assert_contains "$models_json" '"schema_version": "ocw.models.sync.v1"'
  assert_contains "$models_json" 'opencode-go/test-a'
  assert_contains "$models_json" 'opencode-go/test-c'

  models_out="$TMP_ROOT/models-list.txt"
  "$OCW" models list --cache ".codex/models.json" > "$models_out"
  assert_contains "$models_out" "opencode-go/test-b"
  "$OCW" models list --cache ".codex/models.json" --metadata --json > "$TMP_ROOT/models-metadata.json"
  node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); const m = j.models.find((item) => item.id === 'opencode-go/test-a'); if (!m || !m.roles.includes('custom')) process.exit(1)" "$TMP_ROOT/models-metadata.json"

  "$OCW" models profiles --json > "$TMP_ROOT/models-profiles.json"
  node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (!j.profiles.some((item) => item.name === 'balanced')) process.exit(1)" "$TMP_ROOT/models-profiles.json"
  "$OCW" models recommend patch --profile balanced --cache ".codex/models.json" --json > "$TMP_ROOT/models-recommend.json"
  node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (j.model !== 'opencode-go/test-a') process.exit(1)" "$TMP_ROOT/models-recommend.json"
  "$OCW" models configure balanced --cache ".codex/models.json" \
    --cheap opencode-go/test-a \
    --explore opencode-go/test-b \
    --scan opencode-go/test-c \
    --review opencode-go/test-a \
    --patch opencode-go/test-b \
    --dry-run --json > "$TMP_ROOT/models-configure-dry.json"
  node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (j.dry_run !== true || j.routes.length !== 5) process.exit(1)" "$TMP_ROOT/models-configure-dry.json"
  "$OCW" models configure balanced --cache ".codex/models.json" \
    --cheap opencode-go/test-a \
    --explore opencode-go/test-b \
    --scan opencode-go/test-c \
    --review opencode-go/test-a \
    --patch opencode-go/test-b \
    --reason "unit profile" --json > "$TMP_ROOT/models-configure.json"
  node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (j.dry_run !== false || j.routes.length !== 5) process.exit(1)" "$TMP_ROOT/models-configure.json"

  "$OCW" route set cheap opencode-go/test-a --reason "unit route" >/dev/null
  route_json="$TMP_ROOT/route.json"
  "$OCW" route explain cheap --json > "$route_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$route_json"
  assert_contains "$route_json" '"source": "route"'
  assert_contains "$route_json" 'opencode-go/test-a'
  "$OCW" route doctor --cache ".codex/models.json" --json > "$TMP_ROOT/route-doctor.json"
  node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (j.ok !== true || !j.checks.every((check) => check.known === true)) process.exit(1)" "$TMP_ROOT/route-doctor.json"

  OCW_TEST_STAMP="world-route" run_ocw cheap "route file should drive this worker" >/dev/null
  assert_contains ".out/world-route-cheap/metadata.txt" "model=opencode-go/test-a"

  OCW_TEST_STAMP="world-delegate" run_ocw delegate --mode review --json "Review current diff for concrete bugs" > "$TMP_ROOT/delegate.json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$TMP_ROOT/delegate.json"
  assert_contains "$TMP_ROOT/delegate.json" '"schema_version": "ocw.delegate.v1"'
  assert_contains ".out/world-delegate-review/metadata.txt" "delegate=1"
  assert_file ".out/world-delegate-review/delegate.md"

  OCW_TEST_STAMP="world-debug" run_ocw delegate --json "debug the rate limiter path" > "$TMP_ROOT/delegate-debug.json"
  node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (j.mode !== 'cheap') process.exit(1)" "$TMP_ROOT/delegate-debug.json"

  OCW_OUTPUT_ROOT=".out" "$OCW" verdict latest --json > "$TMP_ROOT/verdict.json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$TMP_ROOT/verdict.json"
  assert_contains "$TMP_ROOT/verdict.json" '"schema_version": "ocw.verdict.v1"'

  OCW_OUTPUT_ROOT=".out" "$OCW" savings --json --frontier-cost-per-unit 1 --worker-cost-per-unit 0.1 > "$TMP_ROOT/savings.json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$TMP_ROOT/savings.json"
  assert_contains "$TMP_ROOT/savings.json" '"schema_version": "ocw.savings.v1"'
  node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if ((j.delegated_runs || 0) < 1) process.exit(1)" "$TMP_ROOT/savings.json"

  "$OCW" backend list --json > "$TMP_ROOT/backend-list.json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$TMP_ROOT/backend-list.json"
  assert_contains "$TMP_ROOT/backend-list.json" '"name": "opencode-go"'
  "$OCW" backend add opencode-go --force --json > "$TMP_ROOT/backend-add.json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$TMP_ROOT/backend-add.json"
  "$OCW" backend add custom-local --kind agent --command "$MOCK_OPENCODE" --note "custom test adapter" --force --json > "$TMP_ROOT/backend-custom-add.json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$TMP_ROOT/backend-custom-add.json"
  "$OCW" backend list --json > "$TMP_ROOT/backend-custom-list.json"
  node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); const b = j.backends.find((item) => item.name === 'custom-local'); if (!b || b.command !== process.argv[2] || b.available !== true) process.exit(1)" "$TMP_ROOT/backend-custom-list.json" "$MOCK_OPENCODE"
  OCW_OPENCODE_BIN="$MOCK_OPENCODE" "$OCW" backend doctor --json > "$TMP_ROOT/backend-doctor.json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$TMP_ROOT/backend-doctor.json"
  assert_contains "$TMP_ROOT/backend-doctor.json" '"name": "opencode-go"'
  assert_contains "$TMP_ROOT/backend-doctor.json" '"name": "custom-local"'

  "$OCW" memory add framework "OCW is implemented as a Bash CLI" --tags cli >/dev/null
  "$OCW" memory search framework > "$TMP_ROOT/memory-search.txt"
  assert_contains "$TMP_ROOT/memory-search.txt" "Bash CLI"
  memory_json="$TMP_ROOT/memory.json"
  "$OCW" memory export --json > "$memory_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$memory_json"
  assert_contains "$memory_json" '"schema_version": "ocw.memory.v1"'

  OCW_TEST_STAMP="world-memory" run_ocw cheap "framework" >/dev/null
  assert_contains "mock.log" "Project memory"

  OCW_TEST_STAMP="world-tournament" run_ocw tournament cheap \
    --models opencode-go/test-a,opencode-go/test-b \
    --judge-model opencode-go/test-b \
    "Compare the implementation approach" >/dev/null
  assert_file ".out/world-tournament-tournament/candidates.tsv"
  assert_file ".out/world-tournament-tournament/decision.md"
  assert_contains ".out/world-tournament-tournament/metadata.txt" "mode=tournament"
  audit_output="$TMP_ROOT/tournament-audit.txt"
  OCW_OUTPUT_ROOT=".out" "$OCW" audit world-tournament-tournament > "$audit_output"
  assert_contains "$audit_output" "all tournament candidates exited 0"

  OCW_TEST_STAMP="world-model-bench" run_ocw models bench \
    --models opencode-go/test-a,opencode-go/test-b \
    --iterations 1 \
    --promote review >/dev/null
  "$OCW" route explain review > "$TMP_ROOT/route-review.txt"
  assert_contains "$TMP_ROOT/route-review.txt" "bench world-model-bench-bench"

  "$OCW" hooks install all --force >/dev/null
  assert_file ".codex/ocw-hooks/post-task.sh"
  assert_file ".claude/settings.json"
  assert_file ".github/copilot-instructions.md"
  assert_file ".github/prompts/ocw-pr-review.prompt.md"
  assert_file ".github/agents/ocw-reviewer.agent.md"
  assert_file ".opencode/commands/ocw-review.md"
  "$OCW" copilot doctor >/dev/null

  eval_file="$TMP_ROOT/generated.ocw"
  "$OCW" eval generate --out "$eval_file" --force >/dev/null
  assert_file "$eval_file"
  assert_contains "$eval_file" "mode|task|expected substring"

  "$OCW" dashboard --out ".codex/ocw-dashboard.html" >/dev/null
  assert_file ".codex/ocw-dashboard.html"
  assert_contains ".codex/ocw-dashboard.html" "OCW Dashboard"
  dashboard_json="$TMP_ROOT/dashboard.json"
  OCW_OUTPUT_ROOT=".out" "$OCW" dashboard --json > "$dashboard_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$dashboard_json"
  assert_contains "$dashboard_json" '"schema_version": "ocw.dashboard.v1"'

  audit_json="$TMP_ROOT/mcp-audit.json"
  "$OCW" mcp audit --json > "$audit_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$audit_json"
  assert_contains "$audit_json" '"schema_version": "ocw.mcp.audit.v1"'
  assert_contains "$audit_json" '"overall": "ok"'
}

test_hardening_security_and_ux() {
  local repo="$TMP_ROOT/hardening"
  local status fake_curl curl_log missing_node broken_gh quick_json setup_json explain_json
  local codex_skills="$TMP_ROOT/hardening-codex-skills"
  make_repo "$repo"
  cd "$repo"

  printf '{bad json\n' > bad-models.json
  set +e
  "$OCW" models sync --url "file://$PWD/bad-models.json" --out ".codex/bad-models.json" --json > "$TMP_ROOT/bad-models.out" 2> "$TMP_ROOT/bad-models.err"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "expected bad model JSON to fail"
  assert_contains "$TMP_ROOT/bad-models.err" "[invalid_json]"
  [[ ! -f ".codex/bad-models.json" ]] || fail "invalid model catalog was written"

  set +e
  OCW_CURL_BIN="$TMP_ROOT/missing-curl" "$OCW" models sync --url "https://example.invalid/models.json" --timeout 1 --out ".codex/models.json" > "$TMP_ROOT/missing-curl.out" 2> "$TMP_ROOT/missing-curl.err"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "expected missing curl to fail"
  assert_contains "$TMP_ROOT/missing-curl.err" "[missing_dependency]"

  fake_curl="$TMP_ROOT/fake-curl"
  curl_log="$TMP_ROOT/fake-curl.log"
  cat > "$fake_curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$OCW_FAKE_CURL_LOG"
exit 28
EOF
  chmod +x "$fake_curl"
  set +e
  OCW_CURL_BIN="$fake_curl" OCW_FAKE_CURL_LOG="$curl_log" "$OCW" models sync --url "https://example.invalid/models.json" --timeout 7 --out ".codex/models.json" > "$TMP_ROOT/fake-curl.out" 2> "$TMP_ROOT/fake-curl.err"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "expected fake curl network failure"
  assert_contains "$TMP_ROOT/fake-curl.err" "[network_error]"
  assert_contains "$curl_log" "--max-time 7"
  assert_contains "$curl_log" "--connect-timeout 7"

  missing_node="$TMP_ROOT/missing-node"
  set +e
  OCW_NODE_BIN="$missing_node" "$OCW" mcp doctor --json > "$TMP_ROOT/missing-node.json"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "expected missing node mcp doctor to fail"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$TMP_ROOT/missing-node.json"
  assert_contains "$TMP_ROOT/missing-node.json" '"ok": false'

  broken_gh="$TMP_ROOT/broken-gh"
  cat > "$broken_gh" <<'EOF'
#!/usr/bin/env bash
printf 'broken gh\n' >&2
exit 33
EOF
  chmod +x "$broken_gh"
  set +e
  OCW_GH_BIN="$broken_gh" OCW_OPENCODE_BIN="$MOCK_OPENCODE" OCW_OUTPUT_ROOT=".out" "$OCW" pr review 123 --repo owner/repo > "$TMP_ROOT/broken-gh.out" 2> "$TMP_ROOT/broken-gh.err"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "expected broken gh to fail"
  assert_contains "$TMP_ROOT/broken-gh.err" "[gh_failed]"

  set +e
  OCW_TEST_STAMP="auth-fail" run_ocw cheap "OCW_MOCK_AUTH_FAIL" >/dev/null 2> "$TMP_ROOT/auth-fail.err"
  status=$?
  set -e
  [[ "$status" -eq 42 ]] || fail "expected auth failure 42, got $status"
  assert_contains ".out/auth-fail-cheap/metadata.txt" "status=42"
  assert_contains ".out/auth-fail-cheap/summary.md" "MOCK_AUTH_FAIL"

  set +e
  OCW_OUTPUT_ROOT=".out" "$OCW" verdict auth-fail-cheap --json > "$TMP_ROOT/verdict-fail.json"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "expected failed verdict to be nonzero"
  node -e "const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (j.overall !== 'fail') process.exit(1)" "$TMP_ROOT/verdict-fail.json"

  quick_json="$TMP_ROOT/quickstart.json"
  "$OCW" quickstart --json > "$quick_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$quick_json"
  assert_contains "$quick_json" '"schema_version": "ocw.quickstart.v1"'

  setup_json="$TMP_ROOT/setup.json"
  OCW_CODEX_SKILLS_DIR="$codex_skills" "$OCW" setup codex --force --json > "$setup_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$setup_json"
  assert_file "AGENTS.md"
  assert_file ".mcp.json"
  assert_file ".codex/config.toml"
  assert_file ".codex/ocw-bridge/bridge.py"
  assert_file ".codex/agents/oss-kimi-rapid.toml"
  assert_file ".codex/ocw-hooks/post-task.sh"
  assert_file "$codex_skills/opencode-worker/SKILL.md"

  OCW_TEST_STAMP="explain" run_ocw cheap "explain this run" >/dev/null
  explain_json="$TMP_ROOT/explain.json"
  OCW_OUTPUT_ROOT=".out" "$OCW" explain latest --json > "$explain_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$explain_json"
  assert_contains "$explain_json" '"schema_version": "ocw.explain.v1"'
  OCW_OUTPUT_ROOT=".out" "$OCW" explain latest > "$TMP_ROOT/explain.txt"
  assert_contains "$TMP_ROOT/explain.txt" "Next steps:"
}

test_config_support_and_release_installer() {
  local repo="$TMP_ROOT/config-support"
  local validate_json invalid_status support_archive extract_dir install_plan formula formula_mode homebrew_ok homebrew_hang homebrew_json homebrew_status mcp_json trace_json missing_trace_json trace_status
  make_repo "$repo"
  cd "$repo"

  "$OCW" config init --file custom.ocw.toml >/dev/null
  assert_file custom.ocw.toml
  validate_json="$TMP_ROOT/config-validate.json"
  "$OCW" config validate --file custom.ocw.toml --json > "$validate_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$validate_json"
  assert_contains "$validate_json" '"valid": true'

  printf '[defaults]\nworktree = maybe\n' > bad.ocw.toml
  set +e
  "$OCW" config validate --file bad.ocw.toml > "$TMP_ROOT/bad-config.txt"
  invalid_status=$?
  set -e
  [[ "$invalid_status" -eq 1 ]] || fail "expected invalid config status 1, got $invalid_status"
  assert_contains "$TMP_ROOT/bad-config.txt" "must be a boolean"

  cat > secret.ocw.toml <<'EOF'
[models]
cheap = "opencode-go/qwen3.5-plus"

[defaults]
output_root = ".out"
api_key = "do-not-leak"
EOF

  OCW_CONFIG="$PWD/secret.ocw.toml" OCW_TEST_STAMP="support-run" run_ocw cheap "support bundle" >/dev/null
  support_archive="$TMP_ROOT/support.tgz"
  OCW_CONFIG="$PWD/secret.ocw.toml" OCW_OUTPUT_ROOT=".out" OCW_OPENCODE_BIN="$MOCK_OPENCODE" "$OCW" support bundle --out "$support_archive" >/dev/null
  assert_file "$support_archive"
  extract_dir="$TMP_ROOT/support-extract"
  mkdir -p "$extract_dir"
  tar -xzf "$support_archive" -C "$extract_dir"
  assert_file "$extract_dir/support/README.txt"
  assert_file "$extract_dir/support/doctor.json"
  assert_file "$extract_dir/support/config.sanitized.toml"
  assert_file "$extract_dir/support/latest/manifest.json"
  assert_contains "$extract_dir/support/config.sanitized.toml" "api_key = <redacted>"
  assert_not_contains "$extract_dir/support/config.sanitized.toml" "do-not-leak"
  [[ ! -f "$extract_dir/support/latest/summary.md" ]] || fail "support bundle included summary without opt-in"

  install_plan="$TMP_ROOT/install-release-plan.txt"
  "$ROOT/scripts/install-release.sh" --version v0.7.1-alpha --dry-run --require-attestation > "$install_plan"
  assert_contains "$install_plan" "dry run: would download"
  assert_contains "$install_plan" "would require GitHub artifact attestation verification"
  assert_contains "$install_plan" "ocw-0.7.1-alpha.tar.gz"

  formula="$TMP_ROOT/ocw.rb"
  "$OCW" homebrew formula --version 0.7.1-alpha --sha256 "$(printf 'a%.0s' {1..64})" --out "$formula" >/dev/null
  assert_file "$formula"
  assert_contains "$formula" "class Ocw < Formula"
  assert_contains "$formula" "sha256 \"aaaaaaaa"
  assert_not_contains "$formula" "depends_on \"node\""
  formula_mode="$(stat -c '%a' "$formula" 2>/dev/null || stat -f '%Lp' "$formula")"
  [[ "$formula_mode" == "644" ]] || fail "expected Homebrew formula mode 644, got $formula_mode"

  homebrew_ok="$TMP_ROOT/mdfind-ok"
  cat > "$homebrew_ok" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$homebrew_ok"
  homebrew_json="$TMP_ROOT/homebrew-doctor-ok.json"
  OCW_BREW_BIN="$homebrew_ok" OCW_MDFIND_BIN="$homebrew_ok" "$OCW" homebrew doctor --timeout 1 --json > "$homebrew_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$homebrew_json"
  assert_contains "$homebrew_json" '"schema_version": "ocw.homebrew.doctor.v1"'
  assert_contains "$homebrew_json" '"overall": "ok"'

  homebrew_hang="$TMP_ROOT/mdfind-hang"
  cat > "$homebrew_hang" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
  chmod +x "$homebrew_hang"
  homebrew_json="$TMP_ROOT/homebrew-doctor-timeout.json"
  set +e
  OCW_BREW_BIN="$homebrew_ok" OCW_MDFIND_BIN="$homebrew_hang" "$OCW" homebrew doctor --timeout 1 --json > "$homebrew_json"
  homebrew_status=$?
  set -e
  [[ "$homebrew_status" -ne 0 ]] || fail "expected homebrew doctor timeout to fail"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$homebrew_json"
  assert_contains "$homebrew_json" '"overall": "issue"'
  assert_contains "$homebrew_json" 'timed out after 1s'

  mcp_json="$TMP_ROOT/mcp-doctor.json"
  "$OCW" mcp doctor --json > "$mcp_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$mcp_json"
  assert_contains "$mcp_json" '"schema_version": "ocw.mcp.doctor.v1"'

  trace_json="$TMP_ROOT/trace.json"
  OCW_OUTPUT_ROOT=".out" "$OCW" trace latest --json > "$trace_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$trace_json"
  assert_contains "$trace_json" '"schema_version": "ocw.trace.v1"'

  missing_trace_json="$TMP_ROOT/trace-missing.json"
  set +e
  OCW_OUTPUT_ROOT="$TMP_ROOT/no-runs-yet" "$OCW" trace latest --json > "$missing_trace_json"
  trace_status=$?
  set -e
  [[ "$trace_status" -ne 0 ]] || fail "expected missing trace status to fail"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$missing_trace_json"
  assert_contains "$missing_trace_json" '"ok": false'
  assert_contains "$missing_trace_json" '"error_code": "not_found"'

  OCW_TEST_STAMP="security-eval" run_ocw security eval --iterations 1 >/dev/null
  assert_file ".out/security-eval-eval/eval.tsv"
  assert_contains ".out/security-eval-eval/eval.tsv" "MOCK_OK"
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

test_bridge_command() {
  local repo="$TMP_ROOT/bridge"
  local port config install_json doctor_json test_json status_json start_output stop_output
  make_repo "$repo"
  cd "$repo"
  port=$((4300 + RANDOM % 1000))

  "$OCW" bridge --help >/dev/null

  if "$OCW" bridge status --port "bad-port" > "$TMP_ROOT/bridge-bad-port.out" 2> "$TMP_ROOT/bridge-bad-port.err"; then
    fail "expected bridge status to reject invalid port"
  fi
  assert_contains "$TMP_ROOT/bridge-bad-port.err" "invalid bridge port"

  config="$TMP_ROOT/bridge-codex-config.toml"
  "$OCW" bridge codex-config --port "$port" > "$config"
  assert_contains "$config" "[model_providers.opencode_bridge]"
  assert_contains "$config" "base_url = \"http://127.0.0.1:$port/v1\""
  assert_contains "$config" "[model_providers.opencode_bridge.auth]"
  assert_contains "$config" "OCW_BRIDGE_KEY"

  install_json="$TMP_ROOT/bridge-install.json"
  "$OCW" bridge install --force --json > "$install_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$install_json"
  assert_file ".codex/ocw-bridge/bridge.py"
  assert_file ".codex/ocw-bridge/LICENSE"
  assert_file ".codex/ocw-bridge/opencode-go.env"
  assert_file ".codex/ocw-bridge/bin/oss-scout"
  assert_file ".codex/ocw-bridge/bin/oss-review"
  assert_file ".codex/ocw-bridge/bin/oss-docs"
  assert_file ".codex/ocw-bridge/bin/oss-patch"
  assert_file ".codex/ocw-bridge/orchestration/AGENTS.md"
  assert_file ".codex/ocw-bridge/orchestration/ROUTING.md"
  assert_file ".codex/ocw-bridge/workers/worker.toml"
  assert_file ".codex/ocw-bridge/workers/explorer.toml"
  bash -n ".codex/ocw-bridge/bin/oss-scout"
  bash -n ".codex/ocw-bridge/bin/oss-review"
  bash -n ".codex/ocw-bridge/bin/oss-docs"
  bash -n ".codex/ocw-bridge/bin/oss-patch"
  printf 'LITELLM_MASTER_KEY=env-key\n' > ".codex/ocw-bridge/opencode-go.env"
  assert_contains ".gitignore" ".codex/ocw-bridge/"
  assert_contains ".gitignore" ".codex/ocw-bridge-results/"
  assert_contains ".gitignore" ".codex/ocw-bridge-worktrees/"

  "$OCW" bridge agents sync --force > "$TMP_ROOT/bridge-agents.txt"
  assert_file ".codex/agents/oss-deepseek-pro.toml"
  assert_file ".codex/agents/oss-kimi-rapid.toml"
  assert_file ".codex/agents/oss-flash-support.toml"

  "$OCW" bridge workers sync --force > "$TMP_ROOT/bridge-workers.txt"
  assert_file ".codex/agents/worker.toml"
  assert_file ".codex/agents/explorer.toml"
  assert_contains ".codex/agents/worker.toml" 'name = "worker"'
  assert_contains ".codex/agents/worker.toml" 'model_provider = "opencode_bridge"'
  assert_contains ".codex/agents/worker.toml" 'model = "ocg-deepseek-v4-pro"'
  assert_contains ".codex/agents/worker.toml" 'sandbox_mode = "workspace-write"'
  assert_contains ".codex/agents/explorer.toml" 'name = "explorer"'
  assert_contains ".codex/agents/explorer.toml" 'model_provider = "opencode_bridge"'
  assert_contains ".codex/agents/explorer.toml" 'model = "ocg-kimi-k2.6"'
  assert_contains ".codex/agents/explorer.toml" 'sandbox_mode = "read-only"'

  "$OCW" bridge workers diff > "$TMP_ROOT/bridge-workers-diff.txt"
  assert_contains "$TMP_ROOT/bridge-workers-diff.txt" "ok: .codex/agents/worker.toml"
  assert_contains "$TMP_ROOT/bridge-workers-diff.txt" "ok: .codex/agents/explorer.toml"

  "$OCW" bridge workers doctor > "$TMP_ROOT/bridge-workers-doctor.txt"
  assert_contains "$TMP_ROOT/bridge-workers-doctor.txt" "OCW bridge workers doctor: ok"
  assert_contains "$TMP_ROOT/bridge-workers-doctor.txt" "worker override: true"
  assert_contains "$TMP_ROOT/bridge-workers-doctor.txt" "explorer override: true"

  "$OCW" bridge orchestration sync --force > "$TMP_ROOT/bridge-orchestration.txt"
  assert_file ".codex/ocw-bridge-orchestration/AGENTS.md"
  assert_file ".codex/ocw-bridge-orchestration/ROUTING.md"
  assert_contains ".codex/ocw-bridge-orchestration/ROUTING.md" "Command Matrix"

  "$OCW" bridge codex-config --write --project --force --port "$port" > "$TMP_ROOT/bridge-config-write.txt"
  assert_file ".codex/config.toml"
  assert_contains ".codex/config.toml" "model_provider = \"opencode_bridge\""

  doctor_json="$TMP_ROOT/bridge-doctor.json"
  "$OCW" bridge doctor --json --port "$port" > "$doctor_json"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$doctor_json"
  assert_contains "$doctor_json" '"schema_version": "ocw.bridge.doctor.v1"'
  assert_contains "$doctor_json" '"self_test": true'

  test_json="$TMP_ROOT/bridge-test-before-start.json"
  "$OCW" bridge test --json --port "$port" > "$test_json"
  assert_contains "$test_json" '"self_test": true'

  if "$OCW" bridge start --host 0.0.0.0 --port "$port" > "$TMP_ROOT/bridge-non-loopback.out" 2> "$TMP_ROOT/bridge-non-loopback.err"; then
    fail "expected bridge start to reject non-loopback host"
  fi
  assert_contains "$TMP_ROOT/bridge-non-loopback.err" "refusing to bind bridge to non-loopback host"

  start_output="$TMP_ROOT/bridge-start.txt"
  "$OCW" bridge start --port "$port" --key "cli-key" > "$start_output" 2> "$TMP_ROOT/bridge-start.err"
  assert_contains "$start_output" "OCW bridge"
  status_json="$TMP_ROOT/bridge-status.json"
  "$OCW" bridge status --json --port "$port" --key "cli-key" > "$status_json"
  node -e "const data = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (!data.running) process.exit(1)" "$status_json"
  assert_contains "$status_json" '"health": true'
  "$OCW" bridge status --json --port "$port" --key "env-key" > "$TMP_ROOT/bridge-status-wrong-key.json"
  assert_contains "$TMP_ROOT/bridge-status-wrong-key.json" '"health": false'

  test_json="$TMP_ROOT/bridge-test-after-start.json"
  "$OCW" bridge test --json --port "$port" --key "cli-key" > "$test_json"
  assert_contains "$test_json" '"health": true'
  test_json="$TMP_ROOT/bridge-test-wrong-key.json"
  "$OCW" bridge test --json --port "$port" --key "env-key" > "$test_json"
  assert_contains "$test_json" '"health": false'

  stop_output="$TMP_ROOT/bridge-stop.txt"
  "$OCW" bridge stop > "$stop_output"
  assert_contains "$stop_output" "OCW bridge"

  "$OCW" bridge start --port "$port" > "$TMP_ROOT/bridge-env-start.txt" 2> "$TMP_ROOT/bridge-env-start.err"
  assert_contains "$TMP_ROOT/bridge-env-start.txt" "OCW bridge started"
  "$OCW" bridge status --json --port "$port" > "$TMP_ROOT/bridge-env-status.json"
  node -e "const data = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (!data.running || !data.health) process.exit(1)" "$TMP_ROOT/bridge-env-status.json"
  "$OCW" bridge start --port "$port" > "$TMP_ROOT/bridge-env-start-again.txt" 2> "$TMP_ROOT/bridge-env-start-again.err"
  assert_contains "$TMP_ROOT/bridge-env-start-again.txt" "already running"
  "$OCW" bridge stop > "$TMP_ROOT/bridge-env-stop.txt"
  assert_contains "$TMP_ROOT/bridge-env-stop.txt" "OCW bridge"
}

test_bridge_helper_scripts() {
  local repo="$TMP_ROOT/bridge-helpers"
  local mock_dir="$TMP_ROOT/bridge-helper-bin"
  local helper_log="$TMP_ROOT/bridge-helper.log"
  local report
  make_repo "$repo"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/opencode" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

model=""
title=""
dir=""
auto=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    run|--pure)
      shift
      ;;
    --model)
      model="$2"
      shift 2
      ;;
    --title)
      title="$2"
      shift 2
      ;;
    --dir)
      dir="$2"
      shift 2
      ;;
    --dangerously-skip-permissions)
      auto=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

prompt="$(cat)"
{
  printf 'model=%s\n' "$model"
  printf 'title=%s\n' "$title"
  printf 'dir=%s\n' "$dir"
  printf 'auto=%s\n' "$auto"
  printf 'prompt=%s\n' "$prompt"
} >> "${OCW_HELPER_LOG:?}"

if [[ -n "$dir" ]]; then
  cd "$dir"
fi
if [[ "$prompt" == *"OCW_HELPER_EDIT"* ]]; then
  printf 'helper patch from %s\n' "$model" >> tracked.txt
fi

printf '# MOCK_BRIDGE_HELPER\n\nmodel=%s\ntitle=%s\nauto=%s\n' "$model" "$title" "$auto"
MOCK
  chmod +x "$mock_dir/opencode"

  (
    cd "$repo"
    "$OCW" bridge install --force >/dev/null
    printf 'OPENCODE_GO_API_KEY=helper-key\n' > ".codex/ocw-bridge/opencode-go.env"
    mkdir -p .ai/tasks
    printf 'Map the tracked file and report evidence.\n' > .ai/tasks/sample.md
    printf 'Review tracked.txt for bugs.\n' > .ai/tasks/review.md
    printf 'Draft docs for tracked.txt.\n' > .ai/tasks/docs.md
    printf 'OCW_HELPER_EDIT: append a helper patch marker to tracked.txt.\n' > .ai/tasks/patch.md

    OCW_HELPER_LOG="$helper_log" PATH="$mock_dir:$PATH" .codex/ocw-bridge/bin/oss-scout --task sample --auto-approve > "$TMP_ROOT/oss-scout.out"
    report="$(cat "$TMP_ROOT/oss-scout.out")"
    assert_file "$report"
    assert_contains "$report" "MOCK_BRIDGE_HELPER"
    assert_contains "$report" "title=oss-scout:sample"

    OCW_HELPER_LOG="$helper_log" PATH="$mock_dir:$PATH" .codex/ocw-bridge/bin/oss-review --task .ai/tasks/review.md > "$TMP_ROOT/oss-review.out"
    report="$(cat "$TMP_ROOT/oss-review.out")"
    assert_file "$report"
    assert_contains "$report" "title=oss-review:review"

    OCW_HELPER_LOG="$helper_log" PATH="$mock_dir:$PATH" .codex/ocw-bridge/bin/oss-docs --task docs > "$TMP_ROOT/oss-docs.out"
    report="$(cat "$TMP_ROOT/oss-docs.out")"
    assert_file "$report"
    assert_contains "$report" "opencode-go/deepseek-v4-flash"

    OCW_HELPER_LOG="$helper_log" PATH="$mock_dir:$PATH" .codex/ocw-bridge/bin/oss-patch --task patch --auto-approve > "$TMP_ROOT/oss-patch.out"
    assert_file ".codex/ocw-bridge-results/patch.patch.report.md"
    assert_file ".codex/ocw-bridge-results/patch.patch.diff"
    assert_file ".codex/ocw-bridge-results/patch.patch.status.txt"
    assert_contains ".codex/ocw-bridge-results/patch.patch.diff" "helper patch from opencode-go/deepseek-v4-pro"
    assert_absent ".codex/ocw-bridge-worktrees/patch"
    assert_not_contains "tracked.txt" "helper patch from"
  )

  assert_contains "$helper_log" "title=oss-scout:sample"
  assert_contains "$helper_log" "title=oss-review:review"
  assert_contains "$helper_log" "title=oss-docs:docs"
  assert_contains "$helper_log" "title=oss-patch:patch"
}

test_bridge_proxy_streaming() {
  local repo="$TMP_ROOT/bridge-streaming"
  local port upstream_port mock_server upstream_pid
  make_repo "$repo"
  port=$((5400 + RANDOM % 500))
  upstream_port=$((5900 + RANDOM % 500))
  mock_server="$TMP_ROOT/bridge-mock-upstream.py"

  cat > "$mock_server" <<'PY'
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, obj):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self._json(
                200,
                {
                    "data": [
                        {"id": "deepseek-v4-pro"},
                        {"id": "kimi-k2.6"},
                        {"id": "mimo-v2.5"},
                        {"id": "minimax-m2.5"},
                    ]
                },
            )
            return
        self._json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        if not self.path.rstrip("/").endswith("/chat/completions"):
            self._json(404, {"error": {"message": "not found"}})
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length).decode("utf-8"))
        time.sleep(2)
        self._json(
            200,
            {
                "id": "chatcmpl_mock",
                "object": "chat.completion",
                "choices": [
                    {
                        "index": 0,
                        "finish_reason": "stop",
                        "message": {
                            "role": "assistant",
                            "content": "mock bridge response for " + body.get("model", "unknown"),
                        },
                    }
                ],
                "usage": {"prompt_tokens": 3, "completion_tokens": 4, "total_tokens": 7},
            },
        )

    def log_message(self, fmt, *args):
        return


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY

  (
    cd "$repo"
    "${OCW_PYTHON_BIN:-python3}" "$mock_server" "$upstream_port" > "$TMP_ROOT/bridge-mock-upstream.out" 2> "$TMP_ROOT/bridge-mock-upstream.err" &
    upstream_pid=$!
    trap 'kill "$upstream_pid" >/dev/null 2>&1 || true; wait "$upstream_pid" 2>/dev/null || true; "$OCW" bridge stop >/dev/null 2>&1 || true' EXIT
    sleep 1

    "$OCW" bridge install --force >/dev/null
    printf 'LITELLM_MASTER_KEY=stream-key\nOPENCODE_GO_API_KEY=local-test-key\n' > ".codex/ocw-bridge/opencode-go.env"
    UPSTREAM_BASE="http://127.0.0.1:$upstream_port/v1" \
      SSE_UPSTREAM_HEARTBEAT_SECONDS=1 \
      "$OCW" bridge start --port "$port" --timeout 10 > "$TMP_ROOT/bridge-stream-start.txt" 2> "$TMP_ROOT/bridge-stream-start.err"
    assert_contains "$TMP_ROOT/bridge-stream-start.txt" "OCW bridge started"

    "$OCW" bridge test --live --port "$port" > "$TMP_ROOT/bridge-stream-live.txt"
    assert_contains "$TMP_ROOT/bridge-stream-live.txt" "live models: true"

    curl -fsS --max-time 10 "http://127.0.0.1:$port/v1/models" \
      -H "Authorization: Bearer stream-key" \
      > "$TMP_ROOT/bridge-models.json"
    node -e "const ids = new Set(JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).data.map((item) => item.id)); for (const id of ['deepseek-v4-pro', 'ocg-deepseek-v4-pro', 'opencode-go/deepseek-v4-pro', 'ocg-mimo-v2.5', 'opencode-go/mimo-v2.5', 'ocg-minimax-m2.5']) if (!ids.has(id)) { console.error('missing', id); process.exit(1); }" "$TMP_ROOT/bridge-models.json"

    curl -fsS -N --max-time 10 "http://127.0.0.1:$port/v1/responses" \
      -H "Authorization: Bearer stream-key" \
      -H "Content-Type: application/json" \
      -d '{"model":"ocg-deepseek-v4-pro","input":"hello","stream":true}' \
      > "$TMP_ROOT/bridge-stream.sse"
    assert_contains "$TMP_ROOT/bridge-stream.sse" "event: response.created"
    assert_contains "$TMP_ROOT/bridge-stream.sse" ": upstream_wait"
    assert_contains "$TMP_ROOT/bridge-stream.sse" "event: response.completed"
    assert_contains "$TMP_ROOT/bridge-stream.sse" "mock bridge response"

    curl -fsS --max-time 10 "http://127.0.0.1:$port/v1/responses" \
      -H "Authorization: Bearer stream-key" \
      -H "Content-Type: application/json" \
      -d '{"model":"ocg-kimi-k2.6","input":"hello","stream":false}' \
      > "$TMP_ROOT/bridge-nonstream.json"
    node -e "const data = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); if (data.status !== 'completed' || !JSON.stringify(data.output).includes('mock bridge response')) process.exit(1)" "$TMP_ROOT/bridge-nonstream.json"

    curl -fsS --max-time 10 "http://127.0.0.1:$port/v1/responses" \
      -H "Authorization: Bearer stream-key" \
      -H "Content-Type: application/json" \
      -d '{"model":"ocg-mimo-v2.5","input":"hello","stream":false}' \
      > "$TMP_ROOT/bridge-mimo.json"
    assert_contains "$TMP_ROOT/bridge-mimo.json" "mock bridge response for mimo-v2.5"

    curl -fsS --max-time 10 "http://127.0.0.1:$port/v1/responses" \
      -H "Authorization: Bearer stream-key" \
      -H "Content-Type: application/json" \
      -d '{"model":"opencode-go/minimax-m2.5","input":"hello","stream":false}' \
      > "$TMP_ROOT/bridge-minimax.json"
    assert_contains "$TMP_ROOT/bridge-minimax.json" "mock bridge response for minimax-m2.5"
  )
}

test_bridge_start_proxy_script() {
  local port pid code
  port=$((7600 + RANDOM % 400))

  OPENCODE_GO_API_KEY=placeholder PROXY_PORT="$port" "$ROOT/bridge/opencode-bridge/bin/start-proxy" > "$TMP_ROOT/bridge-start-proxy.out" 2> "$TMP_ROOT/bridge-start-proxy.err" &
  pid=$!
  (
    trap 'kill "$pid" >/dev/null 2>&1 || true; wait "$pid" 2>/dev/null || true' EXIT
    for _ in 1 2 3 4 5; do
      code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$port/health" 2>/dev/null || true)"
      if [[ "$code" != "000" ]]; then
        [[ "$code" == "401" ]] || fail "expected unauthenticated start-proxy health to return 401, got $code"
        curl -fsS --max-time 2 "http://127.0.0.1:$port/health" -H "Authorization: Bearer sk-local-codex-bridge" >/dev/null
        exit 0
      fi
      sleep 1
    done
    sed -n '1,120p' "$TMP_ROOT/bridge-start-proxy.err" || true
    fail "start-proxy did not become reachable"
  )
}

test_mcp_server() {
  node "$ROOT/test/mcp-smoke.js"
}

run_test "help and doctor" test_help_and_doctor
run_test "default routing" test_default_routing
run_test "overrides and summary" test_overrides_and_summary
run_test "config routing and attach" test_config_routing_and_attach
run_test "key management and rotation" test_key_management_and_rotation
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
run_test "world-class workflows" test_world_class_workflows
run_test "hardening security and ux" test_hardening_security_and_ux
run_test "config support and release installer" test_config_support_and_release_installer
run_test "pr summary command" test_pr_summary_command
run_test "pr review command" test_pr_review_command
run_test "bridge command" test_bridge_command
run_test "bridge helper scripts" test_bridge_helper_scripts
run_test "bridge proxy streaming" test_bridge_proxy_streaming
run_test "bridge start-proxy script" test_bridge_start_proxy_script
run_test "mcp server" test_mcp_server

say "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
