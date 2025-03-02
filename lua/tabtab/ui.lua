local Differ = require("tabtab.diff")
local M = {}

local ns_id = vim.api.nvim_create_namespace("tabtab_diff_display")
local word_diff_ns_id = vim.api.nvim_create_namespace("tabtab_word_diff_display")
local ui_augroup = vim.api.nvim_create_augroup("TabTabUI", { clear = true })

---@class TabTabBackup
---@field buffer number
---@field buffer_name string
---@field hunk table
---@field hunks table
---@field marks table
---@field word_diff_marks table
---@field original_maps table
---@field cmp_ghost_text_state boolean|nil
---@field conceal_level_bkp number

---Create a new backup state
---@param bufnr number
---@return TabTabBackup
local function new_state(bufnr, hunk, hunks)
	local conceal_level_bkp = vim.api.nvim_get_option_value("conceallevel", { scope = "local" })
	return {
		buffer = bufnr,
		buffer_name = vim.api.nvim_buf_get_name(bufnr),
		hunk = hunk,
		hunks = hunks,
		marks = {},
		word_diff_marks = {},
		original_maps = {},
		cmp_ghost_text_state = nil,
		conceal_level_bkp = conceal_level_bkp,
	}
end

---@type table<number, TabTabBackup>
local states = {}

local function backup_keymaps(bufnr)
	local state = states[bufnr]
	if not state then
		state = new_state(bufnr)
	end

	-- Store original key mappings
	local tab_mapping = vim.fn.maparg("<M-Tab>", "n", false, true)
	local tabi_mapping = vim.fn.maparg("<M-Tab>", "i", false, true)
	local esc_mapping = vim.fn.maparg("<Esc>", "n", false, true)
	local esci_mapping = vim.fn.maparg("<Esc>", "i", false, true)
	state.original_maps = {
		tab = tab_mapping.rhs,
		tabi = tabi_mapping.rhs,
		esc = esc_mapping.rhs,
		esci = esci_mapping.rhs,
	}

	states[bufnr] = state
end

---Restore keymaps for a buffer
---@param bufnr number
local function restore_keymaps(bufnr)
	local state = states[bufnr]
	if not state then
		return
	end

	-- Restore original key mappings
	if state.original_maps.tab then
		vim.keymap.set("n", "<M-Tab>", state.original_maps.tab, { buffer = bufnr })
	else
		vim.keymap.del("n", "<M-Tab>", { buffer = bufnr })
	end

	if state.original_maps.tabi then
		vim.keymap.set("i", "<M-Tab>", state.original_maps.tabi, { buffer = bufnr })
	else
		vim.keymap.del("i", "<M-Tab>", { buffer = bufnr })
	end

	if state.original_maps.esc then
		vim.keymap.set("n", "<Esc>", state.original_maps.esc, { buffer = bufnr })
	else
		vim.keymap.del("n", "<Esc>", { buffer = bufnr })
	end

	if state.original_maps.esci then
		vim.keymap.set("i", "<Esc>", state.original_maps.esci, { buffer = bufnr })
	else
		vim.keymap.del("i", "<Esc>", { buffer = bufnr })
	end
end

function M.clear_diff_display(bufnr)
	local state = states[bufnr]
	if not state then
		return
	end

	local conceal = state.conceal_level_bkp
	vim.api.nvim_set_option_value("conceallevel", conceal, { scope = "local" })

	-- Clear marks and restore original key mappings
	for _, mark in ipairs(state.marks) do
		vim.api.nvim_buf_del_extmark(state.buffer, ns_id, mark)
	end

	-- Clear word diff marks if they exist
	for _, mark in ipairs(state.word_diff_marks or {}) do
		vim.api.nvim_buf_del_extmark(state.buffer, word_diff_ns_id, mark)
	end

	restore_keymaps(bufnr)
	states[bufnr] = nil
end

---Sets an extmark at the end of a line
---@param bufnr number The buffer in which to set the extmark
---@param line number The line to set the extmark at
local function set_extmark_after(bufnr, line)
	return vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
		virt_text = { { "alt Tab ->", "Changed" } },
		virt_text_pos = "eol",
		hl_mode = "replace",
	})
