local M = {}

local buffer = require("nvim-assist.buffer")
local log = require("nvim-assist.log")
local uv = vim.loop
local server = nil
local clients = {}

-- Generate a unique session hash
local function generate_session_hash()
	local random = math.random(0, 0xFFFFFF)
	local timestamp = os.time()
	return string.format("%06x%08x", random, timestamp):sub(1, 12)
end

-- Session ID and paths
local session_id = generate_session_hash()
local temp_dir = os.getenv("TMPDIR") or "/tmp"
local base_dir = temp_dir .. "/nvim-assist"
local socket_path = base_dir .. "/" .. session_id .. ".sock"
local log_path = base_dir .. "/" .. session_id .. ".log"

local function handle_message(msg)
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

local function create_client_handler(client)
	local content = ""

	return function(err, chunk)
		if err then
			log.error("Read error: " .. err)
			client:close()
			clients[client] = nil
			return
		end

		if not chunk then
			log.info("Client disconnected")
			client:close()
			clients[client] = nil
			return
		end

		content = content .. chunk

		while true do
			local newline_pos = content:find("\n")
			if not newline_pos then
				break
			end

			local message = content:sub(1, newline_pos - 1)
			content = content:sub(newline_pos + 1)

			if #message > 0 then
				vim.schedule(function()
					local response = handle_message(message)
					client:write(response .. "\n")
				end)
			end
		end
	end
end

function M.start()
	if server then
		log.warn("Server already running")
		return false
	end

	-- Initialize logging
	log.init(log_path)

	-- Ensure base directory exists
	vim.fn.mkdir(base_dir, "p")

	-- Remove existing socket file if it exists
	local stat = uv.fs_stat(socket_path)
	if stat then
		uv.fs_unlink(socket_path)
	end

	server = uv.new_pipe(false)
	if not server then
		log.error("Failed to create Unix socket server")
		return false
	end

	local bind_success, bind_err = pcall(function()
		server:bind(socket_path)
	end)

	if not bind_success then
		log.error("Failed to bind to " .. socket_path .. " - " .. tostring(bind_err))
		server = nil
		return false
	end

	server:listen(128, function(err)
		if err then
			log.error("Listen error: " .. err)
			return
		end

		local client = uv.new_pipe(false)
		if not client then
			log.error("Failed to create client socket")
			return
		end

		server:accept(client)
		clients[client] = true

		log.info("Client connected")

		client:read_start(create_client_handler(client))
	end)

	log.info(
		string.format(
			"Server started, session_id: %s, socket_path: %s, log_path: %s",
			session_id,
			socket_path,
			log_path
		)
	)

	return true
end

function M.stop()
	if not server then
		log.warn("Server not running")
		return false
	end

	for client, _ in pairs(clients) do
		client:close()
	end
	clients = {}

	server:close()
	server = nil

	log.info("Server stopped - cleaning up session files")

	-- Close log file
	log.close()

	-- Delete log file
	local log_stat = uv.fs_stat(log_path)
	if log_stat then
		uv.fs_unlink(log_path)
	end

	-- Clean up socket file
	local socket_stat = uv.fs_stat(socket_path)
	if socket_stat then
		uv.fs_unlink(socket_path)
	end

	return true
end

function M.is_running()
	return server ~= nil
end

function M.get_socket_path()
	return socket_path
end

return M
