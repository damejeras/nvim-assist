local M = {}

---@class OpenCodeConfig
---@field provider string AI provider (e.g., "openrouter")
---@field model string Model identifier (e.g., "moonshotai/kimi-k2")

---@class NvimAssistConfig
---@field opencode OpenCodeConfig OpenCode server configuration

local opencode = require("nvim-assist.opencode")
local log = require("nvim-assist.log")
local ui = require("nvim-assist.ui")
local prompts = require("nvim-assist.prompts")

---Format error message with optional detail
---@param base_msg string Base error message
---@param err? string Optional error detail
---@return string # Formatted error message
local function format_error(base_msg, err)
    if err then
        return base_msg .. ": " .. err
    end
    return base_msg
end

---Base64 encode a string
---@param data string String to encode
---@return string # Base64 encoded string
local function base64_encode(data)
    local b64chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local result = ""
    local padding = ""

    -- Process input in chunks of 3 bytes
    for i = 1, #data, 3 do
        local byte1 = string.byte(data, i)
        local byte2 = string.byte(data, i + 1)
        local byte3 = string.byte(data, i + 2)

        local bits = byte1 * 65536
        if byte2 then
            bits = bits + byte2 * 256
        end
        if byte3 then
            bits = bits + byte3
        end

        for j = 1, 4 do
            if i + j - 2 > #data and j > 2 then
                padding = padding .. "="
            else
                local index = math.floor(bits / 262144) % 64 + 1
                result = result .. string.sub(b64chars, index, index)
            end
            bits = (bits * 64) % 16777216
        end
    end

    return result .. padding
end

---Constants
local LOG_CONTENT_LENGTH = 100
local AGENT_NAME = "nvim-assist"

---@type NvimAssistConfig # Default configuration
M.config = {
    opencode = {
        provider = "openrouter",
        model = "moonshotai/kimi-k2",
    },
}

---Run the assist operation with OpenCode
---Internal implementation handling session creation, prompt sending, and event monitoring
---@param bufnr number Buffer number
---@param filepath string File path
---@param start_line number Start line (0-indexed)
---@param content string Selected content
---@param user_prompt string User's instruction
local function run_assist(bufnr, filepath, start_line, content, user_prompt)
    -- Ensure OpenCode server is running
    opencode.start(function(port)
        if not port then
            log.error("Failed to get OpenCode server port")
            return vim.notify(
                "Failed to get OpenCode server port",
                vim.log.levels.ERROR
            )
        end

        log.info("OpenCode server running on port " .. port)

        local cwd = vim.fn.getcwd()

        -- Create OpenCode session
        local session, err = opencode.create_session(port, cwd)
        if not session then
            local error_msg =
                format_error("Failed to create OpenCode session", err)
            log.error(error_msg)
            return vim.notify(error_msg, vim.log.levels.ERROR)
        end

        -- Build session URL for browser interface
        -- Format: http://localhost:PORT/BASE64_CWD/session/SESSION_ID
        local encoded_cwd = base64_encode(cwd)
        local session_url = string.format(
            "http://localhost:%d/%s/session/%s",
            port,
            encoded_cwd,
            session.id
        )

        -- Create tracked virtual line above the selection
        local extmark_id = ui.create_tracked_virtual_text(
            bufnr,
            start_line,
            "Starting implementation...",
            session_url
        )

        -- Track current text for spinner updates
        local current_text = "Starting implementation..."

        -- Animate the spinner
        local timer = ui.create_spinner(bufnr, extmark_id, function()
            return current_text
        end, session_url)

        -- Get the full buffer content to provide context
        local full_buffer = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local full_buffer_content = table.concat(full_buffer, "\n")

        -- Build the AI prompt
        local prompt_text = prompts.build_code_modification_prompt({
            user_prompt = user_prompt,
            filepath = filepath,
            bufnr = bufnr,
            full_buffer_content = full_buffer_content,
            code_section = content,
        })

        -- Send prompt asynchronously with agent and model
        local success, err = opencode.send_prompt_async(
            port,
            session.id,
            cwd,
            prompt_text,
            M.config.opencode.provider,
            M.config.opencode.model,
            AGENT_NAME
        )

        if not success then
            timer:stop()
            timer:close()
            ui.clear_virtual_text(bufnr, extmark_id)
            local error_msg = format_error("Failed to send prompt", err)
            log.error(error_msg)
            vim.notify(error_msg, vim.log.levels.ERROR)
            return
        end

        current_text = "Analyzing selection..."

        -- Subscribe to OpenCode events to update UI and track completion
        opencode.subscribe_to_events(port, session.id, function(event)
            -- Update virtual text based on events
            if
                event.payload.type == "message.part.updated"
                and event.payload.properties
            then
                local part = event.payload.properties.part
                if part and part.sessionID == session.id then
                    -- Update virtual text based on part type
                    if part.type == "tool" and part.tool then
                        current_text = string.format("Running %s", part.tool)
                    elseif part.type == "text" then
                        current_text = "Thinking..."
                    end
                end
            elseif
                event.payload.type == "session.idle"
                and event.payload.properties
            then
                -- Session completed
                local sessionID = event.payload.properties.sessionID
                if sessionID == session.id then
                    timer:stop()
                    timer:close()
                    -- Update virtual text to show robot emoji with URL
                    ui.update_virtual_text(
                        bufnr,
                        extmark_id,
                        "🤖 " .. session_url,
                        nil,
                        nil -- Don't show URL on separate line anymore
                    )
                    log.info("Session completed")
                end
            end
        end)
    end)
