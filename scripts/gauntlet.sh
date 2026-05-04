#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION="$("$ROOT/bin/ocw" version | awk '{print $2}')"
DIST="$ROOT/dist/ocw-$VERSION.tar.gz"
MOCK_OPENCODE="$ROOT/test/fixtures/opencode"
MOCK_GH="$ROOT/test/fixtures/gh"
STRESS_RUNS="${OCW_GAUNTLET_STRESS_RUNS:-100}"
REAL_SMOKE="${OCW_GAUNTLET_REAL_SMOKE:-0}"
REAL_MODEL="${OCW_GAUNTLET_REAL_MODEL:-opencode-go/qwen3.5-plus}"
TMP_ROOT="$(mktemp -d)"
PACKAGE_BUILT=0

cleanup() {
  if [[ "${OCW_GAUNTLET_KEEP_TMP:-0}" == "1" ]]; then
    printf 'gauntlet temp kept: %s\n' "$TMP_ROOT" >&2
  else
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

say() {
  printf '%s\n' "$*"
}

fail() {
  printf 'GAUNTLET FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "missing dir: $1"
}

assert_absent() {
  [[ ! -e "$1" ]] || fail "unexpected path: $1"
}

assert_contains() {
  local file="$1"
  local expected="$2"

  grep -Fq "$expected" "$file" || {
    printf -- '--- %s\n' "$file" >&2
    sed -n '1,160p' "$file" >&2 || true
    fail "expected '$expected' in $file"
  }
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"

  ! grep -Fq "$unexpected" "$file" || fail "did not expect '$unexpected' in $file"
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"
}

make_repo() {
  local repo="$1"

  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    printf 'base\n' > tracked.txt
    printf 'attach me\n' > attach.txt
    git add tracked.txt attach.txt
    git -c user.name='OCW Gauntlet' -c user.email='ocw-gauntlet@example.invalid' commit -q -m init
  )
}

expect_fail() {
  local status

  set +e
  "$@" > "$TMP_ROOT/negative.out" 2> "$TMP_ROOT/negative.err"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "expected failure: $*"
}

install_from_package() {
  local install_dir="$1"
  local extract_dir="$2"

  if [[ ! -f "$DIST" ]]; then
    "$ROOT/scripts/package.sh" >/dev/null
    PACKAGE_BUILT=1
  elif [[ "${OCW_GAUNTLET_SKIP_PACKAGE:-0}" != "1" && "$PACKAGE_BUILT" -eq 0 ]]; then
    "$ROOT/scripts/package.sh" >/dev/null
    PACKAGE_BUILT=1
  fi

  assert_file "$DIST"
  mkdir -p "$install_dir" "$extract_dir"
  tar -xzf "$DIST" -C "$extract_dir"
  assert_file "$extract_dir/ocw-$VERSION/ROADMAP.md"
  assert_file "$extract_dir/ocw-$VERSION/docs/feedback.md"
  assert_file "$extract_dir/ocw-$VERSION/docs/troubleshooting.md"
  assert_file "$extract_dir/ocw-$VERSION/docs/assets/ocw-demo.svg"
  assert_file "$extract_dir/ocw-$VERSION/docs/site/index.html"
  OCW_INSTALL_DIR="$install_dir" "$extract_dir/ocw-$VERSION/install.sh" >/dev/null
  assert_file "$install_dir/ocw"
}

check_completions() {
  local ocw="$1"
  local out_dir="$TMP_ROOT/completions"

  mkdir -p "$out_dir"
  "$ocw" completions bash > "$out_dir/ocw.bash"
  "$ocw" completions zsh > "$out_dir/ocw.zsh"
  "$ocw" completions fish > "$out_dir/ocw.fish"
  bash -n "$out_dir/ocw.bash"
  assert_contains "$out_dir/ocw.bash" "_ocw()"
  assert_contains "$out_dir/ocw.bash" "formula doctor"
  assert_contains "$out_dir/ocw.zsh" "summary review"
  assert_contains "$out_dir/ocw.fish" "mcp help version"
}

