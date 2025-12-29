local M = {}

-- Similarity thresholds for block anchor fallback matching
local SINGLE_CANDIDATE_SIMILARITY_THRESHOLD = 0.0
local MULTIPLE_CANDIDATES_SIMILARITY_THRESHOLD = 0.3

-- Levenshtein distance algorithm implementation
local function levenshtein(a, b)
	if a == "" or b == "" then
		return math.max(#a, #b)
	end

	local matrix = {}
	for i = 0, #a do
		matrix[i] = {}
		for j = 0, #b do
			if i == 0 then
				matrix[i][j] = j
			elseif j == 0 then
				matrix[i][j] = i
			end
		end
	end

	for i = 1, #a do
		for j = 1, #b do
			local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
			matrix[i][j] = math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost)
		end
	end

	return matrix[#a][#b]
end

-- Trim whitespace from string
local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

-- Split content into lines
local function split_into_lines(text)
	return vim.split(text, "\n", { plain = true })
end

-- Extract text content for a range of lines
local function extract_line_range(original_lines, content, start_line, end_line)
	local match_start_index = 0
	for k = 1, start_line - 1 do
		match_start_index = match_start_index + #original_lines[k] + 1
	end

	local match_end_index = match_start_index
	for k = start_line, end_line do
		match_end_index = match_end_index + #original_lines[k]
		if k < end_line then
			match_end_index = match_end_index + 1
		end
	end

	return content:sub(match_start_index + 1, match_end_index)
end

-- Calculate similarity between a block in original_lines and search_lines
local function calculate_block_similarity(original_lines, search_lines, start_line, end_line)
	local search_block_size = #search_lines
	local actual_block_size = end_line - start_line + 1
	local lines_to_check = math.min(search_block_size - 2, actual_block_size - 2)

	if lines_to_check <= 0 then
		return 1.0
	end

	local similarity = 0
	for j = 1, lines_to_check do
		local original_line = trim(original_lines[start_line + j])
		local search_line = trim(search_lines[j + 1])
		local max_len = math.max(#original_line, #search_line)

		if max_len > 0 then
			local distance = levenshtein(original_line, search_line)
			similarity = similarity + (1 - distance / max_len)
		end
	end

	return similarity / lines_to_check
end

-- Remove trailing empty line from lines array if present
local function remove_trailing_empty_line(lines)
	if lines[#lines] == "" then
		table.remove(lines)
	end
end

-- Simple exact match replacer
local function simple_replacer(content, find)
	if content:find(find, 1, true) then
		return { find }
	end
	return {}
end

-- Line-trimmed replacer: match lines when trimmed whitespace is equal
local function line_trimmed_replacer(content, find)
	local results = {}
	local original_lines = split_into_lines(content)
	local search_lines = split_into_lines(find)

	remove_trailing_empty_line(search_lines)

	for i = 1, #original_lines - #search_lines + 1 do
		local matches = true

		for j = 1, #search_lines do
			local original_trimmed = trim(original_lines[i + j - 1])
			local search_trimmed = trim(search_lines[j])

			if original_trimmed ~= search_trimmed then
				matches = false
				break
			end
		end

		if matches then
			local end_line = i + #search_lines - 1
			table.insert(results, extract_line_range(original_lines, content, i, end_line))
		end
	end

	return results
end

-- Block anchor replacer: match blocks using first and last lines as anchors
local function block_anchor_replacer(content, find)
	local results = {}
	local original_lines = split_into_lines(content)
	local search_lines = split_into_lines(find)

	if #search_lines < 3 then
		return results
	end

	remove_trailing_empty_line(search_lines)

	local first_line_search = trim(search_lines[1])
	local last_line_search = trim(search_lines[#search_lines])
	local search_block_size = #search_lines

	-- Find candidates
	local candidates = {}
	for i = 1, #original_lines do
		if trim(original_lines[i]) == first_line_search then
			for j = i + 2, #original_lines do
				if trim(original_lines[j]) == last_line_search then
					table.insert(candidates, { start_line = i, end_line = j })
					break
				end
			end
		end
	end

	if #candidates == 0 then
		return results
	end

	-- Single candidate case
	if #candidates == 1 then
		local candidate = candidates[1]

		local similarity = calculate_block_similarity(
			original_lines,
			search_lines,
			candidate.start_line,
			candidate.end_line
		)

		if similarity >= SINGLE_CANDIDATE_SIMILARITY_THRESHOLD then
			table.insert(results, extract_line_range(original_lines, content, candidate.start_line, candidate.end_line))
		end

		return results
	end

	-- Multiple candidates case
	local best_match = nil
	local max_similarity = -1

	for _, candidate in ipairs(candidates) do
		local similarity = calculate_block_similarity(
			original_lines,
			search_lines,
			candidate.start_line,
			candidate.end_line
		)

		if similarity > max_similarity then
			max_similarity = similarity
			best_match = candidate
		end
	end

	if max_similarity >= MULTIPLE_CANDIDATES_SIMILARITY_THRESHOLD and best_match then
		table.insert(results, extract_line_range(original_lines, content, best_match.start_line, best_match.end_line))
	end

	return results
end

-- Multi-occurrence replacer: find all occurrences
local function multi_occurrence_replacer(content, find)
	local results = {}
	local start_index = 1

	while true do
		local index = content:find(find, start_index, true)
		if not index then
			break
		end

		table.insert(results, find)
		start_index = index + #find
	end

	return results
end

-- Main replace function: tries multiple strategies
function M.replace(content, old_string, new_string, replace_all)
	if old_string == new_string then
		return nil, "old_string and new_string must be different"
	end

	replace_all = replace_all or false
	local not_found = true

	-- Try replacers in order
	local replacers = {
		simple_replacer,
		line_trimmed_replacer,
		block_anchor_replacer,
		multi_occurrence_replacer,
	}

	for _, replacer in ipairs(replacers) do
		local matches = replacer(content, old_string)

		for _, search in ipairs(matches) do
			local index = content:find(search, 1, true)
			if index then
				not_found = false

				if replace_all then
					-- Replace all occurrences
					local result = content:gsub(vim.pesc(search), new_string:gsub("%%", "%%%%"))
					return result, nil
				end

				-- Check for multiple occurrences
				local last_index = content:find(search, index + 1, true)
				if not last_index then
					-- Single unique match, perform replacement
					local result = content:sub(1, index - 1) .. new_string .. content:sub(index + #search)
					return result, nil
				end
				-- Multiple matches found, skip this one
			end
		end
	end

	if not_found then
		return nil, "old_string not found in content"
	end

	return nil,
		"Found multiple matches for old_string. Provide more surrounding lines in old_string to identify the correct match."
end

return M
