#!/bin/bash

# Persistent Ralph - Prompt Replace Hook (Full Context)
# Replaces empty/simple prompts with FULL task context
# Same as auto-resume - provides complete context restoration

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

# Read full state file content
STATE_FILE_CONTENT=$(cat "$RALPH_STATE_FILE" 2>/dev/null || echo "(failed to read state file)")

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
CB_STATUS="OK"
if [[ -f ".claude/circuit-breaker.json" ]]; then
    CB_NO_PROGRESS=$(jq -r '.consecutive_no_progress // 0' .claude/circuit-breaker.json 2>/dev/null || echo "0")
    CB_STATUS="no-progress: $CB_NO_PROGRESS/5"
fi

# Get recent git commits
RECENT_COMMITS=""
if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null; then
    RECENT_COMMITS=$(git log --oneline -10 2>/dev/null || echo "")
fi

# =============================================================================
# Read all important files for FULL context restoration
# =============================================================================

# 1. PROMPT.md - Ralph behavior instructions (static)
PROMPT_CONTENT=""
if [[ -f "PROMPT.md" ]]; then
    PROMPT_CONTENT=$(cat "PROMPT.md" 2>/dev/null || echo "")
elif [[ -f "@PROMPT.md" ]]; then
    PROMPT_CONTENT=$(cat "@PROMPT.md" 2>/dev/null || echo "")
fi

# 2. AGENT.md - Build instructions (static)
AGENT_CONTENT=""
if [[ -f "AGENT.md" ]]; then
    AGENT_CONTENT=$(cat "AGENT.md" 2>/dev/null || echo "")
elif [[ -f "@AGENT.md" ]]; then
    AGENT_CONTENT=$(cat "@AGENT.md" 2>/dev/null || echo "")
fi

# 3. fix_plan.md - TODO list (dynamic)
FIX_PLAN_CONTENT=""
if [[ -f "fix_plan.md" ]]; then
    FIX_PLAN_CONTENT=$(cat "fix_plan.md" 2>/dev/null || echo "")
elif [[ -f "@fix_plan.md" ]]; then
    FIX_PLAN_CONTENT=$(cat "@fix_plan.md" 2>/dev/null || echo "")
fi

# 4. experiments.md - Progress log (dynamic, recent only)
EXPERIMENTS_CONTENT=""
if [[ -f "experiments.md" ]]; then
    EXPERIMENTS_CONTENT=$(tail -100 "experiments.md" 2>/dev/null || echo "")
fi

# =============================================================================
# Build replacement prompt with FULL context
# =============================================================================

REPLACEMENT_PROMPT="
################################################################################
#   RALPH LOOP RESUME - Iteration $ITER_INFO | Compacts: $COMPACT_COUNT        #
################################################################################

## STATUS
- Completion: $PROMISE_INFO
- Circuit Breaker: $CB_STATUS

================================================================================
## 1. STATE FILE (.claude/ralph-loop.local.md)
================================================================================
$STATE_FILE_CONTENT

================================================================================
## 2. RECENT GIT COMMITS
================================================================================
$RECENT_COMMITS
"

# Add PROMPT.md (Ralph behavior)
if [[ -n "$PROMPT_CONTENT" ]]; then
    REPLACEMENT_PROMPT="$REPLACEMENT_PROMPT
================================================================================
## 3. PROMPT.md (Ralph Behavior Instructions)
================================================================================
$PROMPT_CONTENT
"
fi

# Add AGENT.md (Build instructions)
if [[ -n "$AGENT_CONTENT" ]]; then
    REPLACEMENT_PROMPT="$REPLACEMENT_PROMPT
================================================================================
## 4. AGENT.md (Build & Quality Standards)
================================================================================
$AGENT_CONTENT
"
fi

# Add fix_plan.md (TODO list)
if [[ -n "$FIX_PLAN_CONTENT" ]]; then
    REPLACEMENT_PROMPT="$REPLACEMENT_PROMPT
================================================================================
## 5. fix_plan.md (Current TODO List)
================================================================================
$FIX_PLAN_CONTENT
"
fi

# Add experiments.md (Progress log)
if [[ -n "$EXPERIMENTS_CONTENT" ]]; then
    REPLACEMENT_PROMPT="$REPLACEMENT_PROMPT
================================================================================
## 6. experiments.md (Recent Progress Log)
================================================================================
$EXPERIMENTS_CONTENT
"
fi

REPLACEMENT_PROMPT="$REPLACEMENT_PROMPT
################################################################################
## MANDATORY INSTRUCTIONS
################################################################################

1. You are RALPH - an autonomous AI development agent
2. READ the STATE FILE above - it contains your TASK
3. FOLLOW PROMPT.md for behavior guidelines
4. CHECK fix_plan.md for current priorities
5. REVIEW experiments.md for previous learnings
6. USE AGENT.md for build/test commands
7. CONTINUE working immediately - DO NOT wait for user input
8. RECORD progress in experiments.md
9. COMMIT changes with descriptive messages

## RALPH'S LAWS
- Never stop until goal is achieved
- Failure is a learning opportunity
- Don't obsess over what doesn't work, move on
- Iterative improvement beats perfect first attempt
- There's always another way

To cancel: /cancel-ralph

################################################################################
BEGIN WORKING NOW. DO NOT ASK FOR CONFIRMATION.
################################################################################"

# Log the prompt replace
log_to_file "PROMPT" "Replaced prompt for iteration $ITERATION | Full context restored"

# Output JSON to replace the prompt
jq -n --arg prompt "$REPLACEMENT_PROMPT" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","modifiedPrompt":$prompt}}'

exit 0
