#!/usr/bin/env bash
# Run every collector in ship.config.json and aggregate one verdict.
#
#   scripts/collect.sh              compare against committed baselines
#   scripts/collect.sh --baseline   (re)record the baselines
#   scripts/collect.sh --only web   run a single collector by name
#
# No model runs in this file. That is the point: the agent is only allowed to
# look at what a deterministic process already marked as failed, which is what
# keeps the evidence step cheap and keeps a persuasive-sounding model from
# talking its way past a real regression.
#
# Exit: 0 all passed · 1 at least one collector failed · 2 a collector is broken
#
# A broken collector is deliberately not the same as a failing one. "The
# screenshot tool crashed" and "the page regressed" are different facts, and a
# harness that reports them identically will eventually report a crash as a
# clean run.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$HERE")}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 2

MODE="compare"
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) MODE="baseline" ;;
    --only) shift; ONLY="${1:-}" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "collect.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

CFG="$ROOT/ship.config.json"
if [ ! -f "$CFG" ]; then
  echo "collect.sh: no ship.config.json at repo root — run /ship-harness:memory, or just start a ship/review run" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "collect.sh: jq is required" >&2; exit 2; }

EVIDENCE="$ROOT/.evidence"
BASELINE="$EVIDENCE/baseline"
mkdir -p "$EVIDENCE/artifacts" "$BASELINE"

count=$(jq '.collectors | length' "$CFG" 2>/dev/null || echo 0)
if [ "$count" = "0" ] || [ "$count" = "null" ]; then
  echo "collect.sh: ship.config.json defines no collectors." >&2
  echo "Evidence is the point of this harness — see docs/evidence-collectors.md." >&2
  exit 2
fi

worst=0
summaries=()
reports=()

for i in $(seq 0 $((count - 1))); do
  name=$(jq -r ".collectors[$i].name" "$CFG")
  kind=$(jq -r ".collectors[$i].kind // empty" "$CFG")
  cmd=$(jq -r ".collectors[$i].cmd // empty" "$CFG")
  ccfg=$(jq -c ".collectors[$i].config // {}" "$CFG")

  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue

  # Resolve what to actually execute.
  case "$kind" in
    builtin:*)
      builtin="${kind#builtin:}"
      if   [ -f "$PLUGIN_ROOT/collectors/$builtin.mjs" ]; then run=(node "$PLUGIN_ROOT/collectors/$builtin.mjs")
      elif [ -f "$PLUGIN_ROOT/collectors/$builtin.sh" ];  then run=(bash "$PLUGIN_ROOT/collectors/$builtin.sh")
      else
        echo "collect.sh: no builtin collector named '$builtin'" >&2
        worst=2; summaries+=("$name BROKEN no-such-builtin"); continue
      fi
      ;;
    "")
      if [ -z "$cmd" ]; then
        echo "collect.sh: collector '$name' has neither 'kind' nor 'cmd'" >&2
        worst=2; summaries+=("$name BROKEN misconfigured"); continue
      fi
      # shellcheck disable=SC2206
      run=(bash -c "$cmd")
      ;;
    *)
      echo "collect.sh: collector '$name' has unknown kind '$kind'" >&2
      worst=2; summaries+=("$name BROKEN unknown-kind"); continue
      ;;
  esac

  out="$EVIDENCE/$name.json"
  rm -f "$out"

  SHIP_MODE="$MODE" \
  SHIP_NAME="$name" \
  SHIP_ROOT="$ROOT" \
  SHIP_EVIDENCE_DIR="$EVIDENCE" \
  SHIP_BASELINE_DIR="$BASELINE/$name" \
  SHIP_OUT="$out" \
  SHIP_COLLECTOR_CONFIG="$ccfg" \
    "${run[@]}"
  rc=$?

  # A collector that exits 0/1 but writes no report is broken, not passing.
  if [ ! -f "$out" ]; then
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
      printf '{"collector":"%s","status":"BROKEN","failed":[],"artifacts":[],"notes":"collector exited %d without writing %s"}\n' \
        "$name" "$rc" "$out" > "$out"
    else
      printf '{"collector":"%s","status":"BROKEN","failed":[],"artifacts":[],"notes":"collector exited %d"}\n' \
        "$name" "$rc" > "$out"
    fi
    rc=2
  fi

  status=$(jq -r '.status // "BROKEN"' "$out" 2>/dev/null || echo BROKEN)
  nfail=$(jq -r '.failed | length' "$out" 2>/dev/null || echo 0)

  case "$status" in
    PASS)   [ "$worst" -lt 0 ] && worst=0 ;;
    FAIL)   [ "$worst" -lt 1 ] && worst=1 ;;
    *)      worst=2 ;;
  esac
  [ "$rc" -eq 2 ] && worst=2

  summaries+=("$name $status $nfail")
  reports+=("$out")
done

if [ "${#reports[@]}" -eq 0 ]; then
  echo "collect.sh: no collectors ran${ONLY:+ (no collector named '$ONLY')}" >&2
  exit 2
fi

# One aggregate file. The ship skill reads this and nothing else — every
# collector, however it was written, arrives here in the same shape.
overall=$([ "$worst" -eq 0 ] && echo PASS || { [ "$worst" -eq 1 ] && echo FAIL || echo BROKEN; })
jq -s --arg mode "$MODE" --arg status "$overall" '
  {
    mode: $mode,
    status: $status,
    collectors: .,
    failed: [ .[] | select(.status != "PASS") | {collector, status, failed} ]
  }' "${reports[@]}" > "$EVIDENCE/evidence.json" || {
    echo "collect.sh: could not aggregate collector reports" >&2; exit 2; }

printf '\n%-18s %-8s %s\n' "COLLECTOR" "STATUS" "FAILURES"
printf '%-18s %-8s %s\n' "------------------" "--------" "--------"
for s in "${summaries[@]}"; do
  # shellcheck disable=SC2086
  set -- $s
  printf '%-18s %-8s %s\n' "$1" "$2" "$3"
done
echo
case "$worst" in
  0) echo "All collectors passed. Full report: .evidence/evidence.json" ;;
  1) echo "Regressions found. Open ONLY the entries under .failed[] in .evidence/evidence.json" ;;
  2) echo "A collector is BROKEN. This is not a passing run — fix the collector before trusting anything." ;;
esac
exit "$worst"
