local MARKERS = require("tabtab.markers")
local log = require("tabtab.log")

local M = {}

-- Helper function to get relative path of buffer
local function get_relative_path(bufnr)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	-- Get the working directory for the current tab
	local tab_cwd = vim.fn.getcwd(-1, vim.fn.tabpagenr())
	-- Convert absolute path to relative path
	local rel_path = vim.fn.fnamemodify(bufname, ":~:.")
	if tab_cwd then
		rel_path =
			vim.fn.fnamemodify(bufname, ":p"):gsub("^" .. vim.pesc(tab_cwd .. "/"), "")
	end
	return rel_path
end

-- Get the node at the cursor position
local function get_node_at_cursor(bufnr)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	row = row - 1 -- Convert to 0-based indexing

	-- Check if treesitter parser exists for this filetype
	local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
	if not vim.treesitter.language.get_lang(ft) then
		return nil
	end

	-- Get parser and tree
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok or not parser then
		log.error("Failed to get parser for buffer " .. bufnr)
		log.error(debug.traceback(parser))

		return nil
	end

	local tree = parser:parse()[1]
	if not tree then
		return nil
	end

	-- Get root and node at cursor
	local root = tree:root()
	return root:named_descendant_for_range(row, col, row, col)
end

local MAX_EDITABLE_REGION_TOKENS = 450
local MAX_CONTEXT_TOKENS = 100
local CHARACTER_TOKENS = 3

local function tokens_for_node(node, bufnr)
	if not node then
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local text = table.concat(lines, "\n")
		return #text / CHARACTER_TOKENS
	end

	local text = vim.treesitter.get_node_text(node, bufnr)
	return #text / CHARACTER_TOKENS
end

-- Find the closest scope-defining ancestor
local function get_scope_node(node, bufnr)
	while node do
		local parent = node:parent()
		if not parent then
			break
		end
		local tokens = tokens_for_node(parent, bufnr)

		if tokens <= MAX_EDITABLE_REGION_TOKENS then
			node = parent
		else
			break
		end
	end

	if node then
		local start_row, _, end_row, _ = node:range()
		if start_row == end_row then
			return nil
		end
	end

	return node
end

