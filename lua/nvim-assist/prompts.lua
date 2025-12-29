local M = {}

-- Build the AI prompt for code modification tasks
function M.build_code_modification_prompt(params)
	return string.format(
		[[Task: %s

File: %s
Buffer ID: %d

Current buffer content:
```
%s
```

The specific code section to modify:
```
%s
```

Instructions:
1. Find the EXACT code section shown above in the buffer (it may have moved from its original position)
2. Make the changes as requested in the task
3. Use editor_replace_text with bufnr=%d to replace ONLY that specific code section

CRITICAL:
- Search for the exact code content shown in "The specific code section to modify"
- Do NOT rely on line numbers as the buffer may have changed
- Preserve indentation and formatting unless the task specifically requires changing it
- If you need to refresh the buffer content, use editor_get_buffer with the bufnr]],
		params.user_prompt,
		params.filepath,
		params.bufnr,
		params.full_buffer_content,
		params.code_section,
		params.bufnr
	)
end

return M
