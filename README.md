# nvim-assist

A Neovim plugin that automatically opens a socket server allowing external tools to interact with buffers through a simple JSON-based protocol.

## Features

- Automatic TCP socket server management (starts on first buffer, stops on exit)
- Get buffer content via socket
- Apply diffs/updates to buffers
- Three diff types: full replace, line range, and unified diff
- Simple JSON protocol
- Automatic logging to file in current working directory

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "yourusername/nvim-assist",
  config = function()
    require("nvim-assist").setup({
      host = "127.0.0.1",          -- default: server host
      port = 9999,                 -- default: server port
      log_file = "nvim-assist.log" -- default: log file name in cwd
    })
  end
}
```

## Usage

### Server Lifecycle

The server **automatically manages itself**:
- **Auto-starts** when you open the first buffer in Neovim
- **Auto-stops** when you exit Neovim
- Logs all activity to `nvim-assist.log` in your current working directory

### Commands

- `:AssistRestart` - Restart the socket server (only manual command needed)

## Protocol

The plugin uses a line-delimited JSON protocol. Each request and response is a single line of JSON terminated by `\n`.

### Available Commands

#### 1. Ping (Health Check)

Request:
```json
{"command": "ping"}
```

Response:
```json
{"success": true, "message": "pong"}
```

#### 2. Get Buffer Content

Request:
```json
{"command": "get_buffer"}
```

Response:
```json
{
  "success": true,
  "data": {
    "bufnr": 1,
    "content": "file content here...",
    "lines": ["line 1", "line 2", "..."],
    "filepath": "/path/to/file"
  }
}
```

#### 3. Apply Diff

Request:
```json
{
  "command": "apply_diff",
  "data": {
    "type": "full_replace",
    "content": "new content here"
  }
}
```

Diff Types:
- `full_replace` - Replace entire buffer
- `line_range` - Replace specific line range (requires `start_line` and `end_line`)
- `unified_diff` - Apply unified diff format (currently replaces full buffer)

Response:
```json
{"success": true, "message": "Buffer replaced"}
```

## Testing

The `scripts/` directory contains bash scripts for testing:

### Ping Test

```bash
./scripts/ping.sh
```

### Get Buffer Content

```bash
./scripts/get_buffer.sh
```

### Apply Diff

Full replace with file:
```bash
./scripts/apply_diff.sh full_replace scripts/example_content.txt
```

Full replace with text:
```bash
./scripts/apply_diff.sh text "Hello, World!"
```

Line range replace:
```bash
./scripts/apply_diff.sh line_range scripts/example_content.txt 5 10
```

### Environment Variables

Scripts support the following environment variables:
- `NVIM_ASSIST_HOST` - Server host (default: 127.0.0.1)
- `NVIM_ASSIST_PORT` - Server port (default: 9999)

Example:
```bash
NVIM_ASSIST_PORT=8888 ./scripts/get_buffer.sh
```

## Example External Tool Integration

### Python

```python
import socket
import json

def send_command(command, data=None):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(("127.0.0.1", 9999))

    message = {"command": command}
    if data:
        message["data"] = data

    sock.sendall((json.dumps(message) + "\n").encode())
    response = sock.recv(4096).decode().strip()
    sock.close()

    return json.loads(response)

# Get buffer content
result = send_command("get_buffer")
print(result["data"]["content"])

# Apply diff
result = send_command("apply_diff", {
    "type": "full_replace",
    "content": "New content from Python"
})
print(result)
```

### Node.js

```javascript
const net = require('net');

function sendCommand(command, data) {
  return new Promise((resolve, reject) => {
    const client = net.createConnection({ host: '127.0.0.1', port: 9999 }, () => {
      const message = JSON.stringify({ command, data }) + '\n';
      client.write(message);
    });

    client.on('data', (data) => {
      resolve(JSON.parse(data.toString()));
      client.end();
    });

    client.on('error', reject);
  });
}

// Usage
(async () => {
  const buffer = await sendCommand('get_buffer');
  console.log(buffer.data.content);

  const result = await sendCommand('apply_diff', {
    type: 'full_replace',
    content: 'New content from Node.js'
  });
  console.log(result);
})();
```

## Logging

All server activity is logged to `nvim-assist.log` in your current working directory. This includes:
- Server start/stop events
- Client connections and disconnections
- Commands received
- Errors and warnings

You can customize the log file name:

```lua
require("nvim-assist").setup({
  log_file = "my-custom-log.log"
})
```

To monitor logs in real-time:

```bash
tail -f nvim-assist.log
```

## Requirements

- Neovim 0.5+
- `netcat` (nc) for bash test scripts
- `jq` (optional, for pretty-printing JSON in test scripts)

## License

MIT