end

---Main assist function
---Handles visual selection or entire buffer with user prompt
---@param custom_prompt? string Optional prompt (will prompt user if nil)
---@param line1? number Start line from command range (1-indexed)
---@param line2? number End line from command range (1-indexed)
local function assist(custom_prompt, line1, line2)
    log.info("Assist command invoked")

    local bufnr = vim.api.nvim_get_current_buf()
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    local start_line, end_line

    -- If range was provided from command, use it
    if line1 and line2 then
        start_line = line1 - 1 -- Convert to 0-indexed
        end_line = line2 - 1
    else
        -- No range, use entire buffer
        start_line = 0
        end_line = vim.api.nvim_buf_line_count(bufnr) - 1
    end

    -- Capture the content immediately to protect against buffer changes
    local content_lines =
        vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
    local content = table.concat(content_lines, "\n")

    log.debug(
        string.format(
            "Working with lines %d-%d in buffer %d (%s)",
            start_line + 1,
            end_line + 1,
            bufnr,
            filepath
        )
    )
    log.debug(
        string.format(
            "Captured content: %s",
            content:sub(1, LOG_CONTENT_LENGTH)
        )
    )

    -- Highlight the region
    local highlight_marks = ui.highlight_region(bufnr, start_line, end_line)
    vim.cmd("redraw")

    -- If no custom prompt provided, ask user
    if not custom_prompt then
        vim.ui.input({
            prompt = "Prompt: ",
            default = "",
        }, function(input)
            -- Clear highlights
            ui.clear_region_highlights(bufnr, highlight_marks)

            if not input or input == "" then
                log.debug("User cancelled assist")
                return
            end

            -- Continue with the prompt
            run_assist(bufnr, filepath, start_line, content, input)
        end)
    else
        -- Clear highlights and continue immediately
        ui.clear_region_highlights(bufnr, highlight_marks)
        run_assist(bufnr, filepath, start_line, content, custom_prompt)
    end
end

---Setup nvim-assist plugin
---Initializes configuration, logging, commands, and autocommands
---@param user_opts? NvimAssistConfig User configuration (merged with defaults)
function M.setup(user_opts)
    user_opts = user_opts or {}

    vim.keymap.set("v", "<leader>t", ":Assist<CR>")

    -- Merge user config with defaults
    M.config = vim.tbl_deep_extend("force", M.config, user_opts)

    -- Initialize logging
    local temp_dir = os.getenv("TMPDIR") or "/tmp"
    local base_dir = temp_dir .. "/nvim-assist"
    vim.fn.mkdir(base_dir, "p")
    local log_path = base_dir .. "/nvim-assist.log"
    log.init(log_path)

    -- Create single autocommand group for all nvim-assist autocmds
    local augroup = vim.api.nvim_create_augroup("NvimAssist", { clear = true })

    -- Auto-stop OpenCode server and close log on Vim exit
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = augroup,
        callback = function()
            opencode.stop()
            log.close()
        end,
    })

    -- Create :AssistLog command to tail log file
    vim.api.nvim_create_user_command("AssistLog", function()
        log.tail_log()
    end, {})

    -- Create :Assist command to work with visual selections or entire buffer
    vim.api.nvim_create_user_command("Assist", function(opts)
        local custom_prompt = opts.args ~= "" and opts.args or nil
        local line1 = opts.range > 0 and opts.line1 or nil
        local line2 = opts.range > 0 and opts.line2 or nil
        assist(custom_prompt, line1, line2)
    end, {
        nargs = "?",
        range = true,
        desc = "Send selection or buffer to AI assistant",
    })
end

return M
