local M = {}

---@alias Port number TCP port number
---@alias JobId number Job identifier for async tasks

---@class OpenCodeSession
---@field id string Session identifier
---@field directory? string Working directory for the session

---@class ModelInfo
---@field providerID string AI provider identifier
---@field modelID string Model identifier

---@class OpenCodeEventPayload
---@field type string Event type (e.g., "message.part.updated", "session.idle")
---@field properties? table Event-specific properties

---@class OpenCodeEvent
---@field payload OpenCodeEventPayload Event payload data

local uv = vim.loop

---@type userdata? # UV process handle for OpenCode server
local server_handle = nil

---@type Port? # Port number the OpenCode server is running on
local server_port = nil

local log = require("nvim-assist.log")

---Constants for logging and HTTP
local LOG_TRUNCATE_LENGTH = 500
local LOG_PROMPT_LENGTH = 200
local HTTP_SUCCESS_MIN = 200
local HTTP_SUCCESS_MAX = 300

---@type table? # Lazy-loaded plenary.curl module
local curl = nil

---Get plenary.curl module, lazy loading if needed
---@return table # plenary.curl module
local function get_curl()
    if not curl then
        local ok, plenary_curl = pcall(require, "plenary.curl")
        if not ok then
            error(
                "plenary.nvim is required but not installed. Please install nvim-lua/plenary.nvim"
            )
        end
        curl = plenary_curl
    end
    return curl
end

---Format error message with optional detail
---@param base_msg string Base error message
---@param err? string Optional error detail
---@return string # Formatted error message
function M.format_error(base_msg, err)
    if err then
        return base_msg .. ": " .. err
    end
    return base_msg
end

---Local alias for internal use
local format_error = M.format_error

---Check if HTTP status code indicates success
---@param status number HTTP status code
---@return boolean # True if status is in 2xx range
local function is_http_success(status)
    return status >= HTTP_SUCCESS_MIN and status < HTTP_SUCCESS_MAX
end

---Make HTTP request to OpenCode server
---@param port Port Server port number
---@param method string HTTP method ("GET" or "POST")
---@param path string Request path (e.g., "/session")
---@param body? table Request body (will be JSON encoded)
---@param allow_empty? boolean Allow empty response (for async endpoints)
---@return table|boolean|nil response Decoded JSON response or true if empty allowed
---@return string|nil error Error message if request failed
local function request(port, method, path, body, allow_empty)
    local url = string.format("http://localhost:%d%s", port, path)
    log.debug(string.format("HTTP %s: %s", method, url))

    -- Encode body once for both logging and request
    local json_body = nil
    if body then
        json_body = vim.fn.json_encode(body)
        log.debug(
            string.format(
                "Request body: %s",
                json_body:sub(1, LOG_TRUNCATE_LENGTH)
            )
        )
    end

    -- Prepare request options
    local opts = {
        headers = {
            ["content-type"] = "application/json",
        },
    }

    if json_body then
        opts.body = json_body
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
        local err = string.format(
            "HTTP request failed with exit code %d",
            response.exit
        )
        if response.body then
            log.debug(
                string.format(
                    "Response: %s",
                    response.body:sub(1, LOG_TRUNCATE_LENGTH)
                )
            )
        end
        return nil, err
    end

    -- Check HTTP status code
    if not is_http_success(response.status) then
        local err = string.format("HTTP error %d", response.status)
        if response.body then
            log.debug(
                string.format(
                    "Response: %s",
                    response.body:sub(1, LOG_TRUNCATE_LENGTH)
                )
            )
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
        return nil,
            string.format(
                "Failed to parse JSON response: %s",
                response_body:sub(1, LOG_TRUNCATE_LENGTH)
            )
    end

    log.debug(
        string.format(
            "Response: %s",
            vim.fn.json_encode(decoded):sub(1, LOG_TRUNCATE_LENGTH)
        )
    )
    return decoded
end

---Start OpenCode server and find available port
---Server starts in background and calls callback with port when ready
---@param callback fun(port: Port|nil) Called with port number or nil on failure
local function start_opencode_server(callback)
    if server_handle then
        log.info("OpenCode server already running on port " .. server_port)
        return callback(server_port)
    end

    log.info("Starting OpenCode server")

    -- Get the plugin root directory
    local plugin_path =
        vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
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
                log.warn(
                    string.format(
                        "OpenCode server exited with code %d, signal %d",
                        code,
                        signal
                    )
                )
                vim.notify(
                    string.format(
                        "OpenCode server exited with code %d, signal %d",
                        code,
                        signal
                    ),
                    vim.log.levels.WARN
                )
            else
                log.info("OpenCode server stopped")
            end
        end)
    )

    if not server_handle then
        log.error("Failed to start OpenCode server")
        return vim.notify(
            "Failed to start OpenCode server",
            vim.log.levels.ERROR
        )
    end

    -- Helper to create port reader for stdout/stderr
    local output = ""
    local function create_port_reader(stream_name)
        return function(err, data)
            if err then
                if stream_name == "stderr" then
                    log.error("Error reading OpenCode server output: " .. err)
                    vim.notify(
                        "Error reading OpenCode server output: " .. err,
                        vim.log.levels.ERROR
                    )
                end
                return
            end

            if data then
                output = output .. data
                -- Look for port in output
                local port = output:match("http://[^:]+:(%d+)")
                if port and not server_port then
                    server_port = tonumber(port)
                    log.info(
                        string.format(
                            "OpenCode server started on port %d",
                            server_port
                        )
                    )
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

