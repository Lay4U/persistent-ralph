#!/bin/bash

# Persistent Ralph - Stop Hook
# Intercepts session stop and blocks it if Ralph loop is active
# Returns decision: "block" to prevent session termination

set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Check if ralph-loop is active
RALPH_STATE_FILE=".claude/ralph-loop.local.md"

if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  # No active loop - allow normal stop
  echo '{"decision": null}'
  exit 0
fi

# Check if stop hook is already active (prevent infinite loop)
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  # Stop hook already ran once - allow stop to prevent infinite loop
  echo '{"decision": null}'
  exit 0
fi

# Parse markdown frontmatter
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//' || echo "false")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//' || echo "0")
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//' || echo "0")
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/' || echo "")

# Validate active state
if [[ "$ACTIVE" != "true" ]]; then
  echo '{"decision": null}'
  exit 0
fi

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  ITERATION=0
fi
if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  MAX_ITERATIONS=0
fi

# Check if max iterations reached
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  # Max iterations reached - allow stop and cleanup
  rm "$RALPH_STATE_FILE" 2>/dev/null || true
  echo '{"decision": null}'
  exit 0
fi

# Check if completion promise was fulfilled (look in transcript/output)
TRANSCRIPT=$(echo "$HOOK_INPUT" | jq -r '.transcript // ""' 2>/dev/null || echo "")
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  if echo "$TRANSCRIPT" | grep -q "<promise>$COMPLETION_PROMISE</promise>"; then
    # Completion promise found - allow stop and cleanup
    rm "$RALPH_STATE_FILE" 2>/dev/null || true
    echo '{"decision": null}'
    exit 0
  fi
fi

# Increment iteration counter
NEW_ITERATION=$((ITERATION + 1))

# Update state file with new iteration
sed -i "s/^iteration: *[0-9]*/iteration: $NEW_ITERATION/" "$RALPH_STATE_FILE"

# Extract the original prompt
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

# Build the reason message for continuing
if [[ $MAX_ITERATIONS -gt 0 ]]; then
  ITERATION_INFO="Iteration $NEW_ITERATION / $MAX_ITERATIONS"
else
  ITERATION_INFO="Iteration $NEW_ITERATION (unlimited)"
fi

if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  PROMISE_INFO="Complete when: <promise>$COMPLETION_PROMISE</promise>"
else
  PROMISE_INFO="No completion condition set"
fi

# Build the continuation reason
REASON="
===========================================
RALPH LOOP ACTIVE - DO NOT STOP
===========================================
$ITERATION_INFO
$PROMISE_INFO
-------------------------------------------

CONTINUE WORKING ON:
$PROMPT_TEXT

-------------------------------------------
MANDATORY ACTIONS:
1. Check git log for recent progress: git log --oneline -5
2. Review experiments.md if exists
3. Continue the task immediately
4. DO NOT ask for user confirmation
5. DO NOT stop until completion promise is met

To cancel: /cancel-ralph or /ralph-loop:cancel-ralph
==========================================="

# Return JSON to block the stop
jq -n --arg reason "$REASON" '{"decision": "block", "reason": $reason}'

exit 0
