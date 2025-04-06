--- @module 'tabtab.client'
--- @module 'tabtab.providers'
--- @module 'tabtab.providers.tabtab'
--- @module 'tabtab.providers.openai'
--- @module 'tabtab.providers.runpod'
--- @module 'tabtab.providers.alter'
--- @module 'tabtab.diff'
--- @module 'tabtab.diff.parser'
--- @module 'tabtab.cursor'
--- @module 'tabtab.scope'
--- @module 'tabtab.log'

local Diagnostic = require("tabtab.diagnostics")
local Differ = require("tabtab.diff")
local cursor = require("tabtab.cursor")
local log = require("tabtab.log")
local response_handler = require("tabtab.response") ---@type ResponseHandler
local scope = require("tabtab.scope")
local tabtabClient = require("tabtab.client")
local ui = require("tabtab.ui")

---@class TabTabClientDefaults
---@field model string The model to use for completions
---@field temperature number The temperature to use for completions
---@field max_tokens number The maximum number of tokens to generate

---@class TabTabClientOptions
---@field provider string The provider to use (e.g., "openai", "tabtab", "runpod", "alter")
---@field api_key string|nil The API key to use
---@field api_base string The API base URL
---@field defaults TabTabClientDefaults Default parameters for completions

---@class TabTabCursorOptions
---@field exclude_filetypes string[] List of filetypes to exclude
---@field exclude_buftypes string[] List of buffer types to exclude

---@class TabTabKeymapOptions
---@field accept_or_jump string The keymap to jump to the next suggestion
---@field reject string The keymap to reject a suggestion

---@class TabTabLogOptions
---@field level string The log level (TRACE, DEBUG, INFO, WARN, ERROR, OFF)
---@field file string|nil Path to the log file (defaults to $HOME/.local/share/nvim/tabtab.log)

---@class TabTabConfig
---@field client TabTabClientOptions Configuration for the LLM client
---@field cursor TabTabCursorOptions Configuration for cursor tracking
---@field keymaps TabTabKeymapOptions Configuration for keymaps
---@field history_size number Maximum number of changes to keep in history
---@field log TabTabLogOptions Configuration for logging

-- Default configuration
local default_config = {
	client = {
		provider = "openai",
		api_key = os.getenv("GROQ_API_KEY"),
		api_base = "https://api.groq.com/openai",
		defaults = {
			model = "qwen-2.5-coder-32b",
			temperature = 0.3,
			max_tokens = 4096,
		},
	},
	cursor = {
		exclude_filetypes = {
			"TelescopePrompt",
			"neo-tree",
			"NvimTree",
			"lazy",
			"mason",
			"help",
			"quickfix",
			"terminal",
			"Avante",
			"AvanteInput",
			"AvanteSelectedFiles",
			"diffview",
			"NeogitStatus",
		},
		exclude_buftypes = {
			"terminal",
		},
	},
	history_size = 20,
	keymaps = {
		accept_or_jump = "<M-Tab>", -- Example keymap for moving to the next change
		reject = "<Esc>", -- Example keymap for rejecting the change
	},
	log = {
		level = "INFO",
		file = nil, -- Use default path
	},
}

-- Module state
---@class TabTabPlugin
---@field config TabTabConfig
---@field client TabTabClient|nil
---@field change_history {filename: string, diff: string}[]
local M = {}
M.config = vim.deepcopy(default_config)
M.client = nil
M.change_history = {}

---Turns a plain text diff into a change object
---@param diff_string string
---@return {filename: string, diff: string}
function M.diff_to_change(diff_string)
	local lines = vim.split(diff_string, "\n")
	local filename = lines[1]
	table.remove(lines, 1)
	local diff = table.concat(lines, "\n")

	return {
		filename = filename,
		diff = string.format(
			[[```diff
%s
```]],
			diff
		),
	}
end

