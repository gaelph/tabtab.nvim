local Differ = require("tabtab.diff")
local defer = require("tabtab.utils.defer")
local log = require("tabtab.log")

local M = {}

---@class TabTabCursorConfig
---@field exclude_filetypes string[]
---@field exclude_buftypes string[]

-- Default settings
local default_config = {
	-- File types to exclude
	exclude_filetypes = {
		"Avante",
		"AvanteInput",
		"TelescopePrompt",
		"neo-tree",
		"NvimTree",
		"lazy",
		"mason",
		"help",
		"quickfix",
		"terminal",
	},
	-- Buffer types to exclude
	exclude_buftypes = {
		"terminal",
		"prompt",
		"quickfix",
		"nofile",
	},
}

---Store instances by buffer
---@type table<number, CursorMonitor>
M.instances = {}

-- Check if buffer should be excluded
---@param bufnr number
---@return boolean
local function should_exclude(bufnr)
	local filetype = vim.bo[bufnr].filetype
	local buftype = vim.bo[bufnr].buftype

	for _, ft in ipairs(default_config.exclude_filetypes) do
		if filetype == ft then
			log.debug(string.format("EXCLUDE buffer %d, filetype %s", bufnr, filetype))
			return true
		end
	end

	for _, bt in ipairs(default_config.exclude_buftypes) do
		if buftype == bt then
			log.debug(string.format("EXCLUDE buffer %d, buftype %s", bufnr, buftype))
			return true
		end
	end

	return false
end

