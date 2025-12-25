# Testing nvim-assist

This document describes the testing scripts and test scenarios for nvim-assist's replace_text functionality.

## Test Scripts

### `test_replace.sh` - Interactive Comprehensive Test

A comprehensive, interactive test suite that demonstrates all features of the smart text replacement system.

**Run**: `./scripts/test_replace.sh`

**Tests Covered**:

1. **Successful Single Replacement**
   - Replaces 'Hello, World!' with 'Hi there!'
   - Validates exact matching works
   - Expected: `{"success": true, "message": "Text replaced"}`

2. **oldString Not Found Error**
   - Attempts to replace 'NonExistent'
   - Validates error detection for missing text
   - Expected: `{"success": false, "error": "oldString not found in content"}`

3. **Multiple Matches Error**
   - Attempts to replace 'Hello' (appears 3 times)
   - Validates conflict detection for ambiguous matches
   - Expected: `{"success": false, "error": "Found multiple matches for oldString. Provide more surrounding lines in oldString to identify the correct match."}`

4. **Successful replace_all**
   - Replaces all occurrences of 'Hello' with 'Hi'
   - Validates replace_all parameter
   - Expected: `{"success": true, "message": "All occurrences replaced"}`

5. **Line-Trimmed Matching**
   - Replaces text with different indentation
   - Validates indentation-flexible matching
   - Expected: `{"success": true}` despite indentation differences

6. **Block Anchor Matching**
   - Uses first/last line matching with similarity scoring
   - Validates block anchor strategy
   - Expected: `{"success": true}` with fuzzy middle content

7. **Unique Match with Context**
   - Provides surrounding lines to disambiguate
   - Validates context-aware matching
   - Expected: `{"success": true}` when enough context provided

### `quick_test.sh` - Non-Interactive Quick Test

A fast, non-interactive test suite for CI/CD or quick validation.

**Run**: `./scripts/quick_test.sh`

**Tests Covered**:
- Successful replacement
- Not found error
- Multiple matches error
- Replace all functionality
- Same strings validation error

**Exit Codes**:
- `0` - All tests passed
- `1` - Some tests failed

### `demo.sh` - General Demo

General demonstration of all plugin features (get_buffer, apply_diff, etc.).

**Run**: `./scripts/demo.sh`

## Matching Strategies Tested

The test scripts validate all matching strategies:

### 1. Simple Exact Match
```
"Hello, World!" → "Hi there!"
```
Exact string match, most straightforward.

### 2. Line-Trimmed Match
```lua
-- Ignores indentation differences
    function test() {  ←→  function test() {
        ...                    ...
    }                      }
```

### 3. Block Anchor Match
```lua
-- Matches using first/last lines + similarity
function calculate() {           function calculate() {
  let x = 10;                      let a = 1;
  let y = 20;          ≈≈≈≈≈       let b = 2;
  let z = 30;                      ...
  return x + y + z;                return x + y + z;
}                                }
```
Uses Levenshtein distance for middle lines.

### 4. Multi-Occurrence
```
"Hello" appears 3 times → Requires replace_all=true or error
```

## Conflict Detection Validation

### Error Scenarios

| Scenario | Error Message | Test Script |
|----------|---------------|-------------|
| Text not found | `oldString not found in content` | test_replace.sh (Test 2), quick_test.sh |
| Multiple ambiguous matches | `Found multiple matches for oldString. Provide more surrounding lines...` | test_replace.sh (Test 3), quick_test.sh |
| Same old/new strings | `oldString and newString must be different` | quick_test.sh |

### Success Scenarios

| Scenario | Expected Result | Test Script |
|----------|-----------------|-------------|
| Unique match | Text replaced | test_replace.sh (Test 1, 7), quick_test.sh |
| Replace all | All occurrences replaced | test_replace.sh (Test 4), quick_test.sh |
| Indentation differences | Match succeeds | test_replace.sh (Test 5) |
| Block anchor match | Fuzzy match succeeds | test_replace.sh (Test 6) |

## Running Tests

### Prerequisites
1. Neovim running with nvim-assist loaded
2. At least one buffer open (auto-starts server)
3. `jq` installed for JSON parsing
4. `nc` (netcat) for socket communication

### Quick Validation
```bash
# Fast test (30 seconds)
./scripts/quick_test.sh
```

### Comprehensive Testing
```bash
# Interactive test (5-10 minutes)
./scripts/test_replace.sh
```

### Individual Feature Testing
```bash
# Test specific features
./scripts/replace_text.sh "old" "new"
./scripts/get_buffer.sh
./scripts/ping.sh
```

## Expected Behavior

### OpenCode Compatibility

All tests validate that nvim-assist behaves identically to the OpenCode difftool plugin:

- ✓ Same error messages
- ✓ Same matching strategies
- ✓ Same parameter handling
- ✓ Same conflict detection logic

This ensures external tools can integrate seamlessly without learning different error handling patterns.

## CI/CD Integration

Use `quick_test.sh` for automated testing:

```bash
#!/bin/bash
# Example CI script

# Start Neovim in headless mode with nvim-assist
nvim --headless -c "lua require('nvim-assist').setup()" -c "edit test.txt" &
NVIM_PID=$!

# Wait for server to start
sleep 2

# Run tests
./scripts/quick_test.sh
TEST_RESULT=$?

# Cleanup
kill $NVIM_PID

exit $TEST_RESULT
```

## Troubleshooting

### Tests Fail to Connect
```bash
# Check if server is running
./scripts/ping.sh

# Check log file
tail -f nvim-assist.log
```

### Port Already in Use
```bash
# Use different port
NVIM_ASSIST_PORT=9998 ./scripts/quick_test.sh
```

### jq Not Installed
```bash
# Install jq
# macOS
brew install jq

# Linux
sudo apt-get install jq  # Debian/Ubuntu
sudo yum install jq      # RHEL/CentOS
```
