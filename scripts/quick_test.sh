#!/bin/bash

# Quick test script for replace_text functionality
# This is a non-interactive version for quick testing

HOST="${NVIM_ASSIST_HOST:-127.0.0.1}"
PORT="${NVIM_ASSIST_PORT:-9999}"

send_command() {
    local json="$1"
    local response=$(echo "$json" | nc "$HOST" "$PORT" 2>/dev/null)
    if [ -z "$response" ]; then
        echo '{"success":false,"error":"No response from server"}' >&2
        return 1
    fi
    echo "$response"
}

replace_text() {
    local old_string="$1"
    local new_string="$2"
    local replace_all="${3:-false}"

    local old_json=$(echo -n "$old_string" | jq -Rs .)
    local new_json=$(echo -n "$new_string" | jq -Rs .)

    local request="{\"command\":\"replace_text\",\"data\":{\"old_string\":$old_json,\"new_string\":$new_json,\"replace_all\":$replace_all}}"
    send_command "$request"
}

apply_text() {
    local content="$1"
    local content_json=$(echo -n "$content" | jq -Rs .)
    local request="{\"command\":\"apply_diff\",\"data\":{\"type\":\"full_replace\",\"content\":$content_json}}"
    local response=$(send_command "$request" 2>&1)
    if ! echo "$response" | jq -e '.success == true' > /dev/null 2>&1; then
        echo "Failed to apply text to buffer: $response" >&2
        return 1
    fi
}

get_buffer() {
    local response=$(send_command '{"command":"get_buffer"}')
    echo "$response" | jq -r '.data.content' 2>/dev/null
}

test_case() {
    local name="$1"
    local expected="$2"
    shift 2

    echo -n "Testing $name... "
    response=$(replace_text "$@")

    if echo "$response" | jq -e "$expected" > /dev/null 2>&1; then
        echo "✓ PASS"
        return 0
    else
        echo "✗ FAIL"
        echo "  Response: $response"
        return 1
    fi
}

echo "Quick Replace Text Tests"
echo "========================"
echo ""

# Setup
TEST_CONTENT="Hello, World!
Hello, again!
Goodbye!"

# Verify server is responding
echo -n "Checking server connection... "
if ! send_command '{"command":"ping"}' > /dev/null 2>&1; then
    echo "✗ FAILED"
    echo "Error: Cannot connect to nvim-assist server at $HOST:$PORT"
    echo "Make sure Neovim is running with nvim-assist loaded"
    exit 1
fi
echo "✓ OK"
echo ""

# Run tests
passed=0
total=0

# Test 1: Successful replacement
((total++))
apply_text "$TEST_CONTENT"
test_case "successful replacement" '.success == true' "Hello, World!" "Hi there!" && ((passed++))

# Test 2: Not found error
((total++))
apply_text "$TEST_CONTENT"
test_case "not found error" '.error | contains("not found")' "NonExistent" "Something" && ((passed++))

# Test 3: Multiple matches error
((total++))
apply_text "$TEST_CONTENT"
test_case "multiple matches error" '.error | contains("multiple matches")' "Hello" "Hi" && ((passed++))

# Test 4: Replace all
((total++))
apply_text "$TEST_CONTENT"
test_case "replace all" '.success == true' "Hello" "Hi" true && ((passed++))

# Test 5: Same strings error
((total++))
apply_text "$TEST_CONTENT"
test_case "same strings error" '.error | contains("must be different")' "test" "test" && ((passed++))

echo ""
echo "========================"
echo "Results: $passed/$total tests passed"

if [ $passed -eq $total ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
