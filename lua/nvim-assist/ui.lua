local M = {}

-- Namespace for virtual text
local ns_id = vim.api.nvim_create_namespace("nvim-assist")

-- Spinner frames for loading animation
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Helper to get the indentation of a line
local function get_line_indent(bufnr, line)
	local line_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
	local indent = line_text:match("^%s*") or ""
	return indent
end

-- Helper to create a tracked extmark with virtual line
-- Returns the extmark ID which can be used to update or clear it later
function M.create_tracked_virtual_text(bufnr, line, text)
	local indent = get_line_indent(bufnr, line)
	return vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
		virt_lines = { { { indent .. spinner_frames[1] .. " " .. text, "Comment" } } },
		virt_lines_above = true,
		invalidate = true, -- Clear extmark when the line is deleted/modified
	})
end

-- Helper to update virtual line using extmark ID
function M.update_virtual_text(bufnr, extmark_id, text, spinner_index)
	-- Check if buffer is valid and loaded
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return
	end

	-- Try to get the extmark position
	local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns_id, extmark_id, {})
	if not ok or not pos or #pos == 0 then
		return
	end

	-- Get indentation and update the extmark
	local indent = get_line_indent(bufnr, pos[1])
	local spinner = spinner_index and spinner_frames[spinner_index] or ""
	local prefix = spinner_index and (spinner .. " ") or ""

	pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, pos[1], pos[2], {
		id = extmark_id,
		virt_lines = { { { indent .. prefix .. text, "Comment" } } },
		virt_lines_above = true,
		invalidate = true,
	})
end

-- Helper to clear virtual text using extmark ID
function M.clear_virtual_text(bufnr, extmark_id)
	pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, extmark_id)
end

-- Helper to highlight a region
function M.highlight_region(bufnr, start_line, end_line)
	local extmarks = {}
	for line = start_line, end_line do
		-- Get the line length to properly set end_col
		local line_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
		local line_length = #line_text

		local mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
			end_line = line,
			end_col = line_length,
			hl_group = "Visual",
			hl_eol = true,
		})
		table.insert(extmarks, mark_id)
	end
	return extmarks
end

-- Helper to clear region highlights
function M.clear_region_highlights(bufnr, extmarks)
	for _, mark_id in ipairs(extmarks) do
		pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, mark_id)
	end
end

-- Create a spinner animation that updates virtual text
-- Returns a timer and the initial spinner index
function M.create_spinner(bufnr, extmark_id, current_text_callback)
	local spinner_index = 1
	local timer = vim.loop.new_timer()

	timer:start(
		100,
		100,
		vim.schedule_wrap(function()
			spinner_index = (spinner_index % #spinner_frames) + 1
			local text = current_text_callback()
			M.update_virtual_text(bufnr, extmark_id, text, spinner_index)
		end)
	)

	return timer, spinner_index
end

-- Get the number of spinner frames (useful for manual animation)
function M.get_spinner_frame_count()
	return #spinner_frames
end

return M
