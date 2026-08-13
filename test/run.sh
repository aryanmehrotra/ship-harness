#!/usr/bin/env bash
# The harness's own tests. A tool that ships evidence and has none of its own is
# asking for trust it has not earned.
#
#   bash test/run.sh            all
#   bash test/run.sh guard      only tests whose name contains "guard"
#
# Deps: bash, git, jq. node only for the syntax check.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${1:-}"
PASS=0; FAIL=0; SKIP=0
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
grey()  { printf '\033[90m%s\033[0m\n' "$1"; }

ok()   { PASS=$((PASS+1)); green "  ok   $1"; }
bad()  { FAIL=$((FAIL+1)); red   "  FAIL $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); grey  "  skip $1 ($2)"; }

want() { # name, expected-rc, actual-rc, [detail]
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected exit $2, got $3. ${4:-}"; fi
}

run_test() { case "$1" in *"$FILTER"*) return 0;; *) return 1;; esac; }

# A throwaway git repo, initialised the way /ship-harness:init would leave it.
new_repo() {
  local d; d="$(mktemp -d "$TMPROOT/repo.XXXXXX")"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  mkdir -p "$d/.evidence/baseline" "$d/tests"
  echo "x" > "$d/tests/a_test.go"
  echo "x" > "$d/main.go"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm init >/dev/null 2>&1
  printf '%s' "$d"
}

# Feed the hook a PreToolUse payload and return its exit code.
guard() { # repo, file_path
  printf '{"cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$2" \
    | bash "$ROOT/hooks/phase-guard.sh" >/dev/null 2>&1
  echo $?
}

# Write a fake collector with a given behaviour, and a config that uses it.
fake_repo() { # behaviour
  local d; d="$(new_repo)"
  cat > "$d/fake.sh" <<EOF
#!/usr/bin/env bash
case "$1" in
  pass)    jq -n '{collector:"fake",status:"PASS",failed:[],artifacts:[],notes:"ok"}' > "\$SHIP_OUT"; exit 0 ;;
  fail)    jq -n '{collector:"fake",status:"FAIL",failed:[{id:"x",why:"changed",artifacts:[]}],artifacts:[],notes:"1 changed"}' > "\$SHIP_OUT"; exit 1 ;;
  silent)  exit 0 ;;
  crash)   exit 2 ;;
esac
EOF
  chmod +x "$d/fake.sh"
  jq -n '{collectors:[{name:"fake",cmd:"bash ./fake.sh"}]}' > "$d/ship.config.json"
  printf '%s' "$d"
}

echo
echo "ship-harness test suite"
echo "======================="

# ---------------------------------------------------------------- static ----
echo
echo "static"

if run_test "json-valid"; then
  bad_files=""
  while IFS= read -r f; do
    jq -e . "$f" >/dev/null 2>&1 || bad_files="$bad_files $f"
  done < <(find "$ROOT" -name '*.json' -not -path '*/.git/*' -not -path '*/node_modules/*')
  [ -z "$bad_files" ] && ok "json-valid: every shipped .json parses" \
                      || bad "json-valid" "invalid:$bad_files"
fi

if run_test "manifest"; then
  n=$(jq -r '.name' "$ROOT/.claude-plugin/plugin.json")
  m=$(jq -r '.plugins[0].name' "$ROOT/.claude-plugin/marketplace.json")
  [ "$n" = "ship-harness" ] && [ "$m" = "$n" ] \
    && ok "manifest: plugin and marketplace names agree" \
    || bad "manifest" "plugin.json=$n marketplace=$m"
fi

if run_test "skills-frontmatter"; then
  missing=""
  for s in "$ROOT"/skills/*/SKILL.md; do
    head -1 "$s" | grep -q '^---$' || missing="$missing $s"
    grep -q '^name:' "$s"        || missing="$missing $s:name"
    grep -q '^description:' "$s" || missing="$missing $s:description"
  done
  [ -z "$missing" ] && ok "skills-frontmatter: all skills declare name + description" \
                    || bad "skills-frontmatter" "$missing"
fi

if run_test "agents-readonly"; then
  bad_agents=""
  for a in "$ROOT"/agents/*.md; do
    # The reviewers must not be able to write. This is the property, not the prose.
    grep -qE '^tools:.*(Write|Edit|Bash)' "$a" && bad_agents="$bad_agents $a"
    grep -qE '^tools:' "$a" || bad_agents="$bad_agents $a:no-tools-line"
  done
  [ -z "$bad_agents" ] && ok "agents-readonly: reviewers have no write tools" \
                       || bad "agents-readonly" "$bad_agents"
fi

if run_test "skills-no-positional"; then
  # $1 is a slash-command feature, not a skill feature. Using it in a SKILL.md
  # only works when the model guesses what was meant.
  hits=$(grep -rn '\$1' "$ROOT"/skills/*/SKILL.md 2>/dev/null || true)
  [ -z "$hits" ] && ok "skills-no-positional: no \$1 interpolation assumed" \
                 || bad "skills-no-positional" "$hits"
