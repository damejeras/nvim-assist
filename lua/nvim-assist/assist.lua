local M = {}

local opencode = require("nvim-assist.opencode")
local treesitter_util = require("nvim-assist.treesitter")
local server = require("nvim-assist.server")
local log = require("nvim-assist.log")

-- Namespace for virtual text
local ns_id = vim.api.nvim_create_namespace("nvim-assist")

-- Spinner frames for loading animation
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Helper to create a tracked extmark with virtual line
-- Returns the extmark ID which can be used to update or clear it later
local function create_tracked_virtual_text(bufnr, line, text)
	return vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
		virt_lines = { { { spinner_frames[1] .. " " .. text, "Comment" } } },
		virt_lines_above = true,
		invalidate = true, -- Clear extmark when the line is deleted/modified
	})
end

-- Helper to update virtual line using extmark ID
local function update_virtual_text(bufnr, extmark_id, text, spinner_index)
	local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
	if pos and #pos > 0 then
		local spinner = spinner_index and spinner_frames[spinner_index] or ""
		local prefix = spinner_index and (spinner .. " ") or ""
		vim.api.nvim_buf_set_extmark(bufnr, ns_id, pos[1], pos[2], {
			id = extmark_id,
			virt_lines = { { { prefix .. text, "Comment" } } },
			virt_lines_above = true,
			invalidate = true,
		})
	end
end

-- Helper to clear virtual text using extmark ID
local function clear_virtual_text(bufnr, extmark_id)
	pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, extmark_id)
end

-- Get config from init module
local function get_config()
	local init = require("nvim-assist.init")
	return init.config
end

-- Helper to highlight a region
local function highlight_region(bufnr, start_line, end_line)
	local extmarks = {}
	for line = start_line, end_line do
		-- Get the line length to properly set end_col
		local line_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
		local line_length = #line_text

		local mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
			end_line = line,
			end_col = line_length,
			hl_group = "Visual",
			hl_eol = true,
		})
		table.insert(extmarks, mark_id)
	end
	return extmarks
end

-- Helper to clear region highlights
local function clear_region_highlights(bufnr, extmarks)
	for _, mark_id in ipairs(extmarks) do
		pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, mark_id)
	end
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
	local highlight_marks = highlight_region(bufnr, start_row, end_row)

	-- Force redraw to show highlights before input prompt
	vim.cmd("redraw")

	-- Prompt user for what to do
	vim.ui.input({
		prompt = "AI Task: ",
		default = "",
	}, function(input)
		-- Clear highlights
		clear_region_highlights(bufnr, highlight_marks)

		if not input or input == "" then
			log.debug("User cancelled text object modification")
			return
		end

		-- Call assist with the selection and custom prompt
		M.assist(start_row, end_row, input)
	end)
end

