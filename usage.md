```lua
local tsteer = require("nvim-tsteer")
tsteer.setup({
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

vim.keymap.set({ "n", "x", "o" }, "[[", tsteer.goto_unit_start)
vim.keymap.set({ "n", "x", "o" }, "]]", tsteer.goto_unit_end)

-- Note that `expr = true` is needed to make visual mode mapping works

-- like `treesitter-unit`, but repeatable to select incrementally
vim.keymap.set("x", "u", tsteer.select_unit_incremental)
vim.keymap.set("o", "u", tsteer.select_unit)
vim.keymap.set("o", "U", tsteer.select_unit_reverse)

vim.keymap.set("x", "n", tsteer.select_next_sibling)
vim.keymap.set("x", "p", tsteer.select_prev_sibling)
vim.keymap.set("x", "P", tsteer.select_parent)
vim.keymap.set("x", "N", tsteer.select_first_child)
vim.keymap.set("x", "[n", tsteer.select_first_sibling)
vim.keymap.set("x", "]n", tsteer.select_last_sibling)

-- like `nvim-treehopper`, but support different hint providers and injection tree
vim.keymap.set("x", "m", tsteer.hint_parents)
vim.keymap.set("o", "m", tsteer.hint_parents)

-- generic node swapping, repeatable
vim.keymap.set("x", "<M-n>", tsteer.swap_next_sibling)
vim.keymap.set("x", "<M-p>", tsteer.swap_prev_sibling)
```
