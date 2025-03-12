---@class TabTabLogger
---@field level number The current log level
---@field levels table<string, number> Map of level names to their numeric values
---@field log_file string Path to the log file
local M = {}

-- Define log levels (matching Neovim's log levels)
M.levels = {
  TRACE = 0,
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
  OFF = 5
}

-- Default log level
M.level = M.levels.INFO

-- Default log file path
M.log_file = vim.fn.expand("$HOME/.local/share/nvim/tabtab.log")

-- Ensure log directory exists
local function ensure_log_dir()
  local log_dir = vim.fn.fnamemodify(M.log_file, ":h")
  if vim.fn.isdirectory(log_dir) == 0 then
    vim.fn.mkdir(log_dir, "p")
  end
end

-- Format the log message with timestamp and level
---@param level string The log level
---@param msg string The message to log
---@return string formatted_msg The formatted log message
local function format_log(level, msg)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  return string.format("[%s] [%s] %s", timestamp, level, msg)
end

-- Write a message to the log file
---@param msg string The formatted message to write
local function write_to_file(msg)
  ensure_log_dir()
  
  local file = io.open(M.log_file, "a")
  if file then
    file:write(msg .. "\n")
    file:close()
  end
end

-- Set the log level
---@param level string|number The log level to set (can be string name or numeric value)
function M.set_level(level)
  if type(level) == "string" then
    level = M.levels[level:upper()] or M.levels.INFO
  end
  
  M.level = level
end

-- Log a message at a specific level
---@param level_name string The level name
---@param ... any The message parts to log
local function log_at_level(level_name, ...)
  local level_value = M.levels[level_name]
  
  if level_value >= M.level then
    local parts = {...}
    local msg = ""
    
    for i, part in ipairs(parts) do
      if type(part) == "table" then
        msg = msg .. vim.inspect(part)
      else
        msg = msg .. tostring(part)
      end
      
      if i < #parts then
        msg = msg .. " "
      end
    end
    
    local formatted = format_log(level_name, msg)
    write_to_file(formatted)
  end
end

-- Log functions for each level
function M.trace(...) log_at_level("TRACE", ...) end
function M.debug(...) log_at_level("DEBUG", ...) end
function M.info(...) log_at_level("INFO", ...) end
function M.warn(...) log_at_level("WARN", ...) end
function M.error(...) log_at_level("ERROR", ...) end

-- Open the log file in a new buffer
function M.open()
  ensure_log_dir()
  
  -- Create the file if it doesn't exist
  if vim.fn.filereadable(M.log_file) == 0 then
    local file = io.open(M.log_file, "w")
    if file then
      file:write("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] [INFO] TabTab log file created\n")
      file:close()
    end
  end
  
  -- Open the log file in a new buffer
  vim.cmd("split " .. vim.fn.fnameescape(M.log_file))
  
  -- Set up the buffer for logs
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_option(bufnr, "buftype", "")
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  
  -- Move cursor to the end of the file
  vim.api.nvim_command("normal! G")
  
  -- Set up auto-refresh for the log buffer
  vim.api.nvim_create_autocmd({"FocusGained", "BufEnter"}, {
    buffer = bufnr,
    callback = function()
      local cursor_pos = vim.api.nvim_win_get_cursor(0)
      local at_end = cursor_pos[1] == vim.api.nvim_buf_line_count(bufnr)
      
      vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
      vim.cmd("silent! e")
      vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
      
      if at_end then
        vim.api.nvim_command("normal! G")
      else
        vim.api.nvim_win_set_cursor(0, cursor_pos)
      end
    end
  })
end

-- Clear the log file
function M.clear()
  ensure_log_dir()
  
  local file = io.open(M.log_file, "w")
  if file then
    file:write("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] [INFO] Log file cleared\n")
    file:close()
  end
  
  -- Refresh the log buffer if it's open
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local buf_name = vim.api.nvim_buf_get_name(bufnr)
      if buf_name == M.log_file then
        vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
        vim.cmd("buffer " .. bufnr .. " | e")
      end
    end
  end
end

return M
