local M = {}

---@type file*? # File handle for log file
local log_file = nil

---@type string? # Absolute path to log file
local log_path = nil

---Log levels for filtering messages
local LOG_LEVELS = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
}

---@type number # Current minimum log level (1=DEBUG, 2=INFO, 3=WARN, 4=ERROR)
local current_level = LOG_LEVELS.DEBUG

---Initialize the logger with a log file path
---Creates log directory if it doesn't exist and opens file for appending
---@param path string Absolute path to log file
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

---Write log message with timestamp and level
---@param level_name string Log level name for formatting (e.g., "DEBUG", "INFO")
---@param msg string Message to write
local function write_log(level_name, msg)
	if not log_file then
		return
	end

	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	local log_msg = string.format("[%s] [%s] %s\n", timestamp, level_name, msg)
	log_file:write(log_msg)
	log_file:flush()
end

---Write a debug-level log message
---Only written if current log level is DEBUG or lower
---@param msg string Message to log
function M.debug(msg)
	if LOG_LEVELS.DEBUG >= current_level then
		write_log("DEBUG", msg)
	end
end

---Write an info-level log message
---Only written if current log level is INFO or lower
---@param msg string Message to log
function M.info(msg)
	if LOG_LEVELS.INFO >= current_level then
		write_log("INFO", msg)
	end
end

---Write a warning-level log message
---Only written if current log level is WARN or lower
---@param msg string Message to log
function M.warn(msg)
	if LOG_LEVELS.WARN >= current_level then
		write_log("WARN", msg)
	end
end

---Write an error-level log message
---Only written if current log level is ERROR or lower
---@param msg string Message to log
function M.error(msg)
	if LOG_LEVELS.ERROR >= current_level then
		write_log("ERROR", msg)
	end
end

---Set the minimum log level for filtering
---@param level string|number Log level name ("DEBUG", "INFO", "WARN", "ERROR") or numeric value (1-4)
function M.set_level(level)
	if type(level) == "string" then
		current_level = LOG_LEVELS[level:upper()] or LOG_LEVELS.DEBUG
	elseif type(level) == "number" then
		current_level = level
	end
end

---Close the log file
---Flushes and closes the file handle
function M.close()
	if log_file then
		log_file:close()
		log_file = nil
	end
end

---Get the current log file path
---@return string|nil # Absolute path to log file, or nil if not initialized
function M.get_path()
	return log_path
end

---Open log file in a split with auto-reload
---Creates a split window that auto-refreshes and jumps to end on updates
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
