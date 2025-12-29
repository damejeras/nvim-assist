import { type Plugin, tool } from "@opencode-ai/plugin";
import { attach, type NeovimClient } from "neovim";
import { Socket } from "net";

// ============================================================================
// NVIM CLIENT
// ============================================================================

/**
 * Connect to Neovim via msgpack-rpc
 */
async function connectToNvim(): Promise<NeovimClient> {
  const socketPath = process.env.NVIM;

  if (!socketPath) {
    throw new Error("NVIM environment variable is not set");
  }

  return new Promise((resolve, reject) => {
    const socket = new Socket();

    socket.on("connect", () => {
      const nvim = attach({ reader: socket, writer: socket });
      resolve(nvim);
    });

    socket.on("error", (err) => {
      reject(new Error(`Failed to connect to Neovim at ${socketPath}: ${err.message}`));
    });

    socket.connect(socketPath);
  });
}

// ============================================================================
// PLUGIN IMPLEMENTATION
// ============================================================================

export const NvimAssistPlugin: Plugin = async () => {
  // Connect to Neovim once on plugin initialization
  const nvim = await connectToNvim();

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
          const result = await nvim.lua(
            `
            local buffer = require("nvim-assist.buffer")
            return buffer.list_buffers()
            `,
            []
          );

          return JSON.stringify(result, null, 2);
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
          const result = await nvim.lua(
            `
            local buffer = require("nvim-assist.buffer")
            return buffer.get_buffer_content(...)
            `,
            [args.bufnr]
          );

          // Check for errors from Lua function
          if (result && Array.isArray(result) && result[1] === null) {
            throw new Error(result[2] || "Failed to get buffer content");
          }

          return JSON.stringify(result, null, 2);
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
- "old_string not found in content" - Text cannot be found
- "Found multiple matches for old_string. Provide more surrounding lines..." - Ambiguous match, needs more context
- "old_string and new_string must be different" - Validation error
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
          // Call the custom Lua function via lua API
          const result = await nvim.lua(
            `
            local buffer = require("nvim-assist.buffer")
            return buffer.replace_text(...)
            `,
            [
              {
                bufnr: args.bufnr,
                old_string: args.oldString,
                new_string: args.newString,
                replace_all: args.replaceAll ?? false,
              },
            ]
          );

          // Check for errors from Lua function
          if (result && typeof result === "object" && result.success === false) {
            throw new Error(result.error || "Failed to replace text");
          }

          return `Successfully replaced text in buffer ${args.bufnr}`;
        },
      }),
    },
  };
};

export default NvimAssistPlugin;