negative_matrix() {
  local ocw="$1"
  local repo="$TMP_ROOT/negative-repo"

  make_repo "$repo"
  (
    cd "$repo"
    OCW_OPENCODE_BIN="$MOCK_OPENCODE" "$ocw" --help >/dev/null
    OCW_OPENCODE_BIN="$MOCK_OPENCODE" "$ocw" doctor --help >/dev/null
    "$ocw" init --help >/dev/null
    "$ocw" uninstall --help >/dev/null
    "$ocw" config --help >/dev/null
    "$ocw" apply --help >/dev/null
    "$ocw" clean --help >/dev/null
    "$ocw" models --help >/dev/null
    "$ocw" route --help >/dev/null
    "$ocw" tournament --help >/dev/null
    "$ocw" hooks --help >/dev/null
    "$ocw" memory --help >/dev/null
    "$ocw" dashboard --help >/dev/null
    "$ocw" copilot --help >/dev/null
    "$ocw" agent-pack --help >/dev/null
    "$ocw" agents --help >/dev/null
    "$ocw" eval --help >/dev/null
    "$ocw" pr --help >/dev/null
    "$ocw" report --help >/dev/null
    "$ocw" policy --help >/dev/null
    "$ocw" gh-extension --help >/dev/null
    "$ocw" homebrew --help >/dev/null
    "$ocw" security --help >/dev/null
    "$ocw" support --help >/dev/null
    "$ocw" trace --help >/dev/null
    "$ocw" help support >/dev/null
    "$ocw" mcp doctor --json >/dev/null
    "$ocw" mcp audit --json >/dev/null
    "$ocw" mcp-config --help >/dev/null
    "$ocw" completions bash >/dev/null
    "$ocw" completions zsh >/dev/null
    "$ocw" completions fish >/dev/null
    OCW_OPENCODE_BIN="$MOCK_OPENCODE" "$ocw" models >/dev/null

    expect_fail "$ocw" cheap
    expect_fail "$ocw" --unknown cheap task
    expect_fail "$ocw" cheap --unknown task
    expect_fail "$ocw" batch missing-file.ocw
    expect_fail "$ocw" eval missing-file.ocw
    expect_fail "$ocw" suport
    expect_fail "$ocw" clean --days nope
    printf '[defaults]\nworktree = nope\n' > bad.ocw.toml
    expect_fail "$ocw" config validate --file bad.ocw.toml
    expect_fail "$ocw" pr review
    expect_fail "$ocw" apply latest
  )
}

