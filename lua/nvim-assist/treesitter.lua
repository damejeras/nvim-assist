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

-- Get a treesitter node at cursor based on query string
-- Supports: "@function.inner", "@function.outer", "@class.inner", "@class.outer", etc.
function M.get_node_at_cursor(query_string, bufnr)
	bufnr = bufnr or 0

	-- Parse query string (e.g., "@function.inner" -> "function", "inner")
	local capture, scope = query_string:match("@([^%.]+)%.(.+)")
	if not capture or not scope then
		return nil
	end

	-- Get treesitter parser
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok or not parser then
		return nil
	end

	-- Get cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1] - 1 -- Convert to 0-indexed
	local cursor_col = cursor[2]

	-- Parse and get root node
	local trees = parser:parse()
	if not trees or #trees == 0 then
		return nil
	end

	local root = trees[1]:root()
	local node = root:descendant_for_range(cursor_line, cursor_col, cursor_line, cursor_col)

	-- Map capture names to node types
	local node_type_patterns = {
		["function"] = { "function", "method", "arrow_function", "lambda", "function_definition", "method_definition" },
		["class"] = { "class", "class_definition", "class_declaration" },
		["block"] = { "block", "statement_block", "body" },
		["conditional"] = { "if_statement", "switch_statement", "conditional" },
		["loop"] = { "for_statement", "while_statement", "loop" },
		["call"] = { "call_expression", "function_call" },
	}

	local patterns = node_type_patterns[capture]
	if not patterns then
		return nil
	end

	-- Walk up the tree to find matching node
	while node do
		local node_type = node:type()

		-- Check if this node matches any of the patterns
		for _, pattern in ipairs(patterns) do
			if node_type:match(pattern) then
				-- For "inner" scope, try to get the body/block child
				if scope == "inner" then
					-- Look for a body/block child node
					for child in node:iter_children() do
						local child_type = child:type()
						if child_type:match("body") or child_type:match("block") then
							return child
						end
					end
					-- If no body found, return the node itself
					return node
				else
					-- For "outer" scope, return the entire node
					return node
				end
			end
		end

		node = node:parent()
	end

	return nil
end

return M
