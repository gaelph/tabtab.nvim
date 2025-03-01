local parser = require("tabtab.diff.parser")

---@class Differ
local M = {}

---Computes the diff between two strings.
---@param old_content string
---@param new_content string
---@param filename string
---@return string
function M.diff(old_content, new_content, filename)
	-- Create temporary files for diff
	local old_file = vim.fn.tempname()
	local new_file = vim.fn.tempname()

	-- Write contents to temporary files
	vim.fn.writefile(vim.split(old_content, "\n"), old_file)
	vim.fn.writefile(vim.split(new_content, "\n"), new_file)

	-- Get diff using system diff command
	local diff = vim.fn.system({ "diff", "-u", old_file, new_file })

	-- Clean up temporary files
	vim.fn.delete(old_file)
	vim.fn.delete(new_file)

	-- Replace the first two lines (temp file paths) with the relative path
	local diff_lines = vim.split(diff, "\n")
	if #diff_lines >= 2 then
		table.remove(diff_lines, 1) -- Remove first line
		diff_lines[1] = '"' .. filename .. '"' -- Replace second line with relative path
		diff = table.concat(diff_lines, "\n")
	end

	return diff
end

---Computes the diff between two strings.
---@param old_content string
---@param new_content string
---@return string
function M.create_word_diff(old_content, new_content)
	-- Create temporary files for diff
	local old_file = vim.fn.tempname()
	local new_file = vim.fn.tempname()

	-- Write contents to temporary files
	vim.fn.writefile(vim.split(old_content, "\n"), old_file)
	vim.fn.writefile(vim.split(new_content, "\n"), new_file)

	-- Get diff using system diff command with character-level granularity
	-- The regex '.' treats each character as a word boundary
	local diff = vim.fn.system({ "git", "diff", "--word-diff", "--word-diff-regex=.", old_file, new_file })

	-- Clean up temporary files
	vim.fn.delete(old_file)
	vim.fn.delete(new_file)

	return diff
end

---
local function without_autocmds(callback)
	local old_ei = vim.opt.eventignore
	vim.opt.eventignore = "all"

	-- Execute the callback
	callback()

	-- Restore previous settings
	vim.opt.eventignore = old_ei
end

---Move the cursor to a line number
---@param bufnr number
---@param line_number number
---@param start boolean If true, moves to first non-whitespace char, if false moves to end of line
local function move_to_line(bufnr, line_number, start)
	_G.__tabtab_no_clear = true -- will have to be reset to false after the cursor moves

	local line = vim.api.nvim_buf_get_lines(bufnr, line_number - 1, line_number, false)[1]

	if not line then
		return
	end

	local col = 0
	if start then
		-- Find first non-whitespace character
		col = line:match("^%s*()") - 1
		if col < 0 then
			col = 0
		end -- Handle empty lines
	else
		col = math.max(0, #line - 1) -- Move to end of line (0-based index)
	end

	without_autocmds(function()
		local ok, error = pcall(vim.api.nvim_win_set_cursor, 0, { line_number + 1, col })
		if not ok and error then
			vim.print("Moving cursor to " .. line_number + 1 .. ":" .. col .. " failed: " .. error)
		end
	end)
end

---Apply a diff hunk to the current buffer
---@param hunk Hunk A diff hunk containing:
---@param bufnr number The buffer number
---@return nil
function M.apply_hunk(hunk, bufnr)
	without_autocmds(function()
		local current_line = hunk.start_line

		for _, line in ipairs(hunk.lines) do
			local prefix = line:sub(1, 1)
			local content = line:sub(2)

			if prefix == " " then
				-- Context line, just move to next line
				current_line = current_line + 1
			elseif prefix == "-" then
				-- Delete line at current position
				vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, {})
				move_to_line(bufnr, current_line - 1, true)
			elseif prefix == "+" then
				-- Insert new line at current position
				vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, { content })
				move_to_line(bufnr, current_line - 1, false)
				current_line = current_line + 1
			end
		end

		-- Move cursor to the end of the last modified line
		-- if last_modified_line then
		-- 	vim.api.nvim_win_set_cursor(0, { last_modified_line, 0 })
		-- 	vim.cmd("normal! $")
		-- end
	end)
end

---@class WordDiffHunk
---@field start_line number The starting line number of the hunk
---@field new_start_line number The starting line number of the hunk in the new content
---@field count number The number of lines in the hunk
---@field lines WordDiffContent[] The lines in this hunk with their changes

---@class WordDiff
---@field header string[]
---@field hunk WordDiffHunk Hunk containing changes

---@class WordDiffContent
---@field line_num number
---@field absolute_line_num number
---@field changes WordDiffChange[]

---@class WordDiffChange
---@field type "context"|"deletion"|"addition"
---@field text string

-- Parse the @@ line to extract line numbers
local function parse_hunk_header(header)
	-- @@ -start,count +start,count @@
	local old_start, old_count, new_start, new_count = header:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

	return {
		old_start = tonumber(old_start),
		old_count = tonumber(old_count) or 1,
		new_start = tonumber(new_start),
		new_count = tonumber(new_count) or 1,
	}
