-- Main module file for zeta.nvim
local M = {}

-- Default configuration
M.config = {
    -- Add your default configuration options here
    enabled = true,
    -- Add more options as needed
}

-- Setup function to be called by users
function M.setup(opts)
    -- Merge user options with defaults
    opts = opts or {}
    M.config = vim.tbl_deep_extend("force", M.config, opts)
    
    -- Initialize your plugin here
    -- This is where you would set up any autocommands, mappings, etc.
end

-- Add your plugin's functionality here
function M.example_function()
    -- Example function that does something
    print("Hello from zeta.nvim!")
end

return M
