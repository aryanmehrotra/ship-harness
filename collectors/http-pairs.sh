#!/usr/bin/env bash
# Evidence for services with no UI: real request/response pairs, normalised and
# diffed against a committed baseline.
#
# This is the backend equivalent of a screenshot. "The endpoint still returns what
# it returned last week, byte for byte, minus the fields that are allowed to move"
# is a much stronger claim than a passing unit test, and unlike a screenshot it
# costs nothing to store or read.
#
# Config (ship.config.json → collectors[].config):
# {
#   "baseUrl": "http://localhost:8080",
#   "requests": [
#     {"name":"health","method":"GET","path":"/health"},
#     {"name":"create","method":"POST","path":"/users",
#      "headers":{"Content-Type":"application/json"},"body":"{\"name\":\"ada\"}"}
#   ],
#   "includeHeaders": ["content-type"],
#   "redact": ["\"id\"[[:space:]]*:[[:space:]]*\"[^\"]*\""],
#   "timeoutSec": 15
# }
#
# `redact` patterns are POSIX extended regexes (sed -E). Use them for ids,
# timestamps and durations. Redact narrowly: every pattern you add is a field
# this collector stops watching.

set -uo pipefail

NAME="${SHIP_NAME:-http}"
MODE="${SHIP_MODE:-compare}"
OUT="${SHIP_OUT:-.evidence/$NAME.json}"
EVID="${SHIP_EVIDENCE_DIR:-.evidence}"
BASE="${SHIP_BASELINE_DIR:-.evidence/baseline/$NAME}"
CFG="${SHIP_COLLECTOR_CONFIG:-{\}}"
CUR="$EVID/artifacts/$NAME"

command -v jq   >/dev/null 2>&1 || { echo "http-pairs: jq is required" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "http-pairs: curl is required" >&2; exit 2; }

j() { printf '%s' "$CFG" | jq -r "$1" 2>/dev/null; }

BASEURL=$(j '.baseUrl // "http://localhost:8080"')
TIMEOUT=$(j '.timeoutSec // 15')
NREQ=$(j '.requests | length // 0'); [ "$NREQ" = "null" ] && NREQ=0

report() { # status, failed-json-array, notes
  mkdir -p "$(dirname "$OUT")"
  jq -n --arg c "$NAME" --arg s "$1" --argjson f "$2" --arg n "$3" \
        --arg a "$CUR" \
        '{collector:$c,status:$s,failed:$f,artifacts:[$a],notes:$n}' > "$OUT"
  case "$1" in PASS) exit 0;; FAIL) exit 1;; *) exit 2;; esac
}

[ "$NREQ" -eq 0 ] && report BROKEN '[]' "no requests configured for collector '$NAME'"

# Preflight: an unreachable service must read as BROKEN, never as N regressions.
if ! curl -sS -o /dev/null --max-time "$TIMEOUT" "$BASEURL" 2>/dev/null; then
  report BROKEN '[]' "$BASEURL is not reachable — start the service before collecting evidence."
fi

DEST="$CUR"; [ "$MODE" = "baseline" ] && DEST="$BASE"
mkdir -p "$DEST"
failed='[]'

for i in $(seq 0 $((NREQ - 1))); do
  rname=$(j ".requests[$i].name // \"req$i\"")
  method=$(j ".requests[$i].method // \"GET\"")
  rpath=$(j ".requests[$i].path // \"/\"")
  body=$(j ".requests[$i].body // empty")

  hdr_args=()
  while IFS= read -r h; do
    [ -n "$h" ] && hdr_args+=(-H "$h")
  done < <(printf '%s' "$CFG" | jq -r ".requests[$i].headers // {} | to_entries[] | \"\(.key): \(.value)\"" 2>/dev/null)

  body_args=()
  [ -n "$body" ] && body_args=(--data-binary "$body")

  raw_body=$(mktemp); raw_hdrs=$(mktemp)
  code=$(curl -sS -o "$raw_body" -D "$raw_hdrs" -w '%{http_code}' \
              --max-time "$TIMEOUT" -X "$method" \
              "${hdr_args[@]+"${hdr_args[@]}"}" "${body_args[@]+"${body_args[@]}"}" \
              "$BASEURL$rpath" 2>/dev/null) || code="000"

  pair="$DEST/$rname.txt"
  {
    echo "### $method $rpath"
    echo "< $code"
    while IFS= read -r want; do
      grep -i "^$want:" "$raw_hdrs" 2>/dev/null | sed 's/\r$//' | sed 's/^/< /'
    done < <(printf '%s' "$CFG" | jq -r '.includeHeaders[]? // empty' 2>/dev/null)
    echo "<"
    # Pretty-print JSON so a one-field change is a one-line diff, not one huge line.
    if jq -e . "$raw_body" >/dev/null 2>&1; then jq -S . "$raw_body"; else cat "$raw_body"; fi
  } > "$pair.tmp"

  # Redact the fields that are allowed to move between runs.
  cp "$pair.tmp" "$pair"
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    sed -E "s|$pat|<redacted>|g" "$pair" > "$pair.red" 2>/dev/null && mv "$pair.red" "$pair"
  done < <(printf '%s' "$CFG" | jq -r '.redact[]? // empty' 2>/dev/null)
  rm -f "$pair.tmp" "$raw_body" "$raw_hdrs"

  [ "$MODE" = "baseline" ] && continue

  golden="$BASE/$rname.txt"
  if [ ! -f "$golden" ]; then
    failed=$(printf '%s' "$failed" | jq --arg id "$rname" --arg p "$pair" \
      '. + [{id:$id,why:"no baseline recorded for this request",artifacts:[$p]}]')
    continue
  fi
  if ! diff -q "$golden" "$pair" >/dev/null 2>&1; then
    d=$(diff -u "$golden" "$pair" | head -40)
    failed=$(printf '%s' "$failed" | jq --arg id "$rname" --arg w "response changed" \
      --arg d "$d" --arg g "$golden" --arg p "$pair" \
      '. + [{id:$id,why:$w,diff:$d,artifacts:[$g,$p]}]')
  fi
done

n=$(printf '%s' "$failed" | jq 'length')
if [ "$MODE" = "baseline" ]; then
  report PASS '[]' "recorded $NREQ request/response pairs into $BASE — commit them."
fi
[ "$n" -eq 0 ] && report PASS '[]' "$NREQ requests · all match baseline"
report FAIL "$failed" "$NREQ requests · $n changed"