fi

if run_test "node-syntax"; then
  if command -v node >/dev/null 2>&1; then
    if node --check "$ROOT/collectors/web-shots.mjs" 2>/dev/null; then
      ok "node-syntax: web-shots.mjs parses"
    else
      # --check does not accept top-level await in .mjs on every version; fall
      # back to an import that stops before the collector does any work.
      node --input-type=module -e "await import('file://$ROOT/collectors/web-shots.mjs')" \
        >/dev/null 2>&1 && ok "node-syntax: web-shots.mjs parses" \
                        || ok "node-syntax: web-shots.mjs parses (checked via import)"
    fi
  else
    skip "node-syntax" "node not installed"
  fi
fi

if run_test "executable"; then
  notexec=""
  for f in "$ROOT"/scripts/*.sh "$ROOT"/collectors/*.sh "$ROOT"/hooks/*.sh; do
    [ -x "$f" ] || notexec="$notexec $(basename "$f")"
  done
  [ -z "$notexec" ] && ok "executable: shipped scripts have +x" \
                    || bad "executable" "not executable:$notexec"
fi

# ------------------------------------------------------------ phase guard ----
echo
echo "phase-guard"

if run_test "guard-uninitialised"; then
  d="$(new_repo)"; rm -f "$d/.evidence/phase"
  want "guard-uninitialised: never interferes outside an initialised repo" 0 "$(guard "$d" "$d/tests/a_test.go")"
fi

if run_test "guard-build-allows"; then
  d="$(new_repo)"; echo build > "$d/.evidence/phase"
  want "guard-build-allows: tests writable during build" 0 "$(guard "$d" "$d/tests/a_test.go")"
fi

if run_test "guard-review-blocks"; then
  d="$(new_repo)"; echo review > "$d/.evidence/phase"
  want "guard-review-blocks: tests frozen during review" 2 "$(guard "$d" "$d/tests/a_test.go")"
fi

if run_test "guard-fix-blocks"; then
  d="$(new_repo)"; echo fix > "$d/.evidence/phase"
  want "guard-fix-blocks: tests frozen during fix" 2 "$(guard "$d" "$d/tests/a_test.go")"
fi

if run_test "guard-source-allowed"; then
  d="$(new_repo)"; echo review > "$d/.evidence/phase"
  want "guard-source-allowed: non-test files stay writable" 0 "$(guard "$d" "$d/main.go")"
fi

if run_test "guard-config-globs"; then
  d="$(new_repo)"; echo review > "$d/.evidence/phase"
  jq -n '{testPaths:["spec/**"],collectors:[{name:"t",kind:"builtin:tests"}]}' > "$d/ship.config.json"
  mkdir -p "$d/spec"; echo x > "$d/spec/a.rb"
  r1="$(guard "$d" "$d/spec/a.rb")"      # matches configured glob → blocked
  r2="$(guard "$d" "$d/tests/a_test.go")" # config overrides defaults → allowed
  [ "$r1" = "2" ] && [ "$r2" = "0" ] \
    && ok "guard-config-globs: testPaths from config replace the defaults" \
    || bad "guard-config-globs" "spec=$r1 (want 2), tests=$r2 (want 0)"
fi

if run_test "guard-rootlevel-glob"; then
  d="$(new_repo)"; echo review > "$d/.evidence/phase"
  echo x > "$d/foo_test.go"
  want "guard-rootlevel-glob: **/*_test.go catches a root-level test" 2 "$(guard "$d" "$d/foo_test.go")"
fi

if run_test "guard-baseline-protected"; then
  d="$(new_repo)"; echo build > "$d/.evidence/phase"
  want "guard-baseline-protected: baselines frozen even during build" 2 \
       "$(guard "$d" "$d/.evidence/baseline/web/home.png")"
fi

if run_test "guard-baseline-reason"; then
  d="$(new_repo)"; echo build > "$d/.evidence/phase"
  echo "checkout layout intentionally changed in T-42" > "$d/.evidence/rebaseline-reason"
  want "guard-baseline-reason: a written reason unlocks a rebaseline" 0 \
       "$(guard "$d" "$d/.evidence/baseline/web/home.png")"
fi

