#!/usr/bin/env bash
# Deterministic precedent mining. No model runs here.
#
# This is the cheap ranking pass that decides what the agent is *allowed to spend
# context reading*. Git already knows which files churn, which commits were reverts,
# and which files always change together. Paying a model to rediscover that by
# reading the tree is the most common way an agent run gets expensive and vague at
# the same time.
#
#   precedent-scan.sh "auth token refresh" src/auth   # per-ticket (ship S0)
#   precedent-scan.sh --backfill                      # whole-history (setup)

set -uo pipefail

command -v git >/dev/null 2>&1 || { echo "precedent-scan: git is required" >&2; exit 2; }
root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "precedent-scan: not inside a git repository" >&2; exit 2; }
cd "$root" || exit 2

hdr() { printf '\n=== %s ===\n' "$1"; }

# Source directories differ per ecosystem; guessing 'src lib app' silently finds
# nothing in a Go, Rust, Python or Java repo — which reads identically to "this
# repo has no precedent", the single most misleading answer this script can give.
srcdirs() {
  local d found=()
  for d in src lib app pkg internal cmd core services packages apps modules \
           source lib.rs main java main/java; do
    [ -d "$d" ] && found+=("$d")
  done
  if [ "${#found[@]}" -eq 0 ]; then
    # Fall back to every top-level directory that is not obviously not-source.
    while IFS= read -r d; do found+=("$d"); done < <(
      find . -maxdepth 1 -type d ! -name '.*' ! -name node_modules ! -name vendor \
             ! -name dist ! -name build ! -name target ! -name docs ! -name test \
             ! -name tests 2>/dev/null | sed 's|^\./||')
  fi
  printf '%s\n' "${found[@]+"${found[@]}"}"
}

# Files that change on nearly every commit and mean nothing: lockfiles, generated
# code, vendored trees. Left in, they take the top of every ranking and push the
# actual signal off the end of `head`. On a real repo the top co-change pair was
# `go.mod,go.sum` — true, and worth precisely nothing.
NOISE='(^|/)(go\.sum|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|poetry\.lock|Gemfile\.lock|composer\.lock|\.terraform\.lock\.hcl)$'
NOISE="$NOISE"'|\.(pb|gen|generated)\.go$|_generated\.[a-z]+$|\.snap$|\.min\.(js|css)$'
NOISE="$NOISE"'|(^|/)(vendor|node_modules|dist|build|target|\.next)/'

if [ "${1:-}" = "--backfill" ]; then
  hdr "CHURN (where the action is)"
  git log --format= --name-only | grep -v '^$' | grep -Ev "$NOISE" |
    sort | uniq -c | sort -rn | head -50

  # --first-parent is what makes this section worth reading. Without it you get
  # every "to be reverted" and "revert unwanted changes" from inside somebody's
  # PR branch — work-in-progress noise that never reached anyone. With it you get
  # only what actually landed on the mainline, which is the definition of a scar.
  hdr "SCARS — reverts that landed on the mainline (highest signal per token)"
  git log --first-parent --grep='^Revert' --oneline | head -20

  hdr "SCARS — hotfixes, rollbacks and incidents on the mainline"
  git log --first-parent --no-merges -i \
          --grep='rollback\|hotfix\|urgent fix\|prod issue\|incident\|postmortem\|regression' \
          --oneline | head -40

  hdr "AUTHORSHIP (who to believe on which subsystem)"
  git shortlog -sn --no-merges | head -20

  hdr "REWRITES (3+ modifications = an unresolved design problem)"
  git log --format= --name-only | grep -v '^$' | grep -Ev "$NOISE" |
    sort | uniq -c | sort -rn | awk '$1>=3 {print}' | head -30

  hdr "CO-CHANGE COUPLING (files that always change together = an implicit contract)"
  # One `git log` pass rather than 400 `git show` forks. git already emits
  # --name-only paths in sorted order, so no per-commit sort is needed either.
  # Commits touching more than 8 files are dropped: a 40-file tuple never repeats,
  # so it can only add noise.
  git log --no-merges --format='%x01%H' --name-only -n 600 2>/dev/null |
    grep -Ev "$NOISE" |
    awk '
      /^\001/ { if (n >= 2 && n <= 8) print k; k = ""; n = 0; next }
      NF      { k = (k == "" ? $0 : k "," $0); n++ }
      END     { if (n >= 2 && n <= 8) print k }
    ' | sort | uniq -c | sort -rn | awk '$1>=3' | head -25

  hdr "AGE (how much of this history is still true)"
  echo "first commit: $(git log --reverse --format=%as | head -1)"
  echo "last commit:  $(git log -1 --format=%as)"
  echo "commits:      $(git rev-list --count HEAD)"
  exit 0
fi

TERMS="${1:?usage: precedent-scan.sh \"<terms>\" [paths...]}"
shift || true
PATHS=("$@")
RX=$(printf '%s' "$TERMS" | tr ' ' '|')

hdr "DOCS / ADRs / RFCs matching: $TERMS"
grep -rilE "$RX" docs 2>/dev/null | grep -E 'adr|rfc|design|plan|decision' | head -20

hdr "MEMORY + CONVENTIONS matching: $TERMS"
grep -rinE "$RX" docs/memory docs/conventions.md 2>/dev/null | head -20

hdr "CODE precedent (closest existing implementations)"
# shellcheck disable=SC2046
grep -rilE "$RX" $(srcdirs | tr '\n' ' ') 2>/dev/null | head -20

hdr "MERGED PRs (read the review discussion, not just the diff)"
if command -v gh >/dev/null 2>&1; then
  gh pr list --search "$TERMS" --state merged -L 10 2>/dev/null || echo "(gh query failed)"
else
  echo "(gh not installed — merged-PR precedent unavailable)"
fi

if [ "${#PATHS[@]}" -gt 0 ]; then
  hdr "SCARS on the paths being touched"
  git log --grep='revert\|hotfix\|rollback' -i --oneline -- "${PATHS[@]}" | head -20
  hdr "RECENT HISTORY on those paths"
  git log --oneline -30 -- "${PATHS[@]}"
  hdr "WHO OWNS these paths"
  git shortlog -sn --no-merges -- "${PATHS[@]}" | head -5
fi

hdr "REUSE INVENTORY (check before writing anything new)"
for d in src/lib src/utils src/shared src/common lib utils pkg internal/util shared common; do
  [ -d "$d" ] && { echo "-- $d"; ls -1 "$d" | head -25; }
done
[ -f package.json ] && command -v jq >/dev/null 2>&1 && {
  echo "-- npm dependencies"
  jq -r '[(.dependencies//{}),(.devDependencies//{})] | add | keys | join(" ")' package.json 2>/dev/null; }
[ -f go.mod ] && { echo "-- go modules"; grep -E '^\s+[a-z]' go.mod | awk '{print $1}' | head -40; }
[ -f Cargo.toml ] && { echo "-- cargo deps"; sed -n '/^\[dependencies\]/,/^\[/p' Cargo.toml | head -40; }
[ -f pyproject.toml ] && { echo "-- python deps"; grep -E '^\s*"?[a-zA-Z0-9_-]+"?\s*[=>~]' pyproject.toml | head -40; }
[ -f pom.xml ] && { echo "-- maven artifacts"; grep -o '<artifactId>[^<]*' pom.xml | sed 's/<artifactId>//' | sort -u | head -40; }
exit 0
