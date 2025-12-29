local M = {}
local opencode = require("nvim-assist.opencode")
local log = require("nvim-assist.log")
local ui = require("nvim-assist.ui")
local prompts = require("nvim-assist.prompts")

-- Default configuration
M.config = {
	opencode = {
		agent = "nvim-assist",
		provider = "openrouter",
		model = "moonshotai/kimi-k2",
		auto_delete_idle_sessions = true, -- Auto-delete sessions when they go idle
	},
}

-- Internal function that actually runs the assist
local function run_assist(bufnr, filepath, start_line, end_line, content, user_prompt)
	-- Ensure OpenCode server is running
	opencode.start(function(port)
		if not port then
			log.error("Failed to get OpenCode server port")
			return vim.notify("Failed to get OpenCode server port", vim.log.levels.ERROR)
		end

		log.info("OpenCode server running on port " .. port)

		local cwd = vim.fn.getcwd()

		-- Create OpenCode session with configured agent
		local session = opencode.create_session(port, cwd, M.config.opencode.agent)
		if not session then
			return vim.notify("Failed to create OpenCode session", vim.log.levels.ERROR)
		end

		-- Create tracked virtual line above the selection
		local extmark_id = ui.create_tracked_virtual_text(bufnr, start_line, "Starting implementation...")

		-- Track current text for spinner updates
		local current_text = "Starting implementation..."

		-- Animate the spinner
		local timer = ui.create_spinner(bufnr, extmark_id, function()
			return current_text
		end)

		-- Get the full buffer content to provide context
		local full_buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local full_buffer_content = table.concat(full_buffer, "\n")

		-- Build the AI prompt
		local prompt_text = prompts.build_code_modification_prompt({
			user_prompt = user_prompt,
			filepath = filepath,
			bufnr = bufnr,
			full_buffer_content = full_buffer_content,
			code_section = content,
		})

		-- Send prompt asynchronously
		local success = opencode.send_prompt_async(
			port,
			session.id,
			cwd,
			prompt_text,
			M.config.opencode.provider,
			M.config.opencode.model
		)

		if not success then
			timer:stop()
			timer:close()
			ui.clear_virtual_text(bufnr, extmark_id)
			return
		end

		current_text = "Analyzing function..."

		-- Subscribe to OpenCode events to update UI and track completion
		opencode.subscribe_to_events(port, session.id, function(event, session_id)
			-- Update virtual text based on events
			if event.payload.type == "message.part.updated" and event.payload.properties then
				local part = event.payload.properties.part
				if part and part.sessionID == session.id then
					-- Update virtual text based on part type
					if part.type == "tool" and part.tool then
						current_text = string.format("Running %s", part.tool)
					elseif part.type == "text" then
						current_text = "Thinking..."
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

					-- Auto-delete idle sessions if configured
					if M.config.opencode.auto_delete_idle_sessions then
						opencode.delete_session(port, session.id)
					end
				end
			end
		end)
	end)
end

-- Main assist function
-- Works with visual selection (via range) or entire buffer
-- line1, line2: optional range from command (1-indexed)
local function assist(custom_prompt, line1, line2)
	log.info("Assist command invoked")

	local bufnr = vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	local start_line, end_line

	-- If range was provided from command, use it
	if line1 and line2 then
		start_line = line1 - 1 -- Convert to 0-indexed
		end_line = line2 - 1
	else
		-- No range, use entire buffer
		start_line = 0
		end_line = vim.api.nvim_buf_line_count(bufnr) - 1
	end

	-- Capture the content immediately to protect against buffer changes
	local content_lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
	local content = table.concat(content_lines, "\n")

	log.debug(
		string.format("Working with lines %d-%d in buffer %d (%s)", start_line + 1, end_line + 1, bufnr, filepath)
	)
	log.debug(string.format("Captured content: %s", content:sub(1, 100)))

	-- Highlight the region
	local highlight_marks = ui.highlight_region(bufnr, start_line, end_line)
	vim.cmd("redraw")

	-- If no custom prompt provided, ask user
	if not custom_prompt then
		vim.ui.input({
			prompt = "Task: ",
			default = "",
		}, function(input)
			-- Clear highlights
			ui.clear_region_highlights(bufnr, highlight_marks)

			if not input or input == "" then
				log.debug("User cancelled assist")
				return
			end

			-- Continue with the prompt
			run_assist(bufnr, filepath, start_line, end_line, content, input)
		end)
	else
		-- Clear highlights and continue immediately
		ui.clear_region_highlights(bufnr, highlight_marks)
		run_assist(bufnr, filepath, start_line, end_line, content, custom_prompt)
	end
end

-- Setup function
function M.setup(opts)
	opts = opts or {}

	-- Merge user config with defaults
	M.config = vim.tbl_deep_extend("force", M.config, opts)

	-- Initialize logging
	local temp_dir = os.getenv("TMPDIR") or "/tmp"
	local base_dir = temp_dir .. "/nvim-assist"
	vim.fn.mkdir(base_dir, "p")
	local log_path = base_dir .. "/nvim-assist.log"
	log.init(log_path)

	-- Create single autocommand group for all nvim-assist autocmds
	local augroup = vim.api.nvim_create_augroup("NvimAssist", { clear = true })

	-- Auto-stop OpenCode server and close log on Vim exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = augroup,
		callback = function()
			opencode.stop()
			log.close()
		end,
	})

	-- Create :AssistLog command to tail log file
	vim.api.nvim_create_user_command("AssistLog", function()
		log.tail_log()
	end, {})

	-- Create :Assist command to work with visual selections or entire buffer
	vim.api.nvim_create_user_command("Assist", function(opts)
		local custom_prompt = opts.args ~= "" and opts.args or nil
		local line1 = opts.range > 0 and opts.line1 or nil
		local line2 = opts.range > 0 and opts.line2 or nil
		assist(custom_prompt, line1, line2)
	end, {
		nargs = "?",
		range = true,
		desc = "Send selection or buffer to AI assistant",
	})
end

return M