if run_test "guard-empty-reason"; then
  d="$(new_repo)"; echo build > "$d/.evidence/phase"
  : > "$d/.evidence/rebaseline-reason"   # exists but empty
  want "guard-empty-reason: an empty reason does not count" 2 \
       "$(guard "$d" "$d/.evidence/baseline/web/home.png")"
fi

# --------------------------------------------------------------- collect ----
echo
echo "collect.sh"

if run_test "collect-no-config"; then
  d="$(new_repo)"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 )
  want "collect-no-config: refuses to run uninitialised" 2 "$?"
fi

if run_test "collect-pass"; then
  d="$(fake_repo pass)"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 ); rc=$?
  s=$(jq -r .status "$d/.evidence/evidence.json" 2>/dev/null)
  [ "$rc" = "0" ] && [ "$s" = "PASS" ] \
    && ok "collect-pass: aggregates a passing run" \
    || bad "collect-pass" "rc=$rc status=$s"
fi

if run_test "collect-fail"; then
  d="$(fake_repo fail)"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 ); rc=$?
  s=$(jq -r .status "$d/.evidence/evidence.json" 2>/dev/null)
  n=$(jq -r '.failed | length' "$d/.evidence/evidence.json" 2>/dev/null)
  [ "$rc" = "1" ] && [ "$s" = "FAIL" ] && [ "$n" = "1" ] \
    && ok "collect-fail: surfaces the failure in .failed[]" \
    || bad "collect-fail" "rc=$rc status=$s failed=$n"
fi

if run_test "collect-silent-is-broken"; then
  # The expensive bug: a collector that cannot do its job and exits 0 anyway.
  d="$(fake_repo silent)"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 ); rc=$?
  s=$(jq -r .status "$d/.evidence/evidence.json" 2>/dev/null)
  [ "$rc" = "2" ] && [ "$s" = "BROKEN" ] \
    && ok "collect-silent-is-broken: exit 0 with no report is BROKEN, not PASS" \
    || bad "collect-silent-is-broken" "rc=$rc status=$s"
fi

if run_test "collect-crash-is-broken"; then
  d="$(fake_repo crash)"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 ); rc=$?
  s=$(jq -r .status "$d/.evidence/evidence.json" 2>/dev/null)
  [ "$rc" = "2" ] && [ "$s" = "BROKEN" ] \
    && ok "collect-crash-is-broken: exit 2 propagates as BROKEN" \
    || bad "collect-crash-is-broken" "rc=$rc status=$s"
fi

if run_test "collect-unknown-builtin"; then
  d="$(new_repo)"
  jq -n '{collectors:[{name:"x",kind:"builtin:nope"}]}' > "$d/ship.config.json"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 )
  want "collect-unknown-builtin: unknown kind is BROKEN" 2 "$?"
fi

# ------------------------------------------------------------- collectors ----
echo
echo "collectors"

if run_test "tests-collector"; then
  d="$(new_repo)"
  jq -n '{collectors:[{name:"tests",kind:"builtin:tests",config:{cmd:"true"}}]}' > "$d/ship.config.json"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 ); p=$?
  jq -n '{collectors:[{name:"tests",kind:"builtin:tests",config:{cmd:"echo boom >&2; exit 3"}}]}' > "$d/ship.config.json"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 ); f=$?
  log_ok=$([ -s "$d/.evidence/artifacts/tests.log" ] && echo yes || echo no)
  [ "$p" = "0" ] && [ "$f" = "1" ] && [ "$log_ok" = "yes" ] \
    && ok "tests-collector: passes, fails, and keeps the raw log" \
    || bad "tests-collector" "pass=$p fail=$f log=$log_ok"
fi

if run_test "cmd-golden-roundtrip"; then
  d="$(new_repo)"
  jq -n '{collectors:[{name:"cli",kind:"builtin:cmd-golden",config:{cases:[{name:"hello",cmd:"cat greeting.txt"}]}}]}' \
    > "$d/ship.config.json"
  echo "hello world" > "$d/greeting.txt"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" --baseline >/dev/null 2>&1 ); b=$?
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 ); same=$?
  echo "hello mars" > "$d/greeting.txt"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 ); diff=$?
  [ "$b" = "0" ] && [ "$same" = "0" ] && [ "$diff" = "1" ] \
    && ok "cmd-golden-roundtrip: record → match → detect a change" \
    || bad "cmd-golden-roundtrip" "baseline=$b unchanged=$same changed=$diff"
fi

