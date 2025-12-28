local M = {}

local opencode = require("nvim-assist.opencode")
local treesitter_util = require("nvim-assist.treesitter")
local server = require("nvim-assist.server")
local log = require("nvim-assist.log")

-- Namespace for virtual text
local ns_id = vim.api.nvim_create_namespace("nvim-assist")

-- Spinner frames for loading animation
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Helper to create a tracked extmark with virtual text
-- Returns the extmark ID which can be used to update or clear it later
local function create_tracked_virtual_text(bufnr, line, text)
	return vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
		virt_text = { { " " .. spinner_frames[1] .. " " .. text, "Comment" } },
		virt_text_pos = "eol",
	})
end

-- Helper to update virtual text using extmark ID
local function update_virtual_text(bufnr, extmark_id, text, spinner_index)
	local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, extmark_id, {})
	if pos and #pos > 0 then
		local spinner = spinner_index and spinner_frames[spinner_index] or ""
		local prefix = spinner_index and (spinner .. " ") or ""
		vim.api.nvim_buf_set_extmark(bufnr, ns_id, pos[1], pos[2], {
			id = extmark_id,
			virt_text = { { " " .. prefix .. text, "Comment" } },
			virt_text_pos = "eol",
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

-- Main assist function
function M.assist()
	log.info("Assist command invoked")

	-- Save buffer if modified
	if vim.bo.modified then
		vim.cmd("write")
		log.debug("Buffer saved")
	end

	-- Find function using treesitter
	local func_info, err = treesitter_util.find_function_at_cursor()
	if not func_info then
		log.error("Failed to find function: " .. (err or "unknown error"))
		return vim.notify("Failed to find function: " .. (err or "unknown error"), vim.log.levels.ERROR)
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local start_line = func_info.start_line -- 0-indexed
	local end_line = func_info.end_line -- 0-indexed
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local original_lines_count = end_line - start_line + 1

	-- Capture the function content immediately to protect against buffer changes
	local function_lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
	local function_content = table.concat(function_lines, "\n")

	log.debug(
		string.format(
			"Found function at lines %d-%d in buffer %d (%s), original lines: %d",
			start_line + 1,
			end_line + 1,
			bufnr,
			filepath,
			original_lines_count
		)
	)
	log.debug(string.format("Captured function content: %s", function_content:sub(1, 100)))

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

		-- Create tracked virtual text (extmark will follow the line even if content is added/removed above)
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

		-- Send prompt to OpenCode with instructions
		local prompt_text = string.format(
			[[Implement the following function in buffer %d (file: %s).

IMPORTANT: The function to implement is:
```
%s
```

Use the editor tools with socket path: %s

Steps:
1. Use editor_list_buffers with socketPath to verify the buffer exists
2. Use editor_get_buffer with socketPath and bufnr to read the entire buffer
3. Find the EXACT function shown above in the buffer (it may have moved from its original position)
4. Implement the function body based on the function signature and any comments
5. Use editor_replace_text with socketPath and bufnr to replace ONLY that specific function

CRITICAL: Search for the exact function content shown above, do NOT rely on line numbers as the buffer may have changed.
Be sure to preserve the exact indentation and function signature.]],
			bufnr,
			filepath,
			function_content,
			socket_path
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