---
---@param start_row number
---@param end_row number
---@param bufnr number
local function expand_scope(start_row, end_row, amount, bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local tokens = 0
	start_row = start_row - 1
	while tokens <= amount / 2 do
		local line = lines[start_row]
		if not line then
			start_row = start_row + 1
			break
		end
		tokens = tokens + (#line / 3)
		start_row = start_row - 1
	end

	tokens = 0
	end_row = end_row + 1
	while tokens <= amount / 2 do
		local line = lines[end_row]
		if line == nil then
			end_row = end_row - 1
			break
		end

		tokens = tokens + (#line / 3)
		end_row = end_row + 1
	end

	local end_col = 1
	if lines[end_row] then
		end_col = #lines[end_row]
	end

	return start_row, 1, end_row, end_col
end

---Get the current scope for a buffer
---@param bufnr number
---@return Scope|nil
function M.get_current_scope(bufnr)
	local node = get_node_at_cursor(bufnr)
	if not node then
		return nil
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local final_line = ""
	if #lines > 0 then
		final_line = lines[#lines]
	end

	local start_row, start_col, end_row, end_col =
		0, 1, #lines - 1, 1 + #final_line

	-- Get current cursor position
	local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
	cursor_row = cursor_row - 1 -- Convert to 0-based indexing
	cursor_col = cursor_col + 1 -- Convert to 1-based indexing

	local scope_node = get_scope_node(node, bufnr)
	if not scope_node then
		start_row, start_col, end_row, end_col =
			expand_scope(cursor_row, cursor_row, MAX_EDITABLE_REGION_TOKENS, bufnr)
	else
		start_row, start_col, end_row, end_col = scope_node:range()
	end
	-- Ensure start_col is non-negative and valid
	start_col = math.max(0, start_col)

	local start_context_row, start_context_col, end_context_row, end_context_col =
		0, 0, #lines - 1, 1 + #final_line

	-- get context node
	start_context_row, start_context_col, end_context_row, end_context_col =
		expand_scope(start_row, end_row, MAX_CONTEXT_TOKENS, bufnr)

	-- Try avoiding indexes out of bounds
	start_context_row = math.max(start_context_row, 0)
	start_context_row = math.min(start_context_row, #lines - 1)
	start_context_col = math.max(start_context_col, 0)
	if lines[start_context_row + 1] then
		start_context_col = math.min(start_context_col, #lines[start_context_row + 1])
	else
		start_context_col = 0
	end

	start_row = math.max(start_row, 0)
	start_row = math.min(start_row, #lines - 1)
	start_col = math.max(start_col, 0)
	if lines[start_row + 1] then
		start_col = math.min(start_col, #lines[start_row + 1])
	else
		start_col = 0
	end

	end_context_row = math.max(end_context_row, 0)
	end_context_row = math.min(end_context_row, #lines - 1)
	end_context_col = math.max(end_context_col, 0)
	if lines[end_context_row + 1] then
		end_context_col = math.min(end_context_col, #lines[end_context_row + 1])
	else
		end_context_col = 0
	end

	end_row = math.max(end_row, 0)
	end_row = math.min(end_row, #lines - 1)
	end_col = math.max(end_col, 0)
	if lines[end_row + 1] then
		end_col = math.min(end_col, #lines[end_row + 1])
	else
		end_col = 0
	end

	-- Ensure cursor position is valid
	cursor_col = math.max(cursor_col, 0)
	if lines[cursor_row + 1] then
		cursor_col = math.min(cursor_col, #lines[cursor_row + 1])
	else
		cursor_col = 0
	end

	-- Ensure cursor_col and start_col are valid
	cursor_col = math.max(0, cursor_col)
	start_col = math.max(0, start_col)

	-- Ensure start_col is less than end_col
	if start_context_row == start_row and start_col <= start_context_col then
		start_context_col = start_col
	end
	if cursor_row > end_row then
		cursor_row = end_row
		local line =
			vim.api.nvim_buf_get_lines(bufnr, cursor_row, cursor_row + 1, false)[1]
		if cursor_col > #line then
			cursor_col = #line
		end
	end
	if start_row == cursor_row and cursor_col < start_col then
		cursor_col = start_col
	end
	if cursor_row == end_row and cursor_col > end_col then
		cursor_col = end_col
	end
	if end_row == end_context_row and end_col > end_context_col then
		end_col = end_context_col
	end

	local start_content = vim.api.nvim_buf_get_text(
		bufnr,
		start_context_row,
		start_context_col,
		start_row,
		start_col,
		{}
	)

	--

	local editable_start = vim.api.nvim_buf_get_text(
		bufnr,
		start_row,
		start_col,
		cursor_row,
		cursor_col,
		{}
	)

	local editable_end =
		vim.api.nvim_buf_get_text(bufnr, cursor_row, cursor_col, end_row, end_col, {})

	local end_content = vim.api.nvim_buf_get_text(
		bufnr,
		end_row,
		end_col,
		end_context_row,
		end_context_col,
		{}
	)

	local text = ""
	if start_context_row == 0 then
		text = text .. MARKERS.START_OF_FILE
	end

	text = text
		.. string.format(
			"%s%s%s%s%s%s",
			table.concat(start_content, "\n"),
			MARKERS.EDITABLE_REGION_START,
			table.concat(editable_start, "\n"),
			MARKERS.CURSOR,
			table.concat(editable_end, "\n"),
			MARKERS.EDITABLE_REGION_END,
			table.concat(end_content, "\n")
		)

	-- Calculate cursor position relative to the start of the scope text
	local cursor_pos = 0
	for i = start_row, cursor_row - 1 do
		cursor_pos = cursor_pos + #lines[i - start_row + 1] + 1 -- +1 for newline
	end
	cursor_pos = cursor_pos + cursor_col

	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	local indent_char = vim.bo.expandtab and "space" or "tab"
	local indent_size = vim.bo.expandtab and vim.bo.tabstop or 1

	return {
		text = text,
		filetype = filetype,
		filename = get_relative_path(bufnr),
		start_line = start_context_row + 1, --1-based line number
		end_line = end_context_row + 1, --1-based line number
		indent_char = indent_char, -- character used for indentation
		indent_size = indent_size, -- number of spaces or tabs used for indentation
	}
end

---@class Scope
---@field text string
---@field filetype string|nil
---@field filename string
---@field start_line number
---@field end_line number
---@field indent_char "tab"|"space"
---@field indent_size integer

return M