---Start OpenCode server
---@param callback fun(port: Port|nil) Called with port number when ready
function M.start(callback)
    start_opencode_server(callback)
end

---Stop OpenCode server gracefully
---Sends SIGTERM to server process if running
function M.stop()
    if server_handle then
        log.info(
            "Stopping OpenCode server (port "
                .. (server_port or "unknown")
                .. ")"
        )
        server_handle:kill(15) -- SIGTERM
        server_handle = nil
        server_port = nil
    end
end

---Get current OpenCode server port
---@return Port|nil # Port number if server running, nil otherwise
function M.get_port()
    return server_port
end

---Check if OpenCode server is running
---@return boolean # True if server process is active
function M.is_running()
    return server_handle ~= nil
end

---URL encode string for query parameters
---@param str string String to encode
---@return string # URL-encoded string
local function url_encode(str)
    return string.gsub(str, "([^%w%-%.%_%~%/])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

---Create an OpenCode session
---@param port Port Server port number
---@param cwd string Working directory for session
---@return OpenCodeSession|nil session Session object on success
---@return string|nil error Error message on failure
function M.create_session(port, cwd)
    log.debug("Creating OpenCode session")
    local session, err = request(
        port,
        "POST",
        "/session?directory=" .. url_encode(cwd),
        vim.empty_dict()
    )

    if not session then
        return nil, format_error("Failed to create OpenCode session", err)
    end

    if not session.id then
        return nil, "OpenCode session created without ID"
    end

    log.info(string.format("OpenCode session created: %s", session.id))
    return session
end

---Send prompt to OpenCode session asynchronously
---@param port Port Server port number
---@param session_id string Session identifier
---@param cwd string Working directory
---@param prompt_text string Prompt to send to AI
---@param provider_id? string AI provider ID (optional, uses default if nil)
---@param model_id? string Model ID (optional, uses default if nil)
---@param agent_name? string Agent name (optional)
---@return boolean|nil success True on success
---@return string|nil error Error message on failure
function M.send_prompt_async(
    port,
    session_id,
    cwd,
    prompt_text,
    provider_id,
    model_id,
    agent_name
)
    log.debug("Sending prompt to OpenCode session " .. session_id)
    if agent_name then
        log.debug("Using agent: " .. agent_name)
    end
    if provider_id and model_id then
        log.debug(string.format("Model: %s/%s", provider_id, model_id))
    else
        log.debug("Using default model configuration")
    end
    log.debug(
        "Prompt: "
            .. prompt_text:gsub("\n", " "):sub(1, LOG_PROMPT_LENGTH)
            .. "..."
    )

    -- Build request body
    local body = {
        parts = {
            {
                type = "text",
                text = prompt_text,
            },
        },
    }

    -- Include agent if specified
    if agent_name then
        body.agent = agent_name
    end

    -- Only include model if explicitly provided (otherwise use defaults)
    if provider_id and model_id then
        body.model = {
            providerID = provider_id,
            modelID = model_id,
        }
    end

    local response, err = request(
        port,
        "POST",
        string.format(
            "/session/%s/prompt_async?directory=%s",
            session_id,
            url_encode(cwd)
        ),
        body,
        true -- Allow empty response for async endpoint
    )

    if response then
        log.info("Prompt sent successfully")
        return true
    else
        return nil, format_error("Failed to send prompt to OpenCode", err)
    end
end

---Abort an active session
---@param port Port Server port number
---@param session_id string Session identifier to abort
---@param cwd string Working directory
---@return boolean|nil success True on success
---@return string|nil error Error message on failure
function M.abort_session(port, session_id, cwd)
    log.debug("Aborting OpenCode session " .. session_id)

    local response, err = request(
        port,
        "POST",
        string.format(
            "/session/%s/abort?directory=%s",
            session_id,
            url_encode(cwd)
        ),
        vim.empty_dict(),
        true -- Allow empty response
    )

    if response then
        log.info("Session aborted: " .. session_id)
        return true
    else
        return nil, format_error("Failed to abort session", err)
    end
end

---Subscribe to OpenCode event stream for a session
---Calls on_event callback for each received event using Server-Sent Events (SSE)
---@param port Port Server port number
---@param session_id string Session identifier to monitor
---@param on_event fun(event: OpenCodeEvent, session_id: string) Callback for each event
---@return JobId # Job ID for the curl process
function M.subscribe_to_events(port, session_id, on_event)
    log.debug("Subscribing to OpenCode events for session " .. session_id)

    return vim.fn.jobstart(
        string.format("curl -s -N http://localhost:%d/global/event", port),
        {
            on_stdout = function(_, data)
                if not data then
                    return
                end

                for _, line in ipairs(data) do
                    if line ~= "" and line:match("^data:") then
                        local json_str = line:gsub("^data:%s*", "")
                        local ok, event = pcall(vim.fn.json_decode, json_str)

                        if ok and event and event.payload then
                            -- Call the event handler
                            vim.schedule(function()
                                on_event(event, session_id)
                            end)
                        end
                    end
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
                log.debug(
                    string.format(
                        "OpenCode event stream closed (exit code: %d)",
                        exit_code
                    )
                )
            end,
        }
    )
end

return M
