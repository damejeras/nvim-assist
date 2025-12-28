local M = {}
local server = require("nvim-assist.server")
local opencode = require("nvim-assist.opencode")
local assist = require("nvim-assist.assist")
local log = require("nvim-assist.log")

-- Default configuration
M.config = {
	agent_name = "assistant",
	provider_id = "openrouter",
	model_id = "moonshotai/kimi-k2",
}

-- Setup function
function M.setup(opts)
	opts = opts or {}

	-- Merge user config with defaults
	M.config = vim.tbl_deep_extend("force", M.config, opts)

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

	-- Auto-stop server on Vim exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("NvimAssistAutoStop", { clear = true }),
		callback = function()
			opencode.stop()
			server.stop()
		end,
	})

	-- Create :Assist command
	vim.api.nvim_create_user_command("Assist", function()
		assist.assist()
	end, {})

	-- Create :AssistLog command to tail log file
	vim.api.nvim_create_user_command("AssistLog", function()
		log.tail_log()
	end, {})
end

return M