end

---Parse a git word diff format string and group changes into hunks
---@param diff string The git word diff output
---@return WordDiff
function M.word_diff(diff)
	local result = {
		header = {},
		hunk = nil,
	}

	local in_header = true
	local absolute_line_num = 0
	local hunk_line_num = 0

	for _, line in ipairs(vim.split(diff, "\n")) do
		-- Check if we're still in the header section
		if in_header then
			if line:match("^@@") then
				-- This is the last line of the header
				table.insert(result.header, line)
				in_header = false

				-- Start a new hunk
				local hunk_info = parse_hunk_header(line)
				result.hunk = {
					start_line = hunk_info.old_start,
					count = hunk_info.old_count,
					lines = {},
				}
				absolute_line_num = hunk_info.old_start - 1
				hunk_line_num = 0
			elseif line ~= "" then
				table.insert(result.header, line)
			end
		else
			-- We're in the content section
			absolute_line_num = absolute_line_num + 1
			hunk_line_num = hunk_line_num + 1

			-- Parse the line to extract word diff markers
			local changes = {}
			local pos = 1
			local current_text = ""
			local current_type = "context"

			-- Process the line character by character to handle the markers
			while pos <= #line do
				if line:sub(pos, pos + 1) == "[-" then
					-- Start of deletion
					if current_text ~= "" then
						table.insert(changes, { type = current_type, text = current_text })
						current_text = ""
					end
					current_type = "deletion"
					pos = pos + 2
				elseif line:sub(pos, pos + 1) == "-]" then
					-- End of deletion
					table.insert(changes, { type = current_type, text = current_text })
					current_text = ""
					current_type = "context"
					pos = pos + 2
				elseif line:sub(pos, pos + 1) == "{+" then
					-- Start of addition
					if current_text ~= "" then
						table.insert(changes, { type = current_type, text = current_text })
						current_text = ""
					end
					current_type = "addition"
					pos = pos + 2
				elseif line:sub(pos, pos + 1) == "+}" then
					-- End of addition
					table.insert(changes, { type = current_type, text = current_text })
					current_text = ""
					current_type = "context"
					pos = pos + 2
				else
					-- Regular character
					current_text = current_text .. line:sub(pos, pos)
					pos = pos + 1
				end
			end

			-- Add any remaining text
			if current_text ~= "" then
				table.insert(changes, { type = current_type, text = current_text })
			end

			-- Add this line to the current hunk
			if result.hunk then
				table.insert(result.hunk.lines, {
					line_num = hunk_line_num,
					absolute_line_num = absolute_line_num,
					changes = changes,
				})
			end
		end
	end

	return result
end

function M.parse(diff, start_line)
	return parser.parse(diff, start_line)
end

---Apply a word diff to the current buffer
---@param word_diff WordDiff The result of a call to word_diff
---@param bufnr number The buffer number
---@return nil
function M.apply_word_diff(word_diff, bufnr)
	without_autocmds(function()
		local hunk = word_diff.hunk
		-- Group changes by line
		local line_changes = {}

		for _, line_content in ipairs(hunk.lines) do
			local line_num = line_content.absolute_line_num - 1 -- 0-based for API

			if not line_changes[line_num] then
				line_changes[line_num] = {}
			end

			-- Process each change in the line
			for _, change in ipairs(line_content.changes) do
				table.insert(line_changes[line_num], change)
			end
		end

		-- Apply changes line by line
		for line_num, changes in pairs(line_changes) do
			-- Get the current line content
			local current_line = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)[1] or ""
			local new_line = ""
			local has_changes = false

			-- Reconstruct the line with changes applied
			for _, change in ipairs(changes) do
				if change.type == "context" then
					new_line = new_line .. change.text
				elseif change.type == "addition" then
					new_line = new_line .. change.text
					has_changes = true
				end
				-- Skip deletions as they should not be included in the new content
			end

			-- Only update the line if there were actual changes
			if has_changes then
				vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })
			end
		end

		-- Handle completely new lines (lines that only have additions)
		local new_lines = {}
		local insert_at = nil

		for _, line_content in ipairs(hunk.lines) do
			local line_num = line_content.absolute_line_num - 1 -- 0-based for API
			local is_new_line = true
			local new_line = ""

			for _, change in ipairs(line_content.changes) do
				if change.type == "context" or change.type == "deletion" then
					is_new_line = false
					break
				elseif change.type == "addition" then
					new_line = new_line .. change.text
				end
			end

			if is_new_line and new_line ~= "" then
				table.insert(new_lines, new_line)
				if not insert_at then
					insert_at = line_num
				end
			end
		end

		-- Insert all new lines at once
		if #new_lines > 0 and insert_at then
			vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, new_lines)
		end

		-- Reset the flag that prevents clearing
		_G.__tabtab_no_clear = false
	end)
end

---@type Differ
return M