end

---Sets an extmark over a line
---@param bufnr number The buffer in which to set the extmark
---@param line number The line to set the extmark at
---@param content string The content of the extmark
---@param type string The type of the extmark (e.g., "delete", "change")
local function set_extmark_over(bufnr, line, content, type)
	local hi = "Comment"
	local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
	local col = 0

	if type == "delete" then
		hi = "DiffStrikeThrough"
		content = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
	end

	if type == "change" and line == cursor_line - 1 then
		-- if the content of the suggestion on  the line under the cursor is the same
		-- as the content of the original content, from the start of the line to the cursor
		-- then we only show the part of the suggestion that is after the cursor

		-- get the content of the line under the cursor
		local line_start = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]:sub(1, cursor_col) -- only from the start of the line to the cursor
		-- get the content of the suggestion, from the start of the line to the cursor
		local suggestion_start = content:sub(1, cursor_col)
		-- compare the two!
		if line_start == suggestion_start then
			content = content:sub(cursor_col + 1)
			col = cursor_col + 1
		end
	end

	return vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
		virt_text = { { content, hi } },
		virt_text_pos = "overlay",
		virt_text_win_col = col,
		hl_mode = "combine",
	})
end

---Sets an extmark below a line
---@param bufnr number 		The buffer in which to set the extmark
---@param line number 		The line to set the extmark below
---@param lines string[]  The lines to display as virtual text
---@param above boolean 		Whether to place the extmark above the line
---@return number the extmark id
local function set_extmark_lines(bufnr, line, lines, above)
	local virt_lines = {}
	for _, vline in ipairs(lines) do
		virt_lines[#virt_lines + 1] = { { vline, "Comment" } }
	end
	return vim.api.nvim_buf_set_extmark(bufnr, ns_id, line - 1, 0, {
		virt_lines = virt_lines,
		virt_lines_above = above,
		strict = false,
	})
end

---Sets an extmark below a line
---@param bufnr number 		The buffer in which to set the extmark
---@param line number 		The line to set the extmark below
---@param lines string[]  The lines to display as virtual text
---@param _ any						Unused parameter
---@return number the extmark id
local function set_extmark_above(bufnr, line, lines, _)
	local virt_lines = {}
	for _, vline in ipairs(lines) do
		virt_lines[#virt_lines + 1] = { { vline, "Comment" } }
	end
	return vim.api.nvim_buf_set_extmark(bufnr, ns_id, line - 1, 0, {
		virt_lines = virt_lines,
		virt_lines_above = true,
		strict = false,
	})
end

---Close any active completion menu (nvim-cmp or native)
local function close_completion_menu()
	-- Close completion menu if nvim-cmp is available and active
	local has_cmp, cmp = pcall(require, "cmp")
	if has_cmp then
		cmp.abort()
	else
		-- Fallback to traditional pum handling
		if vim.fn.pumvisible() == 1 then
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, true, true), "n", true)
		end
	end
end

---Runs a function without triggering autocommands
---@param callback function The function to run without triggering autocommands
local function without_autocmds(callback)
	local old_ei = vim.opt.eventignore:get()
	vim.opt.eventignore = "all"

	-- Execute the callback
	callback()

	-- Restore previous settings
	vim.opt.eventignore = old_ei
end