package_flow_matrix() {
  local ocw="$1"
  local install_dir="$2"
  local repo="$TMP_ROOT/package-flow-repo"
  local latest apply_status
  local OCW_OPENCODE_BIN="$MOCK_OPENCODE"
  local OCW_GH_BIN="$MOCK_GH"
  local OCW_OUTPUT_ROOT=".out"
  local OCW_MOCK_LOG="$repo/.out/mock.log"
  local OCW_MOCK_GH_LOG="$repo/.out/gh.log"
  local OCW_TEST_CREATED_AT="2026-05-04T00:00:00Z"
  local OCW_CODEX_SKILLS_DIR="$TMP_ROOT/codex-skills"
  local OCW_CLAUDE_SKILLS_DIR="$TMP_ROOT/claude-skills"
  local OCW_OPENCODE_SKILLS_DIR="$TMP_ROOT/opencode-skills"
  local OCW_AGENTS_SKILLS_DIR="$TMP_ROOT/agents-skills"

  make_repo "$repo"
  export OCW_OPENCODE_BIN OCW_GH_BIN OCW_OUTPUT_ROOT OCW_MOCK_LOG OCW_MOCK_GH_LOG OCW_TEST_CREATED_AT
  export OCW_CODEX_SKILLS_DIR OCW_CLAUDE_SKILLS_DIR OCW_OPENCODE_SKILLS_DIR OCW_AGENTS_SKILLS_DIR
  (
    cd "$repo"

    "$ocw" version | grep -Fq "ocw $VERSION"
    "$ocw" doctor --deep > "$TMP_ROOT/doctor.txt"
    assert_contains "$TMP_ROOT/doctor.txt" "doctor deep: ok"
    "$ocw" config init --file ocw.alt.toml >/dev/null
    "$ocw" config validate --file ocw.alt.toml --json > "$TMP_ROOT/config-validate.json"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TMP_ROOT/config-validate.json"
    assert_contains "$TMP_ROOT/config-validate.json" '"valid": true'

    "$ocw" init --project-skills >/dev/null
    "$ocw" init --project-skills >/dev/null
    assert_file ".ocw.toml"
    assert_file "AGENTS.md"
    assert_file "CLAUDE.md"
    assert_file ".opencode/skills/opencode-worker/SKILL.md"
    assert_file ".claude/skills/opencode-worker/SKILL.md"
    assert_file ".agents/skills/opencode-worker/SKILL.md"
    assert_file "$OCW_CODEX_SKILLS_DIR/opencode-worker/SKILL.md"
    assert_eq "$(grep -Fc '.codex/opencode-workers/' .gitignore)" "1"

    "$ocw" agent-pack install >/dev/null
    assert_file ".opencode/agents/ocw-explorer.md"
    assert_file ".opencode/agents/ocw-reviewer.md"
    assert_file ".opencode/agents/ocw-patcher.md"
    assert_file ".opencode/agents/ocw-triage.md"
    git add .gitignore .ocw.toml ocw.alt.toml AGENTS.md CLAUDE.md .opencode .claude .agents
    git -c user.name='OCW Gauntlet' -c user.email='ocw-gauntlet@example.invalid' commit -q -m 'add ocw config'

    OCW_TEST_CREATED_AT="2026-05-04T00:00:01Z" OCW_TEST_STAMP=g-explore "$ocw" explore "map repository" >/dev/null
    OCW_TEST_CREATED_AT="2026-05-04T00:00:02Z" OCW_TEST_STAMP=g-review "$ocw" review "review repository" >/dev/null
    OCW_TEST_CREATED_AT="2026-05-04T00:00:03Z" OCW_TEST_STAMP=g-scan "$ocw" scan "scan repository" >/dev/null
    OCW_TEST_CREATED_AT="2026-05-04T00:00:04Z" OCW_TEST_STAMP=g-cheap "$ocw" cheap --file attach.txt --model opencode-go/minimax-m2.7 --agent build --variant high --auto-approve "cheap attached" >/dev/null
    assert_contains ".out/g-explore-explore/metadata.txt" "mode=explore"
    assert_contains ".out/g-review-review/metadata.txt" "model=opencode-go/deepseek-v4-pro"
    assert_contains ".out/g-scan-scan/summary.md" "MOCK_OK"
    assert_contains ".out/g-cheap-cheap/metadata.txt" "model=opencode-go/minimax-m2.7"
    assert_contains ".out/g-cheap-cheap/metadata.txt" "agent=build"
    assert_contains ".out/g-cheap-cheap/metadata.txt" "variant=high"
    assert_contains ".out/g-cheap-cheap/metadata.txt" "auto_approve=1"
    assert_contains ".out/mock.log" "files=attach.txt"

    OCW_TEST_CREATED_AT="2026-05-04T00:00:05Z" OCW_TEST_STAMP=g-patch "$ocw" --worktree --rm-worktree patch "OCW_MOCK_EDIT" >/dev/null
    assert_contains ".out/g-patch-patch/diff.after.patch" "mock edit from opencode-go/kimi-k2.6"
    assert_not_contains "tracked.txt" "mock edit from opencode-go/kimi-k2.6"
    "$ocw" apply --check .out/g-patch-patch >/dev/null
    "$ocw" apply .out/g-patch-patch >/dev/null
    assert_contains "tracked.txt" "mock edit from opencode-go/kimi-k2.6"

    git add tracked.txt
    git -c user.name='OCW Gauntlet' -c user.email='ocw-gauntlet@example.invalid' commit -q -m 'apply patch'
    printf 'dirty\n' >> tracked.txt
    set +e
    "$ocw" apply .out/g-patch-patch >/dev/null 2> "$TMP_ROOT/apply-dirty.err"
    apply_status=$?
    set -e
    [[ "$apply_status" -ne 0 ]] || fail "apply unexpectedly succeeded on dirty tree"
    assert_contains "$TMP_ROOT/apply-dirty.err" "git worktree is not clean"
    git checkout -- tracked.txt

    cat > tasks.ocw <<'TASKS'
cheap|quick task
review|review task
scan|scan task
TASKS
    OCW_TEST_CREATED_AT="2026-05-04T00:00:06Z" OCW_TEST_STAMP=g-batch "$ocw" batch tasks.ocw --concurrency 3 >/dev/null
    assert_file ".out/g-batch-batch/batch.tsv"
    assert_dir ".out/g-batch-batch-1-cheap"
    assert_dir ".out/g-batch-batch-2-review"
    assert_dir ".out/g-batch-batch-3-scan"
    "$ocw" audit latest > "$TMP_ROOT/batch-audit.txt"
    assert_contains "$TMP_ROOT/batch-audit.txt" "overall: ok"

    OCW_TEST_CREATED_AT="2026-05-04T00:00:07Z" OCW_TEST_STAMP=g-bench "$ocw" bench --models opencode-go/qwen3.5-plus,opencode-go/deepseek-v4-flash --iterations 2 --task "bench task" >/dev/null
    assert_file ".out/g-bench-bench/bench.tsv"
    cat > models.json <<'MODELS'
{
  "models": [
    { "id": "opencode-go/gauntlet-a" },
    { "id": "opencode-go/gauntlet-b" }
  ]
}
MODELS
    "$ocw" models sync --url "file://$PWD/models.json" --out ".codex/models.json" --json > "$TMP_ROOT/models-sync.json"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TMP_ROOT/models-sync.json"
    "$ocw" models list --cache ".codex/models.json" > "$TMP_ROOT/models-list.txt"
    assert_contains "$TMP_ROOT/models-list.txt" "opencode-go/gauntlet-b"
    "$ocw" route set cheap opencode-go/gauntlet-a --reason gauntlet >/dev/null
    "$ocw" route explain cheap --json > "$TMP_ROOT/route.json"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TMP_ROOT/route.json"
    assert_contains "$TMP_ROOT/route.json" "opencode-go/gauntlet-a"
    OCW_TEST_CREATED_AT="2026-05-04T00:00:07Z" OCW_TEST_STAMP=g-routed "$ocw" cheap "route smoke" >/dev/null
    assert_contains ".out/g-routed-cheap/metadata.txt" "model=opencode-go/gauntlet-a"
    OCW_TEST_CREATED_AT="2026-05-04T00:00:07Z" OCW_TEST_STAMP=g-modelbench "$ocw" models bench --models opencode-go/gauntlet-a,opencode-go/gauntlet-b --iterations 1 --promote review >/dev/null
    "$ocw" route explain review > "$TMP_ROOT/route-review.txt"
    assert_contains "$TMP_ROOT/route-review.txt" "bench g-modelbench-bench"
    "$ocw" memory add test_command "make test" --tags tests >/dev/null
    "$ocw" memory search tests > "$TMP_ROOT/memory.txt"
    assert_contains "$TMP_ROOT/memory.txt" "make test"
    "$ocw" memory export --json > "$TMP_ROOT/memory.json"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TMP_ROOT/memory.json"
    OCW_TEST_CREATED_AT="2026-05-04T00:00:07Z" OCW_TEST_STAMP=g-tournament "$ocw" tournament cheap --models opencode-go/gauntlet-a,opencode-go/gauntlet-b --judge-model opencode-go/gauntlet-b "compare candidates" >/dev/null
    assert_file ".out/g-tournament-tournament/candidates.tsv"
    assert_file ".out/g-tournament-tournament/decision.md"
    "$ocw" audit .out/g-tournament-tournament > "$TMP_ROOT/tournament-audit.txt"
    assert_contains "$TMP_ROOT/tournament-audit.txt" "all tournament candidates exited 0"
    "$ocw" dashboard --out ".codex/ocw-dashboard.html" >/dev/null
    assert_file ".codex/ocw-dashboard.html"
    "$ocw" dashboard --json > "$TMP_ROOT/dashboard.json"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TMP_ROOT/dashboard.json"
    "$ocw" hooks install all --force >/dev/null
    assert_file ".codex/ocw-hooks/post-task.sh"
    assert_file ".claude/settings.json"
    assert_file ".github/copilot-instructions.md"
    assert_file ".github/prompts/ocw-pr-review.prompt.md"
    assert_file ".github/agents/ocw-reviewer.agent.md"
    assert_file ".opencode/commands/ocw-review.md"
    "$ocw" copilot doctor >/dev/null

    cat > eval.ocw <<'EVALS'
cheap|Return MOCK_OK for eval|MOCK_OK
review|Return MOCK_OK for review eval|MOCK_OK
EVALS
    OCW_TEST_CREATED_AT="2026-05-04T00:00:07Z" OCW_TEST_STAMP=g-eval "$ocw" eval eval.ocw --iterations 1 >/dev/null
    assert_file ".out/g-eval-eval/eval.tsv"
    "$ocw" eval generate --out ".codex/generated.ocw" --force >/dev/null
    assert_file ".codex/generated.ocw"
    "$ocw" audit .out/g-eval-eval > "$TMP_ROOT/eval-audit.txt"
    assert_contains "$TMP_ROOT/eval-audit.txt" "all eval expectations are present"

    "$ocw" report latest --json --out reports/latest.json >/dev/null
    "$ocw" report latest --html --out reports/latest.html >/dev/null
    "$ocw" report latest --junit --out reports/latest.xml >/dev/null
    "$ocw" report latest --sarif --out reports/latest.sarif >/dev/null
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' reports/latest.json
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' reports/latest.sarif
    assert_contains reports/latest.xml "<testsuite"

    "$ocw" agents sync --force >/dev/null
    "$ocw" agents doctor >/dev/null
    "$ocw" agents diff >/dev/null
    "$ocw" policy init strict --force >/dev/null
    "$ocw" policy check latest > "$TMP_ROOT/policy-check.txt"
    assert_contains "$TMP_ROOT/policy-check.txt" "policy: ok"
    "$ocw" gh-extension install --dir "$TMP_ROOT/gh-ext" >/dev/null
    assert_file "$TMP_ROOT/gh-ext/gh-ocw"
    "$ocw" security init --force >/dev/null
    assert_file ".github/workflows/scorecard.yml"
    assert_contains ".github/workflows/scorecard.yml" "actions/checkout@v6"

    OCW_TEST_CREATED_AT="2026-05-04T00:00:08Z" OCW_TEST_STAMP=g-prsum "$ocw" pr summary 123 --repo owner/repo >/dev/null
    OCW_TEST_CREATED_AT="2026-05-04T00:00:09Z" OCW_TEST_STAMP=g-prrev "$ocw" pr review 123 --repo owner/repo >/dev/null
    assert_file ".out/g-prsum-pr-summary/summary.md"
    assert_file ".out/g-prrev-pr-review/review.md"
    assert_contains ".out/gh.log" "mode=patch"

    "$ocw" manifest latest --json > "$TMP_ROOT/manifest.json"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TMP_ROOT/manifest.json"
    "$ocw" audit latest --json > "$TMP_ROOT/audit.json"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TMP_ROOT/audit.json"
    "$ocw" support bundle --out "$TMP_ROOT/support.tgz" >/dev/null
    assert_file "$TMP_ROOT/support.tgz"
    "$ocw" trace latest --json > "$TMP_ROOT/trace.json"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TMP_ROOT/trace.json"
    "$ocw" homebrew formula --version "$VERSION" --sha256 "$(printf 'a%.0s' {1..64})" --out "$TMP_ROOT/ocw.rb" >/dev/null
    assert_file "$TMP_ROOT/ocw.rb"
    assert_contains "$TMP_ROOT/ocw.rb" "class Ocw < Formula"
    "$ocw" show latest --summary >/dev/null
    "$ocw" show latest --path >/dev/null
    latest="$("$ocw" last)"
    [[ "$(basename "$latest")" == "g-prrev-pr-review" ]] || fail "unexpected latest: $latest"
    OCW_TEST_CREATED_AT="2026-05-04T00:00:10Z" OCW_TEST_STAMP=g-security-eval "$ocw" security eval --iterations 1 >/dev/null
    assert_file ".out/g-security-eval-eval/eval.tsv"

    "$ocw" stats --days 7 > "$TMP_ROOT/stats.txt"
    "$ocw" serve --port 4096 > "$TMP_ROOT/serve.txt"
    assert_contains "$TMP_ROOT/stats.txt" "MOCK_STATS"
    assert_contains "$TMP_ROOT/serve.txt" "MOCK_SERVE"

    "$ocw" clean --all --dry-run > "$TMP_ROOT/clean-all-dry.txt"
    assert_contains "$TMP_ROOT/clean-all-dry.txt" "g-prrev-pr-review"

    printf '\ncustom local notes\n' >> AGENTS.md
    "$ocw" uninstall --project --yes > "$TMP_ROOT/uninstall-project-safe.txt"
    assert_file "AGENTS.md"
    assert_absent ".ocw.toml"
    assert_absent "CLAUDE.md"
    assert_contains "$TMP_ROOT/uninstall-project-safe.txt" "Kept modified"
    assert_absent ".opencode/skills/opencode-worker"
    "$ocw" uninstall --project --force --yes >/dev/null
    assert_absent "AGENTS.md"
    assert_not_contains ".gitignore" ".codex/opencode-workers/"

    OCW_INSTALL_DIR="$install_dir" "$ocw" uninstall --bin --skills --yes >/dev/null
    assert_absent "$install_dir/ocw"
    assert_absent "$OCW_CODEX_SKILLS_DIR/opencode-worker"
    assert_absent "$OCW_CLAUDE_SKILLS_DIR/opencode-worker"
    assert_absent "$OCW_OPENCODE_SKILLS_DIR/opencode-worker"
    assert_absent "$OCW_AGENTS_SKILLS_DIR/opencode-worker"
  )
}

