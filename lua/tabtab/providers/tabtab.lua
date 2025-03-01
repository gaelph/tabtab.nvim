---@meta

---@abstract
---@class TabTabProvider
---Inference APIs should implement this interface
---@field api_key string
---@field api_base string
---@field api_path string
---@field defaults TabTabConfigDefaultTable
---@field streams boolean
local TabTabProvider = {}
TabTabProvider.__index = TabTabProvider

---@class TabTabInferenceRequest
---@field edits {filename: string, diff: string}[]
---@field excerpt Scope
---@field diagnostics Diagnostic[]

---@param opts TabTabClientConfig
---@return TabTabProvider
function TabTabProvider.new(opts)
	local self = setmetatable({}, TabTabProvider)
	self.api_key = opts.api_key
	self.api_base = opts.api_base
	self.api_path = opts.api_path
	self.defaults = opts.defaults
	---@protected
	self.streams = false
	return self
end

---Must be implemented by the provider
---@param request TabTabInferenceRequest
---@return string
function TabTabProvider:make_request_body(request)
	return vim.fn.json_encode(request)
end

---@param response table|nil
---@return string|nil
---Must be implemented by the provider
function TabTabProvider:parse_response(response)
	return nil
end

---@param response { body: string }|nil
---@return string|nil, string|nil
function TabTabProvider:parse_partial_completion(response)
	return nil, "error not implemented"
end

---Creates a request table for use by the TabTab Client
---@param request TabTabInferenceRequest
function TabTabProvider:make_request(request)
	local body = self:make_request_body(request)

	local headers = {
		["Content-Type"] = "application/json",
		["User-Agent"] = "Zed/0.174.6 (macos; aarch64)",
	}

	if self.api_key ~= nil and #self.api_key > 0 then
		headers["Authorization"] = "Bearer " .. self.api_key
	end

	return {
		url = self.api_base .. self.api_path,
		headers = headers,
		body = body,
	}
end

return TabTabProvider
