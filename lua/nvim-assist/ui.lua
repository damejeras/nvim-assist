local M = {}

-- Namespace for virtual text
local ns_id = vim.api.nvim_create_namespace("nvim-assist")

-- Spinner frames for loading animation
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPINNER_UPDATE_INTERVAL_MS = 100

-- Helper to check if buffer is valid and loaded
local function is_buffer_valid(bufnr)
	return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

-- Safe extmark operations (pcall wrappers)
local function safe_get_extmark(bufnr, extmark_id, opts)
	local ok, result = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns_id, extmark_id, opts or {})
	return ok and result or nil
end

local function safe_set_extmark(bufnr, line, col, opts)
	pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, line, col, opts)
end

local function safe_del_extmark(bufnr, extmark_id)
	pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, extmark_id)
end

-- Store target line for tracked extmarks
-- This allows us to reposition them after programmatic buffer changes
local tracked_extmarks = {}

-- Set up autocmd to clean up extmarks when buffers are deleted
local cleanup_group = vim.api.nvim_create_augroup("NvimAssistCleanup", { clear = true })
vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
	group = cleanup_group,
	callback = function(args)
		local bufnr = args.buf
		-- Remove all tracked extmarks for this buffer
		for extmark_id, tracked in pairs(tracked_extmarks) do
			if tracked.bufnr == bufnr then
				tracked_extmarks[extmark_id] = nil
			end
		end
	end,
})

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
	local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
		virt_lines = { { { indent .. spinner_frames[1] .. " " .. text, "Comment" } } },
		virt_lines_above = true,
	})

	-- Track this extmark with its target line
	tracked_extmarks[extmark_id] = { bufnr = bufnr, target_line = line }

	return extmark_id
end

-- Helper to update virtual line using extmark ID
function M.update_virtual_text(bufnr, extmark_id, text, spinner_index)
	-- Check if buffer is valid and loaded
	if not is_buffer_valid(bufnr) then
		return
	end

	-- Get tracked info
	local tracked = tracked_extmarks[extmark_id]
	if not tracked then
		return
	end

	-- Try to get the current extmark position
	local pos = safe_get_extmark(bufnr, extmark_id)
	if not pos or #pos == 0 then
		return
	end

	-- Update at the current position (let it track naturally with buffer changes)
	local line, col = pos[1], pos[2]
	local indent = get_line_indent(bufnr, line)
	local spinner = spinner_index and spinner_frames[spinner_index] or ""
	local prefix = spinner_index and (spinner .. " ") or ""

	safe_set_extmark(bufnr, line, col, {
		id = extmark_id,
		virt_lines = { { { indent .. prefix .. text, "Comment" } } },
		virt_lines_above = true,
	})
end

-- Helper to clear virtual text using extmark ID
function M.clear_virtual_text(bufnr, extmark_id)
	safe_del_extmark(bufnr, extmark_id)
	tracked_extmarks[extmark_id] = nil
end

-- Update target lines for tracked extmarks based on their current positions
-- Call this BEFORE programmatic buffer replacements to capture any manual edits
function M.update_tracked_target_lines()
	for extmark_id, tracked in pairs(tracked_extmarks) do
		local bufnr = tracked.bufnr

		-- Check if buffer is still valid
		if is_buffer_valid(bufnr) then
			-- Get current extmark position
			local pos = safe_get_extmark(bufnr, extmark_id)
			if pos and #pos > 0 then
				-- Update target_line to current position (reflects manual edits)
				local line = pos[1]
				tracked.target_line = line
			else
				tracked_extmarks[extmark_id] = nil
			end
		else
			tracked_extmarks[extmark_id] = nil
		end
	end
end

-- Reposition tracked extmarks to their target lines
-- Call this AFTER programmatic buffer replacements to keep extmarks at the intended location
function M.reposition_tracked_extmarks()
	for extmark_id, tracked in pairs(tracked_extmarks) do
		local bufnr = tracked.bufnr
		local target_line = tracked.target_line

		-- Check if buffer is still valid
		if is_buffer_valid(bufnr) then
			-- Get current extmark details
			local pos = safe_get_extmark(bufnr, extmark_id, { details = true })
			if pos and #pos > 0 then
				-- If extmark is not at target line, reposition it
				local line, _, details = pos[1], pos[2], pos[3] or {}
				if line ~= target_line then
					local indent = get_line_indent(bufnr, target_line)

					-- Update virt_lines with proper indentation
					if details.virt_lines and details.virt_lines[1] and details.virt_lines[1][1] then
						local old_text = details.virt_lines[1][1][1] or ""
						-- Remove old indentation and add new indentation
						local text_without_indent = old_text:match("^%s*(.*)") or old_text
						details.virt_lines[1][1][1] = indent .. text_without_indent
					end

					safe_set_extmark(bufnr, target_line, 0, {
						id = extmark_id,
						virt_lines = details.virt_lines,
						virt_lines_above = true,
					})
				end
			else
				tracked_extmarks[extmark_id] = nil
			end
		else
			tracked_extmarks[extmark_id] = nil
		end
	end
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
		safe_del_extmark(bufnr, mark_id)
	end
end

-- Create a spinner animation that updates virtual text
-- Returns a timer and the initial spinner index
function M.create_spinner(bufnr, extmark_id, current_text_callback)
	local spinner_index = 1
	local timer = vim.loop.new_timer()

	timer:start(
		SPINNER_UPDATE_INTERVAL_MS,
		SPINNER_UPDATE_INTERVAL_MS,
		vim.schedule_wrap(function()
			spinner_index = (spinner_index % #spinner_frames) + 1
			local text = current_text_callback()
			M.update_virtual_text(bufnr, extmark_id, text, spinner_index)
		end)
	)

	return timer
end

return M
