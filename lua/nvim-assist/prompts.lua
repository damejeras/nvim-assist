local M = {}

---@class PromptParams
---@field user_prompt string User's instruction for code modification
---@field bufnr number Buffer number for context
---@field filepath string Full path to the buffer file
---@field full_buffer_content string Complete buffer content
---@field code_section string Selected code section to modify

---Build the AI prompt for code modification tasks
---Formats user input with buffer context for AI processing
---@param params PromptParams Parameter table with user prompt and buffer context
---@return string # Formatted prompt text ready for AI
function M.build_code_modification_prompt(params)
	return string.format(
		[[%s

Source buffer: %d (%s)

Code selected:
```
%s
```]],
		params.user_prompt,
		params.bufnr,
		params.filepath,
		params.code_section
	)
end

return M
