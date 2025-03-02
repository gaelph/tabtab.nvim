---@meta
---@module 'tabtab.provider.tabtab'

---@type table<string, TabTabProvider>
local providers = require("tabtab.providers")

---@class TabTab
---@field client TabTabClient|nil
local M = {}

--- TabTab Client

---@class TabTabConfigDefaultTable
---@field model string
---@field temperature number
---@field max_tokens number

-- Default configuration
---@class TabTabClientConfig
---@field provider "openai"|"runpod"
---@field api_key string|nil
---@field api_base string
---@field api_path string
---@field timeout number
---@field defaults TabTabConfigDefaultTable
M.config = {
	provider = "openai", --or "runpod"
	api_key = nil,
	api_base = "https://api.openai.com/v1",
	timeout = 30,
	defaults = {
		model = "gpt-3.5-turbo",
		temperature = 0.3,
		max_tokens = 1000,
	},
}

---@class TabTabClient
---@field config TabTabClientConfig
---@field provider TabTabProvider
---@field current_job any|nil
local TabTabClient = {}
TabTabClient.__index = TabTabClient

---Creates a new TabTab Client
---@param opts TabTabClientConfig
---@return TabTabClient|nil, string|nil
function TabTabClient.new(opts)
	local self = setmetatable({}, TabTabClient)
	self.config = vim.tbl_deep_extend("force", M.config, opts)
	self.current_job = nil

	local provider = providers[self.config.provider]
	if provider == nil then
		return nil, "No provider configured"
	end

	---@diagnostic disable-next-line: undefined-field
	self.provider = provider.new(self.config)

	return self, nil
end

---Shuts down the current job
---@private
function TabTabClient:shutdown_current_job()
	if self.current_job then
		if not self.current_job.is_terminated then
			self.current_job:kill(9) -- Send SIGKILL
			vim.print("Previous job cancelled")
		end
		self.current_job = nil
	end
end

---Calls the chat completion API
---@private
---@param request TabTabInferenceRequest
---@param callback fun(response: table|nil, error: string|nil)
function TabTabClient:chat_completion(request, callback)
	if not self.provider then
		callback(nil, "No provider configured")
		return
	end

	self:shutdown_current_job()

	local req = self.provider:make_request(request)

	local url = req.url
	local curl_cmd = { "curl", "-s", "-X", "POST" }

	-- Add headers
	for k, v in pairs(req.headers) do
		table.insert(curl_cmd, "-H")
		table.insert(curl_cmd, string.format("%s: %s", k, v))
	end

	-- Add other curl options
	table.insert(curl_cmd, "--max-time")
	table.insert(curl_cmd, string.format("%d", self.config.timeout))
	-- table.insert(curl_cmd, "-k") -- insecure, equivalent to curl's -k option
	table.insert(curl_cmd, url)

	-- vim.print(curl_cmd)

	-- Add payload
	table.insert(curl_cmd, "-d")
	table.insert(curl_cmd, req.body)

	vim.print("Calling " .. url)
	-- vim.print("---BODY---")
	-- vim.print(req.body)

	-- Create the job
	self.current_job = vim.system(curl_cmd, {
		text = true, -- Ensure text mode output
	}, function(obj)
		if obj.code == 0 and obj.stdout then
			callback({ body = obj.stdout }, nil)
		else
			print("error", obj.code, obj.stderr)
			callback(nil, obj.stderr or "Request failed")
		end
		vim.print("Call done")
	end)
end

---Sends a message to the chat completion API
---@public
---@param request TabTabInferenceRequest
---@param callback fun(response: string|nil)
function TabTabClient:complete(request, callback)
	self:shutdown_current_job()

	-- vim.print("=== MESSAGE ===")
	-- for index, line in ipairs(vim.split(message, "\n")) do
	-- 	vim.print(string.format("%d: %s", index, line))
	-- end

	self:chat_completion(request, function(response, error)
		if error ~= nil then
			print("error", error)
			self:shutdown_current_job()
			callback(nil)
			return
		end

		if response == nil then
			print("no completions", nil)
			self:shutdown_current_job()
			callback(nil)
			return
		end

		if self.provider == nil then
			print("no provider")
			self:shutdown_current_job()
			callback(nil)
			return
		end

		if self.provider.streams then
			vim.schedule(function()
				local result, err = self.provider:parse_partial_completion(response)
				if err ~= nil then
					print("error", err)
					self:shutdown_current_job()
					callback(nil)
					return
				end

				if result ~= nil then
					callback(result)
					return
				end
			end)
		else
			vim.schedule(function()
				local result = self.provider:parse_response(response)
				if result == nil then
					print("no response from provider", response.body)
					self:shutdown_current_job()
					callback(nil)
					return
				end

				callback(result)
			end)
		end
	end)
end

-- Initialize the client with configuration
function M.setup(opts)
	M.client = TabTabClient.new(opts)
end

return M
