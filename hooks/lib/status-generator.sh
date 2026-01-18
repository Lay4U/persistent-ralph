#!/bin/bash
# Persistent Ralph - Status Generator
# Generates status.json for external monitoring

# Source utilities (utils.sh is in the same directory)
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Status file configuration
STATUS_FILE="status.json"
PROGRESS_FILE=".claude/progress.json"

# Generate status.json for external monitoring
generate_status() {
    local loop_count=${1:-0}
    local calls_made=${2:-0}
    local last_action=${3:-"unknown"}
    local status=${4:-"running"}
    local exit_reason=${5:-""}

    # Get circuit breaker status
    local cb_state="UNKNOWN"
    local cb_reason=""
    if [[ -f ".claude/circuit-breaker.json" ]]; then
        cb_state=$(json_get ".claude/circuit-breaker.json" ".state" "UNKNOWN")
        cb_reason=$(json_get ".claude/circuit-breaker.json" ".reason" "")
    fi

    # Get session info
    local session_id="unknown"
    local session_iterations=0
    local session_compacts=0
    if [[ -f ".claude/ralph-session.json" ]]; then
        session_id=$(json_get ".claude/ralph-session.json" ".session_id" "unknown")
        session_iterations=$(json_get ".claude/ralph-session.json" ".iteration_count" "0")
        session_compacts=$(json_get ".claude/ralph-session.json" ".compact_count" "0")
    fi

    # Get analysis info
    local confidence=0
    local files_modified=0
    local work_summary=""
    if [[ -f ".claude/response-analysis.json" ]]; then
        confidence=$(json_get ".claude/response-analysis.json" ".analysis.confidence_score" "0")
        files_modified=$(json_get ".claude/response-analysis.json" ".analysis.files_modified" "0")
        work_summary=$(json_get ".claude/response-analysis.json" ".analysis.work_summary" "")
    fi

    # Get recent git info
    local recent_commit=""
    local uncommitted_files=0
    if command -v git &>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
        recent_commit=$(git log --oneline -1 2>/dev/null || echo "")
        uncommitted_files=$(git status --porcelain 2>/dev/null | wc -l | tr -d '\n\r ')
        [[ -z "$uncommitted_files" || ! "$uncommitted_files" =~ ^[0-9]+$ ]] && uncommitted_files=0
    fi

    # Calculate next hour reset time
    local current_minute=$(date +%M)
    local minutes_until_reset=$((60 - current_minute))

    # Generate status JSON
    jq -n \
        --arg timestamp "$(get_iso_timestamp)" \
        --argjson loop_count "$loop_count" \
        --argjson calls_made "$calls_made" \
        --argjson max_calls_per_hour "${RALPH_MAX_CALLS_PER_HOUR:-100}" \
        --arg last_action "$last_action" \
        --arg status "$status" \
        --arg exit_reason "$exit_reason" \
        --arg cb_state "$cb_state" \
        --arg cb_reason "$cb_reason" \
        --arg session_id "$session_id" \
        --argjson session_iterations "$session_iterations" \
        --argjson session_compacts "$session_compacts" \
        --argjson confidence "$confidence" \
        --argjson files_modified "$files_modified" \
        --arg work_summary "$work_summary" \
        --arg recent_commit "$recent_commit" \
        --argjson uncommitted_files "$uncommitted_files" \
        --argjson minutes_until_reset "$minutes_until_reset" \
        '{
            timestamp: $timestamp,
            loop_count: $loop_count,
            rate_limit: {
                calls_made_this_hour: $calls_made,
                max_calls_per_hour: $max_calls_per_hour,
                minutes_until_reset: $minutes_until_reset
            },
            last_action: $last_action,
            status: $status,
            exit_reason: $exit_reason,
            circuit_breaker: {
                state: $cb_state,
                reason: $cb_reason
            },
            session: {
                id: $session_id,
                iterations: $session_iterations,
                compacts: $session_compacts
            },
            analysis: {
                confidence: $confidence,
                files_modified: $files_modified,
                work_summary: $work_summary
            },
            git: {
                recent_commit: $recent_commit,
                uncommitted_files: $uncommitted_files
            }
        }' > "$STATUS_FILE"

    # Also update progress file
    update_progress "$loop_count" "$status"
}

# Update progress.json for tracking over time
update_progress() {
    local loop_count=$1
    local status=$2

    ensure_dir ".claude"

    # Initialize if needed
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo '{"loops": [], "summary": {}}' > "$PROGRESS_FILE"
    fi

    local progress=$(cat "$PROGRESS_FILE")

    # Add loop entry
    local entry=$(jq -n \
        --argjson loop "$loop_count" \
        --arg status "$status" \
        --arg timestamp "$(get_iso_timestamp)" \
        '{loop: $loop, status: $status, timestamp: $timestamp}')

    progress=$(echo "$progress" | jq \
        --argjson entry "$entry" \
        '.loops = [$entry] + .loops | .loops = .loops[:100]')

    # Update summary
    local total_loops=$(echo "$progress" | jq '.loops | length')
    local successful_loops=$(echo "$progress" | jq '[.loops[] | select(.status == "completed")] | length')
    local failed_loops=$(echo "$progress" | jq '[.loops[] | select(.status == "failed" or .status == "halted")] | length')

    progress=$(echo "$progress" | jq \
        --argjson total "$total_loops" \
        --argjson successful "$successful_loops" \
        --argjson failed "$failed_loops" \
        '.summary = {total_loops: $total, successful_loops: $successful, failed_loops: $failed}')

    echo "$progress" > "$PROGRESS_FILE"
}

# Get status summary for display
get_status_summary() {
    if [[ ! -f "$STATUS_FILE" ]]; then
        echo "No status available"
        return
    fi

    local status=$(json_get "$STATUS_FILE" ".status" "unknown")
    local loop=$(json_get "$STATUS_FILE" ".loop_count" "0")
    local cb=$(json_get "$STATUS_FILE" ".circuit_breaker.state" "UNKNOWN")
    local calls=$(json_get "$STATUS_FILE" ".rate_limit.calls_made_this_hour" "0")
    local max_calls=$(json_get "$STATUS_FILE" ".rate_limit.max_calls_per_hour" "100")

    echo "Status: $status | Loop: $loop | Circuit: $cb | Calls: $calls/$max_calls"
}