stress_matrix() {
  local ocw="$1"
  local repo="$TMP_ROOT/stress-repo"
  local i stamp count latest
  local OCW_OPENCODE_BIN="$MOCK_OPENCODE"
  local OCW_OUTPUT_ROOT=".out"
  local OCW_MOCK_LOG="$repo/.out/mock.log"
  local OCW_TEST_CREATED_AT="2026-05-04T00:00:00Z"

  make_repo "$repo"
  export OCW_OPENCODE_BIN OCW_OUTPUT_ROOT OCW_MOCK_LOG OCW_TEST_CREATED_AT
  (
    cd "$repo"

    for i in $(seq 1 "$STRESS_RUNS"); do
      stamp="stress-$i"
      OCW_TEST_STAMP="$stamp" "$ocw" cheap --model opencode-go/qwen3.5-plus "stress run $i" >/dev/null
      assert_file ".out/$stamp-cheap/summary.md"
      assert_file ".out/$stamp-cheap/metadata.txt"
      assert_contains ".out/$stamp-cheap/metadata.txt" "status=0"
      assert_contains ".out/$stamp-cheap/summary.md" "MOCK_OK"
    done

    count="$(find .out -maxdepth 1 -type d -name 'stress-*-cheap' | wc -l | tr -d ' ')"
    assert_eq "$count" "$STRESS_RUNS"
    latest="$("$ocw" last cheap)"
    [[ "$(basename "$latest")" == "stress-$STRESS_RUNS-cheap" ]] || fail "unexpected stress latest: $latest"
  )
}

