# nvim-tsteer

🚗 Various mappings for structural editing powered by tree-sitter.

This plugin was extracted from my dotfiles, consider it as a combination of:

- [nvim-treehopper](https://github.com/mfussenegger/nvim-treehopper)
- [treesitter-unit](https://github.com/David-Kunz/treesitter-unit)
- [Incremental selection of nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter#incremental-selection)

And with some ideas borrowed from:

- [syntax-tree-surfer](https://github.com/ziontee113/syntax-tree-surfer)
- [tree-climber.nvim](https://github.com/drybalka/tree-climber.nvim)

Special credits to the above awesome plugins.

I implemented by myself mainly because:

- Some of those are not well maintained or written in an ugly way, and have many issues which is hard to resolve.
- Except [tree-climber.nvim](https://github.com/drybalka/tree-climber.nvim), all the plugins do not handle injection tree at all, which means they will not work when your cursor resides in comment region (covered by `comment` parser tree).
- I want all the structural editing stuff to be united for better experience and easy customization to suit my editing flow.

This plugin supports all languages with tree-sitter grammar available.

## Features

TBD (screencast)

## Installation

[packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({ "yioneko/nvim-tsteer" })
```

[vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug "yioneko/nvim-tsteer"
```

## Setup

```lua
require('nvim-tsteer').setup({
    -- filter selected node
    filter = function(node, bufnr)
        -- Example: skip all comment nodes
        -- return node:type() ~= "comment"
        return node:named()
    end,
    -- determine whether to select outer region in operator mapping
    operator_outer = function()
        return vim.v.operator == "d"
    end,
    -- which hint provider to use for `hint_parents`
    -- "leap" | "hop"
    hint_provider = "leap",
})
```

The plugin is not bundled with any mappings. You should create your own mappings.

If [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) is already installed, I recommend creating mappings only for supported buffers as following:

```lua
-- Define the module at top level of your config
require("nvim-treesitter").define_modules({
  tsteer = {
    attach = fuction(bufnr, lang)
        -- create buffer-local mapping here
    end,
  }
})

-- And then enable the defined module
require("nvim-treesitter.configs").setup({
    tsteer = {
        enable = true,
        disable = {}, -- you can disable by languages here
    }
})
```

Otherwise, directly creating global mappings is also feasible, but there might be errors if the current buffer do not have tree-sitter parser attached.


