local M = {}

local uv = vim.loop
local server = nil
local clients = {}
local log_file = nil
local message_handler = nil

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

local function log(msg)
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	local log_msg = string.format("[%s] %s\n", timestamp, msg)

	if not log_file then
		-- Ensure base directory exists
		vim.fn.mkdir(base_dir, "p")
		log_file = io.open(log_path, "a")
	end

	if log_file then
		log_file:write(log_msg)
		log_file:flush()
	end
end

local function create_client_handler(client)
	local buffer = ""

	return function(err, chunk)
		if err then
			log("Read error: " .. err)
			client:close()
			clients[client] = nil
			return
		end

		if not chunk then
			log("Client disconnected")
			client:close()
			clients[client] = nil
			return
		end

		buffer = buffer .. chunk

		while true do
			local newline_pos = buffer:find("\n")
			if not newline_pos then
				break
			end

			local message = buffer:sub(1, newline_pos - 1)
			buffer = buffer:sub(newline_pos + 1)

			if #message > 0 and message_handler then
				vim.schedule(function()
					local response = message_handler(message)
					client:write(response .. "\n")
				end)
			end
		end
	end
end

function M.start()
	if server then
		log("Server already running")
		return false
	end

	-- Ensure base directory exists
	vim.fn.mkdir(base_dir, "p")

	-- Remove existing socket file if it exists
	local stat = uv.fs_stat(socket_path)
	if stat then
		uv.fs_unlink(socket_path)
	end

	server = uv.new_pipe(false)
	if not server then
		log("Failed to create Unix socket server")
		return false
	end

	local bind_success, bind_err = pcall(function()
		server:bind(socket_path)
	end)

	if not bind_success then
		log("Failed to bind to " .. socket_path .. " - " .. tostring(bind_err))
		server = nil
		return false
	end

	server:listen(128, function(err)
		if err then
			log("Listen error: " .. err)
			return
		end

		local client = uv.new_pipe(false)
		if not client then
			log("Failed to create client socket")
			return
		end

		server:accept(client)
		clients[client] = true

		log("Client connected")

		client:read_start(create_client_handler(client))
	end)

	log("Server started")
	log("Session ID: " .. session_id)
	log("Socket: " .. socket_path)
	log("Log: " .. log_path)

	return true
end

function M.stop()
	if not server then
		log("Server not running")
		return false
	end

	for client, _ in pairs(clients) do
		client:close()
	end
	clients = {}

	server:close()
	server = nil

	log("Server stopped - cleaning up session files")

	-- Close and delete log file
	if log_file then
		log_file:close()
		log_file = nil
	end

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

function M.restart()
	log("Restarting server...")
	M.stop()
	vim.defer_fn(M.start, 100)
end

function M.is_running()
	return server ~= nil
end

function M.set_message_handler(handler)
	message_handler = handler
end

function M.get_socket_path()
	return socket_path
end

function M.get_session_id()
	return session_id
end

function M.get_log_path()
	return log_path
end

function M.log(msg)
	log(msg)
end

return M