local function highlight_hunk(bufnr, hunk)
	local cursor_line, _ = unpack(vim.api.nvim_win_get_cursor(0))

	local current_line = hunk.start_line
	local pending_removal = {}
	local pending_addition_line = nil
	local pending_addition = {}

	local first_line_changed = nil

	local state = states[bufnr]
	if not state then
		return
	end

	-- Skip the first two lines (diff header)
	for _, line in ipairs(hunk.lines) do
		local prefix = line:sub(1, 1)
		local content = line:sub(2)

		if prefix == "-" then
			-- Store the removal to see if it's part of a replacement
			table.insert(pending_removal, {
				line = current_line,
				content = content,
			})

			if first_line_changed == nil then
				first_line_changed = current_line
			end
			--
		elseif prefix == "+" then
			-- Added line
			if first_line_changed == nil then
				first_line_changed = current_line
			end

			if #pending_removal > 0 then
				-- If there was a pending removal, it wasn't part of a replacement
				local removal = pending_removal[1]
				local mark_id = set_extmark_over(bufnr, removal.line - 1, content, "change")
				table.insert(state.marks, mark_id)
				table.remove(pending_removal, 1)
			else
				-- Store the addition as pending
				-- until we reach the next non-addition line
				if pending_addition_line == nil then
					pending_addition_line = current_line - 1
				end

				table.insert(pending_addition, content)
			end
		else -- prefix == " "
			if pending_addition_line ~= nil and #pending_addition > 0 then
				-- Transform pending_addition array into the required format for virt_lines
				local lines = vim.api.nvim_buf_line_count(bufnr)
				pending_addition_line = math.min(pending_addition_line, lines)
				pending_addition_line = math.max(pending_addition_line, 1)

				local mark_id =
					set_extmark_lines(bufnr, pending_addition_line, pending_addition, pending_addition_line == 1)
				table.insert(state.marks, mark_id)
				pending_addition = {}
				pending_addition_line = nil
			end

			-- If there was a pending removal, it wasn't part of a replacement
			if #pending_removal > 0 then
				local removal = pending_removal[#pending_removal]
				-- the overlay text is the current content of the line
				local mark_id = set_extmark_over(bufnr, removal.line - 1, content, "delete")
				table.insert(state.marks, mark_id)
				pending_removal[#pending_removal] = nil
			end
		end

		if prefix ~= "+" then
			current_line = current_line + 1
		end
	end

	-- Handle any remaining pending removal at the end
	if #pending_removal > 0 then
		for _, removal in ipairs(pending_removal) do
			local ok, mark_id = pcall(set_extmark_over, bufnr, removal.line - 1, removal.content, "delete")

			if ok then
				table.insert(state.marks, mark_id)
			end
		end
	end
	if pending_addition_line ~= nil and #pending_addition > 0 then
		-- Transform pending_addition array into the required format for virt_lines
		local ok, mark_id =
			pcall(set_extmark_lines, bufnr, pending_addition_line, pending_addition, pending_addition_line == 1)
		if ok then
			table.insert(state.marks, mark_id)

			pending_addition = {}
			pending_addition_line = nil
			states[bufnr] = state
		end
	end

	---@diagnostic disable-next-line: assign-type-mismatch
	local mode = vim.api.nvim_get_mode().mode ---@type { mode: string, blocking: boolean }
	if first_line_changed and first_line_changed ~= cursor_line and mode.mode ~= "i" and mode.blocking == false then
		without_autocmds(function()
			vim.api.nvim_win_set_cursor(0, { first_line_changed, 0 })
			vim.cmd("normal! ^")
		end)
	end
end

local function accept_hunk()
	local bufnr = vim.api.nvim_get_current_buf()
	local state = states[bufnr]
	if not state then
		return
	end

	M.clear_diff_display(bufnr)
	vim.api.nvim_clear_autocmds({ group = ui_augroup, buffer = bufnr })

	if M.hunk_contains_cursor(state.hunk, bufnr) then
		vim.api.nvim_exec_autocmds("User", {
			pattern = "TabTabAccept",
			data = {
				bufnr = bufnr,
				bufname = vim.api.nvim_buf_get_name(bufnr),
				hunk = state.hunk,
				hunks = state.hunks,
			},
		})
	else
		--- move cursor to the hunk
		without_autocmds(function()
			-- first, find the first line that has been modified
			local line = state.hunk.start_new_line
			for index, l in ipairs(state.hunk.lines) do
				-- get first char of the line to check it is a space
				local first_char = vim.fn.getline(l):sub(1, 1)
				if first_char ~= " " then
					line = line + index
					break
				end
			end

			vim.api.nvim_win_set_cursor(0, { line, 0 })
			vim.cmd("normal! ^")
			vim.schedule(function()
				M.show_hunk(state.hunk, state.hunks, bufnr)
			end)
		end)
	end
end

local function reject_hunk()
	local bufnr = vim.api.nvim_get_current_buf()
	local state = states[bufnr]
	if not state then
		return
	end

	M.clear_diff_display(bufnr)
	states[bufnr] = nil
	vim.api.nvim_clear_autocmds({ group = ui_augroup })

	vim.api.nvim_exec_autocmds("User", {
		pattern = "TabTabReject",
		data = {
			bufnr = bufnr,
			bufname = vim.api.nvim_buf_get_name(bufnr),
		},
	})
end

local function set_keymaps(bufnr)
	vim.keymap.set("n", "<M-Tab>", accept_hunk, { buffer = bufnr })
	vim.keymap.set("i", "<M-Tab>", accept_hunk, { buffer = bufnr })
	vim.keymap.set("n", "<Esc>", reject_hunk, { buffer = bufnr })
	vim.keymap.set("i", "<Esc>", reject_hunk, { buffer = bufnr })
end

local function setup_autocmds(bufnr, hunk)
	-- autocommand to clear the hunk on buffer unload
	vim.api.nvim_create_autocmd("BufUnload", {
		group = ui_augroup,
		buffer = bufnr,
		once = true,
		callback = function(event)
			-- Clear the hunk or perform any cleanup here
			local buf = event.buf
			M.clear_diff_display(buf)
			vim.api.nvim_clear_autocmds({ group = ui_augroup, buffer = buf })
		end,
	})

	if M.hunk_contains_cursor(hunk, bufnr) then
		-- autocommand to clear the hunk on buffer unload
		vim.api.nvim_create_autocmd("CursorMoved", {
			group = ui_augroup,
			buffer = bufnr,
			once = true,
			callback = function(event)
				vim.print("Clearing hunk for buffer " .. bufnr)
				-- Clear the hunk or perform any cleanup here
				local buf = event.buf
				M.clear_diff_display(buf)
				vim.api.nvim_clear_autocmds({ group = ui_augroup, buffer = buf })
			end,
		})

		vim.api.nvim_create_autocmd({ "CursorMovedI" }, {
			group = ui_augroup,
			buffer = bufnr,
			callback = function()
				vim.print("Clearing hunk for buffer " .. bufnr)
				M.clear_diff_display(bufnr)
				highlight_hunk(bufnr, hunk)
			end,
		})
	end
end

---@param hunk Hunk
---@param _ number the buffer number
---@return boolean
function M.hunk_contains_cursor(hunk, _)
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local start_line = hunk.start_line
	local last_line = start_line + #hunk.lines - 1

	return start_line <= cursor_line and cursor_line <= last_line
end

---@param hunk WordDiffHunk
---@param _ number the buffer number
---@return boolean
function M.word_diff_hunk_contains_cursor(hunk, _)
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local start_line = hunk.start_line
	local last_line = start_line + #hunk.lines - 1

	return start_line <= cursor_line and cursor_line <= last_line
end

---Returns the version of the hunk before, and after the application
---of the changes
---@param hunk Hunk
---@return string, string
function M.hunk_get_versions(hunk)
	local old_lines = {} ---@type string[]
	local new_lines = {} ---@type string[]

	for index, line in ipairs(hunk.lines) do
		if line:sub(1, 1) ~= "+" then
			table.insert(old_lines, line:sub(2))
		end
		if line:sub(1, 1) ~= "-" then
			table.insert(new_lines, line:sub(2))
		end
	end

	return table.concat(old_lines, "\n"), table.concat(new_lines, "\n")
end

---Displays a hunk with extmarks
---Sets up keymaps for accepting and rejecting the hunk
---@param hunk Hunk
---@param hunks Hunk[]
---@param bufnr number
function M.show_hunk(hunk, hunks, bufnr)
	M.clear_diff_display(bufnr)
	local state = new_state(bufnr, hunk, hunks)
	states[bufnr] = state

	backup_keymaps(bufnr)

	if M.hunk_contains_cursor(hunk, bufnr) then
		-- Close completion menu if nvim-cmp is available and active
		close_completion_menu()

		local old_content, new_content = M.hunk_get_versions(hunk)

		local plainDiff = Differ.create_word_diff(old_content, new_content)
		-- vim.print("=== WORD DIFF ===")
		-- vim.print(plainDiff)
		local wDiff = Differ.word_diff(plainDiff)

		wDiff.hunk.start_line = hunk.start_line
		wDiff.hunk.new_start_line = hunk.start_new_line

		vim.schedule(function()
			M.highlight_word_diff(wDiff, bufnr)
			-- highlight_hunk(bufnr, hunk)
		end)
	else
		vim.schedule(function()
			local cursor_line, _ = unpack(vim.api.nvim_win_get_cursor(0))
			local mark_id = set_extmark_after(bufnr, cursor_line - 1)

			table.insert(states[bufnr].marks, mark_id)
		end)
	end

	set_keymaps(bufnr)
	setup_autocmds(bufnr, hunk)

	-- vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChangedI" }, {
	-- 	buffer = bufnr,
	-- 	once = true,
	-- 	callback = function()
	-- 		reject_hunk()
	-- 	end,
	-- })
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

