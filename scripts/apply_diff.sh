#!/bin/bash

HOST="${NVIM_ASSIST_HOST:-127.0.0.1}"
PORT="${NVIM_ASSIST_PORT:-9999}"

send_command() {
    local json="$1"
    echo "$json" | nc "$HOST" "$PORT"
}

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <diff_type> [content_or_file]"
    echo ""
    echo "Diff types:"
    echo "  full_replace <file>     - Replace entire buffer with file content"
    echo "  line_range <file> <start> <end>  - Replace line range with file content"
    echo "  text <text>             - Replace entire buffer with text"
    echo ""
    echo "Examples:"
    echo "  $0 full_replace new_content.txt"
    echo "  $0 line_range new_content.txt 5 10"
    echo "  $0 text 'Hello, World!'"
    exit 1
fi

diff_type="$1"
shift

case "$diff_type" in
    full_replace)
        if [ ! -f "$1" ]; then
            echo "Error: File '$1' not found"
            exit 1
        fi
        content=$(cat "$1" | jq -Rs .)
        request="{\"command\":\"apply_diff\",\"data\":{\"type\":\"full_replace\",\"content\":$content}}"
        ;;
    line_range)
        if [ ! -f "$1" ]; then
            echo "Error: File '$1' not found"
            exit 1
        fi
        content=$(cat "$1" | jq -Rs .)
        start_line="${2:-0}"
        end_line="${3:--1}"
        request="{\"command\":\"apply_diff\",\"data\":{\"type\":\"line_range\",\"content\":$content,\"start_line\":$start_line,\"end_line\":$end_line}}"
        ;;
    text)
        content=$(echo -n "$1" | jq -Rs .)
        request="{\"command\":\"apply_diff\",\"data\":{\"type\":\"full_replace\",\"content\":$content}}"
        ;;
    *)
        echo "Unknown diff type: $diff_type"
        exit 1
        ;;
esac

echo "Applying diff to buffer..."
response=$(send_command "$request")
echo "$response" | jq '.' 2>/dev/null || echo "$response"
