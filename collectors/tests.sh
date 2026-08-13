#!/usr/bin/env bash
# Wrap the repo's own test command and keep its output as evidence.
#
# The point is not to discover that tests exist — it is that the *raw, unsummarised*
# output ends up in .evidence/artifacts/, where the report links to it. A model that
# writes "tests pass" into a report is making a claim; a linked 400-line log is a fact,
# and the difference matters precisely when the claim is wrong.
#
# Config: {"cmd": "go test ./...", "timeoutSec": 900}
#
# There is no baseline here. A test suite is already its own oracle.

set -uo pipefail

NAME="${SHIP_NAME:-tests}"
MODE="${SHIP_MODE:-compare}"
OUT="${SHIP_OUT:-.evidence/$NAME.json}"
EVID="${SHIP_EVIDENCE_DIR:-.evidence}"
CFG="${SHIP_COLLECTOR_CONFIG:-{\}}"
LOG="$EVID/artifacts/$NAME.log"

command -v jq >/dev/null 2>&1 || { echo "tests: jq is required" >&2; exit 2; }

CMD=$(printf '%s' "$CFG" | jq -r '.cmd // empty' 2>/dev/null)
TIMEOUT=$(printf '%s' "$CFG" | jq -r '.timeoutSec // 900' 2>/dev/null)

report() {
  mkdir -p "$(dirname "$OUT")"
  jq -n --arg c "$NAME" --arg s "$1" --argjson f "$2" --arg n "$3" --arg a "$LOG" \
        '{collector:$c,status:$s,failed:$f,artifacts:[$a],notes:$n}' > "$OUT"
  case "$1" in PASS) exit 0;; FAIL) exit 1;; *) exit 2;; esac
}

[ -z "$CMD" ] && report BROKEN '[]' "collector '$NAME' has no .config.cmd"

# Recording a baseline is a no-op for tests, but it must still succeed — the
# baseline pass has to be runnable in a repo that has not been built yet.
if [ "$MODE" = "baseline" ]; then
  report PASS '[]' "tests have no baseline to record"
fi

mkdir -p "$(dirname "$LOG")"

TO=""
if command -v timeout  >/dev/null 2>&1; then TO="timeout $TIMEOUT"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout $TIMEOUT"; fi

# shellcheck disable=SC2086
$TO bash -c "$CMD" >"$LOG" 2>&1; rc=$?

if [ "$rc" -eq 0 ]; then
  report PASS '[]' "$(printf '%s' "$CMD") passed · full output: $LOG"
fi

if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
  report BROKEN '[]' "test command timed out after ${TIMEOUT}s · partial output: $LOG"
fi

tail=$(tail -30 "$LOG" | jq -Rs .)
failed=$(jq -n --arg id "$NAME" --arg w "test command exited $rc" \
               --argjson t "$tail" --arg l "$LOG" \
  '[{id:$id,why:$w,tail:$t,artifacts:[$l]}]')
report FAIL "$failed" "$(printf '%s' "$CMD") failed (exit $rc) · full output: $LOG"
