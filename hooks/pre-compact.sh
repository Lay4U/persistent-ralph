#!/bin/bash

# Persistent Ralph - PreCompact Hook
# Saves state before auto-compact to ensure seamless resume
# Runs before context compaction (manual or auto)

set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Check if ralph-loop is active
RALPH_STATE_FILE=".claude/ralph-loop.local.md"

if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Get trigger type (manual or auto)
TRIGGER=$(echo "$HOOK_INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null || echo "unknown")

# Parse markdown frontmatter
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//' || echo "false")

if [[ "$ACTIVE" != "true" ]]; then
  exit 0
fi

# Extract current state
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//' || echo "0")
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//' || echo "0")
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/' || echo "")
STARTED_AT=$(echo "$FRONTMATTER" | grep '^started_at:' | sed 's/started_at: *//' || echo "")

# Record compact event in state file
COMPACT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Add or update last_compact field
if grep -q '^last_compact:' "$RALPH_STATE_FILE"; then
  sed -i "s/^last_compact: .*/last_compact: $COMPACT_TIME/" "$RALPH_STATE_FILE"
else
  # Add before the closing --- of frontmatter
  sed -i "/^---$/,/^---$/ { /^---$/ { n; /^---$/ i\\
last_compact: $COMPACT_TIME
}}" "$RALPH_STATE_FILE"
fi

# Add or update compact_count
COMPACT_COUNT=$(echo "$FRONTMATTER" | grep '^compact_count:' | sed 's/compact_count: *//' || echo "0")
if [[ ! "$COMPACT_COUNT" =~ ^[0-9]+$ ]]; then
  COMPACT_COUNT=0
fi
NEW_COMPACT_COUNT=$((COMPACT_COUNT + 1))

if grep -q '^compact_count:' "$RALPH_STATE_FILE"; then
  sed -i "s/^compact_count: .*/compact_count: $NEW_COMPACT_COUNT/" "$RALPH_STATE_FILE"
else
  sed -i "/^---$/,/^---$/ { /^---$/ { n; /^---$/ i\\
compact_count: $NEW_COMPACT_COUNT
}}" "$RALPH_STATE_FILE"
fi

# Create/update experiments.md with current progress summary
EXPERIMENTS_FILE="experiments.md"

# Get recent git commits for context preservation
RECENT_COMMITS=""
if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null; then
  RECENT_COMMITS=$(git log --oneline -10 2>/dev/null || echo "No git history")
fi

# Build progress snapshot
SNAPSHOT="
## Compact Event: $COMPACT_TIME

**Trigger:** $TRIGGER
**Iteration:** $ITERATION / $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo 'unlimited'; fi)
**Compact Count:** $NEW_COMPACT_COUNT

### Recent Git Commits
\`\`\`
$RECENT_COMMITS
\`\`\`

---
"

# Append to experiments.md
if [[ -f "$EXPERIMENTS_FILE" ]]; then
  # Prepend to existing file
  EXISTING=$(cat "$EXPERIMENTS_FILE")
  echo -e "$SNAPSHOT\n$EXISTING" > "$EXPERIMENTS_FILE"
else
  # Create new file
  cat > "$EXPERIMENTS_FILE" << EOF
# Ralph Loop Experiments Log

This file tracks the progress of Ralph loop iterations across context compactions.

---
$SNAPSHOT
EOF
fi

# Output message for logging
echo "PreCompact: Saved state for iteration $ITERATION, compact #$NEW_COMPACT_COUNT ($TRIGGER)"

exit 0
