---@class CustomDiff
local M = {}

---@class WordDiffChange
---@field content string The text content
---@field kind "context"|"deletion"|"addition" The type of change

---@class DiffChange
---@field line number The line number where the change occurs
---@field kind "context"|"deletion"|"addition"|"change" The type of change
---@field content string The content of the line
---@field changes? WordDiffChange[] For "change" type, the word-level changes

---Finds the longest common subsequence between two arrays
---@param a any[] First array
---@param b any[] Second array
---@param eq function|nil Optional equality function
---@return table indices Table with indices of LCS in both arrays
local function longest_common_subsequence(a, b, eq)
	eq = eq or function(x, y)
		return x == y
	end

	local m, n = #a, #b
	local C = {}

	-- Initialize the matrix
	for i = 0, m do
		C[i] = {}
		for j = 0, n do
			C[i][j] = 0
		end
	end

	-- Fill the LCS matrix
	for i = 1, m do
		for j = 1, n do
			if eq(a[i], b[j]) then
				C[i][j] = C[i - 1][j - 1] + 1
			else
				C[i][j] = math.max(C[i - 1][j], C[i][j - 1])
			end
		end
	end

	-- Backtrack to find the actual sequence
	local lcs = {}
	local i, j = m, n

	while i > 0 and j > 0 do
		if eq(a[i], b[j]) then
			table.insert(lcs, 1, { a_idx = i, b_idx = j })
			i = i - 1
			j = j - 1
		elseif C[i - 1][j] >= C[i][j - 1] then
			i = i - 1
		else
			j = j - 1
		end
	end

	return lcs
end

---Splits a string into words and separators
---@param str string The string to split
---@return table tokens Array of tokens
local function tokenize(str)
	local tokens = {}
	local i = 1

	while i <= #str do
		-- Check for word (alphanumeric sequence)
		local word_start, word_end = str:find("[%w_]+", i)
		if word_start == i then
			---@diagnostic disable-next-line: param-type-mismatch
			table.insert(tokens, str:sub(word_start, word_end))
			i = word_end + 1
		else
			-- Handle non-word character
			table.insert(tokens, str:sub(i, i))
			i = i + 1
		end
	end

	return tokens
end

---Performs word-level diffing between two strings
---@param old_str string The old string
---@param new_str string The new string
---@return DiffChange[] changes Array of word-level changes
local function word_diff(old_str, new_str)
	local old_tokens = tokenize(old_str)
	local new_tokens = tokenize(new_str)

	local lcs = longest_common_subsequence(old_tokens, new_tokens)

	-- Convert LCS to maps for quick lookup
	local lcs_map_a = {}
	local lcs_map_b = {}
	for _, pos in ipairs(lcs) do
		lcs_map_a[pos.a_idx] = pos.b_idx
		lcs_map_b[pos.b_idx] = pos.a_idx
	end

	-- Generate the changes
	local changes = {}
	local old_idx, new_idx = 1, 1

	while old_idx <= #old_tokens or new_idx <= #new_tokens do
		if old_idx <= #old_tokens and lcs_map_a[old_idx] then
			-- This token is part of LCS (context)
			table.insert(changes, {
				content = old_tokens[old_idx],
				kind = "context",
			})
			new_idx = lcs_map_a[old_idx] + 1
			old_idx = old_idx + 1
		elseif old_idx <= #old_tokens and new_idx <= #new_tokens then
			-- We have tokens in both sequences that aren't in LCS
			-- Handle deletions first, then additions
			local deletion_start = old_idx
			while old_idx <= #old_tokens and not lcs_map_a[old_idx] do
				old_idx = old_idx + 1
			end

			if old_idx > deletion_start then
				local deletion_content = table.concat({ unpack(old_tokens, deletion_start, old_idx - 1) })
				table.insert(changes, {
					content = deletion_content,
					kind = "deletion",
				})
			end

			local addition_start = new_idx
			while new_idx <= #new_tokens and not lcs_map_b[new_idx] do
				new_idx = new_idx + 1
			end

			if new_idx > addition_start then
				local addition_content = table.concat({ unpack(new_tokens, addition_start, new_idx - 1) })
				table.insert(changes, {
					content = addition_content,
					kind = "addition",
				})
			end
		elseif old_idx <= #old_tokens then
			-- Only old tokens left (deletions)
			local deletion_content = table.concat({ unpack(old_tokens, old_idx) })
			table.insert(changes, {
				content = deletion_content,
				kind = "deletion",
			})
			break
		elseif new_idx <= #new_tokens then
			-- Only new tokens left (additions)
			local addition_content = table.concat({ unpack(new_tokens, new_idx) })
			table.insert(changes, {
				content = addition_content,
				kind = "addition",
			})
			break
		end
	end

	-- Merge adjacent changes of the same type
	local merged_changes = {}
	local current_change = nil

	for _, change in ipairs(changes) do
		if not current_change then
			current_change = vim.deepcopy(change)
		elseif current_change.kind == change.kind then
			current_change.content = current_change.content .. change.content
		else
			table.insert(merged_changes, current_change)
			current_change = vim.deepcopy(change)
		end
	end

	if current_change then
		table.insert(merged_changes, current_change)
	end

	return merged_changes
