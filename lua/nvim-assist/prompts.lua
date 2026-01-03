local M = {}

-- Build the AI prompt for code modification tasks
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
