local M = {}

---@class Diagnostic
---@field lnum number 0-indexed
---@field col number 0-indexed
---@field message string
---@field source string
---@field code string
---@field severity string
---@field filename string

--- Gets the filename with extension from a buffer number
---@param bufnr number
---@return string filename The filename with extension
function M.get_filename(bufnr)
	local full_path = vim.api.nvim_buf_get_name(bufnr)
	local filename = vim.fn.fnamemodify(full_path, ":t")
	return filename
end

--- This module is used to gather diagnostics for a given buffer
--- using the vim.diagnostic module
---@param bufnr number
---@param line_start number
---@param line_end number
---@return Diagnostic[]
function M.get_diagnostics(bufnr, line_start, line_end)
	local diagnostics = vim.diagnostic.get(bufnr, {
		severity = { min = vim.diagnostic.severity.WARN },
	})

	local usable_diagnostics = {}

	local filename = M.get_filename(bufnr)

	for _, diagnostic in ipairs(diagnostics) do
		if diagnostic.lnum >= line_start and diagnostic.lnum <= line_end then
			table.insert(usable_diagnostics, {
				lnum = diagnostic.lnum,
				col = diagnostic.col,
				message = diagnostic.message,
				source = diagnostic.source,
				code = diagnostic.code,
				severity = diagnostic.severity,
				filename = filename,
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
		-- Map vim.diagnostic severity to text representation
		local severity = "info"
		local diag_severity = diagnostic.severity

		if diag_severity == vim.diagnostic.severity.ERROR then
			severity = "error"
		elseif diag_severity == vim.diagnostic.severity.WARN then
			severity = "warning"
		elseif diag_severity == vim.diagnostic.severity.INFO then
			severity = "info"
		elseif diag_severity == vim.diagnostic.severity.HINT then
			severity = "hint"
		end
		table.insert(
			result,
			string.format(
				"%s:%d:%d: %s: %s [%s(%s)]",
				diagnostic.filename or "unknown",
				diagnostic.lnum + 1,
				diagnostic.col + 1,
				severity,
				diagnostic.message,
				diagnostic.source,
				diagnostic.code
			)
		)
	end

	return table.concat(result, "\n")
end

return M
