local M = {}
local server = require("nvim-assist.server")
local handlers = require("nvim-assist.handlers")
local opencode = require("nvim-assist.opencode")
local assist = require("nvim-assist.assist")

-- Setup function
function M.setup(opts)
	opts = opts or {}

	-- Set message handler
	server.set_message_handler(handlers.handle_message)

	-- Create restart command
	vim.api.nvim_create_user_command("AssistRestart", function()
		server.restart()
	end, {})

	-- Create command to get session info
	vim.api.nvim_create_user_command("AssistInfo", function()
		local session_id = server.get_session_id()
		local socket_path = server.get_socket_path()
		local log_path = server.get_log_path()
		local opencode_port = opencode.get_port()

		server.log("AssistInfo requested")
		server.log("  Session: " .. session_id)
		server.log("  Socket: " .. socket_path)
		server.log("  Log: " .. log_path)

		if opencode_port then
			server.log("  OpenCode: http://localhost:" .. opencode_port)
		else
			server.log("  OpenCode: not running")
		end

		-- Also print to user for convenience
		print("[nvim-assist] Session: " .. session_id)
		print("[nvim-assist] Socket: " .. socket_path)
		print("[nvim-assist] Log: " .. log_path)
		if opencode_port then
			print("[nvim-assist] OpenCode: http://localhost:" .. opencode_port)
		else
			print("[nvim-assist] OpenCode: not running")
		end

		-- Set environment variable for child processes
		vim.fn.setenv("NVIM_ASSIST_SOCKET", socket_path)
	end, {})

	-- Create :Assist command
	vim.api.nvim_create_user_command("Assist", function()
		assist.assist()
	end, {})

	-- Create :AssistLog command to tail log file
	vim.api.nvim_create_user_command("AssistLog", function()
		local log_path = server.get_log_path()

		-- Create a new split window
		vim.cmd("split")
		local win = vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(win, buf)

		-- Set buffer options
		vim.api.nvim_buf_set_name(buf, "nvim-assist-log")
		vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
		vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
		vim.api.nvim_buf_set_option(buf, "swapfile", false)
		vim.api.nvim_buf_set_option(buf, "modifiable", false)

		-- Use tail -f to follow the log file
		local job_id = vim.fn.termopen("tail -f " .. vim.fn.shellescape(log_path), {
			on_exit = function()
				-- Clean up when terminal exits
			end,
		})

		if job_id <= 0 then
			vim.notify("Failed to start log tail", vim.log.levels.ERROR)
		end
	end, {})

	-- Check if a buffer is already loaded and start server immediately
	local buffers = vim.api.nvim_list_bufs()
	local has_loaded_buffer = false
	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_loaded(buf) then
			has_loaded_buffer = true
			break
		end
	end

	if has_loaded_buffer then
		server.start()
		-- Set environment variable for child processes
		vim.fn.setenv("NVIM_ASSIST_SOCKET", server.get_socket_path())
	else
		-- Auto-start server on first buffer
		vim.api.nvim_create_autocmd("BufEnter", {
			group = vim.api.nvim_create_augroup("NvimAssistAutoStart", { clear = true }),
			callback = function()
				if not server.is_running() then
					server.start()
					-- Set environment variable for child processes
					vim.fn.setenv("NVIM_ASSIST_SOCKET", server.get_socket_path())
				end
			end,
			once = true,
		})
	end

	-- Auto-stop server on Vim exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("NvimAssistAutoStop", { clear = true }),
		callback = function()
			opencode.stop()
			server.stop()
		end,
	})
end

return M
