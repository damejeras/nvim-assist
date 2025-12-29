local M = {}

-- Build the AI prompt for code modification tasks
function M.build_code_modification_prompt(params)
	return string.format(
		[[Task: %s

File: %s
Buffer: %d

Current buffer:
```
%s
```

Selected code:
```
%s
```]],
		params.user_prompt,
		params.filepath,
		params.bufnr,
		params.full_buffer_content,
		params.code_section
	)
end

return M
