#!/bin/bash
# sync-claude-central.sh — sync this Mac's Claude desktop-app sessions with the
# central NAS store.
#
#   ./sync-claude-central.sh          # push: copy local sessions -> NAS (default)
#   ./sync-claude-central.sh pull     # pull: copy NAS sessions -> local
#
# The central store location comes from shared-path.txt next to this script
# (the "mac:" line). Override with:  CLAUDE_CENTRAL=/path ./sync-claude-central.sh
#
# A session = transcript JSONL under .claude/projects + index entry under
# claude-code-sessions. Both are synced; nothing else (no credentials, no
# settings) leaves this machine. Copies are additive and newest-wins (-u):
# nothing is ever deleted from either side.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATHS_FILE="$SCRIPT_DIR/shared-path.txt"

if [ -n "${CLAUDE_CENTRAL:-}" ]; then
    CENTRAL="$CLAUDE_CENTRAL"
else
    if [ ! -f "$PATHS_FILE" ]; then
        cat >&2 <<'EOF'
shared-path.txt not found next to this script — nothing synced.
Create it there with the central store location for each OS, e.g.:

  mac: /Volumes/YourShare/claude-central
  windows: \\yournas\YourShare\claude-central
EOF
        exit 1
    fi
    # take the "mac:" line; tolerate Windows line endings and comments
    CENTRAL="$(tr -d '\r' < "$PATHS_FILE" | sed -n 's/^[[:space:]]*mac:[[:space:]]*//p' | head -1)"
    if [ -z "$CENTRAL" ]; then
        echo "error: no 'mac:' line found in $PATHS_FILE — nothing synced." >&2
        exit 1
    fi
fi

MODE="${1:-push}"

PROJECTS="$HOME/.claude/projects"
SESSIONS="$HOME/Library/Application Support/Claude/claude-code-sessions"

if [ "$MODE" != "push" ] && [ "$MODE" != "pull" ]; then
    echo "usage: $0 [push|pull]" >&2
    exit 2
fi

# Refuse to run if the NAS isn't actually mounted: if the central dir's parent
# is on the same device as local /Volumes, it's a plain local dir and writing
# there would silently fill the boot disk instead of the NAS.
parent="$(dirname "$CENTRAL")"
if [ ! -d "$parent" ] || [ "$(stat -f %d "$parent")" = "$(stat -f %d /Volumes)" ]; then
    echo "error: $parent is not a mounted volume — connect to the NAS first (Finder: Go > Connect to Server > smb://yournas/YourShare)" >&2
    exit 1
fi

mkdir -p "$CENTRAL/projects" "$CENTRAL/claude-code-sessions"

# rsync -v prints each file it copies, but also every directory it traverses
# (lines ending in "/") and its own header/footer lines — filter to just the
# actual files so the output is real progress, and count them.
sync_tree() {
    local label="$1" src="$2" dst="$3"
    echo ""
    echo "==> $label"
    echo "    $src  ->  $dst"
    local files
    files="$(rsync -auv "$src/" "$dst/" \
        | grep -v -e '^$' -e '/$' -e '^\./\{0,1\}$' \
                  -e '^Transfer starting' -e '^sending' -e '^building' \
                  -e '^sent ' -e '^total size' || true)"
    if [ -n "$files" ]; then
        echo "$files" | sed 's/^/    /'
        echo "    -- $(echo "$files" | wc -l | tr -d ' ') file(s) copied"
    else
        echo "    -- up to date, nothing to copy"
    fi
}

if [ "$MODE" = "push" ]; then
    echo "Pushing local sessions -> $CENTRAL"
    sync_tree "transcripts (.claude/projects)" "$PROJECTS" "$CENTRAL/projects"
    sync_tree "session index (claude-code-sessions)" "$SESSIONS" "$CENTRAL/claude-code-sessions"
else
    echo "Pulling $CENTRAL -> local sessions"
    echo "(quit the Claude app first if it's running — it caches the session list)"
    sync_tree "transcripts (.claude/projects)" "$CENTRAL/projects" "$PROJECTS"
    sync_tree "session index (claude-code-sessions)" "$CENTRAL/claude-code-sessions" "$SESSIONS"
fi
echo ""

echo "Done. Central store now has:"
echo "  $(find "$CENTRAL/projects" -name '*.jsonl' | wc -l | tr -d ' ') transcripts, $(find "$CENTRAL/claude-code-sessions" -name 'local_*.json' | wc -l | tr -d ' ') index entries"
