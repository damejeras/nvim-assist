#!/bin/bash

set -e

HOST="${NVIM_ASSIST_HOST:-127.0.0.1}"
PORT="${NVIM_ASSIST_PORT:-9999}"

send_command() {
    local json="$1"
    echo "$json" | nc "$HOST" "$PORT"
}

get_buffer() {
    send_command '{"command":"get_buffer"}' | jq -r '.data.content'
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
    send_command "$request" > /dev/null
}

echo "========================================="
echo "nvim-assist Replace Text Test Script"
echo "========================================="
echo ""
echo "This script tests the smart text replacement"
echo "and conflict resolution features."
echo ""
echo "Make sure you have:"
echo "1. Started Neovim"
echo "2. Loaded the nvim-assist plugin"
echo "3. Opened at least one buffer"
echo ""
echo "Press Enter to start..."
read

echo ""
echo "========================================="
echo "Setting up test content in buffer..."
echo "========================================="

TEST_CONTENT="function greet() {
  console.log('Hello, World!');
}

function farewell() {
  console.log('Goodbye!');
}

function greet(name) {
  console.log('Hello, ' + name);
}

const message = 'Hello';
const another = 'Hello';"

apply_text "$TEST_CONTENT"

echo "Buffer content:"
echo "---"
get_buffer
echo "---"
echo ""
echo "Press Enter to continue..."
read

echo ""
echo "========================================="
echo "Test 1: Successful single replacement"
echo "========================================="
echo "Replacing 'Hello, World!' with 'Hi there!'"
echo ""

response=$(replace_text "Hello, World!" "Hi there!")
echo "Response:"
echo "$response" | jq '.'
echo ""

if echo "$response" | jq -e '.success == true' > /dev/null; then
    echo "✓ SUCCESS: Text replaced"
    echo ""
    echo "Updated buffer:"
    echo "---"
    get_buffer
    echo "---"
else
    echo "✗ FAILED: Expected success but got error"
fi

echo ""
echo "Press Enter to continue..."
read

echo ""
echo "========================================="
echo "Test 2: oldString not found error"
echo "========================================="
echo "Trying to replace 'NonExistent' (should fail)"
echo ""

response=$(replace_text "NonExistent" "Something")
echo "Response:"
echo "$response" | jq '.'
echo ""

if echo "$response" | jq -e '.error | contains("not found")' > /dev/null; then
    echo "✓ SUCCESS: Correctly reported 'not found' error"
else
    echo "✗ FAILED: Expected 'not found' error"
fi

echo ""
echo "Press Enter to continue..."
read

echo ""
echo "========================================="
echo "Test 3: Multiple matches error"
echo "========================================="
echo "Trying to replace 'Hello' (appears 3 times, should fail)"
echo ""

response=$(replace_text "Hello" "Hi")
echo "Response:"
echo "$response" | jq '.'
echo ""

if echo "$response" | jq -e '.error | contains("multiple matches")' > /dev/null; then
    echo "✓ SUCCESS: Correctly reported 'multiple matches' error"
else
    echo "✗ FAILED: Expected 'multiple matches' error"
fi

echo ""
echo "Press Enter to continue..."
read

echo ""
echo "========================================="
echo "Test 4: Successful replace_all"
echo "========================================="
echo "Replacing all 'Hello' with 'Hi' using replace_all=true"
echo ""

response=$(replace_text "Hello" "Hi" true)
echo "Response:"
echo "$response" | jq '.'
echo ""

if echo "$response" | jq -e '.success == true' > /dev/null; then
    echo "✓ SUCCESS: All occurrences replaced"
    echo ""
    echo "Updated buffer:"
    echo "---"
    get_buffer
    echo "---"
else
    echo "✗ FAILED: Expected success but got error"
fi

echo ""
echo "Press Enter to continue..."
read

echo ""
echo "========================================="
echo "Test 5: Line-trimmed matching"
echo "========================================="
echo "Replacing with different indentation (should work)"
echo ""

# Reset buffer with indented content
INDENTED_CONTENT="    function test() {
        console.log('test');
    }"
apply_text "$INDENTED_CONTENT"

echo "Buffer content:"
echo "---"
get_buffer
echo "---"
echo ""

# Try to replace with non-indented version
response=$(replace_text "function test() {
    console.log('test');
}" "function test() {
    console.log('testing');
}")

echo "Response:"
echo "$response" | jq '.'
echo ""

if echo "$response" | jq -e '.success == true' > /dev/null; then
    echo "✓ SUCCESS: Line-trimmed matching worked"
    echo ""
    echo "Updated buffer:"
    echo "---"
    get_buffer
    echo "---"
else
    echo "✗ FAILED: Line-trimmed matching should have worked"
fi

echo ""
echo "Press Enter to continue..."
read

echo ""
echo "========================================="
echo "Test 6: Block anchor matching"
echo "========================================="
echo "Testing block anchor strategy with first/last line matching"
echo ""

BLOCK_CONTENT="function calculate() {
  let x = 10;
  let y = 20;
  let z = 30;
  return x + y + z;
}"
apply_text "$BLOCK_CONTENT"

echo "Buffer content:"
echo "---"
get_buffer
echo "---"
echo ""

# Use block anchor (first and last line) with different middle content
response=$(replace_text "function calculate() {
  let a = 1;
  let b = 2;
  return x + y + z;
}" "function calculate() {
  let result = 10 + 20 + 30;
  return result;
}")

echo "Response:"
echo "$response" | jq '.'
echo ""

if echo "$response" | jq -e '.success == true' > /dev/null; then
    echo "✓ SUCCESS: Block anchor matching worked"
    echo ""
    echo "Updated buffer:"
    echo "---"
    get_buffer
    echo "---"
else
    echo "✗ FAILED: Block anchor matching should have worked"
fi

echo ""
echo "Press Enter to continue..."
read

echo ""
echo "========================================="
echo "Test 7: Unique match with context"
echo "========================================="
echo "Providing more context to make match unique"
echo ""

# Reset to original test content with multiple 'greet' functions
apply_text "$TEST_CONTENT"

echo "Buffer content:"
echo "---"
get_buffer
echo "---"
echo ""

# Replace only the first greet function by providing context
response=$(replace_text "function greet() {
  console.log('Hello, World!');
}" "function greet() {
  console.log('Greetings!');
}")

echo "Response:"
echo "$response" | jq '.'
echo ""

if echo "$response" | jq -e '.success == true' > /dev/null; then
    echo "✓ SUCCESS: Unique match found with context"
    echo ""
    echo "Updated buffer:"
    echo "---"
    get_buffer
    echo "---"
else
    echo "✗ FAILED: Should have found unique match with context"
fi

echo ""
echo "========================================="
echo "Test Summary Complete!"
echo "========================================="
echo ""
echo "All tests finished. Check the results above."
echo "The replace_text command demonstrates:"
echo "  ✓ Exact matching"
echo "  ✓ Line-trimmed matching (indentation flexible)"
echo "  ✓ Block anchor matching (similarity-based)"
echo "  ✓ Conflict detection (not found, multiple matches)"
echo "  ✓ Replace all functionality"
echo ""
echo "These match the OpenCode difftool behavior for"
echo "conflict resolution and smart text replacement."
echo "========================================="