---Displays word diff results with extmarks
---@param word_diff WordDiff The result of a call to word_diff
---@param bufnr number The buffer number
function M.highlight_word_diff(word_diff, bufnr)
	local hunk = word_diff.hunk
	local start_line = hunk.start_line
	local new_start_line = hunk.new_start_line - 1

	local pending_new_lines = {}
	local last_line_with_new_content = nil

	local state = states[bufnr]
	if not state then
		vim.notify("Can't highlight word diff: No state found for buffer " .. bufnr, vim.log.levels.ERROR)
		return
	end

	for _, line_content in ipairs(hunk.lines) do
		local line_num = new_start_line + line_content.absolute_line_num - 1 -- 0-based for API

		-- Track positions and content for each type of change
		local changes_by_position = {}
		local context_length = 0
		local context_string = ""

		-- First pass: collect all changes with their positions
		for _, change in ipairs(line_content.changes) do
			if change.type == "context" then
				context_length = context_length + visual_width(change.text)
				context_string = context_string .. change.text
				-- vim.print("context", change.text, #change.text, context_string, context_length)
			else
				table.insert(changes_by_position, {
					type = change.type,
					text = change.text,
					position = context_length,
				})
			end
		end

		-- Second pass: create extmarks at the correct positions
		for i, change in ipairs(changes_by_position) do
			if change.type == "deletion" then
				local mark_id = vim.api.nvim_buf_set_extmark(bufnr, word_diff_ns_id, line_num, 0, {
					virt_text = { { change.text, "DiffStrikeThrough" } },
					virt_text_pos = "overlay",
					virt_text_win_col = change.position,
					hl_mode = "combine",
					priority = 600,
					strict = false,
					conceal = "",
					ui_watched = true,
				})
				table.insert(state.word_diff_marks, mark_id)
			elseif change.type == "addition" then
				if i == #changes_by_position then -- if it is the last change, add a newline
					change.text = change.text .. "\r"
				end
				local mark_id = vim.api.nvim_buf_set_extmark(bufnr, word_diff_ns_id, line_num, change.position, {
					virt_text = { { change.text, "Comment" } },
					virt_text_pos = "inline",
					hl_mode = "combine",
					priority = 180,
					strict = false,
					ui_watched = true,
				})
				table.insert(state.word_diff_marks, mark_id)
			end
		end

		-- Check if this is a completely new line (only additions, no context)
		local is_new_line = true
		local addition_text = ""

		for _, change in ipairs(line_content.changes) do
			if change.type == "context" then
				is_new_line = false
				break
			elseif change.type == "addition" then
				addition_text = addition_text .. change.text
			end
		end
	end
end

return M
