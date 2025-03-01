local M = {}

-- Parse the @@ line to extract line numbers
local function parse_hunk_header(header)
	-- @@ -start,count +start,count @@
	local old_start, old_count, new_start, new_count =
		header:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

	return {
		old_start = tonumber(old_start),
		old_count = tonumber(old_count) or 1,
		new_start = tonumber(new_start),
		new_count = tonumber(new_count) or 1,
	}
end

---@class Hunk
---@field start_line number
---@field count number
---@field start_new_line number
---@field start_new_count number
---@field lines string[]

---Parses a diff string into a list of hunks
---@param diff string
---@param start_line number
---@return Hunk[]
function M.parse(diff, start_line)
	-- If no differences, return empty result
	if diff == "" then
		return {}
	end

	---@type Hunk[]
	local hunks = {}
	---@type Hunk|nil
	local current_chunk = nil
	local lines = vim.split(diff, "\n")

	-- Skip the first line (filename)
	for i = 2, #lines do
		local line = lines[i]

		if line:match("^@@") then
			-- Start a new chunk when we see @@ markers
			if current_chunk then
				table.insert(hunks, current_chunk)
			end

			local hunk = parse_hunk_header(line)
			current_chunk = {
				start_line = hunk.old_start + start_line - 1,
				count = hunk.old_count,
				start_new_line = hunk.old_start + start_line - 1,
				start_new_count = hunk.new_count,
				lines = {},
			}
		elseif current_chunk and line ~= "\\ No newline at end of file" then
			-- Add lines to current chunk, preserving the diff markers
			table.insert(current_chunk.lines, line)
		end
	end

	-- Add the last chunk if exists
	if current_chunk then
		table.insert(hunks, current_chunk)
	end

	-- Process each chunk to make it relative to the scope
	for _, chunk in ipairs(hunks) do
		-- Remove any lines that would fall outside the scope
		local valid_lines = {}
		for _, line in ipairs(chunk.lines) do
			-- Keep lines that start with +, -, or space
			if line:match("^[%+%- ]") then
				table.insert(valid_lines, line)
			end
		end
		chunk.lines = valid_lines
	end

	return hunks
end

return M
