# zeta.nvim

A Neovim plugin written in Lua.

## Features

- [List your plugin features here]

## Requirements

- Neovim >= 0.5.0

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    'yourusername/zeta.nvim',
    config = function()
        require('zeta').setup({
            -- your configuration here
        })
    end
}
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    'yourusername/zeta.nvim',
    config = function()
        require('zeta').setup({
            -- your configuration here
        })
    end
}
```

## Configuration

```lua
require('zeta').setup({
    enabled = true,
    -- Add more options as needed
})
```

## Usage

[Explain how to use your plugin]

## Commands

- `:ZetaExample` - Runs the example function

## License

[Your license information]
