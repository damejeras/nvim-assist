local M = {}

local opencode = require("nvim-assist.opencode")
local treesitter_util = require("nvim-assist.treesitter")
local server = require("nvim-assist.server")
local log = require("nvim-assist.log")
local ui = require("nvim-assist.ui")

-- Get config from init module
local function get_config()
	local init = require("nvim-assist.init")
	return init.config
end

-- Handle text object modification
-- query_string: treesitter query like "@function.inner" or "@function.outer"
function M.modify_textobj(query_string)
	local bufnr = vim.api.nvim_get_current_buf()

	-- Get the treesitter range for the text object
	local node = treesitter_util.get_node_at_cursor(query_string)
	if not node then
		vim.notify("No " .. query_string .. " found at cursor", vim.log.levels.WARN)
		return
	end

	local start_row, _, end_row, _ = node:range()

	-- Highlight the region
	local highlight_marks = ui.highlight_region(bufnr, start_row, end_row)

	-- Force redraw to show highlights before input prompt
	vim.cmd("redraw")

	-- Prompt user for what to do
	vim.ui.input({
		prompt = "AI Task: ",
		default = "",
	}, function(input)
		-- Clear highlights
		ui.clear_region_highlights(bufnr, highlight_marks)

		if not input or input == "" then
			log.debug("User cancelled text object modification")
			return
		end

		-- Call assist with the selection and custom prompt
		M.assist(start_row, end_row, input)
	end)
end

-- Main assist function with custom prompt and selection
-- If no parameters provided, uses cursor position to find function
function M.assist(start_line, end_line, custom_prompt)
	log.info("Assist command invoked")

	local bufnr = vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	-- If no selection provided, find function at cursor
	if not start_line or not end_line then
		local func_info, err = treesitter_util.find_function_at_cursor()
		if not func_info then
			log.error("Failed to find function: " .. (err or "unknown error"))
			return vim.notify("Failed to find function: " .. (err or "unknown error"), vim.log.levels.ERROR)
		end
		start_line = func_info.start_line -- 0-indexed
		end_line = func_info.end_line -- 0-indexed
	end

	-- Capture the content immediately to protect against buffer changes
	local content_lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
	local content = table.concat(content_lines, "\n")

	log.debug(
		string.format(
			"Working with lines %d-%d in buffer %d (%s)",
			start_line + 1,
			end_line + 1,
			bufnr,
			filepath
		)
	)
	log.debug(string.format("Captured content: %s", content:sub(1, 100)))

	-- Determine the prompt
	local user_prompt = custom_prompt or "Implement this function"

	-- Ensure OpenCode server is running
	opencode.start(function(port)
		if not port then
			log.error("Failed to get OpenCode server port")
			return vim.notify("Failed to get OpenCode server port", vim.log.levels.ERROR)
		end

		log.info("OpenCode server running on port " .. port)

		local cwd = vim.fn.getcwd()
		local config = get_config()

		-- Create OpenCode session with configured agent
		local session = opencode.create_session(port, cwd, config.opencode.agent)
		if not session then
			return vim.notify("Failed to create OpenCode session", vim.log.levels.ERROR)
		end

		-- Create tracked virtual line above the selection
		local extmark_id = ui.create_tracked_virtual_text(bufnr, start_line, "AI: Starting implementation...")

		-- Track current text for spinner updates
		local current_text = "AI: Starting implementation..."

		-- Animate the spinner
		local timer = ui.create_spinner(bufnr, extmark_id, function()
			return current_text
		end)

		-- Get nvim-assist socket path
		local socket_path = server.get_socket_path()

		-- Get the full buffer content to provide context
		local full_buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local full_buffer_content = table.concat(full_buffer, "\n")

		-- Send prompt to OpenCode with instructions
		local prompt_text = string.format(
			[[Task: %s

File: %s
Buffer ID: %d
Editor Socket Path: %s

Current buffer content:
```
%s
```

The specific code section to modify:
```
%s
```

Instructions:
1. Find the EXACT code section shown above in the buffer (it may have moved from its original position)
2. Make the changes as requested in the task
3. Use editor_replace_text with socketPath=%s and bufnr=%d to replace ONLY that specific code section

CRITICAL:
- Search for the exact code content shown in "The specific code section to modify"
- Do NOT rely on line numbers as the buffer may have changed
- Preserve indentation and formatting unless the task specifically requires changing it
- If you need to refresh the buffer content, use editor_get_buffer with the socketPath and bufnr]],
			user_prompt,
			filepath,
			bufnr,
			socket_path,
			full_buffer_content,
			content,
			socket_path,
			bufnr
		)

		-- Send prompt asynchronously
		local success = opencode.send_prompt_async(
			port,
			session.id,
			cwd,
			prompt_text,
			config.opencode.provider,
			config.opencode.model
		)

		if success then
			current_text = "AI: Analyzing function..."
		else
			timer:stop()
			timer:close()
			ui.clear_virtual_text(bufnr, extmark_id)
			return
		end

		-- Subscribe to OpenCode events to update UI and track completion
		opencode.subscribe_to_events(port, session.id, function(event, session_id)
			-- Update virtual text based on events
			if event.payload.type == "message.part.updated" and event.payload.properties then
				local part = event.payload.properties.part
				if part and part.sessionID == session.id then
					-- Update virtual text based on part type
					if part.type == "tool" and part.tool then
						current_text = string.format("AI: Running %s", part.tool)
					elseif part.type == "text" then
						current_text = "AI: Thinking..."
					end
				end
			elseif event.payload.type == "session.idle" and event.payload.properties then
				-- Session completed
				local sessionID = event.payload.properties.sessionID
				if sessionID == session.id then
					timer:stop()
					timer:close()
					ui.clear_virtual_text(bufnr, extmark_id)
					log.info("Session completed")
				end
			end
		end)
	end)
end

return M
