local M = {}

local uv = vim.loop
local server_handle = nil
local server_port = nil
local server = require("nvim-assist.server")

-- Find an available port by starting server without -p flag
local function start_opencode_server(callback)
	if server_handle then
		server.log("OpenCode server already running on port " .. server_port)
		return callback(server_port)
	end

	server.log("Starting OpenCode server")

	-- Start opencode serve without port to get random available port
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)

	server_handle = uv.spawn(
		"opencode",
		{
			args = { "serve" },
			stdio = { nil, stdout, stderr },
		},
		vim.schedule_wrap(function(code, signal)
			server_handle = nil
			server_port = nil
			if code ~= 0 and code ~= 15 then -- 15 is SIGTERM (normal shutdown)
				server.log(string.format("OpenCode server exited with code %d, signal %d", code, signal))
				vim.notify(
					string.format("OpenCode server exited with code %d, signal %d", code, signal),
					vim.log.levels.WARN
				)
			else
				server.log("OpenCode server stopped")
			end
		end)
	)

	if not server_handle then
		server.log("ERROR: Failed to start OpenCode server")
		return vim.notify("Failed to start OpenCode server", vim.log.levels.ERROR)
	end

	-- Read stderr to find the port (opencode prints "Listening on http://localhost:PORT")
	local output = ""
	stderr:read_start(function(err, data)
		if err then
			server.log("ERROR: Error reading OpenCode server output: " .. err)
			vim.notify("Error reading OpenCode server output: " .. err, vim.log.levels.ERROR)
			return
		end

		if data then
			output = output .. data
			-- Look for port in output
			local port = output:match("http://[^:]+:(%d+)")
			if port and not server_port then
				server_port = tonumber(port)
				server.log(string.format("OpenCode server started on port %d", server_port))
				vim.schedule(function()
					callback(server_port)
				end)
			end
		end
	end)

	-- Also read stdout
	stdout:read_start(function(err, data)
		if err then
			return
		end
		if data then
			output = output .. data
			local port = output:match("http://[^:]+:(%d+)")
			if port and not server_port then
				server_port = tonumber(port)
				server.log(string.format("OpenCode server started on port %d", server_port))
				vim.schedule(function()
					callback(server_port)
				end)
			end
		end
	end)
end

function M.start(callback)
	start_opencode_server(callback)
end

function M.stop()
	if server_handle then
		server.log("Stopping OpenCode server (port " .. (server_port or "unknown") .. ")")
		server_handle:kill(15) -- SIGTERM
		server_handle = nil
		server_port = nil
	end
end

function M.get_port()
	return server_port
end

function M.is_running()
	return server_handle ~= nil
end

return M
