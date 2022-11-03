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

- Some of those are not well maintained or have a number of issues hard to be resolved.
- Except [tree-climber.nvim](https://github.com/drybalka/tree-climber.nvim), all the plugins do not handle injection tree at all, which means they will not work when your cursor resides in comment region (covered by `comment` parser tree).
- I want all the structural editing stuff to be united for better experience and easy customization to suit my editing flow.

This plugin supports all languages with tree-sitter grammar available.

## Features

TBD (screencast)

The plugin is not bundled with any default mappings, you should assign your own keys for them instead. Here are all the current available mappings.

```lua
local tsteer = require("nvim-tsteer")

vim.keymap.set({ "n", "x", "o" }, "[[", tsteer.goto_unit_start)
vim.keymap.set({ "n", "x", "o" }, "]]", tsteer.goto_unit_end)

-- Note that `expr = true` is needed to make visual mode mapping works

-- like `treesitter-unit`, but repeatable to select incrementally
vim.keymap.set("x", "u", tsteer.select_unit_incremental, { expr = true })
vim.keymap.set("x", "U", tsteer.select_unit_incremental_reverse, { expr = true })
vim.keymap.set("o", "u", tsteer.select_unit)
vim.keymap.set("o", "U", tsteer.select_unit_reverse)

vim.keymap.set("x", "n", tsteer.select_next_sibling, { expr = true })
vim.keymap.set("x", "p", tsteer.select_prev_sibling, { expr = true })
vim.keymap.set("x", "P", tsteer.select_parent, { expr = true })
vim.keymap.set("x", "N", tsteer.select_first_child, { expr = true })
vim.keymap.set("x", "[n", tsteer.select_first_sibling, { expr = true })
vim.keymap.set("x", "]n", tsteer.select_last_sibling, { expr = true })

-- like `nvim-treehopper`, but support different hint providers and injection tree
vim.keymap.set("x", "m", tsteer.hint_parents, { expr = true })
vim.keymap.set("o", "m", tsteer.hint_parents)

-- generic node swapping, repeatable
vim.keymap.set("x", "<M-n>", tsteer.swap_next_sibling, { expr = true })
vim.keymap.set("x", "<M-p>", tsteer.swap_prev_sibling, { expr = true })
```

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
    -- whether to set jump list before node selection
    set_jump = true,
    -- determine whether to select outer region in operator mapping
    operator_outer = function()
        return vim.v.operator == "d"
    end,
    -- which hint provider to use for `hint_parents`
    -- "leap" | "hop"
    hint_provider = "leap",
})
```

If [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) is already installed, I recommend creating mappings only for supported buffers as following:

```lua
-- Define the module at top level of your config
require("nvim-treesitter").define_modules({
  tsteer = {
    attach = fuction(bufnr, lang)
        -- create buffer-local mapping here
    end,
    detach = function() end, -- this is required
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
