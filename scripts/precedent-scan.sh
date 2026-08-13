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

if [ "${1:-}" = "--backfill" ]; then
  hdr "CHURN (where the action is)"
  git log --format= --name-only | grep -v '^$' | sort | uniq -c | sort -rn | head -50

  hdr "SCARS (reverts, hotfixes, rollbacks — highest signal per token in the repo)"
  git log --grep='revert\|rollback\|hotfix\|urgent\|prod issue\|incident\|postmortem' \
          -i --oneline --no-merges | head -60

  hdr "AUTHORSHIP (who to believe on which subsystem)"
  git shortlog -sn --no-merges | head -20

  hdr "REWRITES (3+ modifications = an unresolved design problem)"
  git log --format= --name-only | grep -v '^$' | sort | uniq -c | sort -rn |
    awk '$1>=3 {print}' | head -30

  hdr "CO-CHANGE COUPLING (files that always change together = an implicit contract)"
  git log --format='%H' --no-merges | head -400 | while read -r c; do
    git show --format= --name-only "$c" | grep -v '^$' | sort | paste -sd, -
  done | sort | uniq -c | sort -rn | awk '$1>=3' | head -25

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
