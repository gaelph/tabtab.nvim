---@meta

local MARKERS = require("tabtab.markers")
local Differ = require("tabtab.diff")
---@module 'tabtab.scope'
---@module 'tabtab.diff'

---@class ResponseHandler
local M = {}

-- Extract the text between markers from a string
---@param text string
---@return string|nil, integer
local function extract_between_markers(text)
	local start_marker = MARKERS.EDITABLE_REGION_START
	local end_marker = MARKERS.EDITABLE_REGION_END
	local cursor_marker = MARKERS.CURSOR

	local start_pos = text:find(start_marker)
	if not start_pos then
		start_pos = text:find(start_marker)
	end
	local end_pos = text:find(end_marker)

	if not end_pos then
		end_pos = #text - 1
	end

	if not start_pos or not end_pos then
		return nil, 0
	end

	-- Extract the text between markers, adjusting for marker length
	local extracted = text:sub(start_pos + #start_marker, end_pos - 1)

	-- Remove any cursor markers from the extracted text
	return extracted:gsub(cursor_marker, "")
end

-- Create the final suggestion by replacing content between markers and removing markers
---@param original_excerpt string The original excerpt from the current scope
---@param response string The response from the model
---@return string|nil
local function create_suggestion(original_excerpt, response)
	local start_marker = MARKERS.EDITABLE_REGION_START
	local end_marker = MARKERS.EDITABLE_REGION_END

	-- Extract the new content from response
	local new_content = extract_between_markers(response)
	if not new_content then
		return nil
	end

	-- Find the markers in the original excerpt
	local start_pos = original_excerpt:find(start_marker)
	local end_pos = original_excerpt:find(end_marker)
	if not start_pos or not end_pos then
		return nil
	end

	-- Replace the content between markers and remove the markers
	local before_marker = original_excerpt:sub(1, start_pos - 1)
	local after_marker = original_excerpt:sub(end_pos + #end_marker)

	return before_marker .. new_content .. after_marker
end

local function strip_markers(text)
	local start_marker = MARKERS.EDITABLE_REGION_START
	local end_marker = MARKERS.EDITABLE_REGION_END
	local cursor_marker = MARKERS.CURSOR
	local start_of_file = MARKERS.START_OF_FILE

	local stripped = text:gsub(start_marker, "")
	stripped = stripped:gsub(end_marker, "")
	stripped = stripped:gsub(cursor_marker, "")
	stripped = stripped:gsub(start_of_file, "")

	-- Remove any cursor markers from the extracted text
	return stripped
end

---Create a diff between the current scope and suggested text
---@param response string
---@param current_scope Scope
---@return Hunk[]|nil
function M.process_response(response, current_scope)
	if response == nil then
		vim.notify("Cant' process response: Response is nil", vim.log.levels.ERROR)
		return nil
	end

	-- Get the current content of the traget scope
	-- with markers for editable regions and cursor position
	local original_excerpt = current_scope.text

	-- Get the response content with markers for editable regions and cursor position
	local response_excerpt = response
	local cursor_line, _ = unpack(vim.api.nvim_win_get_cursor(0))
	cursor_line = math.max(cursor_line - current_scope.start_line + 1, 1)

	if not original_excerpt then
		vim.notify("Can't process response: Excerpt is nil", vim.log.levels.ERROR)
		return nil
	end

	-- Create the suggestion by replacing content between markers and removing them
	local suggestion = create_suggestion(original_excerpt, response)
	if not suggestion then
		vim.notify("Could not process markers in response", vim.log.levels.ERROR)
		return nil
	end

	local original = strip_markers(original_excerpt)
	suggestion = strip_markers(suggestion)

	if #suggestion / #original < 0.8 then
		vim.print("!!! Suggestion removes more than 20% of the original content ! ABORT !!!")
		return nil
	end

	-- vim.print("=== ORIGINAL ===")
	-- for index, line in ipairs(vim.split(original, "\n")) do
	-- 	vim.print(string.format("%d: %s", index, line))
	-- end
	--
	-- vim.print("=== RESPONSE ===")
	-- for index, line in ipairs(vim.split(suggestion, "\n")) do
	-- 	vim.print(string.format("%d: %s", index, line))
	-- end

	-- Compute the diff between the current scope and the suggestion
	local diff = Differ.diff(original, suggestion, current_scope.filename)

	-- print("=== SUGGESTION ===")
	-- print(diff)

	-- Return the parsed hunks of the diff for easy processing
	local hunks = Differ.parse(diff, current_scope.start_line)

	return hunks
end

---@type ResponseHandler
return M
