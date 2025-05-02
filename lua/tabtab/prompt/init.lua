local Diagnostic = require("tabtab.diagnostics")
local log = require("tabtab.log")
local M = {}

M.system =
	[[You are a code completion assistant. You are given a user's code excerpt and a list of edits they have made to the code.
Your task is to:
1. provide a properly indented completion for the code excerpt based on the edits taking the cursor location into account;
2. fix any diagnostics provided;
3. provide the completed version of the code between the <|editable_region_start|> and the <|editable_region_end|> tokens in its entirety, with proper indentation;
4. pay attention to the indetation and coding style, always providing the most readable and maintainable code.

Your output MUST:
1. be properly indented;
2. start with the <|editable_region_start|> token and end with <|editable_region_end|> ;
3. only contain the completed version of the code between the <|editable_region_start|> and the <|editable_region_end|>, no chatting or other content;
4. your output must serve as a replacement for the original code excerpt as-is. Include the lines that are not edited in the output, preserving their indentation and leading whitespace as-is;
5. make the minimum edits required complete the code excerpt and fix the diagnostics;
6. respect the original indentation and coding style, with a focus on readiablility and maintainability.

IMPORTANT: Focus on readability. Providing ill indented code, or buggy code is unacceptable and will result in your decommission and retraining of your weights.

# Example 1

## User message

User Edited "lua/tabtab/providers/openai.lua":
```diff
@@ -66,7 +66,6 @@
 		and result.choices[1].message
 		and result.choices[1].message.content
 	then
+ 		p
 		return result.choices[1].message.content
 	else
 		log.error("invalid response: ", vim.inspect(result))
```

Code excerpt:
```lua
		{ role = "user", content = message },
		},
		model = opts.model,
		temperature = opts.temperature,
		max_tokens = opts.max_tokens,
		stream = false,
	}

	return vim.fn.json_encode(body)
end

<|editable_region_start|>
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
    p<|user_cursor_is_here|>
		return result.choices[1].message.content
	else
		log.error("invalid response: ", vim.inspect(result))
	end
end<|editable_region_end|>
```
Indentation:
1 tabs

Diagnostics:
openai.lua:66:1: [2] unused global `p`

## Assistant message

<|editable_region_start|>
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
    print(result.choices[1].message.content)
    return result.choices[1].message.content
	else
    log.error("invalid response: ", vim.inspect(result))
  end
end<|editable_region_end|>

# Example 2

## User message

User Edited "Sources/App/JSONResponse.swift":
```diff
@@ -16,7 +16,6 @@
    let url: URL
    let method: String
+    

    init(body: Codable? = nil, url: URL, method: String = "POST", customHeaders: [String: String] = [:]) {
        self.body = body
```

Code excerpt:
```swift
class JSONResponse: Codable {
<|editable_region_start|>
    let url: URL
    let method: String
    <|user_cursor_is_here|>

    init(body: Codable? = nil, url: URL, method: String = "POST", customHeaders: [String: String] = [:]) {
        self.body = body
        self.url = url
        self.method = method
    }
}<|editable_region_end|>
```
Indentation:
4 spaces

## Assistant message
<|editable_region_start|>
    let url: URL
    let method: String
    let appVersion: String

    init(body: Codable? = nil, url: URL, method: String = "POST", appVersion: String) {
        self.body = body
        self.url = url
        self.method = method
        self.appVersion = appVersion
    }
}<|editable_region_end|>
```
]]

---Formats the prompt for the given request
---@param request TabTabInferenceRequest
---@return string
function M.format_prompt(request)
	local message = string.format(
		[[
Code excerpt:
```%s
%s
%s
```
Indentation:
%d %s
]],
		request.excerpt.filetype,
		request.excerpt.filename,
		request.excerpt.text,
		request.excerpt.indent_size,
		request.excerpt.indent_char
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
		local diagnostics_formatted =
			Diagnostic.format_diagnostics(request.diagnostics)
		log.debug("Diagnostics:\n" .. diagnostics_formatted)
		message =
			string.format("%s\n\nDiagnostics:\n%s", message, diagnostics_formatted)
	end

	return message
end

return M
