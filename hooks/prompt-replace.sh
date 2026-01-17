#!/bin/bash

# Persistent Ralph - Prompt Replace Hook (Enhanced)
# Replaces empty/simple prompts with full task context
# Includes circuit breaker and analysis status

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/lib/utils.sh"

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Check if ralph-loop is active
RALPH_STATE_FILE=".claude/ralph-loop.local.md"

if [[ ! -f "$RALPH_STATE_FILE" ]]; then
    exit 0
fi

# Parse markdown frontmatter
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//' || echo "false")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//' || echo "0")
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//' || echo "0")
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/' || echo "")
COMPACT_COUNT=$(echo "$FRONTMATTER" | grep '^compact_count:' | sed 's/compact_count: *//' || echo "0")

# Validate active state
if [[ "$ACTIVE" != "true" ]]; then
    exit 0
fi

# Validate numeric fields
[[ ! "$ITERATION" =~ ^[0-9]+$ ]] && ITERATION=0
[[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] && MAX_ITERATIONS=0
[[ ! "$COMPACT_COUNT" =~ ^[0-9]+$ ]] && COMPACT_COUNT=0

# Check if max iterations reached
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
    rm "$RALPH_STATE_FILE" 2>/dev/null || true
    exit 0
fi

# Extract prompt
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
    exit 0
fi

# Build iteration info
if [[ $MAX_ITERATIONS -gt 0 ]]; then
    ITER_INFO="$ITERATION / $MAX_ITERATIONS"
else
    ITER_INFO="$ITERATION (unlimited)"
fi

# Build completion info
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
    PROMISE_INFO="<promise>$COMPLETION_PROMISE</promise>"
else
    PROMISE_INFO="(no completion condition)"
fi

# Get circuit breaker status
CB_STATUS=""
if [[ -f ".claude/circuit-breaker.json" ]]; then
    CB_STATE=$(jq -r '.state // "UNKNOWN"' .claude/circuit-breaker.json 2>/dev/null || echo "UNKNOWN")
    CB_NO_PROGRESS=$(jq -r '.consecutive_no_progress // 0' .claude/circuit-breaker.json 2>/dev/null || echo "0")
    CB_STATUS="Circuit: $CB_STATE (no-progress: $CB_NO_PROGRESS)"
fi

# Get recent git commits
RECENT_COMMITS=""
if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null; then
    RECENT_COMMITS=$(git log --oneline -5 2>/dev/null || echo "")
fi

# Build the replacement prompt
REPLACEMENT_PROMPT="
================================================================================
RALPH LOOP RESUME - Iteration $ITER_INFO | Compacts: $COMPACT_COUNT
================================================================================

TASK:
$PROMPT_TEXT

COMPLETION: $PROMISE_INFO
$CB_STATUS

RECENT PROGRESS:
$RECENT_COMMITS

================================================================================
INSTRUCTIONS:
1. Review git log for recent progress
2. Check experiments.md if exists
3. Continue working immediately
4. Record progress in experiments.md
5. DO NOT ask for confirmation
6. DO NOT stop until completion promise is met

RALPH'S LAWS: Never stop. Failure is learning. Always find another way.
================================================================================
"

# Log the prompt replace
log_to_file "PROMPT" "Replaced empty prompt for iteration $ITERATION"

# Output JSON to replace the prompt
jq -n --arg prompt "$REPLACEMENT_PROMPT" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","modifiedPrompt":$prompt}}'

exit 0
