#!/bin/bash
# Persistent Ralph - Rate Limiter
# Tracks API call counts and rate limits

# Source utilities
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/utils.sh"

# Configuration
CALL_COUNT_FILE=".claude/call-count.json"
MAX_CALLS_PER_HOUR=${RALPH_MAX_CALLS_PER_HOUR:-100}
API_LIMIT_HOURS=${RALPH_API_LIMIT_HOURS:-5}

# Initialize rate limiter
init_rate_limiter() {
    ensure_dir ".claude"

    if [[ ! -f "$CALL_COUNT_FILE" ]]; then
        cat > "$CALL_COUNT_FILE" << EOF
{
    "calls_this_hour": 0,
    "hour_started": "$(get_iso_timestamp)",
    "total_calls": 0,
    "session_started": "$(get_iso_timestamp)",
    "api_limit_triggered": false,
    "last_api_limit": null
}
EOF
    fi
}

# Check if we can make another call
can_make_call() {
    init_rate_limiter

    local current_hour=$(date +%Y%m%d%H)
    local stored_hour=$(json_get "$CALL_COUNT_FILE" '.hour_started' '')
    local stored_hour_short=$(echo "$stored_hour" | sed 's/[-T:]//g' | cut -c1-10)

    # Reset if new hour
    if [[ "$current_hour" != "$stored_hour_short" ]]; then
        reset_hourly_count
    fi

    local calls=$(json_get "$CALL_COUNT_FILE" '.calls_this_hour' '0')

    if [[ $calls -ge $MAX_CALLS_PER_HOUR ]]; then
        return 1  # Cannot make call
    fi

    return 0  # Can make call
}

# Increment call counter
increment_call_counter() {
    init_rate_limiter

    local data=$(cat "$CALL_COUNT_FILE")
    local calls=$(echo "$data" | jq -r '.calls_this_hour // 0')
    local total=$(echo "$data" | jq -r '.total_calls // 0')

    calls=$((calls + 1))
    total=$((total + 1))

    echo "$data" | jq \
        --argjson calls "$calls" \
        --argjson total "$total" \
        '.calls_this_hour = $calls | .total_calls = $total' > "$CALL_COUNT_FILE"

    echo "$calls"
}

# Reset hourly count
reset_hourly_count() {
    init_rate_limiter

    local data=$(cat "$CALL_COUNT_FILE")
    echo "$data" | jq \
        --arg hour "$(get_iso_timestamp)" \
        '.calls_this_hour = 0 | .hour_started = $hour' > "$CALL_COUNT_FILE"
}

# Check for 5-hour API limit
check_api_limit() {
    init_rate_limiter

    local last_limit=$(json_get "$CALL_COUNT_FILE" '.last_api_limit' 'null')

    if [[ "$last_limit" != "null" && -n "$last_limit" ]]; then
        local limit_epoch=$(date -d "$last_limit" +%s 2>/dev/null || echo "0")
        local current_epoch=$(get_epoch_seconds)
        local hours_since=$(( (current_epoch - limit_epoch) / 3600 ))

        if [[ $hours_since -lt $API_LIMIT_HOURS ]]; then
            local remaining=$((API_LIMIT_HOURS - hours_since))
            echo "API limit active. $remaining hours remaining."
            return 1
        fi
    fi

    return 0
}

# Record API limit trigger
record_api_limit() {
    init_rate_limiter

    local data=$(cat "$CALL_COUNT_FILE")
    echo "$data" | jq \
        --arg limit "$(get_iso_timestamp)" \
        '.api_limit_triggered = true | .last_api_limit = $limit' > "$CALL_COUNT_FILE"

    log_to_file "RATE" "API limit triggered at $(get_iso_timestamp)"
}

# Clear API limit
clear_api_limit() {
    init_rate_limiter

    local data=$(cat "$CALL_COUNT_FILE")
    echo "$data" | jq \
        '.api_limit_triggered = false | .last_api_limit = null' > "$CALL_COUNT_FILE"
}

# Get rate limit status message
get_rate_limit_status() {
    init_rate_limiter

    local calls=$(json_get "$CALL_COUNT_FILE" '.calls_this_hour' '0')
    local total=$(json_get "$CALL_COUNT_FILE" '.total_calls' '0')

    echo "Calls this hour: $calls/$MAX_CALLS_PER_HOUR | Total: $total"
}
