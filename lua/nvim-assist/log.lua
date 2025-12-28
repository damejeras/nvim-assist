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
	-- Don't open the file immediately, we'll do it lazily on first write
end

-- Internal function to write log message
local function write_log(level_name, msg)
	if not log_path then
		return
	end

	-- Open log file lazily
	if not log_file then
		local base_dir = vim.fn.fnamemodify(log_path, ":h")
		vim.fn.mkdir(base_dir, "p")
		log_file = io.open(log_path, "a")
	end

	if log_file then
		local timestamp = os.date("%Y-%m-%d %H:%M:%S")
		local log_msg = string.format("[%s] [%s] %s\n", timestamp, level_name, msg)
		log_file:write(log_msg)
		log_file:flush()
	end
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

-- Open log file in a split with tail -f
function M.tail_log()
	if not log_path then
		vim.notify("Log file not initialized", vim.log.levels.WARN)
		return
	end

	vim.cmd("split")
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, bufnr)

	vim.fn.termopen("tail -f " .. vim.fn.shellescape(log_path))

	-- Set buffer options to prevent filetype detection
	vim.bo[bufnr].filetype = ""
	vim.bo[bufnr].buftype = "terminal"
end

return M
