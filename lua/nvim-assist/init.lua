local M = {}
local server = require("nvim-assist.server")
local opencode = require("nvim-assist.opencode")
local assist = require("nvim-assist.assist")
local log = require("nvim-assist.log")

-- Default configuration
M.config = {
	agent_name = "build",
	provider_id = "openrouter",
	model_id = "moonshotai/kimi-k2",
	-- Set to false to disable automatic text object mappings
	enable_text_objects = true,
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

	-- Register treesitter text object mappings with 'm' prefix
	-- These work like vim-textobj and nvim-treesitter-textobjects
	if M.config.enable_text_objects then
		local text_objects = {
			{ key = "mif", query = "@function.inner", desc = "Modify inner function" },
			{ key = "maf", query = "@function.outer", desc = "Modify around function" },
			{ key = "mic", query = "@class.inner", desc = "Modify inner class" },
			{ key = "mac", query = "@class.outer", desc = "Modify around class" },
			{ key = "mib", query = "@block.inner", desc = "Modify inner block" },
			{ key = "mab", query = "@block.outer", desc = "Modify around block" },
			{ key = "mio", query = "@conditional.inner", desc = "Modify inner conditional" },
			{ key = "mao", query = "@conditional.outer", desc = "Modify around conditional" },
			{ key = "mil", query = "@loop.inner", desc = "Modify inner loop" },
			{ key = "mal", query = "@loop.outer", desc = "Modify around loop" },
		}

		for _, obj in ipairs(text_objects) do
			vim.keymap.set("n", obj.key, function()
				assist.modify_textobj(obj.query)
			end, { desc = obj.desc, silent = true })
		end
	end
end

return M