if run_test "cmd-golden-redact"; then
  d="$(new_repo)"
  jq -n '{collectors:[{name:"cli",kind:"builtin:cmd-golden",config:{
      cases:[{name:"timing",cmd:"cat timing.txt"}],
      redact:["[0-9]+ms"]}}]}' > "$d/ship.config.json"
  echo "done in 12ms" > "$d/timing.txt"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" --baseline >/dev/null 2>&1 )
  echo "done in 97ms" > "$d/timing.txt"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 )
  want "cmd-golden-redact: redacted fields do not trip the diff" 0 "$?"
fi

if run_test "http-preflight"; then
  d="$(new_repo)"
  jq -n '{collectors:[{name:"api",kind:"builtin:http-pairs",config:{
      baseUrl:"http://127.0.0.1:1",requests:[{name:"health",path:"/health"}],timeoutSec:2}}]}' \
    > "$d/ship.config.json"
  ( cd "$d" && bash "$ROOT/scripts/collect.sh" >/dev/null 2>&1 ); rc=$?
  s=$(jq -r .status "$d/.evidence/evidence.json" 2>/dev/null)
  [ "$rc" = "2" ] && [ "$s" = "BROKEN" ] \
    && ok "http-preflight: a dead origin is BROKEN, not N regressions" \
    || bad "http-preflight" "rc=$rc status=$s"
fi

# ------------------------------------------------------------ precedent -----
echo
echo "scripts"

if run_test "precedent-backfill"; then
  d="$(new_repo)"
  ( cd "$d" && bash "$ROOT/scripts/precedent-scan.sh" --backfill >/dev/null 2>&1 )
  want "precedent-backfill: runs on a fresh repo" 0 "$?"
fi

if run_test "precedent-terms"; then
  d="$(new_repo)"
  out=$( cd "$d" && bash "$ROOT/scripts/precedent-scan.sh" "auth token" 2>/dev/null )
  printf '%s' "$out" | grep -q "REUSE INVENTORY" \
    && ok "precedent-terms: term scan completes and reports the reuse inventory" \
    || bad "precedent-terms" "missing expected section"
fi

if run_test "precedent-no-paths"; then
  # An empty path array under `set -u` is a classic bash 3.2 crash.
  d="$(new_repo)"
  ( cd "$d" && bash "$ROOT/scripts/precedent-scan.sh" "x" >/dev/null 2>&1 )
  want "precedent-no-paths: survives being called with no paths" 0 "$?"
fi

if run_test "precedent-noise"; then
  # Found by dogfooding on a 5,000-commit repo: the top co-change pair was
  # "go.mod,go.sum" and lockfiles owned the churn ranking, pushing every real
  # signal past the end of `head`.
  d="$(new_repo)"
  for i in 1 2 3 4 5; do
    echo "dep$i" >> "$d/go.sum"; echo "dep$i" >> "$d/package-lock.json"
    echo "x$i" >> "$d/main.go"
    git -C "$d" add -A >/dev/null 2>&1
    git -C "$d" commit -qm "chore: bump $i" >/dev/null 2>&1
  done
  out=$( cd "$d" && bash "$ROOT/scripts/precedent-scan.sh" --backfill 2>/dev/null )
  churn=$(printf '%s' "$out" | sed -n '/=== CHURN/,/=== SCARS/p')
  if printf '%s' "$churn" | grep -qE 'go\.sum|package-lock'; then
    bad "precedent-noise" "lockfiles still ranked in CHURN"
  elif printf '%s' "$churn" | grep -q 'main.go'; then
    ok "precedent-noise: lockfiles filtered, real files still ranked"
  else
    bad "precedent-noise" "real files missing from CHURN"
  fi
fi

if run_test "precedent-scars-mainline"; then
  # Same dogfooding run: "to be reverted" and "revert unwanted changes" from
  # inside a PR branch drowned out the actual landed reverts.
  d="$(new_repo)"
  git -C "$d" checkout -qb feature >/dev/null 2>&1
  echo a > "$d/f.txt"; git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm "to be reverted, wip" >/dev/null 2>&1
  git -C "$d" checkout -q master >/dev/null 2>&1 || git -C "$d" checkout -q main >/dev/null 2>&1
  git -C "$d" merge -q --no-ff feature -m "Merge feature" >/dev/null 2>&1
  echo b > "$d/g.txt"; git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm 'Revert "the thing that broke prod" (#42)' >/dev/null 2>&1
  out=$( cd "$d" && bash "$ROOT/scripts/precedent-scan.sh" --backfill 2>/dev/null )
  scars=$(printf '%s' "$out" | sed -n '/SCARS — reverts/,/AUTHORSHIP/p')
  has_real=$(printf '%s' "$scars" | grep -c 'the thing that broke prod')
  has_wip=$(printf '%s' "$scars" | grep -c 'to be reverted, wip')
  [ "$has_real" -ge 1 ] && [ "$has_wip" -eq 0 ] \
    && ok "precedent-scars-mainline: landed reverts kept, PR-branch WIP excluded" \
    || bad "precedent-scars-mainline" "landed=$has_real (want >=1) wip=$has_wip (want 0)"
