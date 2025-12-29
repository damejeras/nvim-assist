local M = {}
local replace = require("nvim-assist.replace")
local ui = require("nvim-assist.ui")

-- Validate buffer exists and is loaded
local function validate_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return nil, "Buffer " .. bufnr .. " is not valid"
	end

	if not vim.api.nvim_buf_is_loaded(bufnr) then
		return nil, "Buffer " .. bufnr .. " is not loaded"
	end

	return bufnr
end

-- Get a specific buffer's content and metadata
function M.get_buffer_content(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- Validate buffer exists and is loaded
	local valid_bufnr, err = validate_buffer(bufnr)
	if not valid_bufnr then
		return nil, err
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return {
		bufnr = bufnr,
		content = table.concat(lines, "\n"),
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
			local buftype = vim.bo[bufnr].buftype
			local listed = vim.bo[bufnr].buflisted

			-- Only include normal file buffers (not help, quickfix, etc.)
			if buftype == "" and listed then
				table.insert(buffers, {
					bufnr = bufnr,
					filepath = filepath,
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

	-- Validate buffer exists and is loaded
	local valid_bufnr, err = validate_buffer(bufnr)
	if not valid_bufnr then
		return { success = false, error = err }
	end

	-- Get buffer content
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	-- Store cursor positions for all windows showing this buffer
	local cursor_positions = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == bufnr then
			cursor_positions[win] = vim.api.nvim_win_get_cursor(win)
		end
	end

	-- Attempt replacement
	local new_content, replace_err = replace.replace(content, old_string, new_string, replace_all)

	if replace_err or new_content == nil then
		return { success = false, error = replace_err }
	end

	-- Split into lines
	local new_lines = vim.split(new_content, "\n", { plain = true })

	-- Find the first line where change occurs
	local first_changed_line = nil
	for i = 1, math.min(#lines, #new_lines) do
		if lines[i] ~= new_lines[i] then
			first_changed_line = i
			break
		end
	end

	-- If no difference found in common lines but sizes differ, change is at the end
	if not first_changed_line and #lines ~= #new_lines then
		first_changed_line = math.min(#lines, #new_lines) + 1
	end

	-- Calculate line difference
	local line_diff = #new_lines - #lines

	-- Update target lines to current extmark positions (captures manual edits)
	ui.update_tracked_target_lines()

	-- Apply the changes to the buffer
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

	-- Reposition tracked extmarks after programmatic buffer change
	ui.reposition_tracked_extmarks()

	-- Adjust cursor positions for all windows showing this buffer
	if first_changed_line and line_diff ~= 0 then
		for win, pos in pairs(cursor_positions) do
			if vim.api.nvim_win_is_valid(win) then
				local row, col = pos[1], pos[2]
				-- If cursor is on or after the first changed line, adjust it
				if row >= first_changed_line then
					local new_row = row + line_diff
					-- Ensure the new row is valid (at least 1, at most the number of lines)
					new_row = math.max(1, math.min(new_row, #new_lines))
					vim.api.nvim_win_set_cursor(win, { new_row, col })
				end
			end
		end
	end

	return {
		success = true,
		message = replace_all and "All occurrences replaced" or "Text replaced",
	}
end

return M
