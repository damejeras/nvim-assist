local M = {}

local log_file = nil
local log_path = nil

-- Log levels
local LOG_LEVELS = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
}

-- Current log level (can be configured)
local current_level = LOG_LEVELS.DEBUG

-- Initialize the logger with a log file path
function M.init(path)
	log_path = path

	-- Create log directory if needed
	local base_dir = vim.fn.fnamemodify(path, ":h")
	vim.fn.mkdir(base_dir, "p")

	-- Open log file immediately
	log_file = io.open(path, "a")
	if not log_file then
		vim.notify("Failed to open log file: " .. path, vim.log.levels.WARN)
	end
end

-- Internal function to write log message
local function write_log(level_name, msg)
	if not log_file then
		return
	end

	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	local log_msg = string.format("[%s] [%s] %s\n", timestamp, level_name, msg)
	log_file:write(log_msg)
	log_file:flush()
end

-- Debug level logging
function M.debug(msg)
	if LOG_LEVELS.DEBUG >= current_level then
		write_log("DEBUG", msg)
	end
end

-- Info level logging
function M.info(msg)
	if LOG_LEVELS.INFO >= current_level then
		write_log("INFO", msg)
	end
end

-- Warning level logging
function M.warn(msg)
	if LOG_LEVELS.WARN >= current_level then
		write_log("WARN", msg)
	end
end

-- Error level logging
function M.error(msg)
	if LOG_LEVELS.ERROR >= current_level then
		write_log("ERROR", msg)
	end
end

-- Set the minimum log level
function M.set_level(level)
	if type(level) == "string" then
		current_level = LOG_LEVELS[level:upper()] or LOG_LEVELS.DEBUG
	elseif type(level) == "number" then
		current_level = level
	end
end

-- Close the log file
function M.close()
	if log_file then
		log_file:close()
		log_file = nil
	end
end

-- Get the current log path
function M.get_path()
	return log_path
end

-- Open log file in a split with auto-reload
function M.tail_log()
	if not log_path then
		vim.notify("Log file not initialized", vim.log.levels.WARN)
		return
	end

	-- Open log file in a split
	vim.cmd("split " .. vim.fn.fnameescape(log_path))
	local bufnr = vim.api.nvim_get_current_buf()

	-- Enable autoread for this buffer
	vim.bo[bufnr].autoread = true

	-- Jump to end of file
	vim.cmd("normal! G")

	-- Set up autocommand to check for changes and jump to end
	local augroup = vim.api.nvim_create_augroup("NvimAssistLogTail", { clear = false })
	vim.api.nvim_create_autocmd({ "CursorHold", "FocusGained" }, {
		group = augroup,
		buffer = bufnr,
		callback = function()
			vim.cmd("checktime")
			vim.cmd("normal! G")
		end,
	})
end

return M
