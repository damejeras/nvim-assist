#!/bin/bash

HOST="${NVIM_ASSIST_HOST:-127.0.0.1}"
PORT="${NVIM_ASSIST_PORT:-9999}"

send_command() {
    local json="$1"
    echo "$json" | nc "$HOST" "$PORT"
}

get_buffer_content() {
    local request='{"command":"get_buffer"}'
    send_command "$request"
}

echo "Getting buffer content from Neovim..."
response=$(get_buffer_content)
echo "$response" | jq '.' 2>/dev/null || echo "$response"