real_provider_smoke() {
  local ocw="$1"
  local repo="$TMP_ROOT/real-provider-repo"

  if [[ "$REAL_SMOKE" != "1" ]]; then
    say "gauntlet real provider smoke: skipped"
    return
  fi

  command -v opencode >/dev/null 2>&1 || fail "OCW_GAUNTLET_REAL_SMOKE=1 requires opencode on PATH"
  make_repo "$repo"
  (
    cd "$repo"
    OCW_OUTPUT_ROOT=".out" OCW_TEST_STAMP=real-smoke "$ocw" cheap --model "$REAL_MODEL" "Read tracked.txt and return a one-line summary. Do not edit files." >/dev/null
    assert_file ".out/real-smoke-cheap/metadata.txt"
    assert_file ".out/real-smoke-cheap/summary.md"
    assert_contains ".out/real-smoke-cheap/metadata.txt" "status=0"
    assert_contains ".out/real-smoke-cheap/summary.md" "Files changed"
  )
}

main() {
  local install_dir="$TMP_ROOT/bin"
  local extract_dir="$TMP_ROOT/extract"
  local ocw="$install_dir/ocw"

  say "gauntlet: package install flow, negative matrix, stress runs=$STRESS_RUNS"
  install_from_package "$install_dir" "$extract_dir"
  "$ocw" --help | grep -Fq "ocw uninstall"
  check_completions "$ocw"
  negative_matrix "$ocw"
  package_flow_matrix "$ocw" "$install_dir"

  install_from_package "$install_dir" "$extract_dir-reinstall"
  stress_matrix "$ocw"
  real_provider_smoke "$ocw"

  say "gauntlet: ok"
}

main "$@"
