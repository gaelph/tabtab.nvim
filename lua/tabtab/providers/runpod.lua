local TabTabProvider = require("tabtab.providers.tabtab")

---A provider for the Runpod API
---@class TabTabRunpodProvider
---@inherits TabTabProvider
local TabTabRunpodProvider = {}
TabTabRunpodProvider.__index = TabTabRunpodProvider
setmetatable(TabTabRunpodProvider, { __index = TabTabProvider })

--
function TabTabRunpodProvider.new(opts)
	local self = setmetatable({}, { __index = TabTabRunpodProvider })

	local defaults = vim.tbl_deep_extend("force", {
		model = "tabtab-mlx",
		temperature = 0.3,
		max_tokens = 1000,
	}, opts.defaults or {})
	self.api_key = opts.api_key
	self.api_base = opts.api_base
	self.api_path = "/runsync"
	self.defaults = defaults
	self.streams = false

	return self
end

---@param request TabTabInferenceRequest
function TabTabRunpodProvider:make_request_body(request, opts)
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
%s
]],
					edit.filename,
					edit.diff
				)
			)
		end

		message = string.format(
			[[User edited:
%s

%s
			]],
			table.concat(edits, "\n"),
			message
		)
	end

	local body = {
		input = {
			prompt = message,
			sampling_params = {
				temperature = opts.temperature,
				max_tokens = opts.max_tokens,
			},
		},
	}

	return body
end

--
function TabTabRunpodProvider:parse_response(response)
	local ok, result = pcall(vim.fn.json_decode, response.body)
	if not ok then
		return nil
	end

	if
		result
		and result.output
		and result.output[1].choices
		and result.output[1].choices[1]
		and result.output[1].choices[1].tokens
	then
		return result.output[1].choices[1].tokens[1]
	end
end

return TabTabRunpodProvider