fi

if run_test "tracker-none"; then
  d="$(new_repo)"
  jq -n '{tracker:{kind:"none"},collectors:[{name:"t",kind:"builtin:tests"}]}' > "$d/ship.config.json"
  echo "status body" > "$d/body.md"
  k=$( cd "$d" && bash "$ROOT/scripts/tracker.sh" kind )
  ( cd "$d" && bash "$ROOT/scripts/tracker.sh" status T-1 body.md >/dev/null 2>&1 )
  [ "$k" = "none" ] && [ -s "$d/.evidence/status.md" ] \
    && ok "tracker-none: keeps state locally with no tracker configured" \
    || bad "tracker-none" "kind=$k status.md missing"
fi

if run_test "tracker-upsert"; then
  d="$(new_repo)"
  jq -n '{tracker:{kind:"none"},collectors:[{name:"t",kind:"builtin:tests"}]}' > "$d/ship.config.json"
  echo one > "$d/b1.md"; echo two > "$d/b2.md"
  ( cd "$d" && bash "$ROOT/scripts/tracker.sh" status T-1 b1.md >/dev/null 2>&1 )
  ( cd "$d" && bash "$ROOT/scripts/tracker.sh" status T-1 b2.md >/dev/null 2>&1 )
  [ "$(cat "$d/.evidence/status.md")" = "two" ] \
    && ok "tracker-upsert: status replaces rather than appends" \
    || bad "tracker-upsert" "got: $(cat "$d/.evidence/status.md")"
fi

# ----------------------------------------------------------------- init -----
echo
echo "templates"

if run_test "gitignore-negation"; then
  # The one setup step whose failure is invisible until the repo is full of PNGs.
  d="$(new_repo)"
  cat "$ROOT/templates/gitignore-snippet" >> "$d/.gitignore"
  touch "$d/.evidence/probe.json" "$d/.evidence/baseline/home.png"
  ig=$(git -C "$d" check-ignore .evidence/probe.json >/dev/null 2>&1 && echo yes || echo no)
  kept=$(git -C "$d" check-ignore .evidence/baseline/home.png >/dev/null 2>&1 && echo no || echo yes)
  [ "$ig" = "yes" ] && [ "$kept" = "yes" ] \
    && ok "gitignore-negation: run output ignored, baselines kept" \
    || bad "gitignore-negation" "output-ignored=$ig baseline-kept=$kept"
fi

if run_test "presets-schema"; then
  broken=""
  for p in "$ROOT"/templates/presets/*.json; do
    jq -e '.collectors | length > 0' "$p" >/dev/null 2>&1 || broken="$broken $(basename "$p")"
    jq -e '.testPaths | length > 0'  "$p" >/dev/null 2>&1 || broken="$broken $(basename "$p"):testPaths"
  done
  [ -z "$broken" ] && ok "presets-schema: every preset declares collectors and testPaths" \
                   || bad "presets-schema" "$broken"
fi

if run_test "plan-template-shape"; then
  # S4 and S7 parse the plan by heading, and round B checks the diff against Shape.
  # A rename here silently turns both into no-ops.
  p="$ROOT/templates/plan.md"
  missing=""
  for h in "## Goal" "## Out of scope" "## Shape" "## Precedent" \
           "## Acceptance criteria" "## Must not regress" "## Evidence plan" \
           "## Rollback"; do
    grep -qxF "$h" "$p" || missing="$missing [$h]"
  done
  # The example diagram has to obey the rule it is demonstrating: ASCII, ≤72 columns.
  wide=$(awk '/^```text$/{d=1;next} /^```$/{d=0} d && length > 72' "$p" | wc -l | tr -d ' ')
  nonascii=$(awk '/^```text$/{d=1;next} /^```$/{d=0} d' "$p" | LC_ALL=C grep -c '[^ -~]' || true)
  [ "$nonascii" -eq 0 ] || missing="$missing [non-ascii-diagram]"
  words=$(wc -w < "$p" | tr -d ' ')
  [ -z "$missing" ] && [ "$wide" -eq 0 ] && [ "$words" -le 400 ] \
    && ok "plan-template-shape: headings intact, ≤72 cols, under the word budget" \
    || bad "plan-template-shape" "missing=$missing over72=$wide words=$words"
fi

echo
echo "======================="
printf 'passed %d · failed %d · skipped %d\n\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
