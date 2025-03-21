# tabtab.nvim

Bring the power of AI code suggestions directly into your Neovim workflow. Inspired by modern AI-powered editors like Cursor and Zed, tabtab.nvim provides intelligent, context-aware code completions that help you write better code faster.

> Disclaimer: This is early stages for tabtab. Expect things to break.

## Features

- **Intelligent Code Suggestions**: Get contextually relevant code completions as you type
- **Tab-Through Experience**: Accept suggestions with a simple Tab press, similar to Cursor and Zed editors
- **Scope-Aware**: Understands your code context to provide more accurate suggestions
- **Diagnostic Integration**: Uses your code diagnostics to improve suggestion quality
- **Multiple LLM Providers**: Support for various AI backends including OpenAI, RunPod, and Alter
- **Minimal UI**: Non-intrusive interface that stays out of your way until you need it

## Requirements

- Neovim >= 0.10.0
- An API key for your chosen LLM provider (OpenAI, Groq, etc.)

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    'gaelph/tabtab.nvim',
    config = function()
        require('tabtab').setup({
            client = {
                provider = "openai",  -- or "tabtab", "runpod", "alter"
                api_key = os.getenv("GROQ_API_KEY"),  -- or your preferred API key
                api_base = "https://api.groq.com/openai",  -- adjust based on provider
                defaults = {
                    model = "qwen-2.5-coder-32b",  -- recommended for performance
                    temperature = 0.3,
                    max_tokens = 4096,
                }
            }
        })
    end
}
```

## Configuration

```lua
require('tabtab').setup({
    -- LLM client configuration
    client = {
        -- Provider to use: "openai", "tabtab", "runpod", or "alter"
        provider = "openai",

        -- API key (defaults to GROQ_API_KEY environment variable)
        api_key = os.getenv("GROQ_API_KEY"),

        -- API base URL
        api_base = "https://api.groq.com/openai",

        -- Default parameters for completions
        defaults = {
            -- Model to use for completions
            model = "qwen-2.5-coder-32b",

            -- Temperature for generation (0.0 to 1.0)
            temperature = 0.3,

            -- Maximum tokens to generate
            max_tokens = 4096,
        },
    },

    -- Cursor tracking configuration
    cursor = {
        -- Filetypes to exclude from cursor tracking
        exclude_filetypes = {
            "TelescopePrompt",
            "neo-tree",
            "NvimTree",
            "lazy",
            "mason",
            "help",
            "quickfix",
            "terminal",
            "Avante",
            "AvanteInput",
            "AvanteSelectedFiles",
            "diffview",
            "NeogitStatus",
        },

        -- Buffer types to exclude from cursor tracking
        exclude_buftypes = {
            "terminal",
        },
    },

	-- Keymaps configuration
	keymaps = {
		accept_or_jump = "<M-Tab>", -- Example keymap for accepting or jumping to the next change
		reject = "<Esc>", -- Example keymap for rejecting a change
	},

    -- Maximum number of changes to keep in history
    history_size = 20,
})
```

## Usage

tabtab.nvim works by analyzing your code context and offering intelligent suggestions as you type:

1. Write code as you normally would
2. When tabtab detects an opportunity for a suggestion, it will offer a completion
3. Press Alt+Tab (default keybinding) to trigger a suggestion
4. Use Tab to accept the suggestion and move through multiple suggestions

### Recommended Models

For the best experience, we recommend using one of these models:

- **Zeta model by Zed Industries**: Great balance of quality and speed
- **Qwen 2.5 Coder 32B from Groq**: Higher capability with good performance

### Current Limitations

tabtab.nvim is under active development. Some areas we're working on:

- Improving trigger detection for more natural suggestion flow
- Refining keybinding options (Alt+Tab isn't ideal for many users)
- Enhancing suggestion quality and speed

While not yet as polished as commercial offerings like Cursor or Supermaven, tabtab.nvim brings similar functionality directly into your Neovim environment.

## How It Works

tabtab.nvim tracks your cursor position and code context to understand what you're working on. When you make changes, it:

1. Captures your current code scope
2. Analyzes recent changes and diagnostics
3. Sends this context to the configured LLM
4. Processes the LLM's response into applicable code hunks
5. Presents suggestions that you can accept with Alt+Tab

This approach allows for contextually relevant suggestions that understand both your immediate code and the broader project structure.

## Contributing

Contributions are welcome! We're particularly interested in:

- Improving suggestion triggering logic
- Adding support for more LLM providers
- Enhancing the UI experience
- Optimizing performance

## License

See [LICENSE](LICENSE)

## Logging

tabtab.nvim includes a comprehensive logging system to help with debugging and understanding the plugin's behavior:

### Configuration

```lua
require('tabtab').setup({
    -- Other configuration options...
    
    -- Logging configuration
    log = {
        -- Log level: "TRACE", "DEBUG", "INFO", "WARN", "ERROR", or "OFF"
        level = "INFO",
        
        -- Optional custom log file path (defaults to $HOME/.local/share/nvim/tabtab.log)
        file = nil,
    },
})
```

### Log Levels

- **TRACE**: Most detailed logging, includes all operations
- **DEBUG**: Detailed information useful for debugging
- **INFO**: General information about normal operation (default)
- **WARN**: Warnings and potential issues
- **ERROR**: Error conditions that might affect functionality
- **OFF**: Disable all logging

### Commands

tabtab.nvim provides commands to interact with logs:

- `:TabTabLogs` - Open the log file in a new buffer
- `:TabTabClearLogs` - Clear the log file

### Log File Location

By default, logs are stored at:
```
$HOME/.local/share/nvim/tabtab.log
```

You can customize this location in the configuration.

