#!/bin/bash
# Persistent Ralph - Session Manager
# Manages session lifecycle with 24-hour expiration

# Source utilities (utils.sh is in the same directory)
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Configuration
SESSION_FILE=".claude/ralph-session.json"
SESSION_EXPIRY_HOURS=${RALPH_SESSION_EXPIRY_HOURS:-24}
SESSION_HISTORY_FILE=".claude/session-history.json"

# Initialize session manager
# Creates new session if:
# 1. Session file doesn't exist, OR
# 2. Session file exists but is expired
init_session() {
    ensure_dir ".claude"

    if [[ ! -f "$SESSION_FILE" ]]; then
        create_new_session > /dev/null  # Suppress session_id echo
        return
    fi

    # Check if existing session is expired
    local expires_at=$(json_get "$SESSION_FILE" '.expires_at' '')
    if [[ -n "$expires_at" ]]; then
        local expire_epoch=$(date -d "$expires_at" +%s 2>/dev/null || echo "0")
        local current_epoch=$(get_epoch_seconds)

        if [[ $current_epoch -gt $expire_epoch ]]; then
            # Session expired - save to history and create new one
            log_to_file "SESSION" "Existing session expired, creating new session"
            save_session_to_history "Auto-expired (24h timeout)"
            rm -f "$SESSION_FILE"
            create_new_session > /dev/null  # Suppress session_id echo
        fi
    fi
}

# Create new session
create_new_session() {
    local session_id="ralph-$(date +%s)-$$"

    cat > "$SESSION_FILE" << EOF
{
    "session_id": "$session_id",
    "created_at": "$(get_iso_timestamp)",
    "last_activity": "$(get_iso_timestamp)",
    "iteration_count": 0,
    "compact_count": 0,
    "expires_at": "$(date -u -d "+${SESSION_EXPIRY_HOURS} hours" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    log_to_file "SESSION" "New session created: $session_id"
    echo "$session_id"
}

# Check if session is valid (not expired)
is_session_valid() {
    init_session

    local expires_at=$(json_get "$SESSION_FILE" '.expires_at' '')

    if [[ -z "$expires_at" ]]; then
        return 0  # No expiration, assume valid
    fi

    local expire_epoch=$(date -d "$expires_at" +%s 2>/dev/null || echo "0")
    local current_epoch=$(get_epoch_seconds)

    if [[ $current_epoch -gt $expire_epoch ]]; then
        log_to_file "SESSION" "Session expired"
        return 1
    fi

    return 0
}

# Update session activity
update_session_activity() {
    init_session

    local data=$(cat "$SESSION_FILE")
    local iterations=$(echo "$data" | jq -r '.iteration_count // 0')
    iterations=$((iterations + 1))

    echo "$data" | jq \
        --arg activity "$(get_iso_timestamp)" \
        --argjson iterations "$iterations" \
        '.last_activity = $activity | .iteration_count = $iterations' > "$SESSION_FILE"
}

# Increment compact count
increment_compact_count() {
    init_session

    local data=$(cat "$SESSION_FILE")
    local compacts=$(echo "$data" | jq -r '.compact_count // 0')
    compacts=$((compacts + 1))

    echo "$data" | jq \
        --argjson compacts "$compacts" \
        '.compact_count = $compacts' > "$SESSION_FILE"
}

# Get session info
get_session_info() {
    init_session

    local session_id=$(json_get "$SESSION_FILE" '.session_id' 'unknown')
    local created=$(json_get "$SESSION_FILE" '.created_at' 'unknown')
    local iterations=$(json_get "$SESSION_FILE" '.iteration_count' '0')
    local compacts=$(json_get "$SESSION_FILE" '.compact_count' '0')

    echo "Session: $session_id | Created: $created | Iterations: $iterations | Compacts: $compacts"
}

# Expire session (for graceful end)
expire_session() {
    init_session

    local reason=${1:-"Manual expiration"}

    # Save to history
    save_session_to_history "$reason"

    # Remove current session
    rm -f "$SESSION_FILE"

    log_to_file "SESSION" "Session expired: $reason"
}

# Save session to history
save_session_to_history() {
    local reason=$1

    if [[ ! -f "$SESSION_FILE" ]]; then
        return
    fi

    local session_data=$(cat "$SESSION_FILE")

    # Initialize history if needed
    if [[ ! -f "$SESSION_HISTORY_FILE" ]]; then
        echo '{"sessions": []}' > "$SESSION_HISTORY_FILE"
    fi

    # Add to history
    local history=$(cat "$SESSION_HISTORY_FILE")
    local entry=$(echo "$session_data" | jq \
        --arg reason "$reason" \
        --arg ended "$(get_iso_timestamp)" \
        '. + {end_reason: $reason, ended_at: $ended}')

    echo "$history" | jq \
        --argjson entry "$entry" \
        '.sessions = [$entry] + .sessions | .sessions = .sessions[:10]' > "$SESSION_HISTORY_FILE"
}

# Extend session
extend_session() {
    init_session

    local hours=${1:-$SESSION_EXPIRY_HOURS}

    local data=$(cat "$SESSION_FILE")
    local new_expiry=$(date -u -d "+${hours} hours" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "$data" | jq \
        --arg expires "$new_expiry" \
        '.expires_at = $expires' > "$SESSION_FILE"

    log_to_file "SESSION" "Session extended by $hours hours"
}
