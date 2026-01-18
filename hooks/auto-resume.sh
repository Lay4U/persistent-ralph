#!/bin/bash

# Persistent Ralph - Auto-resume Hook (Enhanced)
# Triggers on ANY session start (including new sessions, compact, resume)
# Injects strong context with circuit breaker and analysis status

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
STARTED_AT=$(echo "$FRONTMATTER" | grep '^started_at:' | sed 's/started_at: *//' || echo "unknown")

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

# Get source from hook input
SOURCE=$(echo "$HOOK_INPUT" | jq -r '.source // "new_session"' 2>/dev/null || echo "new_session")

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
    PROMISE_INFO="No completion condition (runs until cancelled)"
fi

# Get circuit breaker status
CB_STATUS="Not initialized"
if [[ -f ".claude/circuit-breaker.json" ]]; then
    CB_STATE=$(jq -r '.state // "UNKNOWN"' .claude/circuit-breaker.json 2>/dev/null || echo "UNKNOWN")
    CB_REASON=$(jq -r '.reason // ""' .claude/circuit-breaker.json 2>/dev/null || echo "")
    CB_NO_PROGRESS=$(jq -r '.consecutive_no_progress // 0' .claude/circuit-breaker.json 2>/dev/null || echo "0")
    CB_STATUS="$CB_STATE | No progress: $CB_NO_PROGRESS"
    [[ -n "$CB_REASON" ]] && CB_STATUS="$CB_STATUS | $CB_REASON"
fi

# Get analysis summary
ANALYSIS_SUMMARY="No previous analysis"
if [[ -f ".claude/response-analysis.json" ]]; then
    LOOP=$(jq -r '.loop_number // 0' .claude/response-analysis.json 2>/dev/null || echo "0")
    CONFIDENCE=$(jq -r '.analysis.confidence_score // 0' .claude/response-analysis.json 2>/dev/null || echo "0")
    FILES=$(jq -r '.analysis.files_modified // 0' .claude/response-analysis.json 2>/dev/null || echo "0")
    SUMMARY=$(jq -r '.analysis.work_summary // ""' .claude/response-analysis.json 2>/dev/null || echo "")
    ANALYSIS_SUMMARY="Loop $LOOP | Confidence: $CONFIDENCE% | Files: $FILES"
    [[ -n "$SUMMARY" ]] && ANALYSIS_SUMMARY="$ANALYSIS_SUMMARY | $SUMMARY"
fi

# Get recent git commits
RECENT_COMMITS=""
if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null; then
    RECENT_COMMITS=$(git log --oneline -10 2>/dev/null || echo "No git history")
fi

# Get experiments.md summary if exists
EXPERIMENTS_SUMMARY=""
if [[ -f "experiments.md" ]]; then
    EXPERIMENTS_SUMMARY=$(head -50 experiments.md 2>/dev/null || echo "")
fi

# Build context message
CONTEXT_MSG="
################################################################################
#                                                                              #
#   PERSISTENT RALPH LOOP - AUTOMATIC RESUME                                   #
#   Source: $SOURCE | Compacts: $COMPACT_COUNT | Started: $STARTED_AT         #
#                                                                              #
################################################################################

## STATUS
- Iteration: $ITER_INFO
- Completion: $PROMISE_INFO
- Circuit Breaker: $CB_STATUS
- Last Analysis: $ANALYSIS_SUMMARY

## TASK
\`\`\`
$PROMPT_TEXT
\`\`\`

## RECENT PROGRESS (git log)
\`\`\`
$RECENT_COMMITS
\`\`\`
"

if [[ -n "$EXPERIMENTS_SUMMARY" ]]; then
    CONTEXT_MSG="$CONTEXT_MSG
## EXPERIMENTS LOG (recent)
\`\`\`
$EXPERIMENTS_SUMMARY
\`\`\`
"
fi

CONTEXT_MSG="$CONTEXT_MSG
################################################################################
#                                                                              #
#   MANDATORY INSTRUCTIONS                                                     #
#                                                                              #
#   1. You are in an AUTONOMOUS RALPH LOOP                                     #
#   2. Review git log and experiments.md for previous progress                 #
#   3. CONTINUE the task immediately - DO NOT wait for user input              #
#   4. Record significant progress in experiments.md                           #
#   5. DO NOT stop until the completion promise is met                         #
#   6. If blocked, try alternative approaches                                  #
#                                                                              #
#   CIRCUIT BREAKER:                                                           #
#   - Progress is tracked automatically                                        #
#   - Loop will halt if no progress after 5 iterations                         #
#   - Make file changes to show progress                                       #
#                                                                              #
#   RALPH'S LAWS:                                                              #
#   - Never stop until goal is achieved                                        #
#   - Failure is a learning opportunity                                        #
#   - Don't obsess over what doesn't work, move on                            #
#   - Iterative improvement beats perfect first attempt                        #
#   - There's always another way                                               #
#                                                                              #
#   To cancel: /cancel-ralph or /ralph-loop:cancel-ralph                       #
#                                                                              #
################################################################################

BEGIN WORKING NOW. DO NOT ASK FOR CONFIRMATION. START IMMEDIATELY.
"

# Log the resume
log_to_file "RESUME" "Source: $SOURCE | Iteration: $ITERATION | Compacts: $COMPACT_COUNT"

# Output JSON with additionalContext
jq -n --arg context "$CONTEXT_MSG" '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$context}}'

exit 0
