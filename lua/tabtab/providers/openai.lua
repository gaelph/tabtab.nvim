local TabTabProvider = require("tabtab.providers.tabtab")
local Diagnostic = require("tabtab.diagnostics")
local Prompt = require("tabtab.prompt")

---A provider for the OpenAI API
---@class TabTabOpenAIProvider
---@inherits TabTabProvider
local TabTabOpenAIProvider = {}
TabTabOpenAIProvider.__index = TabTabOpenAIProvider
setmetatable(TabTabOpenAIProvider, { __index = TabTabProvider })

---Creates a new instance of the OpenAI provider
---@param opts TabTabClientConfig
---@return TabTabOpenAIProvider
function TabTabOpenAIProvider.new(opts)
	local instance = setmetatable({}, { __index = TabTabOpenAIProvider })

	local defaults = vim.tbl_deep_extend("force", {
		model = "qwen2.5-0.5b-instruct-mlx",
		temperature = 0.3,
		max_tokens = 1000,
	}, opts.defaults or {})
	instance.api_key = opts.api_key
	instance.api_base = opts.api_base
	instance.api_path = "/v1/chat/completions"
	instance.defaults = defaults

	return instance
end

---@param request TabTabInferenceRequest
function TabTabOpenAIProvider:make_request_body(request, opts)
	opts = vim.tbl_deep_extend("force", {}, self.defaults, opts or {})

	local message = Prompt.format_prompt(request)

	local body = {
		messages = {
			{
				role = "system",
				content = Prompt.system,
			},
			{ role = "user", content = message },
		},
		model = opts.model,
		temperature = opts.temperature,
		max_tokens = opts.max_tokens,
		stream = false,
	}

	return vim.fn.json_encode(body)
end

function TabTabOpenAIProvider:parse_response(response)
	local ok, result = pcall(vim.fn.json_decode, response.body)
	if not ok then
		return nil
	end

	if
		result
		and result.choices
		and result.choices[1]
		and result.choices[1].message
		and result.choices[1].message.content
	then
		return result.choices[1].message.content
	end
end

return TabTabOpenAIProvider
