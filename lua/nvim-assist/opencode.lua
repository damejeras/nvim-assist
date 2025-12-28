local M = {}

local uv = vim.loop
local server_handle = nil
local server_port = nil
local log = require("nvim-assist.log")

-- URL encode helper
local function url_encode(str)
	return string.gsub(str, "([^%w%-%.%_%~%/])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
end

-- Make HTTP request to OpenCode server
local function request(port, method, path, body, allow_empty)
	-- Add -w flag to get HTTP status code
	local cmd = string.format("curl -s -w '\\n%%{http_code}' -X %s 'http://localhost:%d%s'", method, port, path)

	if body then
		local json = vim.fn.json_encode(next(body) == nil and vim.empty_dict() or body)
		cmd = cmd .. string.format(" -H 'Content-Type: application/json' -d '%s'", json:gsub("'", "'\\''"))
		log.debug(string.format("Request body: %s", json:sub(1, 500)))
	end

	log.debug(string.format("Executing: curl -X %s http://localhost:%d%s", method, port, path))

	local result = vim.fn.system(cmd)
	local exit_code = vim.v.shell_error

	if exit_code ~= 0 then
		log.error(string.format("curl failed with exit code %d", exit_code))
		log.error(string.format("Response: %s", result:sub(1, 500)))
		return nil
	end

	-- Split response body and HTTP status code
	local lines = vim.split(result, "\n", { plain = true })
	local http_code = tonumber(lines[#lines])
	local response_body = table.concat(vim.list_slice(lines, 1, #lines - 1), "\n")

	log.debug(string.format("HTTP Status: %d", http_code or 0))

	-- Check HTTP status code
	if not http_code or http_code < 200 or http_code >= 300 then
		log.error(string.format("HTTP error %d", http_code or 0))
		log.error(string.format("Response: %s", response_body:sub(1, 500)))
		return nil
	end

	-- Empty response is OK for async endpoints or if explicitly allowed
	if response_body == "" or response_body:match("^%s*$") then
		if allow_empty then
			log.debug("Empty response (OK for async endpoint)")
			return true -- Return a truthy value to indicate success
		else
			log.error("Empty response from OpenCode server")
			return nil
		end
	end

	local ok, decoded = pcall(vim.fn.json_decode, response_body)
	if not ok then
		log.error(string.format("Failed to parse JSON response: %s", response_body:sub(1, 500)))
		return nil
	end

	log.debug(string.format("Response: %s", vim.fn.json_encode(decoded):sub(1, 500)))
	return decoded
end

-- Find an available port by starting server without -p flag
local function start_opencode_server(callback)
	if server_handle then
		log.info("OpenCode server already running on port " .. server_port)
		return callback(server_port)
	end

	log.info("Starting OpenCode server")

	-- Get the plugin root directory
	local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
	local config_path = plugin_path .. "/opencode/opencode.jsonc"

	-- Get the socket path from the server module
	local server = require("nvim-assist.server")
	local socket_path = server.get_socket_path()

	log.info("Setting OPENCODE_CONFIG to: " .. config_path)
	log.info("Setting NVIM_ASSIST_SOCKET to: " .. socket_path)

	-- Start opencode serve without port to get random available port
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)

	-- Copy current environment and add OPENCODE_CONFIG and NVIM_ASSIST_SOCKET
	local env = {}
	for k, v in pairs(vim.fn.environ()) do
		table.insert(env, k .. "=" .. v)
	end
	table.insert(env, "OPENCODE_CONFIG=" .. config_path)
	table.insert(env, "NVIM_ASSIST_SOCKET=" .. socket_path)

	server_handle = uv.spawn(
		"opencode",
		{
			args = { "serve" },
			stdio = { nil, stdout, stderr },
			env = env,
		},
		vim.schedule_wrap(function(code, signal)
			server_handle = nil
			server_port = nil
			if code ~= 0 and code ~= 15 then -- 15 is SIGTERM (normal shutdown)
				log.warn(string.format("OpenCode server exited with code %d, signal %d", code, signal))
				vim.notify(
					string.format("OpenCode server exited with code %d, signal %d", code, signal),
					vim.log.levels.WARN
				)
			else
				log.info("OpenCode server stopped")
			end
		end)
	)

	if not server_handle then
		log.error("Failed to start OpenCode server")
		return vim.notify("Failed to start OpenCode server", vim.log.levels.ERROR)
	end

	-- Read stderr to find the port (opencode prints "Listening on http://localhost:PORT")
	local output = ""
	stderr:read_start(function(err, data)
		if err then
			log.error("Error reading OpenCode server output: " .. err)
			vim.notify("Error reading OpenCode server output: " .. err, vim.log.levels.ERROR)
			return
		end

		if data then
			output = output .. data
			-- Look for port in output
			local port = output:match("http://[^:]+:(%d+)")
			if port and not server_port then
				server_port = tonumber(port)
				log.info(string.format("OpenCode server started on port %d", server_port))
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
				log.info(string.format("OpenCode server started on port %d", server_port))
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
		log.info("Stopping OpenCode server (port " .. (server_port or "unknown") .. ")")
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

-- Create an OpenCode session
function M.create_session(port, cwd, agent_name)
	log.info("Creating OpenCode session with agent: " .. agent_name)
	local session = request(port, "POST", "/session?directory=" .. url_encode(cwd), {
		agentName = agent_name,
	})

	if not session or not session.id then
		log.error("Failed to create OpenCode session")
		return nil
	end

	log.info(string.format("OpenCode session created: %s (agent: %s)", session.id, agent_name))
	return session
end

-- Send a prompt to an OpenCode session asynchronously
function M.send_prompt_async(port, session_id, cwd, prompt_text, provider_id, model_id)
	log.info("Sending prompt to OpenCode session " .. session_id)
	log.debug(string.format("Model: %s/%s", provider_id, model_id))
	log.debug("Prompt: " .. prompt_text:gsub("\n", " "):sub(1, 200) .. "...")

	local response = request(
		port,
		"POST",
		string.format("/session/%s/prompt_async?directory=%s", session_id, url_encode(cwd)),
		{
			parts = {
				{
					type = "text",
					text = prompt_text,
				},
			},
			model = {
				providerID = provider_id,
				modelID = model_id,
			},
		},
		true -- Allow empty response for async endpoint
	)

	if response then
		log.info("Prompt sent successfully")
		return true
	else
		log.error("Failed to send prompt to OpenCode")
		return false
	end
end

-- Subscribe to OpenCode events for a session
-- Calls on_event callback for each event received
-- Returns the job ID
function M.subscribe_to_events(port, session_id, on_event)
	log.debug("Subscribing to OpenCode events for session " .. session_id)

	return vim.fn.jobstart(string.format("curl -s -N http://localhost:%d/global/event", port), {
		on_stdout = function(_, data)
			if not data then
				return
			end

			for _, line in ipairs(data) do
				if line == "" or not line:match("^data:") then
					goto continue
				end

				local json_str = line:gsub("^data:%s*", "")
				local ok, event = pcall(vim.fn.json_decode, json_str)

				if not ok or not event or not event.payload then
					goto continue
				end

				-- Call the event handler
				vim.schedule(function()
					on_event(event, session_id)
				end)

				::continue::
			end
		end,
		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						log.warn(string.format("curl stderr: %s", line))
					end
				end
			end
		end,
		on_exit = function(_, exit_code, _)
			log.debug(string.format("OpenCode event stream closed (exit code: %d)", exit_code))
		end,
	})
end

return M
