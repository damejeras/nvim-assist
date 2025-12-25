#!/bin/bash

HOST="${NVIM_ASSIST_HOST:-127.0.0.1}"
PORT="${NVIM_ASSIST_PORT:-9999}"

send_command() {
    local json="$1"
    echo "$json" | nc "$HOST" "$PORT"
}

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <old_string> <new_string> [replace_all]"
    echo ""
    echo "Examples:"
    echo "  $0 'Hello' 'Hi'"
    echo "  $0 'foo' 'bar' true"
    echo ""
    echo "This uses smart matching strategies to find and replace text:"
    echo "  - Exact matching"
    echo "  - Line-trimmed matching (ignores indentation)"
    echo "  - Block anchor matching (uses first/last lines)"
    echo "  - Multi-occurrence handling"
    echo ""
    echo "Error messages:"
    echo "  - 'oldString not found in content' - text not found"
    echo "  - 'Found multiple matches...' - ambiguous match, provide more context"
    echo "  - 'oldString and newString must be different' - same values provided"
    exit 1
fi

old_string="$1"
new_string="$2"
replace_all="${3:-false}"

# Escape strings for JSON
old_string_json=$(echo -n "$old_string" | jq -Rs .)
new_string_json=$(echo -n "$new_string" | jq -Rs .)

request="{\"command\":\"replace_text\",\"data\":{\"old_string\":$old_string_json,\"new_string\":$new_string_json,\"replace_all\":$replace_all}}"

echo "Replacing text in buffer..."
response=$(send_command "$request")
echo "$response" | jq '.' 2>/dev/null || echo "$response"
