#!/usr/bin/env bash
# Vendoring fallback: copy the harness into a repo instead of installing the plugin.
#
#   bash install.sh /path/to/your/repo
#
# The plugin is the supported path (see README). Use this when you want the files
# in-tree and reviewable, when you are on a Claude Code build without plugin
# support, or when a repo must work for someone who has installed nothing.
#
# The cost is real: every repo pins a snapshot, and upgrading means re-running this
# everywhere. The plugin updates in one place.

set -euo pipefail

TARGET="${1:?usage: install.sh /path/to/repo}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR=".claude/ship-harness"

[ -d "$TARGET" ] || { echo "install.sh: no such directory: $TARGET" >&2; exit 1; }
git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "install.sh: $TARGET is not a git repository." >&2
  echo "The harness needs git: precedent mining, the plan-commit approval gate and the" >&2
  echo "build worktree all depend on it." >&2
  exit 1; }

mkdir -p "$TARGET/.claude/skills" "$TARGET/.claude/agents" "$TARGET/$VENDOR"
cp -R "$SRC/skills/."      "$TARGET/.claude/skills/"
cp -R "$SRC/agents/."      "$TARGET/.claude/agents/"
cp -R "$SRC/scripts"       "$TARGET/$VENDOR/"
cp -R "$SRC/collectors"    "$TARGET/$VENDOR/"
cp -R "$SRC/templates"     "$TARGET/$VENDOR/"
cp -R "$SRC/hooks"         "$TARGET/$VENDOR/"
cp -R "$SRC/schema"        "$TARGET/$VENDOR/"
chmod +x "$TARGET/$VENDOR/scripts/"*.sh "$TARGET/$VENDOR/collectors/"*.sh \
         "$TARGET/$VENDOR/hooks/"*.sh 2>/dev/null || true

# Skills reference ${CLAUDE_PLUGIN_ROOT}, which only exists for an installed plugin.
# Rewrite it to the vendored location so the same skill text works both ways.
find "$TARGET/.claude/skills" -name '*.md' -type f -exec \
  sed -i.bak "s|\${CLAUDE_PLUGIN_ROOT}|\${CLAUDE_PROJECT_DIR}/$VENDOR|g" {} \;
find "$TARGET/.claude/skills" -name '*.md.bak' -delete

cat <<MSG

Vendored into $TARGET/$VENDOR

One manual step — the hook cannot register itself. Merge this into
$TARGET/.claude/settings.json:

{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\$CLAUDE_PROJECT_DIR/$VENDOR/hooks/phase-guard.sh"
          }
        ]
      }
    ]
  }
}

Without it, "tests are frozen during review" and "baselines cannot be silently
overwritten" become suggestions in a prompt rather than rules — which is the
difference this harness is built on.

Then, in $TARGET:
  1. /ship-harness:ship <TICKET>     sets the repo up on first run, then plans
  2. /ship-harness:review <PR>       review someone else's work
MSG
