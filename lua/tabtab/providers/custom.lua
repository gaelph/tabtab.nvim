local Diagnostic = require("tabtab.diagnostics")
local Prompt = require("tabtab.prompt")
local TabTabProvider = require("tabtab.providers.tabtab")

---A provider for the OpenAI API
---@class TabTabCustomProvider
---@inherits TabTabProvider
local TabTabCustomProvider = {}
TabTabCustomProvider.__index = TabTabCustomProvider
setmetatable(TabTabCustomProvider, { __index = TabTabProvider })

---Creates a new instance of the OpenAI provider
---@param opts TabTabClientConfig
---@return TabTabCustomProvider
function TabTabCustomProvider.new(opts)
	local instance = setmetatable({}, { __index = TabTabCustomProvider })

	local defaults = vim.tbl_deep_extend("force", {
		model = "qwen2.5-0.5b-instruct-mlx",
		temperature = 0.3,
		max_tokens = 1000,
	}, opts.defaults or {})
	instance.api_key = opts.api_key
	instance.api_base = opts.api_base
	instance.api_path = "/completions"
	instance.defaults = defaults

	return instance
end

---@param request TabTabInferenceRequest
function TabTabCustomProvider:make_request_body(request, opts)
	opts = vim.tbl_deep_extend("force", {}, self.defaults, opts or {})

	local body = {
		excerpt = string.format(
			[[```%s:
%s
```]],
			request.excerpt.filename,
			request.excerpt.text
		),
		speculated_output = string.format(
			[[```%s:
%s
```]],
			request.excerpt.filename,
			request.excerpt.text
		),
	}

	local edits = {}
	if request.edits and #request.edits > 0 then
		for _, edit in ipairs(request.edits) do
			table.insert(
				edits,
				string.format(
					[[User edited "%s":
%s]],
					edit.filename,
					edit.diff
				)
			)
		end

		body.edits = table.concat(edits, "\n")
	end

	local diagnostics = {}
	if request.diagnostics and #request.diagnostics > 0 then
		for _, diag in ipairs(request.diagnostics) do
			table.insert(diagnostics, Diagnostic.format_diagnostic(diag))
		end

		body.diagonostics = table.concat(diagnostics, "\n")
	end

	return vim.fn.json_encode(body)
end

function TabTabCustomProvider:parse_response(response)
	local ok, result = pcall(vim.fn.json_decode, response.body)
	if not ok then
		return nil
	end

	if result and result.output then
		return result.output
	end
end

return TabTabCustomProvider
