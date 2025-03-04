---@class CustomDiff
local M = {}

---@class WordDiffChange
---@field content string The text content
---@field kind "context"|"deletion"|"addition" The type of change
---@field visual_position number
---@field actual_position number

---@class DiffChange
---@field line number The line number where the change occurs
---@field kind "context"|"deletion"|"addition"|"change" The type of change
---@field content string The content of the line
---@field changes? WordDiffChange[] For "change" type, the word-level changes

---Finds the longest common subsequence between two arrays
---@param a string[] First array
---@param b string[] Second array
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
		elseif C[i - 1][j] == C[i][j - 1] then
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

---Calculate the visual width of a string, accounting for tabs
---@param str string The string to calculate the width of
---@return number The visual width of the string
local function visual_width(str)
	local expandtab = vim.api.nvim_get_option_value("expandtab", { scope = "local" })
	local tabstop = vim.api.nvim_get_option_value("tabstop", { scope = "local" })

	if expandtab then
		return #str
	end

	local width = 0
	for i = 1, #str do
		local char = str:sub(i, i)
		if char == "\t" then
			-- Calculate how many spaces this tab represents visually
			width = width + tabstop - (width % tabstop)
		else
			width = width + 1
		end
	end
	return width
end

---Find the common whitespace prefix between two strings
---@param str1 string First string
---@param str2 string Second string
---@return string common_prefix The common whitespace prefix
---@return string str1_trimmed The first string with common prefix removed
---@return string str2_trimmed The second string with common prefix removed
local function find_common_whitespace_prefix(str1, str2)
	local i = 1
	local prefix = ""

	-- Find the common whitespace prefix
	while i <= #str1 and i <= #str2 do
		local char1 = str1:sub(i, i)
		local char2 = str2:sub(i, i)

		if char1 == char2 and (char1 == " " or char1 == "\t") then
			prefix = prefix .. char1
			i = i + 1
		else
			break
		end
	end

	return prefix, str1:sub(#prefix + 1), str2:sub(#prefix + 1)
end

---Performs word-level diffing between two strings
---@param old_str string The old string
---@param new_str string The new string
---@return WordDiffChange[] changes Array of word-level changes
local function word_diff(old_str, new_str)
	-- Handle common whitespace prefix
	local common_prefix, old_trimmed, new_trimmed = find_common_whitespace_prefix(old_str, new_str)

	-- Tokenize the trimmed strings
	local old_tokens = tokenize(old_trimmed)
	local new_tokens = tokenize(new_trimmed)

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

	-- Add the common prefix as a context change if it exists
	if #common_prefix > 0 then
		table.insert(changes, {
			content = common_prefix,
			kind = "context",
			visual_position = 0,
			actual_position = 0,
		})
	end

	local old_idx, new_idx = 1, 1

	while old_idx <= #old_tokens or new_idx <= #new_tokens do
		if old_idx <= #old_tokens and lcs_map_a[old_idx] and lcs_map_b[new_idx] then
			-- This token is part of LCS (context)
			table.insert(changes, {
				content = old_tokens[old_idx],
				kind = "context",
			})
			new_idx = new_idx + 1
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

	-- Track positions for changes
	local visual_pos = 0
	local actual_pos = 0

	for _, change in ipairs(changes) do
		if not current_change then
			current_change = vim.deepcopy(change)
			if not current_change.visual_position then
				current_change.visual_position = visual_pos
			end
			if not current_change.actual_position then
				current_change.actual_position = actual_pos
			end
		elseif current_change.kind == change.kind then
			current_change.content = current_change.content .. change.content
		else
			table.insert(merged_changes, current_change)
			visual_pos = current_change.visual_position + visual_width(current_change.content)
			actual_pos = current_change.actual_position + #current_change.content

			local next = vim.deepcopy(change)
			if not next.visual_position then
				next.visual_position = visual_pos
			end
			if not next.actual_position then
				next.actual_position = actual_pos
			end

			current_change = next
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
	local lcs_map_a = {}
	local lcs_map_b = {}
	for _, pos in ipairs(lcs) do
		lcs_map_a[pos.a_idx] = pos.b_idx
		lcs_map_b[pos.b_idx] = pos.a_idx
	end

	-- Generate the changes
	local changes = {}
	local old_idx, new_idx = 1, 1

	while old_idx <= #old_lines or new_idx <= #new_lines do
		if old_idx <= #old_lines and lcs_map_a[old_idx] and lcs_map_b[new_idx] then
			-- this token is part of LCS (context)
			table.insert(changes, {
				content = old_lines[old_idx],
				kind = "context",
				line = new_idx,
			})
			new_idx = new_idx + 1
			old_idx = old_idx + 1

		-- change
		elseif
			old_idx <= #old_lines
			and new_idx <= #new_lines
			and not lcs_map_a[old_idx]
			and not lcs_map_b[new_idx]
		then
			-- we have lines in both sequences that aren't in any LCS
			local wdiff = word_diff(old_lines[old_idx], new_lines[new_idx])
			if #wdiff == 1 then
				if wdiff[1].kind ~= "context" then
					table.insert(changes, {
						content = old_lines[old_idx],
						kind = "deletion",
						line = old_idx,
					})
					table.insert(changes, {
						content = new_lines[new_idx],
						kind = "addition",
						line = new_idx,
					})
				else
					table.insert(changes, {
						content = old_lines[old_idx],
						kind = "context",
						line = new_idx,
					})
				end
			else -- if #wdiff == 1
				table.insert(changes, {
					content = new_lines[new_idx],
					kind = "change",
					line = new_idx,
					changes = wdiff,
				})
			end
			old_idx = old_idx + 1
			new_idx = new_idx + 1

		-- deletion
		elseif old_idx <= #old_lines and not lcs_map_a[old_idx] then
			table.insert(changes, {
				content = old_lines[old_idx],
				kind = "deletion",
				line = old_idx,
			})
			old_idx = old_idx + 1

			-- addition
		elseif new_idx <= #new_lines and not lcs_map_b[new_idx] then
			local last_change = changes[#changes]
			local current_content = nil
			local line = new_idx
			if last_change and last_change.kind == "addition" then
				line = last_change.line
				current_content = vim.split(last_change.content, "\n")
				table.remove(changes, #changes)
			else
				current_content = {}
			end
			table.insert(current_content, new_lines[new_idx])

			table.insert(changes, {
				line = line,
				content = table.concat(current_content, "\n"),
				kind = "addition",
			})
			new_idx = new_idx + 1
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
