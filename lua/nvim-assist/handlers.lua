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
		local buffer_data = buffer.get_current_content()
		return vim.json.encode({
			success = true,
			data = buffer_data,
		})
	elseif command == "apply_diff" then
		local result = buffer.apply_diff(decoded.data or {})
		return vim.json.encode(result)
	elseif command == "ping" then
		return vim.json.encode({ success = true, message = "pong" })
	else
		return vim.json.encode({
			success = false,
			error = "Unknown command: " .. (command or "nil"),
		})
	end
end

return M
