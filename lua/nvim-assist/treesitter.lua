local M = {}

-- Find the function or method node containing the cursor or at a specific line
function M.find_function_at_cursor(bufnr, line)
	bufnr = bufnr or 0

	-- Get treesitter parser for current buffer
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok or not parser then
		return nil, "No treesitter parser available for this buffer"
	end

	-- Get cursor/line position (1-indexed)
	local cursor_line, cursor_col
	if line then
		-- Use provided line (assume 0-indexed)
		cursor_line = line
		cursor_col = 0
	else
		-- Use cursor position
		local cursor = vim.api.nvim_win_get_cursor(0)
		cursor_line = cursor[1] - 1 -- Convert to 0-indexed for treesitter
		cursor_col = cursor[2]
	end

	-- Parse and get root node
	local trees = parser:parse()
	if not trees or #trees == 0 then
		return nil, "Failed to parse buffer"
	end

	local root = trees[1]:root()

	-- Find node at cursor position
	local node = root:descendant_for_range(cursor_line, cursor_col, cursor_line, cursor_col)

	-- Walk up the tree to find a function or method node
	while node do
		local node_type = node:type()

		-- Check if this is a function-like node
		-- Common node types across languages: function, function_definition, method, method_definition, etc.
		if
			node_type:match("function")
			or node_type:match("method")
			or node_type:match("arrow_function")
			or node_type:match("lambda")
		then
			local start_line, start_col, end_line, end_col = node:range()

			return {
				node = node,
				start_line = start_line, -- 0-indexed
				start_col = start_col,
				end_line = end_line, -- 0-indexed
				end_col = end_col,
			}, nil
		end

		node = node:parent()
	end

	return nil, "No function found at cursor position"
end

return M
