-- Minimal init file for running tests
-- This ensures that the tests can find the required modules

-- Add the parent directory to the Lua path
-- local parent_dir = vim.fn.fnamemodify(vim.fn.expand('%:p:h'), ':h:h:h:h')
-- vim.opt.runtimepath:append(parent_dir)
vim.opt.runtimepath:append(os.getenv("HOME") .. "/projects/tabtab.nvim")
vim.opt.runtimepath:append(os.getenv("HOME") .. "/.local/share/nvim/lazy/plenary.nvim")

vim.cmd([[
set rtp+=.
set rtp+=../plenary.nvim
runtime !plugin/plenary.vim
	]])

-- Ensure plenary is available
local has_plenary, _ = pcall(require, "plenary")
if not has_plenary then
	error("Plenary is required for running tests. Please ensure it's installed.")
end
