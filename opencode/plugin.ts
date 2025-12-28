import { type Plugin, tool } from "@opencode-ai/plugin";
import { createConnection, Socket } from "net";

// ============================================================================
// NVIM-ASSIST CLIENT
// ============================================================================

/**
 * Send a command to nvim-assist server and get response
 */
async function sendCommand(
  socketPath: string,
  command: string,
  data?: any,
): Promise<any> {
  return new Promise((resolve, reject) => {
    const socket: Socket = createConnection(socketPath, () => {
      const message = JSON.stringify({ command, data }) + "\n";
      socket.write(message);
    });

    let responseData = "";

    socket.on("data", (chunk) => {
      responseData += chunk.toString();
      // Check if we have a complete line
      if (responseData.includes("\n")) {
        socket.end();
      }
    });

    socket.on("end", () => {
      try {
        const response = JSON.parse(responseData.trim());
        if (response.success === false) {
          reject(new Error(response.error || "Command failed"));
        } else {
          resolve(response);
        }
      } catch (e) {
        reject(new Error(`Failed to parse response: ${responseData}`));
      }
    });

    socket.on("error", (err) => {
      reject(
        new Error(
          `Failed to connect to nvim-assist socket at ${socketPath}: ${err.message}`,
        ),
      );
    });

    socket.setTimeout(5000, () => {
      socket.destroy();
      reject(new Error("Connection timeout"));
    });
  });
}

// ============================================================================
// PLUGIN IMPLEMENTATION
// ============================================================================

export const NvimAssistPlugin: Plugin = async () => {
  // Get socket path from environment variable
  const socketPath = process.env.NVIM_ASSIST_SOCKET;

  if (!socketPath) {
    throw new Error("NVIM_ASSIST_SOCKET environment variable is not set");
  }

  return {
    tool: {
      editor_list_buffers: tool({
        description: `Lists all open buffers in Neovim.

Returns an array of buffer objects with:
- bufnr: Buffer number (use this with editor_get_buffer and editor_replace_text)
- filepath: Absolute path to the file

Usage:
- Use this to discover which files are open in Neovim
- Get the bufnr for buffers you want to read or modify
- Use editor_get_buffer with the bufnr to read specific buffer content
- Use editor_replace_text with the bufnr to modify specific buffers
- For files not in this list, use the regular Read tool`,
        args: {},
        async execute() {
          const response = await sendCommand(socketPath, "list_buffers");
          return JSON.stringify(response.data, null, 2);
        },
      }),

      editor_get_buffer: tool({
        description: `Gets buffer content from Neovim. Must be preferred over default Read tool, whenever possible.

Returns:
- bufnr: Buffer number
- content: Full buffer content as string
- filepath: Absolute path to the file

Usage:
- ALWAYS use editor_list_buffers first to get available buffer numbers
- Buffer number (bufnr) is REQUIRED - you must specify which buffer to read
- The content returned is always up-to-date with the buffer state
- This ensures explicit, intentional buffer access`,
        args: {
          bufnr: tool.schema.number().describe("Buffer number to read"),
        },
        async execute(args) {
          const response = await sendCommand(socketPath, "get_buffer", {
            bufnr: args.bufnr,
          });
          return JSON.stringify(response.data, null, 2);
        },
      }),

      editor_replace_text: tool({
        description: `Replaces text in a specific Neovim buffer using smart matching strategies.

This tool will detect conflicts and return informative errors when:
- oldString is not found in the buffer
- Multiple ambiguous matches are found
- Buffer is not valid or not loaded

Matching Strategies (tried in order):
1. Exact match
2. Line-trimmed match (ignores indentation differences)
3. Block anchor match (uses first/last lines with similarity scoring)
4. Multi-occurrence match

Error Handling:
- "oldString not found in content" - Text cannot be found
- "Found multiple matches for oldString. Provide more surrounding lines..." - Ambiguous match, needs more context
- "oldString and newString must be different" - Validation error
- "Buffer X is not valid/loaded" - Invalid buffer number

Usage:
- ALWAYS use editor_list_buffers first to get available buffer numbers
- ALWAYS use editor_get_buffer to read the target buffer before replacing
- Buffer number (bufnr) is REQUIRED - you must specify which buffer to modify
- When replacing text, preserve exact content as it appears in the buffer
- If you get a "multiple matches" error, provide more surrounding lines in oldString to make it unique
- This ensures explicit, intentional buffer modifications`,
        args: {
          bufnr: tool.schema.number().describe("Buffer number to modify"),
          oldString: tool.schema
            .string()
            .describe("The text to find and replace"),
          newString: tool.schema
            .string()
            .describe(
              "The replacement text (must be different from oldString)",
            ),
          replaceAll: tool.schema
            .boolean()
            .optional()
            .describe("Replace all occurrences (default: false)"),
        },
        async execute(args) {
          await sendCommand(socketPath, "replace_text", {
            bufnr: args.bufnr,
            old_string: args.oldString,
            new_string: args.newString,
            replace_all: args.replaceAll ?? false,
          });

          return `Successfully replaced text in buffer ${args.bufnr}`;
        },
      }),
    },
  };
};

export default NvimAssistPlugin;
