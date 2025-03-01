local TabTabProvider = require("tabtab.providers.tabtab")
local Diagnostic = require("tabtab.diagnostics")

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

	local message = string.format(
		[[
Code excerpt:
```
%s
%s
```]],
		request.excerpt.filename,
		request.excerpt.text
	)

	if request.edits and #request.edits > 0 then
		local edits = {} --[[ @as string[] ]]
		for _, edit in ipairs(request.edits) do
			table.insert(
				edits,
				string.format(
					[[User edited %s:
%s]],
					edit.filename,
					edit.diff
				)
			)
		end

		message = string.format(
			[[User edited:
%s

%s]],
			table.concat(edits, "\n"),
			message
		)
	end

	if request.diagnostics and #request.diagnostics > 0 then
		message = string.format("%s\n\nDiagnostics:\n%s", message, Diagnostic.format_diagnostics(request.diagnostics))
	end

	local body = {
		messages = {
			{
				role = "system",
				content = [[You are a code completion assistant. You are given a user's code excerpt and a list of edits they have made to the code. Your task is to provide a completion for the code excerpt based on the edits taking the cursor location into account. The user cursor is at  the <|user_cursor_is_here|> marker. Do not delete that line, complete what comes after the marker. If diagnostics are provided, you should try to fix them. You only provide the completed version of the code between the <|editable_region_start|> and the <|editable_region_end|> tokens in its entirety. You preserve blank lines and indentation, and you match the user's coding style. Avoid leaving placeholder comments. Your output starts with the <|editable_region_start|> token and ends with <|editable_region_end|>. Your output can serve as a replacement for the original code excerpt as-is. Include the lines that are not edited in the output.]],
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
