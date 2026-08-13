#!/usr/bin/env bash
# Is the installed harness behind the latest release?
#
# Emits one JSON object. Never fails a run: no network, no gh, rate-limited API, private
# repo — all of them are "unknown", not an error. A version check that can break someone's
# build is worse than no version check.
#
#   bash scripts/version-check.sh          # cached for 24h
#   bash scripts/version-check.sh --force  # ignore the cache
#
# {"current":"0.5.0","latest":"0.6.0","behind":true,"checked":"2026-08-13","source":"cache|api|none"}

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the offline path is testable, and so a fork can point at its own releases.
REPO="${SHIP_HARNESS_REPO:-aryanmehrotra/ship-harness}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ship-harness"
CACHE="$CACHE_DIR/latest-version"
TTL_HOURS=24
FORCE="${1:-}"

current=$(jq -r '.version // "unknown"' "$HERE/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)
today=$(date -u +%Y-%m-%d)

emit() { # latest, source
  local latest="$1" src="$2" behind=false
  if [ "$latest" != "unknown" ] && [ "$current" != "unknown" ] && [ "$latest" != "$current" ]; then
    # Only "behind" if latest sorts strictly above current. A local build ahead of the
    # published release is a normal state for whoever is developing the harness.
    newest=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)
    [ "$newest" = "$latest" ] && behind=true
  fi
  printf '{"current":"%s","latest":"%s","behind":%s,"checked":"%s","source":"%s"}\n' \
    "$current" "$latest" "$behind" "$today" "$src"
}

# --- cache -------------------------------------------------------------------
if [ "$FORCE" != "--force" ] && [ -f "$CACHE" ]; then
  cached_at=$(sed -n 1p "$CACHE" 2>/dev/null)
  cached_ver=$(sed -n 2p "$CACHE" 2>/dev/null)
  if [ -n "${cached_at:-}" ] && [ -n "${cached_ver:-}" ]; then
    age=$(( ( $(date -u +%s) - cached_at ) / 3600 ))
    if [ "$age" -lt "$TTL_HOURS" ]; then emit "$cached_ver" cache; exit 0; fi
  fi
fi

# --- ask, quietly ------------------------------------------------------------
latest=""
if command -v gh >/dev/null 2>&1; then
  latest=$(gh api "repos/$REPO/releases/latest" -q '.tag_name' 2>/dev/null | sed 's/^v//')
fi
if [ -z "$latest" ] && command -v curl >/dev/null 2>&1; then
  latest=$(curl -fsS -m 3 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
           | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//')
fi

# gh and curl both print an error body to stdout on 404/rate-limit, so an unvalidated
# capture becomes the "latest version" — malformed JSON downstream, and every user told they
# are behind. Only a thing shaped like a version counts.
case "$latest" in
  [0-9]*.[0-9]*) : ;;
  *) latest="" ;;
esac

if [ -z "$latest" ]; then emit unknown none; exit 0; fi

mkdir -p "$CACHE_DIR" 2>/dev/null && printf '%s\n%s\n' "$(date -u +%s)" "$latest" > "$CACHE" 2>/dev/null
emit "$latest" api
