#!/bin/bash
# Persistent Ralph - Response Analyzer
# Analyzes Claude output to detect completion signals and progress
# Includes RALPH_STATUS block parsing and dual-condition EXIT_SIGNAL gate

# Source utilities (utils.sh is in the same directory)
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Analysis configuration
ANALYSIS_FILE=".claude/response-analysis.json"
EXIT_SIGNALS_FILE=".claude/exit-signals.json"

# Dual-condition EXIT_SIGNAL gate configuration
# Requires BOTH completion_indicators >= 2 AND exit_signal == true from Claude
MAX_CONSECUTIVE_TEST_LOOPS=3
MAX_CONSECUTIVE_DONE_SIGNALS=2

# Completion keywords
COMPLETION_KEYWORDS=(
    "done"
    "complete"
    "finished"
    "all tasks complete"
    "project complete"
    "ready for review"
    "implementation complete"
    "fully implemented"
)

# No work patterns
NO_WORK_PATTERNS=(
    "nothing to do"
    "no changes needed"
    "already implemented"
    "up to date"
    "no further action"
)

# Test-only patterns
TEST_PATTERNS=(
    "running tests"
    "npm test"
    "pytest"
    "jest"
    "bats"
    "cargo test"
    "go test"
)

# Analyze response for completion signals
# Arguments: transcript_text, loop_number
# Returns: JSON analysis result
analyze_response() {
    local transcript=$1
    local loop_number=${2:-0}

    ensure_dir ".claude"

    local has_completion_signal=false
    local is_test_only=false
    local is_stuck=false
    local has_progress=false
    local exit_signal=false
    local confidence_score=0
    local work_summary=""

    # 1. Check for explicit promise tag
    if echo "$transcript" | grep -q "<promise>"; then
        has_completion_signal=true
        exit_signal=true
        confidence_score=100
        work_summary="Completion promise found"
    fi

    # 2. Check for RALPH_STATUS block
    if echo "$transcript" | grep -q -- "---RALPH_STATUS---"; then
        local status=$(echo "$transcript" | grep "STATUS:" | cut -d: -f2 | xargs)
        local exit_sig=$(echo "$transcript" | grep "EXIT_SIGNAL:" | cut -d: -f2 | xargs)

        if [[ "$exit_sig" == "true" || "$status" == "COMPLETE" ]]; then
            has_completion_signal=true
            exit_signal=true
            confidence_score=100
        fi
    fi

    # 3. Check for completion keywords
    for keyword in "${COMPLETION_KEYWORDS[@]}"; do
        if echo "$transcript" | grep -qi "$keyword"; then
            has_completion_signal=true
            confidence_score=$((confidence_score + 10))
            break
        fi
    done

    # 4. Check for no-work patterns
    for pattern in "${NO_WORK_PATTERNS[@]}"; do
        if echo "$transcript" | grep -qi "$pattern"; then
            has_completion_signal=true
            confidence_score=$((confidence_score + 15))
            work_summary="No work remaining"
            break
        fi
    done

    # 5. Detect test-only loops
    local test_count=0
    local impl_count=0

    for pattern in "${TEST_PATTERNS[@]}"; do
        if echo "$transcript" | grep -qi "$pattern"; then
            test_count=$((test_count + 1))
        fi
    done

    impl_count=$(echo "$transcript" | grep -ci "implementing\|creating\|writing\|adding\|function\|class" 2>/dev/null | tr -d '\n\r ' || echo "0")
    [[ -z "$impl_count" || ! "$impl_count" =~ ^[0-9]+$ ]] && impl_count=0

    if [[ $test_count -gt 0 && $impl_count -eq 0 ]]; then
        is_test_only=true
        work_summary="Test execution only"
    fi

    # 6. Detect errors (potential stuck loop)
    local error_count=$(echo "$transcript" | grep -v '"[^"]*error[^"]*":' | \
        grep -cE '(^Error:|^ERROR:|error:|Exception|Fatal|FATAL|failed)' 2>/dev/null | tr -d '\n\r ' || echo "0")
    [[ -z "$error_count" || ! "$error_count" =~ ^[0-9]+$ ]] && error_count=0

    if [[ $error_count -gt 5 ]]; then
        is_stuck=true
    fi

    # 7. Check for file changes via git
    local files_modified=0
    if command -v git &>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
        files_modified=$(git diff --name-only 2>/dev/null | wc -l | tr -d '\n\r ')
        [[ -z "$files_modified" || ! "$files_modified" =~ ^[0-9]+$ ]] && files_modified=0
        if [[ $files_modified -gt 0 ]]; then
            has_progress=true
            confidence_score=$((confidence_score + 20))
        fi
    fi

    # 8. Determine exit signal if not already set
    if [[ "$exit_signal" != "true" && $confidence_score -ge 40 ]]; then
        exit_signal=true
    fi

    # Write analysis result
    jq -n \
        --argjson loop_number "$loop_number" \
        --arg timestamp "$(get_iso_timestamp)" \
        --argjson has_completion_signal "$has_completion_signal" \
        --argjson is_test_only "$is_test_only" \
        --argjson is_stuck "$is_stuck" \
        --argjson has_progress "$has_progress" \
        --argjson files_modified "$files_modified" \
        --argjson confidence_score "$confidence_score" \
        --argjson exit_signal "$exit_signal" \
        --argjson error_count "$error_count" \
        --arg work_summary "$work_summary" \
        '{
            loop_number: $loop_number,
            timestamp: $timestamp,
            analysis: {
                has_completion_signal: $has_completion_signal,
                is_test_only: $is_test_only,
                is_stuck: $is_stuck,
                has_progress: $has_progress,
                files_modified: $files_modified,
                confidence_score: $confidence_score,
                exit_signal: $exit_signal,
                error_count: $error_count,
                work_summary: $work_summary
            }
        }' > "$ANALYSIS_FILE"

    # Return key values for use in hooks
    echo "$exit_signal|$has_progress|$files_modified|$error_count|$is_stuck"
}