-- URL encode helper
local function url_encode(str)
	return string.gsub(str, "([^%w%-%.%_%~%/])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
end

-- Make HTTP request to OpenCode server
local function request(port, method, path, body, allow_empty)
	-- Add -w flag to get HTTP status code
	local cmd = string.format("curl -s -w '\\n%%{http_code}' -X %s 'http://localhost:%d%s'", method, port, path)

	if body then
		local json = vim.fn.json_encode(next(body) == nil and vim.empty_dict() or body)
		cmd = cmd .. string.format(" -H 'Content-Type: application/json' -d '%s'", json:gsub("'", "'\\''"))
		log.debug(string.format("Request body: %s", json:sub(1, 500)))
	end

	log.debug(string.format("Executing: curl -X %s http://localhost:%d%s", method, port, path))

	local result = vim.fn.system(cmd)
	local exit_code = vim.v.shell_error

	if exit_code ~= 0 then
		log.error(string.format("curl failed with exit code %d", exit_code))
		log.error(string.format("Response: %s", result:sub(1, 500)))
		return nil
	end

	-- Split response body and HTTP status code
	local lines = vim.split(result, "\n", { plain = true })
	local http_code = tonumber(lines[#lines])
	local response_body = table.concat(vim.list_slice(lines, 1, #lines - 1), "\n")

	log.debug(string.format("HTTP Status: %d", http_code or 0))

	-- Check HTTP status code
	if not http_code or http_code < 200 or http_code >= 300 then
		log.error(string.format("HTTP error %d", http_code or 0))
		log.error(string.format("Response: %s", response_body:sub(1, 500)))
		return nil
	end

	-- Empty response is OK for async endpoints or if explicitly allowed
	if response_body == "" or response_body:match("^%s*$") then
		if allow_empty then
			log.debug("Empty response (OK for async endpoint)")
			return true -- Return a truthy value to indicate success
		else
			log.error("Empty response from OpenCode server")
			return nil
		end
	end

	local ok, decoded = pcall(vim.fn.json_decode, response_body)
	if not ok then
		log.error(string.format("Failed to parse JSON response: %s", response_body:sub(1, 500)))
		return nil
	end

	log.debug(string.format("Response: %s", vim.fn.json_encode(decoded):sub(1, 500)))
	return decoded
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
		log.info("Creating OpenCode session with agent: " .. config.agent_name)
		local session = request(port, "POST", "/session?directory=" .. url_encode(cwd), {
			agentName = config.agent_name,
		})
		if not session or not session.id then
			log.error("Failed to create OpenCode session")
			return vim.notify("Failed to create OpenCode session", vim.log.levels.ERROR)
		end

		log.info(string.format("OpenCode session created: %s (agent: %s)", session.id, config.agent_name))

		-- Create tracked virtual line above the selection
		-- virt_lines_above will automatically place it above the start_line
		local extmark_id = create_tracked_virtual_text(bufnr, start_line, "AI: Starting implementation...")

		-- Animate the spinner
		local spinner_index = 1
		local current_text = "AI: Starting implementation..."
		local timer = vim.loop.new_timer()
		timer:start(
			100,
			100,
			vim.schedule_wrap(function()
				spinner_index = (spinner_index % #spinner_frames) + 1
				update_virtual_text(bufnr, extmark_id, current_text, spinner_index)
			end)
		)

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

		log.info("Sending prompt to OpenCode session " .. session.id)
		log.debug(string.format("Model: %s/%s", config.provider_id, config.model_id))
		log.debug("Prompt: " .. prompt_text:gsub("\n", " "):sub(1, 200) .. "...")

		local response = request(
			port,
			"POST",
			string.format("/session/%s/prompt_async?directory=%s", session.id, url_encode(cwd)),
			{
				parts = {
					{
						type = "text",
						text = prompt_text,
					},
				},
				model = {
					providerID = config.provider_id,
					modelID = config.model_id,
				},
			},
			true -- Allow empty response for async endpoint
		)

		if response then
			log.info("Prompt sent successfully")
			current_text = "AI: Analyzing function..."
			update_virtual_text(bufnr, extmark_id, current_text, spinner_index)
		else
			log.error("Failed to send prompt to OpenCode")
			timer:stop()
			timer:close()
			clear_virtual_text(bufnr, extmark_id)
			return
		end

		-- Subscribe to OpenCode events to log session activity
		log.debug("Subscribing to OpenCode events for session " .. session.id)
		vim.fn.jobstart(string.format("curl -s -N http://localhost:%d/global/event", port), {
			on_stdout = function(_, data)
				if not data then
					return
				end

				for _, line in ipairs(data) do
					if line == "" or not line:match("^data:") then
						goto continue
					end

					local json_str = line:gsub("^data:%s*", "")
					local ok, event = pcall(vim.fn.json_decode, json_str)

					if not ok or not event or not event.payload then
						goto continue
					end

					-- Update virtual text based on events
					vim.schedule(function()
						if event.payload.type == "message.part.updated" and event.payload.properties then
							local part = event.payload.properties.part
							if part and part.sessionID == session.id then
								-- Update virtual text based on part type
								if part.type == "tool" and part.tool then
									current_text = string.format("AI: Running %s", part.tool)
									update_virtual_text(bufnr, extmark_id, current_text, spinner_index)
								elseif part.type == "text" then
									current_text = "AI: Thinking..."
									update_virtual_text(bufnr, extmark_id, current_text, spinner_index)
								end
							end
						elseif event.payload.type == "session.idle" and event.payload.properties then
							-- Session completed
							local sessionID = event.payload.properties.sessionID
							if sessionID == session.id then
								timer:stop()
								timer:close()
								clear_virtual_text(bufnr, extmark_id)
								log.info("Session completed")
							end
						end
					end)

					::continue::
				end
			end,
			on_stderr = function(_, data)
				if data then
					for _, line in ipairs(data) do
						if line ~= "" then
							log.warn(string.format("curl stderr: %s", line))
						end
					end
				end
			end,
			on_exit = function(_, exit_code, _)
				log.debug(string.format("OpenCode event stream closed (exit code: %d)", exit_code))
				vim.schedule(function()
					timer:stop()
					timer:close()
					clear_virtual_text(bufnr, extmark_id)
				end)
			end,
		})
	end)
end

return M
