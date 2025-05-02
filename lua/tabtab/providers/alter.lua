local Prompt = require("tabtab.prompt")
local TabTabProvider = require("tabtab.providers.tabtab")
local log = require("tabtab.log")

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
	instance.pending_completion = ""

	return instance
end

---@param request TabTabInferenceRequest
function TabTabAlterProvider:make_request_body(request, opts)
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

---
function TabTabAlterProvider:parse_partial_completion(response)
	if not response then
		return nil, "error no response"
	end
	if not response.body then
		return nil, "error no response body"
	end

	local lines = vim.split(response.body, "\n")
	log.debug(lines)

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
				log.debug(self.pending_completion)
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

--- The role of this function is to parse the full response from the API.
--- @param response table The full response from the API.
--- @return string|nil The completion string, or nil if parsing failed.
function TabTabAlterProvider:parse_response(response)
	local ok, result = pcall(vim.fn.json_decode, response.body)
	if not ok then
		vim.notify_once("Error parsing response", vim.log.levels.ERROR)
		log.error(string.format("Error parsing response: %s", response.body))
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