# Get analysis summary for context injection
get_analysis_summary() {
    if [[ ! -f "$ANALYSIS_FILE" ]]; then
        echo "No previous analysis"
        return
    fi

    local loop=$(json_get "$ANALYSIS_FILE" ".loop_number" "0")
    local confidence=$(json_get "$ANALYSIS_FILE" ".analysis.confidence_score" "0")
    local files=$(json_get "$ANALYSIS_FILE" ".analysis.files_modified" "0")
    local summary=$(json_get "$ANALYSIS_FILE" ".analysis.work_summary" "")

    echo "Loop $loop | Confidence: $confidence% | Files: $files | $summary"
}

# Update exit signals tracking
update_exit_signals() {
    local exit_signals_file=".claude/exit-signals.json"

    if [[ ! -f "$ANALYSIS_FILE" ]]; then
        return
    fi

    local is_test_only=$(json_get "$ANALYSIS_FILE" ".analysis.is_test_only" "false")
    local has_completion_signal=$(json_get "$ANALYSIS_FILE" ".analysis.has_completion_signal" "false")
    local has_progress=$(json_get "$ANALYSIS_FILE" ".analysis.has_progress" "false")
    local confidence=$(json_get "$ANALYSIS_FILE" ".analysis.confidence_score" "0")
    local loop_number=$(json_get "$ANALYSIS_FILE" ".loop_number" "0")

    # Initialize signals file if needed
    if [[ ! -f "$exit_signals_file" ]]; then
        echo '{"test_only_loops": [], "done_signals": [], "completion_indicators": []}' > "$exit_signals_file"
    fi

    local signals=$(cat "$exit_signals_file")

    # Update arrays
    if [[ "$is_test_only" == "true" ]]; then
        signals=$(echo "$signals" | jq ".test_only_loops += [$loop_number]")
    elif [[ "$has_progress" == "true" ]]; then
        signals=$(echo "$signals" | jq '.test_only_loops = []')
    fi

    if [[ "$has_completion_signal" == "true" ]]; then
        signals=$(echo "$signals" | jq ".done_signals += [$loop_number]")
    fi

    if [[ $confidence -ge 60 ]]; then
        signals=$(echo "$signals" | jq ".completion_indicators += [$loop_number]")
    fi

    # Keep only last 5 of each
    signals=$(echo "$signals" | jq '.test_only_loops = .test_only_loops[-5:]')
    signals=$(echo "$signals" | jq '.done_signals = .done_signals[-5:]')
    signals=$(echo "$signals" | jq '.completion_indicators = .completion_indicators[-5:]')

    echo "$signals" > "$exit_signals_file"
}

