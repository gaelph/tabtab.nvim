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

local cursor = require("tabtab.cursor")
local ui = require("tabtab.ui")
local Differ = require("tabtab.diff")
local Diagnostic = require("tabtab.diagnostics")
local scope = require("tabtab.scope")
local response_handler = require("tabtab.response") ---@type ResponseHandler
local tabtabClient = require("tabtab.client")

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

---@class TabTabConfig
---@field client TabTabClientOptions Configuration for the LLM client
---@field cursor TabTabCursorOptions Configuration for cursor tracking
---@field keymaps TabTabKeymapOptions Configuration for keymaps
---@field history_size number Maximum number of changes to keep in history

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

---Adds a change to the change history
---Appends the change to the end of the history
---Limits the history to the last 10 changes
---@param change string
function M.add_change(change)
	local lines = vim.split(change, "\n")
	local filename = lines[1]
	table.remove(lines, 1)
	local diff = table.concat(lines, "\n")

	table.insert(M.change_history, {
		filename = filename,
		diff = string.format(
			[[```diff
%s
```]],
			diff
		),
	})
	while #M.change_history > M.config.history_size do
		table.remove(M.change_history, 1)
	end
end

local function setup_event_handlers()
	-- listen to User event
	vim.api.nvim_create_autocmd("User", {
		pattern = "TabTabCursorDiff",
		callback = function(args)
			if not M.client then
				return
			end

			if ui.is_presenting then
				return
			end

			local diff = args.data.diff
			local bufnr = args.data.bufnr
			local buffer_name = args.data.buffer_name

			-- The Excerpt is the current scope with markers for editable regions and cursor position
			local current_scope = scope.get_current_scope(bufnr)
			if current_scope then
				-- If there is a pending change, add the diff to the message
				if diff then
					M.add_change(diff)
				end

				local diagnostics = Diagnostic.get_diagnostics(bufnr, current_scope.start_line, current_scope.end_line)

				---@type TabTabInferenceRequest
				local request = {
					edits = M.change_history,
					excerpt = current_scope,
					diagnostics = diagnostics,
				}

				M.client:complete(request, function(response)
					if not response then
						return
					end

					local hunks = response_handler.process_response(response, current_scope)

					local old_scope = current_scope
					current_scope = scope.get_current_scope(bufnr)

					if current_scope == nil then
						vim.print("No scope found")
						return
					end

					if old_scope.text ~= current_scope.text then
						vim.print("Suggestion discarded because scope has changed")
						return
					end

					if hunks == nil or #hunks == 0 then
						vim.print("No hunks to apply")
						return
					end

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
				print(string.format("No scope found at cursor position in buffer %s", bufnr))
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "TabTabSuggestion",
		callback = function(args)
			local hunks = args.data.hunks
			local bufnr = args.data.bufnr
			local buffer_name = args.data.buffer_name

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
					hunk = candidate
					table.remove(hunks, index)
				end
			end

			-- vim.print("=== HUNKS 1 ===")
			-- vim.print(hunk)
			-- vim.print(hunks)

			if not hunk then
				if #hunks == 0 then
					return
				end
				hunk = hunks[1]
				table.remove(hunks, 1)
			end

			vim.schedule(function()
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

			-- vim.print("=== HUNKS 2 ===")
			-- vim.print(hunks)

			Differ.apply_hunk(hunk, bufnr)

			if #hunks == 0 then
				vim.schedule(function()
					_G.__tabtab_no_clear = false
				end)
				return
			end

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
	tabtabClient.setup(opts.client)
	cursor.setup(opts.cursor)

	M.client = tabtabClient.client

	setup_event_handlers()
end

return M