---Adds a change to the change history
---Appends the change to the end of the history
---Limits the history to the last 10 changes
---@param change string
function M.add_change(change)
	log.debug("Adding change to history:", change)

	table.insert(M.change_history, M.diff_to_change(change))

	while #M.change_history > M.config.history_size do
		table.remove(M.change_history, 1)
	end
	log.debug("History size:", #M.change_history)
end

local function setup_event_handlers()
	-- listen to User event
	vim.api.nvim_create_autocmd("User", {
		pattern = "TabTabCursorDiff",
		callback = function(args)
			if not M.client then
				log.warn("No client initialized")
				return
			end

			if ui.is_presenting then
				log.debug("UI is already presenting, ignoring diff")
				return
			end

			local diff = args.data.diff
			local bufnr = args.data.bufnr
			local buffer_name = args.data.buffer_name
			local no_update = args.data.no_update

			log.debug("Received cursor diff event for buffer:", buffer_name)

			-- The Excerpt is the current scope with markers for editable regions and cursor position
			local current_scope = scope.get_current_scope(bufnr)
			if current_scope then
				log.debug(
					"Found scope at lines",
					current_scope.start_line,
					"-",
					current_scope.end_line
				)

				local edits = vim.tbl_map(function(change)
					return change
				end, M.change_history)

				-- If there is a pending change, add the diff to the message
				if diff then
					table.insert(edits, M.diff_to_change(diff))
				end

				local diagnostics = Diagnostic.get_diagnostics(
					bufnr,
					current_scope.start_line,
					current_scope.end_line
				)
				if #diagnostics > 0 then
					log.debug("Found", #diagnostics, "diagnostics in scope")
				end

				---@type TabTabInferenceRequest
				local request = {
					edits = edits,
					excerpt = current_scope,
					diagnostics = diagnostics,
				}

				if diff and not no_update then
					M.add_change(diff)
				end

				log.info(
					"Sending completion request to provider:",
					M.config.client.provider
				)
				M.client:complete(request, function(response)
					if not response then
						log.error("No response received from provider")
						return
					end

					log.debug("Received response from provider")
					local hunks = response_handler.process_response(response, current_scope)

					local old_scope = current_scope
					current_scope = scope.get_current_scope(bufnr)

					if current_scope == nil then
						log.warn("No scope found after response")
						vim.print("No scope found")
						return
					end

					-- if old_scope.text ~= current_scope.text then
					-- 	log.warn("Scope has changed, discarding suggestion")
					-- 	vim.print("Suggestion discarded because scope has changed")
					-- 	return
					-- end

					if ui.is_presenting then
						log.info("UI is already presenting, ignoring diff")
					end

					if hunks == nil or #hunks == 0 then
						log.warn("No hunks to apply")
						vim.print("No hunks to apply")
						return
					end

					log.info("Triggering suggestion event with", #hunks, "hunks")
					vim.api.nvim_exec_autocmds("User", {
						pattern = "TabTabSuggestion",
						data = {
							hunks = hunks,
							bufnr = bufnr,
							buffer_name = buffer_name,
						},
					})
				end)
			else
				log.warn("No scope found at cursor position in buffer", bufnr)
				print(
					string.format("No scope found at cursor position in buffer %s", bufnr)
				)
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "TabTabSuggestion",
		callback = function(args)
			local hunks = args.data.hunks
			local bufnr = args.data.bufnr
			local buffer_name = args.data.buffer_name

			log.debug("Handling suggestion event with", #hunks, "hunks")

			local buffers = vim.api.nvim_list_bufs()
			for _, buffer in ipairs(buffers) do
				if
					vim.api.nvim_buf_is_loaded(buffer)
					and vim.api.nvim_buf_is_valid(buffer)
					and vim.api.nvim_buf_get_name(buffer) == buffer_name
				then
					bufnr = buffer
				end
			end

			local hunk = nil --[[@as Hunk|nil]]

			for index, candidate in ipairs(hunks) do
				if ui.hunk_contains_cursor(candidate, bufnr) then
					log.debug("Found hunk containing cursor at index", index)
					hunk = candidate
					table.remove(hunks, index)
				end
			end

			if not hunk then
				if #hunks == 0 then
					log.warn("No hunks available")
					return
				end
				log.debug("No hunk contains cursor, using first hunk")
				hunk = hunks[1]
				table.remove(hunks, 1)
			end

			vim.schedule(function()
				log.info("Showing hunk with", #hunks, "remaining hunks")
				ui.show_hunk(hunk, hunks, bufnr)
			end)
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "TabTabAccept",
		callback = function(args)
			local bufnr = args.data.bufnr --[[@as number]]
			local hunk = args.data.hunk --[[@as Hunk]]
			local hunks = args.data.hunks --[[@as Hunk[] ]]

			log.info("Accepting hunk with", #hunks, "remaining hunks")
			Differ.apply_hunk(hunk, bufnr)

			if #hunks == 0 then
				log.debug("No more hunks, clearing UI")
				vim.schedule(function()
					_G.__tabtab_no_clear = false
				end)
				return
			end

			log.debug("Triggering suggestion event for next hunk")
			vim.api.nvim_exec_autocmds("User", {
				pattern = "TabTabSuggestion",
				data = {
					bufnr = bufnr,
					hunks = hunks,
				},
			})
		end,
	})
end

_G.__tabtab_no_clear = false

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", default_config, opts or {})

	-- Configure logging first
	if opts.log then
		if opts.log.file then
			log.log_file = opts.log.file
		end
		if opts.log.level then
			log.set_level(opts.log.level)
		end
	end

	log.info("Initializing TabTab with configuration:", vim.inspect(opts))

	tabtabClient.setup(opts.client)
	cursor.setup(opts.cursor)

	M.client = tabtabClient.client
	M.config = opts

	setup_event_handlers()
	log.info("TabTab initialized successfully")
end

return M