# Check if should exit gracefully based on accumulated signals
should_exit_gracefully() {
    local exit_signals_file=".claude/exit-signals.json"

    if [[ ! -f "$exit_signals_file" ]]; then
        echo ""
        return 1
    fi

    local signals=$(cat "$exit_signals_file")

    local test_loops=$(echo "$signals" | jq '.test_only_loops | length')
    local done_signals=$(echo "$signals" | jq '.done_signals | length')
    local completion_indicators=$(echo "$signals" | jq '.completion_indicators | length')

    # Check exit conditions
    if [[ $test_loops -ge 3 ]]; then
        echo "test_saturation"
        return 0
    fi

    if [[ $done_signals -ge 2 ]]; then
        echo "completion_signals"
        return 0
    fi

    # Dual-condition EXIT_SIGNAL gate
    # Requires BOTH completion_indicators >= 2 AND exit_signal == true from Claude
    # This prevents premature exits when heuristics detect completion patterns
    # but Claude explicitly indicates work is still in progress via RALPH_STATUS block
    local claude_exit_signal="false"
    if [[ -f "$ANALYSIS_FILE" ]]; then
        claude_exit_signal=$(json_get "$ANALYSIS_FILE" ".analysis.exit_signal" "false")
    fi

    if [[ $completion_indicators -ge 2 ]] && [[ "$claude_exit_signal" == "true" ]]; then
        echo "project_complete"
        return 0
    fi

    echo ""
    return 1
}

# Parse RALPH_STATUS block from transcript
# Returns: STATUS|TASKS_COMPLETED|FILES_MODIFIED|TESTS_STATUS|WORK_TYPE|EXIT_SIGNAL|RECOMMENDATION
parse_ralph_status() {
    local transcript=$1

    if ! echo "$transcript" | grep -q -- "---RALPH_STATUS---"; then
        echo ""
        return 1
    fi

    # Extract the status block
    local status_block=$(echo "$transcript" | sed -n '/---RALPH_STATUS---/,/---END_RALPH_STATUS---/p')

    local status=$(echo "$status_block" | grep "^STATUS:" | cut -d: -f2 | xargs)
    local tasks=$(echo "$status_block" | grep "TASKS_COMPLETED_THIS_LOOP:" | cut -d: -f2 | xargs)
    local files=$(echo "$status_block" | grep "FILES_MODIFIED:" | cut -d: -f2 | xargs)
    local tests=$(echo "$status_block" | grep "TESTS_STATUS:" | cut -d: -f2 | xargs)
    local work_type=$(echo "$status_block" | grep "WORK_TYPE:" | cut -d: -f2 | xargs)
    local exit_sig=$(echo "$status_block" | grep "EXIT_SIGNAL:" | cut -d: -f2 | xargs)
    local recommendation=$(echo "$status_block" | grep "RECOMMENDATION:" | cut -d: -f2- | xargs)

    echo "$status|$tasks|$files|$tests|$work_type|$exit_sig|$recommendation"
    return 0
}

# Check @fix_plan.md for completion
check_fix_plan_completion() {
    local fix_plan_file="@fix_plan.md"

    if [[ ! -f "$fix_plan_file" ]]; then
        echo ""
        return 1
    fi

    local total_items=$(grep -c "^- \[" "$fix_plan_file" 2>/dev/null || echo "0")
    local completed_items=$(grep -c "^- \[x\]" "$fix_plan_file" 2>/dev/null || echo "0")

    if [[ $total_items -gt 0 ]] && [[ $completed_items -eq $total_items ]]; then
        echo "plan_complete"
        return 0
    fi

    echo "$completed_items/$total_items"
    return 1
}
