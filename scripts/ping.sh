#!/bin/bash

HOST="${NVIM_ASSIST_HOST:-127.0.0.1}"
PORT="${NVIM_ASSIST_PORT:-9999}"

send_command() {
    local json="$1"
    echo "$json" | nc "$HOST" "$PORT"
}

echo "Pinging nvim-assist server..."
response=$(send_command '{"command":"ping"}')
echo "$response" | jq '.' 2>/dev/null || echo "$response"
