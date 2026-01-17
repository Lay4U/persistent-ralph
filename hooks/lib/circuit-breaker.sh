#!/bin/bash
# Persistent Ralph - Circuit Breaker
# Prevents runaway loops by detecting stagnation
# Based on Michael Nygard's "Release It!" pattern

# Source utilities
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/utils.sh"

# Circuit Breaker States
CB_STATE_CLOSED="CLOSED"        # Normal operation
CB_STATE_HALF_OPEN="HALF_OPEN"  # Monitoring mode
CB_STATE_OPEN="OPEN"            # Execution halted

# Configuration
CB_STATE_FILE=".claude/circuit-breaker.json"
CB_NO_PROGRESS_THRESHOLD=5      # Open after N loops with no progress
CB_SAME_ERROR_THRESHOLD=3       # Open after N loops with same error

# Initialize circuit breaker
init_circuit_breaker() {
    ensure_dir ".claude"

    if [[ ! -f "$CB_STATE_FILE" ]] || ! jq '.' "$CB_STATE_FILE" > /dev/null 2>&1; then
        jq -n \
            --arg state "$CB_STATE_CLOSED" \
            --arg last_change "$(get_iso_timestamp)" \
            '{
                state: $state,
                last_change: $last_change,
                consecutive_no_progress: 0,
                consecutive_same_error: 0,
                last_progress_loop: 0,
                total_opens: 0,
                reason: ""
            }' > "$CB_STATE_FILE"
    fi
}

# Get current circuit breaker state
get_circuit_state() {
    init_circuit_breaker
    json_get "$CB_STATE_FILE" ".state" "$CB_STATE_CLOSED"
}

# Check if execution should be halted
should_halt() {
    local state=$(get_circuit_state)
    [[ "$state" == "$CB_STATE_OPEN" ]]
}

# Record loop result and update circuit breaker state
# Arguments: loop_number, files_changed, has_errors
record_loop_result() {
    local loop_number=${1:-0}
    local files_changed=${2:-0}
    local has_errors=${3:-false}

    init_circuit_breaker

    local state_data=$(cat "$CB_STATE_FILE")
    local current_state=$(echo "$state_data" | jq -r '.state')
    local consecutive_no_progress=$(echo "$state_data" | jq -r '.consecutive_no_progress // 0')
    local consecutive_same_error=$(echo "$state_data" | jq -r '.consecutive_same_error // 0')
    local last_progress_loop=$(echo "$state_data" | jq -r '.last_progress_loop // 0')
    local total_opens=$(echo "$state_data" | jq -r '.total_opens // 0')

    # Ensure integers
    consecutive_no_progress=$((consecutive_no_progress + 0))
    consecutive_same_error=$((consecutive_same_error + 0))
    last_progress_loop=$((last_progress_loop + 0))
    total_opens=$((total_opens + 0))

    # Detect progress
    local has_progress=false
    if [[ $files_changed -gt 0 ]]; then
        has_progress=true
        consecutive_no_progress=0
        last_progress_loop=$loop_number
    else
        consecutive_no_progress=$((consecutive_no_progress + 1))
    fi

    # Detect repeated errors
    if [[ "$has_errors" == "true" ]]; then
        consecutive_same_error=$((consecutive_same_error + 1))
    else
        consecutive_same_error=0
    fi

    # Determine new state
    local new_state="$current_state"
    local reason=""

    case $current_state in
        "$CB_STATE_CLOSED")
            if [[ $consecutive_no_progress -ge $CB_NO_PROGRESS_THRESHOLD ]]; then
                new_state="$CB_STATE_OPEN"
                reason="No progress in $consecutive_no_progress consecutive loops"
            elif [[ $consecutive_same_error -ge $CB_SAME_ERROR_THRESHOLD ]]; then
                new_state="$CB_STATE_OPEN"
                reason="Same error repeated $consecutive_same_error times"
            elif [[ $consecutive_no_progress -ge 2 ]]; then
                new_state="$CB_STATE_HALF_OPEN"
                reason="Monitoring: $consecutive_no_progress loops without progress"
            fi
            ;;
        "$CB_STATE_HALF_OPEN")
            if [[ "$has_progress" == "true" ]]; then
                new_state="$CB_STATE_CLOSED"
                reason="Progress detected, recovered"
            elif [[ $consecutive_no_progress -ge $CB_NO_PROGRESS_THRESHOLD ]]; then
                new_state="$CB_STATE_OPEN"
                reason="No recovery after $consecutive_no_progress loops"
            fi
            ;;
        "$CB_STATE_OPEN")
            reason="Circuit breaker is open"
            ;;
    esac

    # Update total_opens if transitioning to OPEN
    if [[ "$new_state" == "$CB_STATE_OPEN" && "$current_state" != "$CB_STATE_OPEN" ]]; then
        total_opens=$((total_opens + 1))
    fi

    # Write updated state
    jq -n \
        --arg state "$new_state" \
        --arg last_change "$(get_iso_timestamp)" \
        --argjson consecutive_no_progress "$consecutive_no_progress" \
        --argjson consecutive_same_error "$consecutive_same_error" \
        --argjson last_progress_loop "$last_progress_loop" \
        --argjson total_opens "$total_opens" \
        --arg reason "$reason" \
        --argjson current_loop "$loop_number" \
        '{
            state: $state,
            last_change: $last_change,
            consecutive_no_progress: $consecutive_no_progress,
            consecutive_same_error: $consecutive_same_error,
            last_progress_loop: $last_progress_loop,
            total_opens: $total_opens,
            reason: $reason,
            current_loop: $current_loop
        }' > "$CB_STATE_FILE"

    # Log state transition
    if [[ "$new_state" != "$current_state" ]]; then
        log_to_file "CIRCUIT" "State: $current_state -> $new_state | Reason: $reason"
    fi

    # Return whether halted
    [[ "$new_state" == "$CB_STATE_OPEN" ]]
}

# Reset circuit breaker
reset_circuit_breaker() {
    local reason=${1:-"Manual reset"}

    jq -n \
        --arg state "$CB_STATE_CLOSED" \
        --arg last_change "$(get_iso_timestamp)" \
        --arg reason "$reason" \
        '{
            state: $state,
            last_change: $last_change,
            consecutive_no_progress: 0,
            consecutive_same_error: 0,
            last_progress_loop: 0,
            total_opens: 0,
            reason: $reason
        }' > "$CB_STATE_FILE"

    log_to_file "CIRCUIT" "Reset: $reason"
}

# Get circuit breaker status message
get_circuit_status_message() {
    init_circuit_breaker

    local state=$(json_get "$CB_STATE_FILE" ".state" "CLOSED")
    local reason=$(json_get "$CB_STATE_FILE" ".reason" "")
    local no_progress=$(json_get "$CB_STATE_FILE" ".consecutive_no_progress" "0")
    local current_loop=$(json_get "$CB_STATE_FILE" ".current_loop" "0")

    case $state in
        "$CB_STATE_CLOSED")
            echo "CIRCUIT: CLOSED (normal) | Loop: $current_loop"
            ;;
        "$CB_STATE_HALF_OPEN")
            echo "CIRCUIT: HALF_OPEN (monitoring) | No progress: $no_progress | $reason"
            ;;
        "$CB_STATE_OPEN")
            echo "CIRCUIT: OPEN (halted) | $reason"
            ;;
    esac
}
