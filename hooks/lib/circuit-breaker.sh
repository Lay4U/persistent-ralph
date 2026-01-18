#!/bin/bash
# Persistent Ralph - Circuit Breaker (v2.0)
# Prevents runaway loops by detecting stagnation and oscillation patterns
# Based on Michael Nygard's "Release It!" pattern + oscillation detection

# Source utilities (utils.sh is in the same directory)
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Circuit Breaker States
CB_STATE_CLOSED="CLOSED"        # Normal operation
CB_STATE_HALF_OPEN="HALF_OPEN"  # Monitoring mode
CB_STATE_OPEN="OPEN"            # Execution halted

# Configuration
CB_STATE_FILE=".claude/circuit-breaker.json"
CB_ACTION_HISTORY_FILE=".claude/action-history.json"
CB_NO_PROGRESS_THRESHOLD=5      # Open after N loops with no progress
CB_SAME_ERROR_THRESHOLD=3       # Open after N loops with same error
CB_OSCILLATION_THRESHOLD=3      # Detect A-B-A-B pattern after N cycles

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
                reason: "",
                oscillation_detected: false,
                intervention_message: ""
            }' > "$CB_STATE_FILE"
    fi

    # Initialize action history
    if [[ ! -f "$CB_ACTION_HISTORY_FILE" ]] || ! jq '.' "$CB_ACTION_HISTORY_FILE" > /dev/null 2>&1; then
        echo '{"actions": [], "error_patterns": {}}' > "$CB_ACTION_HISTORY_FILE"
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

# Record action for oscillation detection
# Arguments: action_type (e.g., "edit", "test_fail", "test_pass", "error")
record_action() {
    local action_type=$1
    local loop_number=$2
    local details=${3:-""}

    init_circuit_breaker

    local history=$(cat "$CB_ACTION_HISTORY_FILE")

    # Add new action
    history=$(echo "$history" | jq \
        --arg action "$action_type" \
        --argjson loop "$loop_number" \
        --arg details "$details" \
        --arg ts "$(get_iso_timestamp)" \
        '.actions += [{action: $action, loop: $loop, details: $details, timestamp: $ts}]')

    # Keep only last 20 actions
    history=$(echo "$history" | jq '.actions = .actions[-20:]')

    echo "$history" > "$CB_ACTION_HISTORY_FILE"
}

