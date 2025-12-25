# nvim-assist Architecture

## File Structure

```
lua/nvim-assist/
├── init.lua     - Plugin entry point and lifecycle management
├── handlers.lua - Message protocol handlers
├── buffer.lua   - Buffer operations (read/write)
└── server.lua   - TCP server implementation
```

## Module Responsibilities

### init.lua (Plugin Entry Point) - 45 lines
- **Plugin Lifecycle**: Setup, commands, autocommands
- **Orchestration**: Wire together server, handlers, and lifecycle hooks
- **Responsibilities**:
  - `setup()` - Configure plugin and lifecycle hooks
- **Dependencies**: Requires `server` and `handlers` modules

### handlers.lua (Message Protocol) - 32 lines
- **Protocol Handling**: Decode messages, route commands, encode responses
- **Command Routing**: Route to appropriate buffer operations
- **Supported Commands**: get_buffer, apply_diff, ping
- **API**:
  - `handle_message(msg)` - Handle incoming JSON messages
- **Dependencies**: Requires `buffer` module

### buffer.lua (Buffer Operations) - 38 lines
- **Buffer Access**: Read and write Neovim buffers
- **Diff Application**: Apply various diff types to buffers
- **API**:
  - `get_current_content()` - Get current buffer content and metadata
  - `apply_diff(diff_data)` - Apply changes to buffer (full_replace, line_range, unified_diff)
- **Dependencies**: Only uses Neovim API

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
buffer.lua (get_current_content / apply_diff)
    ↓ (Neovim API)
Buffer
    ↓ (return result)
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
{"command": "ping"}
```

**Response**:
```json
{"success": true, "data": {...}}
{"success": true, "message": "..."}
{"success": false, "error": "..."}
```

## Separation of Concerns

- **server.lua**: Generic TCP server, no Neovim-specific logic (only vim.loop)
- **handlers.lua**: Protocol logic, no direct Neovim API usage
- **buffer.lua**: Pure buffer operations, no networking or protocol knowledge
- **init.lua**: Pure plugin lifecycle and orchestration, no business logic
- Clean interfaces: callback pattern (server ↔ handlers), module imports (handlers ↔ buffer, init ↔ server/handlers)

## Module Size

- **init.lua**: 45 lines (plugin entry point)
- **handlers.lua**: 32 lines (protocol handlers)
- **buffer.lua**: 38 lines (buffer operations)
- **server.lua**: 159 lines (TCP server + logging)

Total: 274 lines of well-separated, highly readable code

## Dependency Graph

```
init.lua
 ├── server.lua (lifecycle management)
 └── handlers.lua (message routing)
      └── buffer.lua (buffer operations)
```

Each module has a single, clear responsibility with minimal dependencies.
