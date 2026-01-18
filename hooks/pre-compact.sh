#!/bin/bash

# Persistent Ralph - PreCompact Hook
# Saves state before auto-compact to ensure seamless resume
# Records progress snapshot in experiments.md

set -euo pipefail

# Get script directory (use SCRIPT_DIR env var if set, otherwise detect)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
fi
source "$SCRIPT_DIR/lib/utils.sh"

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
COMPACT_COUNT=$(echo "$FRONTMATTER" | grep '^compact_count:' | sed 's/compact_count: *//' || echo "0")

# Ensure numeric
[[ ! "$ITERATION" =~ ^[0-9]+$ ]] && ITERATION=0
[[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] && MAX_ITERATIONS=0
[[ ! "$COMPACT_COUNT" =~ ^[0-9]+$ ]] && COMPACT_COUNT=0

# Increment compact count
NEW_COMPACT_COUNT=$((COMPACT_COUNT + 1))
COMPACT_TIME=$(get_iso_timestamp)

# Update state file
if grep -q '^last_compact:' "$RALPH_STATE_FILE"; then
    sed -i "s/^last_compact: .*/last_compact: $COMPACT_TIME/" "$RALPH_STATE_FILE"
else
    sed -i "/^active:/a last_compact: $COMPACT_TIME" "$RALPH_STATE_FILE"
fi

if grep -q '^compact_count:' "$RALPH_STATE_FILE"; then
    sed -i "s/^compact_count: .*/compact_count: $NEW_COMPACT_COUNT/" "$RALPH_STATE_FILE"
else
    sed -i "/^active:/a compact_count: $NEW_COMPACT_COUNT" "$RALPH_STATE_FILE"
fi

# Get recent git commits
RECENT_COMMITS=""
if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null; then
    RECENT_COMMITS=$(git log --oneline -10 2>/dev/null || echo "No git history")
fi

# Get circuit breaker status if available
CB_STATUS=""
if [[ -f ".claude/circuit-breaker.json" ]]; then
    CB_STATE=$(jq -r '.state // "UNKNOWN"' .claude/circuit-breaker.json 2>/dev/null || echo "UNKNOWN")
    CB_REASON=$(jq -r '.reason // ""' .claude/circuit-breaker.json 2>/dev/null || echo "")
    CB_STATUS="Circuit Breaker: $CB_STATE"
    [[ -n "$CB_REASON" ]] && CB_STATUS="$CB_STATUS ($CB_REASON)"
fi

# Get analysis summary if available
ANALYSIS_SUMMARY=""
if [[ -f ".claude/response-analysis.json" ]]; then
    CONFIDENCE=$(jq -r '.analysis.confidence_score // 0' .claude/response-analysis.json 2>/dev/null || echo "0")
    FILES=$(jq -r '.analysis.files_modified // 0' .claude/response-analysis.json 2>/dev/null || echo "0")
    ANALYSIS_SUMMARY="Analysis: Confidence $CONFIDENCE%, Files modified: $FILES"
fi

# Build progress snapshot
SNAPSHOT="
## Compact Event: $COMPACT_TIME

**Trigger:** $TRIGGER
**Iteration:** $ITERATION / $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo 'unlimited'; fi)
**Compact Count:** $NEW_COMPACT_COUNT
$CB_STATUS
$ANALYSIS_SUMMARY

### Recent Git Commits
\`\`\`
$RECENT_COMMITS
\`\`\`

---
"

# Write to experiments.md
EXPERIMENTS_FILE="experiments.md"

if [[ -f "$EXPERIMENTS_FILE" ]]; then
    # Prepend to existing file
    EXISTING=$(cat "$EXPERIMENTS_FILE")
    echo -e "$SNAPSHOT\n$EXISTING" > "$EXPERIMENTS_FILE"
else
    # Create new file
    cat > "$EXPERIMENTS_FILE" << EOF
# Ralph Loop Experiments Log

This file tracks progress across context compactions.
It serves as persistent memory for the Ralph loop.

---
$SNAPSHOT
EOF
fi

# Log the compact event
log_to_file "COMPACT" "Trigger: $TRIGGER | Iteration: $ITERATION | Compact #$NEW_COMPACT_COUNT"

exit 0
