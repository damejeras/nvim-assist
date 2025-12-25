local M = {}

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