end

---Computes line-level diff between two strings
---@param old_content string The old content
---@param new_content string The new content
---@return DiffChange[] changes Array of line-level changes
function M.compute_diff(old_content, new_content)
	local old_lines = vim.split(old_content, "\n")
	local new_lines = vim.split(new_content, "\n")

	-- Find the LCS of lines
	local lcs = longest_common_subsequence(old_lines, new_lines)

	-- Convert LCS to a map for quick lookup
	local lcs_map = {}
	for _, pos in ipairs(lcs) do
		lcs_map[pos.a_idx] = pos.b_idx
	end

	-- Generate the changes
	local changes = {}
	local old_idx, new_idx = 1, 1

	while old_idx <= #old_lines or new_idx <= #new_lines do
		if old_idx <= #old_lines and lcs_map[old_idx] then
			-- This line is in both (context)
			table.insert(changes, {
				line = new_idx,
				kind = "context",
				content = new_lines[new_idx],
			})
			old_idx = old_idx + 1
			new_idx = lcs_map[old_idx - 1] + 1
		elseif
			new_idx <= #new_lines
			and old_idx <= #old_lines
			and not lcs_map[old_idx]
			and not vim.tbl_contains(vim.tbl_values(lcs_map), new_idx)
		then
			-- Line changed (not in LCS)
			local change = {
				line = new_idx,
				kind = "change",
				content = new_lines[new_idx],
				changes = word_diff(old_lines[old_idx], new_lines[new_idx]),
			}
			table.insert(changes, change)
			old_idx = old_idx + 1
			new_idx = new_idx + 1
		elseif old_idx <= #old_lines and not lcs_map[old_idx] then
			-- Line deleted
			table.insert(changes, {
				line = new_idx,
				kind = "deletion",
				content = old_lines[old_idx],
			})
			old_idx = old_idx + 1
		elseif new_idx <= #new_lines then
			-- Collect consecutive additions
			local start_idx = new_idx
			local content = new_lines[new_idx]
			new_idx = new_idx + 1

			while new_idx <= #new_lines and not vim.tbl_contains(vim.tbl_values(lcs_map), new_idx) do
				content = content .. "\n" .. new_lines[new_idx]
				new_idx = new_idx + 1
			end

			table.insert(changes, {
				line = start_idx,
				kind = "addition",
				content = content,
			})
		end
	end

	return changes
end

---Formats diff changes as a string for debugging
---@param changes DiffChange[] Array of diff changes
---@return string formatted_diff The formatted diff string
function M.format_diff(changes)
	local result = {}

	for _, change in ipairs(changes) do
		if change.kind == "context" then
			-- Context lines are prepended with a space
			table.insert(result, " " .. change.content)
		elseif change.kind == "deletion" then
			-- Deleted lines are prepended with a minus sign
			table.insert(result, "-" .. change.content)
		elseif change.kind == "addition" then
			-- Added lines are prepended with a plus sign
			-- Split multi-line additions
			local added_lines = vim.split(change.content, "\n")
			for _, line in ipairs(added_lines) do
				table.insert(result, "+" .. line)
			end
		elseif change.kind == "change" then
			-- Changed lines are prepended with a percent sign
			local formatted_line = ""

			for _, word_change in ipairs(change.changes) do
				if word_change.kind == "context" then
					formatted_line = formatted_line .. word_change.content
				elseif word_change.kind == "deletion" then
					formatted_line = formatted_line .. "[-" .. word_change.content .. "-]"
				elseif word_change.kind == "addition" then
					formatted_line = formatted_line .. "{+" .. word_change.content .. "+}"
				end
			end

			table.insert(result, "%" .. formatted_line)
		end
	end

	return table.concat(result, "\n")
end

return M ---@type CustomDiff
