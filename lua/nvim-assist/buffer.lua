local M = {}
local replace = require("nvim-assist.replace")

-- Get the current buffer's content and metadata
function M.get_current_content()
	local bufnr = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return {
		bufnr = bufnr,
		content = table.concat(lines, "\n"),
		lines = lines,
		filepath = vim.api.nvim_buf_get_name(bufnr),
	}
end

-- List all open buffers with their metadata
function M.list_buffers()
	local buffers = {}
	local bufs = vim.api.nvim_list_bufs()

	for _, bufnr in ipairs(bufs) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			local filepath = vim.api.nvim_buf_get_name(bufnr)
			local modified = vim.api.nvim_buf_get_option(bufnr, "modified")
			local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
			local listed = vim.api.nvim_buf_get_option(bufnr, "buflisted")

			-- Only include normal file buffers (not help, quickfix, etc.)
			if buftype == "" and listed then
				table.insert(buffers, {
					bufnr = bufnr,
					filepath = filepath,
					modified = modified,
					is_current = bufnr == vim.api.nvim_get_current_buf(),
				})
			end
		end
	end

	return buffers
end

-- Replace text in buffer using smart matching strategies
function M.replace_text(replace_data)
	local bufnr = replace_data.bufnr or vim.api.nvim_get_current_buf()
	local old_string = replace_data.old_string
	local new_string = replace_data.new_string
	local replace_all = replace_data.replace_all or false

	-- Validate inputs
	if not old_string or not new_string then
		return { success = false, error = "old_string and new_string are required" }
	end

	if old_string == new_string then
		return { success = false, error = "oldString and newString must be different" }
	end

	-- Get current buffer content
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	-- Attempt replacement
	local new_content, err = replace.replace(content, old_string, new_string, replace_all)

	if err then
		return { success = false, error = err }
	end

	-- Apply the changes to the buffer
	local new_lines = vim.split(new_content, "\n", { plain = true })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

	return {
		success = true,
		message = replace_all and "All occurrences replaced" or "Text replaced",
	}
end

-- Apply a diff to the buffer
function M.apply_diff(diff_data)
	local bufnr = diff_data.bufnr or vim.api.nvim_get_current_buf()

	if diff_data.type == "full_replace" then
		local lines = vim.split(diff_data.content, "\n", { plain = true })
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		return { success = true, message = "Buffer replaced" }
	elseif diff_data.type == "line_range" then
		local start_line = diff_data.start_line or 0
		local end_line = diff_data.end_line or -1
		local lines = vim.split(diff_data.content, "\n", { plain = true })
		vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, lines)
		return { success = true, message = "Lines updated" }
	elseif diff_data.type == "unified_diff" then
		local lines = vim.split(diff_data.content, "\n", { plain = true })
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		return { success = true, message = "Diff applied" }
	else
		return { success = false, error = "Unknown diff type: " .. (diff_data.type or "nil") }
	end
end

return M
