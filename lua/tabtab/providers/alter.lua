local TabTabProvider = require("tabtab.providers.tabtab")

---A provider for the OpenAI API
---@class TabTabOpenAIProvider
---@inherits TabTabProvider
---@field pending_completions table<string, string>
local TabTabAlterProvider = {}
TabTabAlterProvider.__index = TabTabAlterProvider
setmetatable(TabTabAlterProvider, { __index = TabTabProvider })

--
function TabTabAlterProvider.new(opts)
	local instance = setmetatable({}, { __index = TabTabAlterProvider })

	local defaults = vim.tbl_deep_extend("force", {
		model = "Groq#llama3.3-70b-versatile",
		-- model = "tabtab-mlx",
		temperature = 0.3,
		max_tokens = 1000,
	}, opts.defaults or {})
	instance.api_key = opts.api_key
	instance.api_base = opts.api_base
	instance.api_path = "/v1/chat/completions"
	instance.defaults = defaults
	instance.streams = true
	instance.pending_completions = {}

	return instance
end

---@param request TabTabInferenceRequest
function TabTabAlterProvider:make_request_body(request, opts)
	opts = vim.tbl_deep_extend("force", {}, self.defaults, opts or {})

	local message = string.format(
		[[
User excerpt:
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
				content = [[You are a code completion assistant. You are given a user's code excerpt and a list of edits they have made to the code. Your task is to provide a completion for the code excerpt based on the edits taking the cursor location into account. If diagnostics are provided, you should try to fix them. You only provide the completed version of the code between the <|editable_region_start|> and the <|editable_region_end|> tokens in its entirety. You preserve blank lines and indentation, and you match the user's coding style. Don't leave placeholder comments, implement the code if necessary. Your output starts with the <|editable_region_start|> token and ends with <|editable_region_end|>. Your output can serve as a replacement for the original code excerpt as-is. Include the lines that are not edited in the output.]],
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

function TabTabAlterProvider:parse_partial_completion(response)
	if not response then
		return nil, "error no response"
	end
	if not response.body then
		return nil, "error no response body"
	end

	local lines = vim.split(response.body, "\n")

	for _, line in ipairs(lines) do
		local json = line:sub(#"data: ")

		local ok, result = pcall(vim.fn.json_decode, json)
		if not ok then
			vim.print("error", result, json)
			goto continue
		end

		if not result then
			return nil, "error no result"
		end

		-- vim.print("result", result)

		if
			result.finish_reason
			and result.finish_reason == "stop"
			and result.id
			and self.pending_completions[result.id]
		then
			local finished_result = self.pending_completions[result.id]
			self.pending_completions[result.id] = nil
			return finished_result, nil
		end

		if result.finish_reason == nil then
			if not self.pending_completions[result.id] then
				self.pending_completions[result.id] = ""
			end
			local token = result.choices[1].delta.content
			local finish_reason = result.choices[1].finish_reason
			if finish_reason == "stop" then
				local finished_result = self.pending_completions[result.id]
				self.pending_completions[result.id] = nil
				return finished_result, nil
			end
			if token then
				self.pending_completions[result.id] = self.pending_completions[result.id] .. token
			else
				goto continue
				-- local completed = self.pending_completions[result.id]
				-- self.pending_completions[result.id] = nil
				-- return completed, nil
			end
		end
		::continue::
	end

	return nil, "error decoding stream"
end

function TabTabAlterProvider:parse_response(response)
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

return TabTabAlterProvider
