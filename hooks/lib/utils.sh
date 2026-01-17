#!/bin/bash
# Persistent Ralph - Utility Functions
# Cross-platform date and JSON utilities

# Get ISO timestamp
get_iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get epoch seconds
get_epoch_seconds() {
    date +%s
}

# Safe JSON read with default
json_get() {
    local file=$1
    local path=$2
    local default=$3

    if [[ ! -f "$file" ]]; then
        echo "$default"
        return
    fi

    local value=$(jq -r "$path // empty" "$file" 2>/dev/null)
    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Ensure directory exists
ensure_dir() {
    local dir=$1
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
}

# Log to file
log_to_file() {
    local level=$1
    local message=$2
    local log_file=${3:-".claude/ralph-log.txt"}

    ensure_dir "$(dirname "$log_file")"
    echo "[$(get_iso_timestamp)] [$level] $message" >> "$log_file"
}
