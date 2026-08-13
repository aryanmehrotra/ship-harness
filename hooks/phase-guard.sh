#!/usr/bin/env bash
# PreToolUse guard for ship-harness.
#
# Two rules, both of which the README claims are "enforced, not asked nicely".
# This file is the enforcement. Without it they are just prose in a skill.
#
#   1. Test files are frozen during the review and fix phases.
#      You write tests in the build phase, before implementation. After that,
#      an agent that can edit tests to make a review finding disappear will
#      eventually do exactly that. It is the cheapest available fix and it is
#      always wrong.
#
#   2. Committed baselines are frozen unless a reason was written down.
#      The baseline is the oracle. Silently re-recording it turns every future
#      visual regression into a pass. A rebaseline is allowed — it just has to
#      be a decision someone made on purpose and can be read back later.
#
# Both rules are scoped to a repo that has actually been initialised
# (`.evidence/phase` exists). Outside such a repo this hook exits immediately,
# so installing the plugin never changes how you work anywhere else.
#
# Phase values, written by the ship skill: plan build review fix evidence report
#
# Block protocol: exit 2 with the reason on stderr. Claude Code feeds stderr
# back to the model, so the reason has to explain what to do instead.

set -u

input=$(cat)

# --- extract the target path, tolerating every tool-input shape ------------
if command -v jq >/dev/null 2>&1; then
  path=$(printf '%s' "$input" | jq -r '
    .tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty
  ' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
else
  # jq is a hard dependency of the harness, but never fail *closed* on a
  # missing dependency — that would block every edit in every repo.
  exit 0
fi

[ -z "${path:-}" ] && exit 0
[ -z "${cwd:-}" ] && cwd="$PWD"

# --- locate the repo, then the harness state ------------------------------
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/.evidence/phase" ] || exit 0

phase=$(tr -d '[:space:]' < "$root/.evidence/phase")
[ -z "$phase" ] && exit 0

# Normalise to a repo-relative path so config globs stay portable.
#
# This cannot be a plain prefix strip. The tool reports the path the caller used,
# while git reports the physical one, and on macOS every path under /tmp differs
# between the two (/var vs /private/var). Any repo reached through a symlink has
# the same problem. A failed strip leaves an absolute path, every glob silently
# stops matching, and the guard quietly protects nothing — which looks exactly
# like a guard that is working.
abspath() {
  local p="$1" d b acc=""
  d=$(dirname "$p"); b=$(basename "$p")
  # The file, and possibly several of its parents, may not exist yet.
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
    acc="$(basename "$d")/$acc"; d=$(dirname "$d")
  done
  [ -d "$d" ] && d=$(cd "$d" 2>/dev/null && pwd -P)
  printf '%s/%s%s' "$d" "$acc" "$b"
}

phys_root=$(cd "$root" 2>/dev/null && pwd -P) || phys_root="$root"
case "$path" in
  /*) rel=$(abspath "$path") ;;
  *)  rel=$(abspath "$PWD/$path") ;;
esac
rel="${rel#"$phys_root"/}"
# Still absolute means the edit is outside this repo entirely; not ours to police.
case "$rel" in /*) exit 0 ;; esac

# --- rule 2: baselines are the oracle -------------------------------------
case "$rel" in
  .evidence/baseline/*)
    reason_file="$root/.evidence/rebaseline-reason"
    if [ -s "$reason_file" ]; then
      exit 0
    fi
    cat >&2 <<EOF
ship-harness: refusing to modify a committed baseline.

  $rel

The baseline is the oracle every later run is compared against. Overwriting it
makes the regression you are looking at disappear along with every future one on
this surface.

If this change to the baseline is intended, write the reason first:

  echo "<why the expected output legitimately changed>" > .evidence/rebaseline-reason

That reason is copied into the evidence report, so the next person reading the
report can see the oracle moved and why.
EOF
    exit 2
    ;;
esac

# --- rule 1: tests are frozen after the build phase -----------------------
case "$phase" in
  review|fix) ;;
  *) exit 0 ;;
esac

cfg="$root/ship.config.json"
if [ -f "$cfg" ]; then
  patterns=$(jq -r '.testPaths[]? // empty' "$cfg" 2>/dev/null)
else
  patterns=""
fi
# Sensible defaults so the guard still works before anyone edits the config.
[ -z "$patterns" ] && patterns='tests/**
test/**
spec/**
**/*_test.go
**/*_test.py
**/test_*.py
**/*.test.ts
**/*.test.tsx
**/*.test.js
**/*.spec.ts
**/*.spec.js
**/*Test.java
**/*_spec.rb'

matched=""
while IFS= read -r glob; do
  [ -z "$glob" ] && continue
  # In bash [[ ]] patterns, * spans '/', so 'tests/**' behaves like a recursive
  # match. A leading '**/' is also tested stripped, so 'foo_test.go' at the repo
  # root matches '**/*_test.go' the way a reader expects it to.
  # shellcheck disable=SC2053  # unquoted on purpose: these ARE globs
  if [[ "$rel" == $glob ]]; then matched="$glob"; break; fi
  bare="${glob#\*\*/}"
  # shellcheck disable=SC2053
  if [ "$bare" != "$glob" ] && [[ "$rel" == $bare ]]; then matched="$glob"; break; fi
done <<< "$patterns"

[ -z "$matched" ] && exit 0

cat >&2 <<EOF
ship-harness: tests are frozen during the '$phase' phase.

  $rel   (matched testPaths pattern: $matched)

Tests are written and committed in the build phase, before the implementation, so
that the review rounds have a fixed target. Editing them now means the finding you
are responding to can be made to vanish rather than be fixed, which is the one
failure mode this pipeline exists to prevent.

Do one of these instead:

  1. Fix the implementation so the existing test passes.
  2. If the finding is genuinely *about* the test — it asserts the wrong thing, or
     the plan's acceptance criteria changed — say so out loud, then unfreeze for
     this one edit:
         echo build > .evidence/phase
     and set it back to '$phase' immediately afterwards. That flip is visible in
     the run, which is the point.
EOF
exit 2
