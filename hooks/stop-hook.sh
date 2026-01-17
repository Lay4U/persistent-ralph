#!/bin/bash

# Persistent Ralph - Stop Hook (Enhanced with Circuit Breaker & Response Analyzer)
# Intercepts session stop, analyzes response, and blocks if Ralph loop is active
# Includes stagnation detection, rate limiting, session management, and status generation

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/circuit-breaker.sh"
source "$SCRIPT_DIR/lib/response-analyzer.sh"
source "$SCRIPT_DIR/lib/rate-limiter.sh"
source "$SCRIPT_DIR/lib/session-manager.sh"
source "$SCRIPT_DIR/lib/status-generator.sh"

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
[[ ! "$ITERATION" =~ ^[0-9]+$ ]] && ITERATION=0
[[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] && MAX_ITERATIONS=0

# Check if max iterations reached
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
    rm "$RALPH_STATE_FILE" 2>/dev/null || true
    log_to_file "STOP" "Max iterations reached ($ITERATION). Loop ended."
    echo '{"decision": null}'
    exit 0
fi

# Get transcript from hook input for analysis
TRANSCRIPT=$(echo "$HOOK_INPUT" | jq -r '.transcript // ""' 2>/dev/null || echo "")

# Check if completion promise was fulfilled
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
    if echo "$TRANSCRIPT" | grep -q "<promise>$COMPLETION_PROMISE</promise>"; then
        rm "$RALPH_STATE_FILE" 2>/dev/null || true
        reset_circuit_breaker "Completion promise fulfilled"
        log_to_file "STOP" "Completion promise '$COMPLETION_PROMISE' detected. Loop ended."
        echo '{"decision": null}'
        exit 0
    fi
fi

# Analyze response
NEW_ITERATION=$((ITERATION + 1))
ANALYSIS_RESULT=$(analyze_response "$TRANSCRIPT" "$NEW_ITERATION")
IFS='|' read -r EXIT_SIGNAL HAS_PROGRESS FILES_MODIFIED ERROR_COUNT IS_STUCK <<< "$ANALYSIS_RESULT"

# Update exit signals tracking
update_exit_signals

# Check for graceful exit conditions
EXIT_REASON=$(should_exit_gracefully)
if [[ -n "$EXIT_REASON" ]]; then
    rm "$RALPH_STATE_FILE" 2>/dev/null || true
    reset_circuit_breaker "Graceful exit: $EXIT_REASON"
    log_to_file "STOP" "Graceful exit: $EXIT_REASON"
    echo '{"decision": null}'
    exit 0
fi

# Update circuit breaker with this loop's result
HAS_ERRORS="false"
[[ $ERROR_COUNT -gt 0 ]] && HAS_ERRORS="true"

if record_loop_result "$NEW_ITERATION" "$FILES_MODIFIED" "$HAS_ERRORS"; then
    # Circuit breaker opened - halt execution
    CB_STATUS=$(get_circuit_status_message)
    log_to_file "STOP" "Circuit breaker opened. Halting loop."

    # Allow stop but provide context about why
    REASON="
================================================================================
CIRCUIT BREAKER OPENED - Loop Halted
================================================================================

$CB_STATUS

The Ralph loop has been automatically stopped because no progress was detected
over multiple iterations.

Possible causes:
- Task may be complete
- Claude may be stuck on an error
- The prompt may need clarification

To resume:
1. Review experiments.md for progress
2. Check git log for recent changes
3. Update the task if needed
4. Run: /ralph-loop \"continue task\" to restart

================================================================================
"
    rm "$RALPH_STATE_FILE" 2>/dev/null || true
    jq -n --arg reason "$REASON" '{"decision": null, "reason": $reason}'
    exit 0
fi

# Update iteration in state file
sed -i "s/^iteration: *[0-9]*/iteration: $NEW_ITERATION/" "$RALPH_STATE_FILE"

# Extract the original prompt for context
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

# Build iteration info
if [[ $MAX_ITERATIONS -gt 0 ]]; then
    ITERATION_INFO="Iteration $NEW_ITERATION / $MAX_ITERATIONS"
else
    ITERATION_INFO="Iteration $NEW_ITERATION (unlimited)"
fi

# Build completion info
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
    PROMISE_INFO="Complete when: <promise>$COMPLETION_PROMISE</promise>"
else
    PROMISE_INFO="No completion condition set"
fi

# Get circuit breaker and analysis status
CB_STATUS=$(get_circuit_status_message)
ANALYSIS_SUMMARY=$(get_analysis_summary)

# Build the continuation reason
REASON="
================================================================================
RALPH LOOP - CONTINUING
================================================================================
$ITERATION_INFO
$PROMISE_INFO

CIRCUIT BREAKER: $CB_STATUS
ANALYSIS: $ANALYSIS_SUMMARY
--------------------------------------------------------------------------------

TASK:
$PROMPT_TEXT

--------------------------------------------------------------------------------
MANDATORY ACTIONS:
1. Check git log --oneline -5 for recent progress
2. Review experiments.md if exists
3. Continue the task immediately
4. Record progress in experiments.md
5. DO NOT ask for user confirmation

RALPH'S LAWS:
- Never stop until goal is achieved
- Failure is a learning opportunity
- Don't obsess over what doesn't work, move on
- Iterative improvement beats perfect first attempt
- There's always another way

To cancel: /cancel-ralph or /ralph-loop:cancel-ralph
================================================================================
"

# Update session activity
update_session_activity

# Increment call counter for rate limiting
increment_call_counter > /dev/null

# Check rate limit
if ! can_make_call; then
    RATE_STATUS=$(get_rate_limit_status)
    log_to_file "STOP" "Rate limit reached. $RATE_STATUS"
    generate_status "$NEW_ITERATION" "0" "rate_limit" "paused" "Rate limit reached"

    RATE_REASON="
================================================================================
RATE LIMIT REACHED - Loop Paused
================================================================================

$RATE_STATUS

The Ralph loop has been temporarily paused due to rate limiting.
It will automatically resume when the limit resets (next hour).

To check status: cat status.json
To cancel: /cancel-ralph

================================================================================
"
    jq -n --arg reason "$RATE_REASON" '{"decision": null, "reason": $reason}'
    exit 0
fi

# Check session validity
if ! is_session_valid; then
    log_to_file "STOP" "Session expired"
    generate_status "$NEW_ITERATION" "0" "session_expired" "ended" "Session expired"
    rm "$RALPH_STATE_FILE" 2>/dev/null || true
    echo '{"decision": null}'
    exit 0
fi

# Generate status for monitoring
generate_status "$NEW_ITERATION" "$(json_get '.claude/call-count.json' '.calls_this_hour' '0')" "continuing" "running"

# Log the continuation
log_to_file "STOP" "Continuing loop. $ITERATION_INFO | Files: $FILES_MODIFIED | Errors: $ERROR_COUNT"

# Return JSON to block the stop
jq -n --arg reason "$REASON" '{"decision": "block", "reason": $reason}'

exit 0