---Get the content of a buffer
---@param bufnr number
---@return string
local function get_buffer_content(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return table.concat(lines, "\n")
end

---@class CursorMonitor
---@field bufnr number
---@field buffer_name string
---@field previous_content string
---@field insert_start_content string  -- Content when insert mode was entered
---@field is_disabled boolean
---@field changes_counter number
---@field insert_timer any  -- Custom timer for insert mode pauses
---@field _emit_diff function
---@field timer any
local CursorMonitor = {}
CursorMonitor.__index = CursorMonitor

local function get_filename(bufnr)
	-- Get the buffer's relative path
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

---Creates a new cursor monitor instance for a buffer.
---@return CursorMonitor|nil
function CursorMonitor.new(bufnr)
	if not should_exclude(bufnr) then
		local self = setmetatable({}, CursorMonitor)
		self.bufnr = bufnr
		self.buffer_name = vim.api.nvim_buf_get_name(bufnr)
		self.previous_content = get_buffer_content(bufnr)
		self.is_disabled = false
		self.insert_start_content = "" -- Initialize insert_start_content

		-- Function to emit diff
		local function _emit_diff(force, no_update)
			if not vim.api.nvim_buf_is_valid(self.bufnr) then
				self:teardown()
				return
			end

			if self.is_disabled then
				return
			end

			local current_content = get_buffer_content(bufnr)
			if current_content == self.previous_content and force then
				vim.api.nvim_exec_autocmds("User", {
					pattern = "TabTabCursorDiff",
					data = {
						bufnr = self.bufnr,
						buffer_name = self.buffer_name,
						no_update = no_update,
					},
				})
			elseif
				self.previous_content ~= "" and self.previous_content ~= current_content
			then
				local diff =
					Differ.diff(self.previous_content, current_content, get_filename(bufnr))
				-- log.debug(diff)
				if diff ~= "" then
					-- Emit a User autocommand with the diff data
					vim.api.nvim_exec_autocmds("User", {
						pattern = "TabTabCursorDiff",
						data = {
							diff = diff,
							bufnr = bufnr,
							buffer_name = self.buffer_name,
							no_update = no_update,
						},
					})
				end
			end
			if not no_update then
				self.previous_content = get_buffer_content(self.bufnr)
			end
		end -- _emit_diff

		local emit_diff, timer = defer.debounce_trailing(_emit_diff, 250) -- Reduced from 500ms
		self._emit_diff = emit_diff
		self.timer = timer
		self.changes_counter = 0
		self.insert_start_content = "" -- Initialize insert_start_content

		-- Create timer for periodic checks (every 2 seconds)
		-- self.check_timer = vim.loop.new_timer()
		-- self.check_timer:start(
		-- 	200,
		-- 	200,
		-- 	vim.schedule_wrap(function()
		-- 		if self.changes_counter > 0 then
		-- 			self:emit_diff()
		-- 		end
		-- 	end)
		-- )

		self:setup_autocmds()

		return self
	end

	return nil
end

---Enables the cursor monitor
function CursorMonitor:disable()
	self.is_disabled = true
end

---Enables the cursor monitor
function CursorMonitor:enable()
	self.is_disabled = false
end

---Computes the diff between the previous and current content
---and emits it as a User autocommand
---@param force boolean|nil
---@param no_update boolean|nil
function CursorMonitor:emit_diff(force, no_update)
	self._emit_diff(force or false, no_update)
	self.changes_counter = 0
end

---Sets the previous content of the buffer to the current content
function CursorMonitor:get_buffer_content()
	if not vim.api.nvim_buf_is_valid(self.bufnr) then
		self:teardown()
		return
	end

	self.previous_content = get_buffer_content(self.bufnr)
end

---Removes the instance from the instances table
---and deletes the associated autocommand group
function CursorMonitor:teardown()
	local group =
		vim.api.nvim_create_augroup("TabTabCursor" .. self.bufnr, { clear = true })

	-- Clean up any pending insert timer
	if self.insert_timer then
		vim.fn.timer_stop(self.insert_timer)
		self.insert_timer = nil
	end

	vim.api.nvim_del_augroup_by_id(group)
	M.instances[self.bufnr] = nil
end

-- Setup autocmds for this instance
function CursorMonitor:setup_autocmds()
	local bufnr = self.bufnr
	local group =
		vim.api.nvim_create_augroup("TabTabCursor" .. bufnr, { clear = true })

	-- Store content when entering insert mode
	vim.api.nvim_create_autocmd({ "ModeChanged" }, {
		group = group,
		pattern = "*:i",
		callback = function(event)
			if event.buf == self.bufnr then
				log.debug(event.event)
				-- Store the buffer content at insert mode start
				self.insert_start_content = get_buffer_content(self.bufnr)
				self.previous_content = self.insert_start_content
				-- Emit diff immediately when entering insert mode
				vim.defer_fn(function()
					self:emit_diff(true, false)
				end, 80)
			end
		end,
	})

	-- Track typing in insert mode and reset the timer
	vim.api.nvim_create_autocmd({ "TextChangedI" }, {
		group = group,
		buffer = bufnr,
		callback = function()
			if should_exclude(self.bufnr) then
				self:teardown()
				return
			end

			-- Cancel any existing timer
			if self.insert_timer then
				vim.fn.timer_stop(self.insert_timer)
				self.insert_timer = nil
			end

			-- Start a new timer that will emit a diff after 300ms of no typing
			self.insert_timer = vim.fn.timer_start(300, function()
				-- Compare current content with insert_start_content
				local current_content = get_buffer_content(self.bufnr)
				if current_content ~= self.insert_start_content then
					self:emit_diff(true, true) -- Don't update previous_content
				end
			end)
		end,
	})

	-- Emit diff when leaving insert mode
	vim.api.nvim_create_autocmd("InsertLeave", {
		group = group,
		buffer = bufnr,
		callback = function()
			-- Cancel any pending insert timer
			if self.insert_timer then
				vim.fn.timer_stop(self.insert_timer)
				self.insert_timer = nil
			end

			-- Emit diff immediately
			self:emit_diff(true, false) -- Will update previous_content
		end,
	})

	-- Track all text changes in normal mode
	vim.api.nvim_create_autocmd({ "TextChanged" }, {
		group = group,
		buffer = bufnr,
		callback = function(event)
			local mode = vim.api.nvim_get_mode()
			if mode.mode == "n" then
				log.debug(event.event)
				self:_emit_diff(false, false)
			end
		end,
	})
end

---Setup function to initialize the module
---@param config TabTabCursorConfig
function M.setup(config)
	-- Merge user config with defaults
	if config then
		default_config = vim.tbl_deep_extend("force", default_config, config)
	end

	-- Create an autocommand for buffer creation
	local group = vim.api.nvim_create_augroup("TabTabCursorInit", { clear = true })

	vim.api.nvim_create_autocmd({ "BufEnter" }, {
		group = group,
		callback = function(args)
			local bufnr = args.buf

			-- Skip if we already have an instance or if buffer should be excluded
			if M.instances[bufnr] or should_exclude(bufnr) then
				if M.instances[bufnr] then
					log.debug("Buffer %d already has an instance, skipping", bufnr)
				end
				return
			end

			-- Create new instance for this buffer
			M.instances[bufnr] = CursorMonitor.new(bufnr)
		end,
	})

	-- Cleanup instances when buffers are deleted
	vim.api.nvim_create_autocmd({ "BufDelete" }, {
		group = group,
		callback = function(args)
			-- Delete the buffer-specific augroup
			xpcall(vim.api.nvim_del_augroup_by_name, function(err)
				log.error(debug.traceback(err))
			end, "TabTabCursor" .. args.buf)
			if M.instances[args.buf] ~= nil then
				local instance = M.instances[args.buf]
				instance.timer:close()

				-- Clean up any pending insert timer
				if instance.insert_timer then
					vim.fn.timer_stop(instance.insert_timer)
					instance.insert_timer = nil
				end

				-- Remove the instance
				M.instances[args.buf] = nil
			end
		end,
	})
end

---Get the cursor monitor instance for a buffer.
---@param bufnr number
---@return CursorMonitor|nil
function M.get_instance(bufnr)
	return M.instances[bufnr]
end

return M
