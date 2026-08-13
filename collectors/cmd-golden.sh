#!/usr/bin/env bash
# Evidence for CLIs, codegen, formatters, compilers, migrations — anything whose
# observable behaviour is "run it and look at what came out".
#
# Captures stdout, stderr and exit code for each case, normalises the parts that
# are allowed to move, and diffs against a committed golden file.
#
# Config (ship.config.json → collectors[].config):
# {
#   "cases": [
#     {"name":"help",        "cmd":"./bin/app --help"},
#     {"name":"migrate-plan","cmd":"./bin/app migrate --dry-run"}
#   ],
#   "redact": ["[0-9]+(\\.[0-9]+)?(ms|s)\\b", "/Users/[^/ ]+"],
#   "timeoutSec": 120
# }

set -uo pipefail

NAME="${SHIP_NAME:-cmd}"
MODE="${SHIP_MODE:-compare}"
OUT="${SHIP_OUT:-.evidence/$NAME.json}"
EVID="${SHIP_EVIDENCE_DIR:-.evidence}"
BASE="${SHIP_BASELINE_DIR:-.evidence/baseline/$NAME}"
CFG="${SHIP_COLLECTOR_CONFIG:-{\}}"
CUR="$EVID/artifacts/$NAME"

command -v jq >/dev/null 2>&1 || { echo "cmd-golden: jq is required" >&2; exit 2; }
j() { printf '%s' "$CFG" | jq -r "$1" 2>/dev/null; }

NCASE=$(j '.cases | length // 0'); [ "$NCASE" = "null" ] && NCASE=0
TIMEOUT=$(j '.timeoutSec // 120')

report() {
  mkdir -p "$(dirname "$OUT")"
  jq -n --arg c "$NAME" --arg s "$1" --argjson f "$2" --arg n "$3" --arg a "$CUR" \
        '{collector:$c,status:$s,failed:$f,artifacts:[$a],notes:$n}' > "$OUT"
  case "$1" in PASS) exit 0;; FAIL) exit 1;; *) exit 2;; esac
}

[ "$NCASE" -eq 0 ] && report BROKEN '[]' "no cases configured for collector '$NAME'"

DEST="$CUR"; [ "$MODE" = "baseline" ] && DEST="$BASE"
mkdir -p "$DEST"
failed='[]'

# `timeout` is GNU; macOS ships it as gtimeout via coreutils, and neither is
# guaranteed. Degrade to running without a timeout rather than failing outright.
TO=""
if command -v timeout  >/dev/null 2>&1; then TO="timeout $TIMEOUT"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout $TIMEOUT"; fi

for i in $(seq 0 $((NCASE - 1))); do
  cname=$(j ".cases[$i].name // \"case$i\"")
  ccmd=$(j ".cases[$i].cmd // empty")
  [ -z "$ccmd" ] && continue

  golden_out="$DEST/$cname.txt"
  so=$(mktemp); se=$(mktemp)
  # shellcheck disable=SC2086
  $TO bash -c "$ccmd" >"$so" 2>"$se"; rc=$?

  {
    echo "### $ccmd"
    echo "exit: $rc"
    echo "--- stdout"
    cat "$so"
    echo "--- stderr"
    cat "$se"
  } > "$golden_out"
  rm -f "$so" "$se"

  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    sed -E "s|$pat|<redacted>|g" "$golden_out" > "$golden_out.red" 2>/dev/null \
      && mv "$golden_out.red" "$golden_out"
  done < <(printf '%s' "$CFG" | jq -r '.redact[]? // empty' 2>/dev/null)

  [ "$MODE" = "baseline" ] && continue

  golden="$BASE/$cname.txt"
  if [ ! -f "$golden" ]; then
    failed=$(printf '%s' "$failed" | jq --arg id "$cname" --arg p "$golden_out" \
      '. + [{id:$id,why:"no golden file recorded for this case",artifacts:[$p]}]')
    continue
  fi
  if ! diff -q "$golden" "$golden_out" >/dev/null 2>&1; then
    d=$(diff -u "$golden" "$golden_out" | head -40)
    failed=$(printf '%s' "$failed" | jq --arg id "$cname" --arg d "$d" \
      --arg g "$golden" --arg p "$golden_out" \
      '. + [{id:$id,why:"output changed",diff:$d,artifacts:[$g,$p]}]')
  fi
done

n=$(printf '%s' "$failed" | jq 'length')
[ "$MODE" = "baseline" ] && report PASS '[]' "recorded $NCASE golden files into $BASE — commit them."
[ "$n" -eq 0 ] && report PASS '[]' "$NCASE cases · all match golden"
report FAIL "$failed" "$NCASE cases · $n changed"
