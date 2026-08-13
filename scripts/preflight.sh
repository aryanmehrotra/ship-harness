#!/usr/bin/env bash
# What state is this repo in, and what does the harness owe it before work starts?
#
# Emits one JSON object. Nothing here is a judgement call, which is the point: the
# decision to backfill or refresh should not depend on a model's mood, and a user should
# never have to know that `backfill` is a thing that exists.
#
#   bash scripts/preflight.sh
#
# needs[] is ordered. Do them in that order; each is a precondition for the next.

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

CFG="ship.config.json"
now=$(date -u +%s)

json_bool() { [ "$1" = "1" ] && echo true || echo false; }

# --- config ------------------------------------------------------------------
has_cfg=0; setup_confirmed=0; confirmed_at=null
if [ -f "$CFG" ]; then
  has_cfg=1
  c=$(jq -r '.setup.confirmedAt // empty' "$CFG" 2>/dev/null)
  if [ -n "$c" ] && [ "$c" != "null" ]; then setup_confirmed=1; confirmed_at="\"$c\""; fi
fi

# --- memory ------------------------------------------------------------------
# "Empty" means the templates are there but nobody has filled them — the state a fresh
# init leaves behind, and the one where every plan cites nothing.
mem_files=0; mem_lines=0; mem_empty=1
if [ -d docs/memory ]; then
  for f in docs/memory/*.md; do
    [ -e "$f" ] || continue
    mem_files=$((mem_files + 1))
    n=$(grep -cvE '^\s*$|^#|^>|^\s*<empty|^\|' "$f" 2>/dev/null || echo 0)
    mem_lines=$((mem_lines + n))
  done
fi
[ "$mem_lines" -gt 10 ] && mem_empty=0

# Age of the last memory commit — the signal refresh exists for. Untouched for 30+ days
# means every line in it is a claim nobody has re-checked since.
mem_age=-1
if [ -d docs/memory ]; then
  last=$(git log -1 --format=%ct -- docs/memory 2>/dev/null)
  [ -n "$last" ] && mem_age=$(( (now - last) / 86400 ))
fi

# --- gaps --------------------------------------------------------------------
# Questions a previous run could not answer from memory. This is the harness's own
# to-do list, and the reason it gets better at a repo instead of merely older.
gaps=0
[ -f .evidence/memory-gaps.md ] && gaps=$(grep -cE '^- ' .evidence/memory-gaps.md 2>/dev/null || echo 0)

# --- harness version ---------------------------------------------------------
# Cached for a day and silent when offline. A run must never fail because GitHub is down.
upd='{"current":"unknown","latest":"unknown","behind":false,"checked":"","source":"none"}'
vc="$(dirname "${BASH_SOURCE[0]}")/version-check.sh"
[ -x "$vc" ] && upd=$(bash "$vc" 2>/dev/null || echo "$upd")

# --- run state ---------------------------------------------------------------
phase="none"; [ -f .evidence/phase ] && phase=$(tr -d '[:space:]' < .evidence/phase)
repo_commits=$(git rev-list --count HEAD 2>/dev/null || echo 0)

# --- needs, in order ---------------------------------------------------------
needs=()
[ "$has_cfg" = "0" ]          && needs+=('"init"')
[ "$setup_confirmed" = "0" ]  && needs+=('"confirm-budgets"')
[ "$mem_empty" = "1" ] && [ "$repo_commits" -gt 20 ] && needs+=('"backfill"')
{ [ "$mem_age" -gt 30 ] || [ "$gaps" -gt 0 ]; } && [ "$mem_empty" = "0" ] && needs+=('"refresh"')

printf '{\n'
printf '  "config": %s,\n'            "$(json_bool $has_cfg)"
printf '  "setupConfirmed": %s,\n'    "$(json_bool $setup_confirmed)"
printf '  "confirmedAt": %s,\n'       "$confirmed_at"
printf '  "memory": { "files": %d, "lines": %d, "empty": %s, "ageDays": %d },\n' \
  "$mem_files" "$mem_lines" "$(json_bool $mem_empty)" "$mem_age"
printf '  "openGaps": %d,\n'          "$gaps"
printf '  "harness": %s,\n'          "$upd"
printf '  "phase": "%s",\n'           "$phase"
printf '  "repoCommits": %d,\n'       "$repo_commits"
printf '  "needs": [%s]\n'            "$(IFS=,; echo "${needs[*]:-}")"
printf '}\n'
