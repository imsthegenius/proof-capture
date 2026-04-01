#!/bin/bash
# Universal brain-sync hook — works in ANY workspace.
# Reads .workspace-map.json to resolve the current project's vault path.
# Drop a symlink or copy into any project's .claude/hooks/ to activate.

BRAIN_DIR="$HOME/Desktop/second-brain"
MAP_FILE="$BRAIN_DIR/.workspace-map.json"
WORKSPACE="$(pwd)"

# Resolve vault path from workspace map
if [ -f "$MAP_FILE" ]; then
    VAULT_PATH=$(python3 -c "
import json, sys
with open('$MAP_FILE') as f:
    m = json.load(f)
# Try exact match, then prefix match (for worktrees/subdirs)
wp = '$WORKSPACE'
path = m.get(wp)
if not path:
    for k, v in sorted(m.items(), key=lambda x: -len(x[0])):
        if wp.startswith(k):
            path = v
            break
print(path or '')
" 2>/dev/null)
else
    VAULT_PATH=""
fi

# If no mapping found, use a generic fallback
if [ -z "$VAULT_PATH" ]; then
    VAULT_PATH="learnings"
fi

# Project-specific counter (hash the workspace path)
HASH=$(echo -n "$WORKSPACE" | md5 2>/dev/null || echo -n "$WORKSPACE" | md5sum 2>/dev/null | cut -d' ' -f1)
COUNTER_FILE="/tmp/.claude-brain-sync-${HASH}"

# Initialize counter if missing
if [ ! -f "$COUNTER_FILE" ]; then
    echo "0" > "$COUNTER_FILE"
fi

# Increment counter
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Only check every 10 tool calls
if [ $((COUNT % 10)) -ne 0 ]; then
    exit 0
fi

# Check if any brain files were modified in the last 10 minutes
RECENT=$(find "$BRAIN_DIR" -name "*.md" -not -path "*/.git/*" -not -path "*/.obsidian/*" -mmin -10 2>/dev/null | wc -l | tr -d ' ')

if [ "$RECENT" = "0" ]; then
    echo "BRAIN SYNC: ~$COUNT tool calls without updating the second brain. Persist progress/decisions/learnings to:"
    echo "  ~/Desktop/second-brain/$VAULT_PATH/"
    echo "Do this BEFORE continuing other work."
fi

exit 0
