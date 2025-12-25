# nvim-assist Architecture

## File Structure

```
lua/nvim-assist/
├── init.lua     - Plugin entry point and lifecycle management
├── handlers.lua - Message protocol handlers
├── buffer.lua   - Buffer operations (read/write/replace)
├── replace.lua  - Smart text replacement with conflict detection
└── server.lua   - TCP server implementation
```

## Module Responsibilities

### init.lua (Plugin Entry Point) - 45 lines
- **Plugin Lifecycle**: Setup, commands, autocommands
- **Orchestration**: Wire together server, handlers, and lifecycle hooks
- **Responsibilities**:
  - `setup()` - Configure plugin and lifecycle hooks
- **Dependencies**: Requires `server` and `handlers` modules

### handlers.lua (Message Protocol) - 36 lines
- **Protocol Handling**: Decode messages, route commands, encode responses
- **Command Routing**: Route to appropriate buffer operations
- **Supported Commands**: get_buffer, apply_diff, replace_text, ping
- **API**:
  - `handle_message(msg)` - Handle incoming JSON messages
- **Dependencies**: Requires `buffer` module

### buffer.lua (Buffer Operations) - 85 lines
- **Buffer Access**: Read and write Neovim buffers
- **Diff Application**: Apply various diff types to buffers
- **Smart Replacement**: Replace text with conflict detection
- **API**:
  - `get_current_content()` - Get current buffer content and metadata
  - `apply_diff(diff_data)` - Apply changes to buffer (full_replace, line_range, unified_diff)
  - `replace_text(replace_data)` - Replace text using smart matching strategies
- **Dependencies**: Requires `replace` module, uses Neovim API

### replace.lua (Smart Text Replacement) - 335 lines
- **Conflict Detection**: Detects ambiguous matches and missing text
- **Multiple Strategies**: Tries multiple matching approaches
- **Informative Errors**: Returns specific error messages for conflict resolution
- **Matching Strategies**:
  - Simple exact matching
  - Line-trimmed matching (ignores indentation)
  - Block anchor matching (uses first/last lines with similarity scoring)
  - Multi-occurrence handling
- **API**:
  - `replace(content, old_string, new_string, replace_all)` - Replace text with conflict detection
- **Error Messages**:
  - "oldString not found in content" - Text not found in buffer
  - "Found multiple matches for oldString. Provide more surrounding lines in oldString to identify the correct match." - Ambiguous match
  - "oldString and newString must be different" - Validation error
- **Dependencies**: None (pure Lua logic)

### server.lua (TCP Server) - 159 lines
- **Server Management**: Start, stop, restart TCP server
- **Client Handling**: Accept and manage client connections
- **Message Transport**: Receive and send line-delimited JSON
- **Logging**: File-based logging to cwd
- **API**:
  - `start()` - Start the TCP server
  - `stop()` - Stop the TCP server and cleanup
  - `restart()` - Restart with delay
  - `is_running()` - Check server status
  - `configure(opts)` - Set host, port, log_file
  - `set_message_handler(handler)` - Set callback for messages
- **Dependencies**: Only uses vim.loop (libuv)

## Data Flow

```
External Tool
    ↓ (TCP socket)
server.lua (receive message)
    ↓ (call message_handler callback)
handlers.lua (handle_message, decode JSON)
    ↓ (route command)
buffer.lua (get_current_content / apply_diff / replace_text)
    ↓ (for replace_text)
replace.lua (conflict detection & replacement)
    ↓ (Neovim API)
Buffer
    ↓ (return result or error)
handlers.lua (encode JSON response)
    ↓ (return to server)
server.lua (send response)
    ↓ (TCP socket)
External Tool
```

## Lifecycle

1. **Startup**: `BufEnter` autocmd → `server.start()`
2. **Runtime**: Clients connect → messages handled → responses sent
3. **Shutdown**: `VimLeavePre` autocmd → `server.stop()`

## Protocol

**Format**: Line-delimited JSON (`\n` terminated)

**Request**:
```json
{"command": "get_buffer"}
{"command": "apply_diff", "data": {"type": "full_replace", "content": "..."}}
{"command": "replace_text", "data": {"old_string": "...", "new_string": "...", "replace_all": false}}
{"command": "ping"}
```

**Response**:
```json
{"success": true, "data": {...}}
{"success": true, "message": "..."}
{"success": false, "error": "oldString not found in content"}
{"success": false, "error": "Found multiple matches for oldString. Provide more surrounding lines in oldString to identify the correct match."}
```

### replace_text Command

The `replace_text` command uses smart matching strategies (inspired by OpenCode difftool) to find and replace text with conflict detection:

**Parameters**:
- `old_string` (required): Text to find and replace
- `new_string` (required): Replacement text (must be different from old_string)
- `replace_all` (optional, default: false): Replace all occurrences

**Matching Strategies** (tried in order):
1. Exact match
2. Line-trimmed match (ignores indentation)
3. Block anchor match (uses first/last lines with similarity scoring)
4. Multi-occurrence match

**Error Responses**:
- `"oldString not found in content"` - Text cannot be found using any strategy
- `"Found multiple matches for oldString. Provide more surrounding lines in oldString to identify the correct match."` - Multiple matches found, needs more context
- `"oldString and newString must be different"` - Validation error

## Separation of Concerns

- **server.lua**: Generic TCP server, no Neovim-specific logic (only vim.loop)
- **handlers.lua**: Protocol logic, no direct Neovim API usage
- **buffer.lua**: Pure buffer operations, no networking or protocol knowledge
- **init.lua**: Pure plugin lifecycle and orchestration, no business logic
- Clean interfaces: callback pattern (server ↔ handlers), module imports (handlers ↔ buffer, init ↔ server/handlers)

## Module Size

- **init.lua**: 45 lines (plugin entry point)
- **handlers.lua**: 36 lines (protocol handlers)
- **buffer.lua**: 85 lines (buffer operations)
- **replace.lua**: 335 lines (smart text replacement)
- **server.lua**: 159 lines (TCP server + logging)

Total: 660 lines of well-separated, highly readable code

## Dependency Graph

```
init.lua
 ├── server.lua (lifecycle management)
 └── handlers.lua (message routing)
      └── buffer.lua (buffer operations)
           └── replace.lua (conflict detection)
```

Each module has a single, clear responsibility with minimal dependencies.

## OpenCode Integration

The `replace.lua` module implements the same conflict resolution logic as the OpenCode difftool plugin, enabling seamless integration:

1. **Same Error Messages**: Returns identical error messages for conflict resolution
2. **Same Matching Strategies**: Uses the same text matching algorithms
3. **Same Parameters**: Accepts the same arguments (old_string, new_string, replace_all)

This allows external OpenCode plugins to:
- Send `replace_text` commands to nvim-assist
- Receive informative errors when conflicts occur
- Implement conflict resolution logic based on error responses
- Apply changes when no conflicts are detected
