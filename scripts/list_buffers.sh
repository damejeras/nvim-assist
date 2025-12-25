#!/bin/bash

HOST="${NVIM_ASSIST_HOST:-127.0.0.1}"
PORT="${NVIM_ASSIST_PORT:-9999}"

send_command() {
    local json="$1"
    echo "$json" | nc "$HOST" "$PORT"
}

echo "Listing open buffers in Neovim..."
response=$(send_command '{"command":"list_buffers"}')
echo "$response" | jq '.' 2>/dev/null || echo "$response"
