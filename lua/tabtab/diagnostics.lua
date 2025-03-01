local M = {}

---@class Diagnostic
---@field lnum number 0-indexed
---@field col number 0-indexed
---@field message string
---@field source string
---@field code string

--- This module is used to gather diagnostics for a given buffer
--- using the vim.diagnostic module
---@param bufnr number
---@param line_start number
---@param line_end number
---@return Diagnostic[]
function M.get_diagnostics(bufnr, line_start, line_end)
	-- vim.print("Getting diagnostics for " .. bufnr, line_start, line_end)
	local diagnostics = vim.diagnostic.get(bufnr, {
		severity = vim.diagnostic.severity.WARN,
	})

	local usable_diagnostics = {}

	for _, diagnostic in ipairs(diagnostics) do
		if diagnostic.lnum >= line_start and diagnostic.lnum <= line_end then
			table.insert(usable_diagnostics, {
				lnum = diagnostic.lnum,
				col = diagnostic.col,
				message = diagnostic.message,
				source = diagnostic.source,
				code = diagnostic.code,
			})
		end
	end

	return usable_diagnostics
end

---Formats diagnostics into a string
---@param diagnostics Diagnostic[]
---@return string
function M.format_diagnostics(diagnostics)
	local result = {}
	for _, diagnostic in ipairs(diagnostics) do
		table.insert(
			result,
			string.format(
				"[line %s col %s] %s(%s): %s",
				diagnostic.lnum + 1,
				diagnostic.col + 1,
				diagnostic.source,
				diagnostic.code,
				diagnostic.message
			)
		)
	end

	return table.concat(result, "\n")
end

return M
