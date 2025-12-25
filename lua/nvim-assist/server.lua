local M = {}

local uv = vim.loop
local server = nil
local clients = {}
local log_file = nil

local config = {
	host = "127.0.0.1",
	port = 9999,
	log_file = "nvim-assist.log",
}

local message_handler = nil

local function log(msg)
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	local log_msg = string.format("[%s] %s\n", timestamp, msg)

	if not log_file then
		local cwd = vim.fn.getcwd()
		local log_path = cwd .. "/" .. config.log_file
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

	server = uv.new_tcp()
	if not server then
		log("Failed to create TCP server")
		return false
	end

	local bind_success, bind_err = pcall(function()
		server:bind(config.host, config.port)
	end)

	if not bind_success then
		log("Failed to bind to " .. config.host .. ":" .. config.port .. " - " .. tostring(bind_err))
		server = nil
		return false
	end

	server:listen(128, function(err)
		if err then
			log("Listen error: " .. err)
			return
		end

		local client = uv.new_tcp()
		if not client then
			log("Failed to create client socket")
			return
		end

		server:accept(client)
		clients[client] = true

		log("Client connected")

		client:read_start(create_client_handler(client))
	end)

	log("Server started on " .. config.host .. ":" .. config.port)
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

	log("Server stopped")

	if log_file then
		log_file:close()
		log_file = nil
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

function M.configure(opts)
	config.host = opts.host or config.host
	config.port = opts.port or config.port
	config.log_file = opts.log_file or config.log_file
end

function M.set_message_handler(handler)
	message_handler = handler
end

return M