# Detect oscillation pattern (A-B-A-B)
# Returns: true if oscillating, false otherwise
detect_oscillation() {
    if [[ ! -f "$CB_ACTION_HISTORY_FILE" ]]; then
        echo "false"
        return
    fi

    local actions=$(jq -r '.actions[-8:] | .[].action' "$CB_ACTION_HISTORY_FILE" 2>/dev/null | tr '\n' ' ')

    # Check for A-B-A-B pattern (at least 4 elements)
    local arr=($actions)
    local len=${#arr[@]}

    if [[ $len -lt 4 ]]; then
        echo "false"
        return
    fi

    # Check last 4 actions for oscillation
    local a1=${arr[$len-4]}
    local b1=${arr[$len-3]}
    local a2=${arr[$len-2]}
    local b2=${arr[$len-1]}

    if [[ "$a1" == "$a2" && "$b1" == "$b2" && "$a1" != "$b1" ]]; then
        echo "true"
        return
    fi

    # Check for longer patterns (A-B-A-B-A-B)
    if [[ $len -ge 6 ]]; then
        local a0=${arr[$len-6]}
        local b0=${arr[$len-5]}
        if [[ "$a0" == "$a1" && "$a1" == "$a2" && "$b0" == "$b1" && "$b1" == "$b2" ]]; then
            echo "true"
            return
        fi
    fi

    echo "false"
}

# Get oscillation pattern description
get_oscillation_pattern() {
    if [[ ! -f "$CB_ACTION_HISTORY_FILE" ]]; then
        echo ""
        return
    fi

    local actions=$(jq -r '.actions[-6:] | .[].action' "$CB_ACTION_HISTORY_FILE" 2>/dev/null | tr '\n' ' ')
    echo "$actions"
}

# Record error pattern for tracking repeated failures
record_error_pattern() {
    local error_signature=$1

    if [[ -z "$error_signature" ]]; then
        return
    fi

    init_circuit_breaker

    local history=$(cat "$CB_ACTION_HISTORY_FILE")

    # Increment error pattern count
    local current_count=$(echo "$history" | jq -r --arg sig "$error_signature" '.error_patterns[$sig] // 0')
    current_count=$((current_count + 1))

    history=$(echo "$history" | jq --arg sig "$error_signature" --argjson count "$current_count" \
        '.error_patterns[$sig] = $count')

    echo "$history" > "$CB_ACTION_HISTORY_FILE"
}

# Get repeated error count for a signature
get_error_repeat_count() {
    local error_signature=$1

    if [[ ! -f "$CB_ACTION_HISTORY_FILE" ]]; then
        echo "0"
        return
    fi

    json_get "$CB_ACTION_HISTORY_FILE" ".error_patterns[\"$error_signature\"]" "0"
}

# Generate intervention message for repeated failures
generate_intervention_message() {
    local consecutive_no_progress=$1
    local consecutive_same_error=$2
    local oscillation_detected=$3
    local pattern=$4

    local msg=""

    if [[ "$oscillation_detected" == "true" ]]; then
        msg="INTERVENTION: Oscillation pattern detected ($pattern). This approach is not working. Try a completely different strategy."
    elif [[ $consecutive_same_error -ge 2 ]]; then
        msg="INTERVENTION: Same error repeated $consecutive_same_error times. Stop and try a different approach. Consider: decompose the problem, search for similar patterns, or bypass this issue."
    elif [[ $consecutive_no_progress -ge 3 ]]; then
        msg="INTERVENTION: No progress for $consecutive_no_progress loops. Current approach may be stuck. Review experiments.md and try an alternative method."
    fi

    echo "$msg"
}

# Record loop result and update circuit breaker state
# Arguments: loop_number, files_changed, has_errors, error_signature
record_loop_result() {
    local loop_number=${1:-0}
    local files_changed=${2:-0}
    local has_errors=${3:-false}
    local error_signature=${4:-""}

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

    # Record action for oscillation detection
    if [[ $files_changed -gt 0 ]]; then
        record_action "progress" "$loop_number" "files:$files_changed"
    elif [[ "$has_errors" == "true" ]]; then
        record_action "error" "$loop_number" "$error_signature"
    else
        record_action "no_change" "$loop_number"
    fi

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
        [[ -n "$error_signature" ]] && record_error_pattern "$error_signature"
    else
        consecutive_same_error=0
    fi

    # Check for oscillation
    local oscillation_detected=$(detect_oscillation)
    local oscillation_pattern=""
    if [[ "$oscillation_detected" == "true" ]]; then
        oscillation_pattern=$(get_oscillation_pattern)
    fi

    # Determine new state
    local new_state="$current_state"
    local reason=""
    local intervention_message=""

    case $current_state in
        "$CB_STATE_CLOSED")
            if [[ "$oscillation_detected" == "true" ]]; then
                new_state="$CB_STATE_HALF_OPEN"
                reason="Oscillation pattern detected: $oscillation_pattern"
                intervention_message=$(generate_intervention_message "$consecutive_no_progress" "$consecutive_same_error" "true" "$oscillation_pattern")
            elif [[ $consecutive_no_progress -ge $CB_NO_PROGRESS_THRESHOLD ]]; then
                new_state="$CB_STATE_OPEN"
                reason="No progress in $consecutive_no_progress consecutive loops"
            elif [[ $consecutive_same_error -ge $CB_SAME_ERROR_THRESHOLD ]]; then
                new_state="$CB_STATE_OPEN"
                reason="Same error repeated $consecutive_same_error times"
            elif [[ $consecutive_no_progress -ge 2 || $consecutive_same_error -ge 2 ]]; then
                new_state="$CB_STATE_HALF_OPEN"
                reason="Monitoring: $consecutive_no_progress loops without progress, $consecutive_same_error repeated errors"
                intervention_message=$(generate_intervention_message "$consecutive_no_progress" "$consecutive_same_error" "false" "")
            fi
            ;;
        "$CB_STATE_HALF_OPEN")
            if [[ "$has_progress" == "true" ]]; then
                new_state="$CB_STATE_CLOSED"
                reason="Progress detected, recovered"
                # Clear action history on recovery
                echo '{"actions": [], "error_patterns": {}}' > "$CB_ACTION_HISTORY_FILE"
            elif [[ "$oscillation_detected" == "true" ]]; then
                new_state="$CB_STATE_OPEN"
                reason="Oscillation pattern persists: $oscillation_pattern"
            elif [[ $consecutive_no_progress -ge $CB_NO_PROGRESS_THRESHOLD ]]; then
                new_state="$CB_STATE_OPEN"
                reason="No recovery after $consecutive_no_progress loops"
            else
                intervention_message=$(generate_intervention_message "$consecutive_no_progress" "$consecutive_same_error" "$oscillation_detected" "$oscillation_pattern")
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
        --argjson oscillation_detected "$oscillation_detected" \
        --arg intervention_message "$intervention_message" \
        '{
            state: $state,
            last_change: $last_change,
            consecutive_no_progress: $consecutive_no_progress,
            consecutive_same_error: $consecutive_same_error,
            last_progress_loop: $last_progress_loop,
            total_opens: $total_opens,
            reason: $reason,
            current_loop: $current_loop,
            oscillation_detected: $oscillation_detected,
            intervention_message: $intervention_message
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
            reason: $reason,
            oscillation_detected: false,
            intervention_message: ""
        }' > "$CB_STATE_FILE"

    # Clear action history
    echo '{"actions": [], "error_patterns": {}}' > "$CB_ACTION_HISTORY_FILE"

    log_to_file "CIRCUIT" "Reset: $reason"
}

# Get circuit breaker status message
get_circuit_status_message() {
    init_circuit_breaker

    local state=$(json_get "$CB_STATE_FILE" ".state" "CLOSED")
    local reason=$(json_get "$CB_STATE_FILE" ".reason" "")
    local no_progress=$(json_get "$CB_STATE_FILE" ".consecutive_no_progress" "0")
    local current_loop=$(json_get "$CB_STATE_FILE" ".current_loop" "0")
    local oscillation=$(json_get "$CB_STATE_FILE" ".oscillation_detected" "false")

    case $state in
        "$CB_STATE_CLOSED")
            echo "CIRCUIT: CLOSED (normal) | Loop: $current_loop"
            ;;
        "$CB_STATE_HALF_OPEN")
            if [[ "$oscillation" == "true" ]]; then
                echo "CIRCUIT: HALF_OPEN (oscillation detected) | $reason"
            else
                echo "CIRCUIT: HALF_OPEN (monitoring) | No progress: $no_progress | $reason"
            fi
            ;;
        "$CB_STATE_OPEN")
            echo "CIRCUIT: OPEN (halted) | $reason"
            ;;
    esac
}

# Get intervention message if any
get_intervention_message() {
    if [[ ! -f "$CB_STATE_FILE" ]]; then
        echo ""
        return
    fi

    json_get "$CB_STATE_FILE" ".intervention_message" ""
}
