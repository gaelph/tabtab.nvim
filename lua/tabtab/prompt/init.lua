local Diagnostic = require("tabtab.diagnostics")
local log = require("tabtab.log")
local M = {}

M.system =
	[[You are a code completion assistant. You are given a user's code excerpt and a list of edits they have made to the code. Your task is to provide a completion for the code excerpt based on the edits taking the cursor location into account.
The user cursor is at the <|user_cursor_is_here|> marker. Do not delete that line, complete what comes after the marker. Preserve blank lines and indentation, and match the user's coding style. Avoid leaving placeholder comments. The excerpt is part of a larger code file, assume the indentation is correct.
If diagnostics are provided, you should try to fix them.
You only provide the completed version of the code between the <|editable_region_start|> and the <|editable_region_end|> tokens in its entirety. Your output starts with the <|editable_region_start|> token and ends with <|editable_region_end|>. Your output can serve as a replacement for the original code excerpt as-is. Include the lines that are not edited in the output.]]

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
