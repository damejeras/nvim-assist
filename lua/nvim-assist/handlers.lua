local M = {}
local buffer = require("nvim-assist.buffer")

-- Handle incoming messages from the server
function M.handle_message(msg)
	local ok, decoded = pcall(vim.json.decode, msg)
	if not ok then
		return vim.json.encode({ success = false, error = "Invalid JSON" })
	end

	local command = decoded.command

	if command == "get_buffer" then
		local bufnr = decoded.data and decoded.data.bufnr
		local buffer_data, err = buffer.get_buffer_content(bufnr)

		if err then
			return vim.json.encode({
				success = false,
				error = err,
			})
		end

		return vim.json.encode({
			success = true,
			data = buffer_data,
		})
	elseif command == "list_buffers" then
		local buffers = buffer.list_buffers()
		return vim.json.encode({
			success = true,
			data = buffers,
		})
	elseif command == "replace_text" then
		local result = buffer.replace_text(decoded.data or {})
		return vim.json.encode(result)
	else
		return vim.json.encode({
			success = false,
			error = "Unknown command: " .. (command or "nil"),
		})
	end
end

return M
