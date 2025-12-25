local M = {}
local server = require("nvim-assist.server")
local handlers = require("nvim-assist.handlers")

-- Setup function
function M.setup(opts)
	opts = opts or {}

	-- Configure server
	server.configure({
		host = opts.host,
		port = opts.port,
		log_file = opts.log_file,
	})

	-- Set message handler
	server.set_message_handler(handlers.handle_message)

	-- Create restart command
	vim.api.nvim_create_user_command("AssistRestart", function()
		server.restart()
	end, {})

	-- Auto-start server on first buffer
	vim.api.nvim_create_autocmd("BufEnter", {
		group = vim.api.nvim_create_augroup("NvimAssistAutoStart", { clear = true }),
		callback = function()
			if not server.is_running() then
				server.start()
			end
		end,
		once = true,
	})

	-- Auto-stop server on Vim exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("NvimAssistAutoStop", { clear = true }),
		callback = function()
			server.stop()
		end,
	})
end

return M
