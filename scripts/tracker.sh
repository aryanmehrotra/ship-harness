#!/usr/bin/env bash
# Tracker adapter. Four verbs, one contract, so the pipeline never hardcodes GitHub.
#
#   tracker.sh fetch  <id>            print the ticket and its discussion
#   tracker.sh status <id> <file>     upsert THE single status comment from <file>
#   tracker.sh link   <id>            print a URL (or a local path) for the report
#   tracker.sh kind                   print the configured tracker kind
#
# "Upsert" matters: one comment per ticket, edited in place. A pipeline that posts
# a new comment per stage turns a ticket into a changelog nobody reads, and the
# current state stops being findable — which defeats the point of keeping state
# there at all.
#
# Adding Jira or Linear means implementing these four verbs. Nothing else in the
# harness knows what a tracker is.

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CFG="$ROOT/ship.config.json"
EVID="$ROOT/.evidence"

kind="none"
if [ -f "$CFG" ] && command -v jq >/dev/null 2>&1; then
  kind=$(jq -r '.tracker.kind // "none"' "$CFG" 2>/dev/null)
fi

verb="${1:-}"; shift || true

case "$verb" in
  kind) echo "$kind"; exit 0 ;;

  fetch)
    id="${1:?tracker.sh fetch <id>}"
    case "$kind" in
      github)
        command -v gh >/dev/null 2>&1 || { echo "tracker: gh not installed" >&2; exit 2; }
        # Strip a leading # or a common prefix so both '#123' and 'T-123' work.
        num="${id##*[!0-9]}"
        gh issue view "$num" --comments 2>/dev/null \
          || gh pr view "$num" --comments 2>/dev/null \
          || { echo "tracker: could not fetch $id from GitHub" >&2; exit 2; }
        ;;
      none)
        echo "(tracker: none — no ticket system configured)"
        echo "The ticket text is whatever the user pasted into the conversation."
        [ -f "$EVID/status.md" ] && { echo; echo "--- last local status ---"; cat "$EVID/status.md"; }
        ;;
      *) echo "tracker: unknown kind '$kind'" >&2; exit 2 ;;
    esac
    ;;

  status)
    id="${1:?tracker.sh status <id> <file>}"
    file="${2:?tracker.sh status <id> <file>}"
    [ -f "$file" ] || { echo "tracker: no such file: $file" >&2; exit 2; }
    mkdir -p "$EVID"
    case "$kind" in
      github)
        command -v gh >/dev/null 2>&1 || { echo "tracker: gh not installed" >&2; exit 2; }
        num="${id##*[!0-9]}"
        cid_file="$EVID/comment-id"
        if [ -s "$cid_file" ]; then
          cid=$(cat "$cid_file")
          repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
          if gh api -X PATCH "repos/$repo/issues/comments/$cid" \
               -f body="$(cat "$file")" >/dev/null 2>&1; then
            echo "updated comment $cid on $id"; exit 0
          fi
          # The comment was deleted, or we lost access. Fall through and make a new
          # one rather than dropping the status on the floor.
          echo "tracker: could not edit comment $cid, posting a new one" >&2
        fi
        url=$(gh issue comment "$num" --body-file "$file" 2>/dev/null) || {
          echo "tracker: could not comment on $id" >&2; exit 2; }
        printf '%s' "${url##*-}" > "$cid_file"
        echo "$url"
        ;;
      none)
        cp "$file" "$EVID/status.md"
        echo "$EVID/status.md"
        ;;
      *) echo "tracker: unknown kind '$kind'" >&2; exit 2 ;;
    esac
    ;;

  link)
    id="${1:?tracker.sh link <id>}"
    case "$kind" in
      github)
        num="${id##*[!0-9]}"
        gh issue view "$num" --json url -q .url 2>/dev/null || echo "(no url)"
        ;;
      none) echo "$EVID/status.md" ;;
    esac
    ;;

  *)
    sed -n '2,16p' "$0"
    exit 2
    ;;
esac
