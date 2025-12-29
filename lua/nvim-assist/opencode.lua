local M = {}

local uv = vim.loop
local server_handle = nil
local server_port = nil
local log = require("nvim-assist.log")

-- Lazy load plenary curl
local curl = nil
local function get_curl()
	if not curl then
		local ok, plenary_curl = pcall(require, "plenary.curl")
		if not ok then
			error("plenary.nvim is required but not installed. Please install nvim-lua/plenary.nvim")
		end
		curl = plenary_curl
	end
	return curl
end

-- Make HTTP request to OpenCode server
local function request(port, method, path, body, allow_empty)
	local url = string.format("http://localhost:%d%s", port, path)
	log.debug(string.format("HTTP %s: %s", method, url))

	if body then
		local json = vim.fn.json_encode(body)
		log.debug(string.format("Request body: %s", json:sub(1, 500)))
	end

	-- Prepare request options
	local opts = {
		headers = {
			["content-type"] = "application/json",
		},
	}

	if body then
		opts.body = vim.fn.json_encode(body)
	end

	-- Make the request using the appropriate method
	local curl_lib = get_curl()
	local response
	if method == "GET" then
		response = curl_lib.get(url, opts)
	elseif method == "POST" then
		response = curl_lib.post(url, opts)
	else
		return nil, string.format("Unsupported HTTP method: %s", method)
	end

	-- Check for curl errors
	if response.exit ~= 0 then
		local err = string.format("HTTP request failed with exit code %d", response.exit)
		if response.body then
			log.debug(string.format("Response: %s", response.body:sub(1, 500)))
		end
		return nil, err
	end

	-- Check HTTP status code
	if response.status < 200 or response.status >= 300 then
		local err = string.format("HTTP error %d", response.status)
		if response.body then
			log.debug(string.format("Response: %s", response.body:sub(1, 500)))
		end
		return nil, err
	end

	log.debug(string.format("HTTP Status: %d", response.status))

	-- Empty response is OK for async endpoints or if explicitly allowed
	local response_body = response.body or ""
	if response_body == "" or response_body:match("^%s*$") then
		if allow_empty then
			log.debug("Empty response (OK for async endpoint)")
			return true
		else
			return nil, "Empty response from OpenCode server"
		end
	end

	-- Parse JSON response
	local ok, decoded = pcall(vim.fn.json_decode, response_body)
	if not ok then
		return nil, string.format("Failed to parse JSON response: %s", response_body:sub(1, 500))
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

	-- Get the Neovim RPC socket path
	local nvim_socket = vim.v.servername

	log.info("Setting OPENCODE_CONFIG to: " .. config_path)
	log.info("Setting NVIM to: " .. nvim_socket)

	-- Start opencode serve without port to get random available port
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)

	-- Inherit parent environment and add required variables
	local env = {}
	for k, v in pairs(vim.fn.environ()) do
		table.insert(env, k .. "=" .. v)
	end
	table.insert(env, "OPENCODE_CONFIG=" .. config_path)
	table.insert(env, "NVIM=" .. nvim_socket)

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

	-- Helper to create port reader for stdout/stderr
	local output = ""
	local function create_port_reader(stream_name)
		return function(err, data)
			if err then
				if stream_name == "stderr" then
					log.error("Error reading OpenCode server output: " .. err)
					vim.notify("Error reading OpenCode server output: " .. err, vim.log.levels.ERROR)
				end
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
		end
	end

	-- Read both stdout and stderr to find the port
	stderr:read_start(create_port_reader("stderr"))
	stdout:read_start(create_port_reader("stdout"))
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

-- URL encode helper for query parameters
local function url_encode(str)
	return string.gsub(str, "([^%w%-%.%_%~%/])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
end

-- Create an OpenCode session
function M.create_session(port, cwd, agent_name)
	log.debug("Creating OpenCode session with agent: " .. agent_name)
	local session, err = request(port, "POST", "/session?directory=" .. url_encode(cwd), {
		agentName = agent_name,
	})

	if not session then
		return nil, "Failed to create OpenCode session" .. (err and (": " .. err) or "")
	end

	if not session.id then
		return nil, "OpenCode session created without ID"
	end

	log.info(string.format("OpenCode session created: %s (agent: %s)", session.id, agent_name))
	return session
end

-- Delete an OpenCode session
function M.delete_session(port, session_id)
	log.info("Deleting OpenCode session: " .. session_id)

	local url = string.format("http://localhost:%d/session/%s", port, session_id)
	log.debug(string.format("HTTP DELETE: %s", url))

	local curl_lib = get_curl()
	local response = curl_lib.request({
		url = url,
		method = "delete",
		headers = {
			["content-type"] = "application/json",
		},
	})

	-- Check for curl errors
	if response.exit ~= 0 then
		local err = string.format("Failed to delete session %s (exit code %d)", session_id, response.exit)
		log.error(err)
		return nil, err
	end

	-- Check HTTP status code
	if response.status < 200 or response.status >= 300 then
		local err = string.format("Failed to delete session %s (HTTP %d)", session_id, response.status)
		log.error(err)
		return nil, err
	end

	log.info(string.format("Session %s deleted successfully", session_id))
	return true
end

-- Send a prompt to an OpenCode session asynchronously
function M.send_prompt_async(port, session_id, cwd, prompt_text, provider_id, model_id)
	log.debug("Sending prompt to OpenCode session " .. session_id)
	log.debug(string.format("Model: %s/%s", provider_id, model_id))
	log.debug("Prompt: " .. prompt_text:gsub("\n", " "):sub(1, 200) .. "...")

	local response, err = request(
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
		return nil, "Failed to send prompt to OpenCode" .. (err and (": " .. err) or "")
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
