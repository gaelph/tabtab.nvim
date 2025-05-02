local Diagnostic = require("tabtab.diagnostics")
local Prompt = require("tabtab.prompt")
local TabTabProvider = require("tabtab.providers.tabtab")
local log = require("tabtab.log")

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
	opts = opts or { defaults = {} }
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
	instance.streams = true
	instance.pending_completion = ""

	return instance
end

---Creates the request body for the OpenAI API
---@param request TabTabInferenceRequest
---@param opts? table
---@return string
function TabTabOpenAIProvider:make_request_body(request, opts)
	opts = vim.tbl_deep_extend("force", {}, self.defaults or {}, opts or {})

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
		stream = true,
	}

	return vim.fn.json_encode(body)
end

---Parses a partial completion from the OpenAI API
---@param response any
---@return string?, string?
function TabTabOpenAIProvider:parse_partial_completion(response)
	if not response then
		return nil, "error no response"
	end
	if not response.body then
		return nil, "error no response body"
	end

	local lines = vim.split(response.body, "\n")
	log.debug(lines)

	--- We need to parse the response line by line
	for _, line in ipairs(lines) do
		local json = line
		json = json:sub(#"data: ")

		if #json == 0 then
			goto continue
		end

		if vim.endswith(line, "[DONE]") then
			local result = self.pending_completion
			self.pending_completion = ""
			return result, nil
		end

		--- W
		local ok, result = pcall(vim.fn.json_decode, json)
		if not ok then
			log.error("error", result, json)
			vim.notify_once(string.format("error: %s", result), vim.log.levels.ERROR)
			goto continue
		end

		if not result then
			vim.notify("No result", vim.log.levels.ERROR)
			return nil, "error no result"
		end

		if result.finish_reason and result.finish_reason == "stop" then
			local finished_result = self.pending_completion
			self.pending_completion = ""
			return finished_result, nil
		end

		if result.finish_reason == nil then
			local token = result.choices[1].delta.content
			local finish_reason = result.choices[1].finish_reason
			if finish_reason == "stop" then
				local finished_result = self.pending_completion
				self.pending_completion = ""
				return finished_result, nil
			end
			if token then
				self.pending_completion = self.pending_completion .. token
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

--- Parses a response from the OpenAI API
---@param response any
---@return string?
function TabTabOpenAIProvider:parse_response(response)
	local ok, result = pcall(vim.fn.json_decode, response.body)
	if not ok then
		log.error("Failed to parse response: ", response.body)
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
	else
		log.error("invalid response: ", vim.inspect(result))
	end
end

return TabTabOpenAIProvider
