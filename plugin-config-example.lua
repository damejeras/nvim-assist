-- Example configuration for nvim-assist
-- Copy this to your Neovim config (init.lua or lazy.nvim spec)

-- For lazy.nvim:
return {
	dir = "/path/to/nvim-assist", -- Change to your local path, or use your repo URL
	config = function()
		require("nvim-assist").setup({
			host = "127.0.0.1", -- Server host (default: 127.0.0.1)
			port = 9999, -- Server port (default: 9999)
			log_file = "nvim-assist.log", -- Log file name in cwd (default: nvim-assist.log)
		})
	end,
}

-- For init.lua (without plugin manager):
-- require("nvim-assist").setup({
--     host = "127.0.0.1",
--     port = 9999,
--     log_file = "nvim-assist.log",
-- })

-- Server Management:
-- The server automatically starts when you open the first buffer
-- and stops when you exit Neovim. All activity is logged to the log file.
--
-- Manual control:
-- :AssistRestart - Restart the server (only command needed)
