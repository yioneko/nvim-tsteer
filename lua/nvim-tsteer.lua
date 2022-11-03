-- TODO: 1. multiple nodes selection 2. history
local o = require("nvim-tsteer.config")
local hint = require("nvim-tsteer.hint")
local utils = require("nvim-tsteer.utils")
local TSCursor = require("nvim-tsteer.cursor")

local M = {}

local state = {
  in_select = false,
  au_id = nil,
  winnr = nil,
  visual_mode = nil,
  expand = false, -- TODO
  selected_node = nil,
  prev_range = nil,
  tscurosr = nil,
}

local function clear_visual_detect_au()
  if state.au_id ~= nil then
    pcall(vim.api.nvim_del_autocmd, state.au_id)
  end
  state.au_id = nil
end

local function reset_select_state()
  clear_visual_detect_au()
  state.winnr = nil
  state.in_select = false
  state.visual_mode = nil
  state.selected_node = nil
  state.prev_range = nil
  state.tscurosr = nil
end

local function node_filter(node, bufnr)
  return o.get().filter(node, bufnr) and not utils.is_node_text_empty(node, bufnr)
end

local function sync_select_state(winnr, range)
  winnr = winnr or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winnr)
  range = range or state.prev_range or utils.get_cursor_range(winnr)
  if
    winnr == state.winnr
    and state.tscurosr
    and utils.range_contains(utils.node_range(state.tscurosr:deref()), range)
  then
    return state.tscurosr
  end
  local node = utils.get_node_for_range(winnr, range)
  local parser = utils.get_parser(vim.api.nvim_win_get_buf(winnr))
  local tcurosr = TSCursor:new(node, bufnr, parser, node_filter)

  -- sift up for node with same range
  -- TODO: not much friendly to child navigation
  while node and tcurosr:parent() and utils.node_contains(node, tcurosr:parent()) do
    node = tcurosr:to_parent()
  end

  state.selected_node = node
  state.tscurosr = tcurosr
  state.winnr = winnr

  return state.tscurosr
end

local function window_range(winnr)
  local info = vim.fn.getwininfo(winnr)[1]
  return info.topline - 1, info.botline
end

function M.hint_parents(winnr, _, cb)
  winnr = winnr or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winnr)

  local nodes = {}
  local cur = utils.get_node_at_cursor(winnr)
  local parser = utils.get_parser(vim.api.nvim_win_get_buf(winnr))
  local tcursor = TSCursor:new(cur, bufnr, parser, node_filter)
  local top, bot = window_range(winnr)

  while cur and (cur:start() >= top or cur:end_() <= bot) do
    table.insert(nodes, cur)
    cur = tcursor:to_parent()
  end

  hint.hint(winnr, nodes, function(node)
    if cb then
      cb(node)
    else
      utils.select_node(winnr, node, false)
    end
  end)
end

local function operator_select(get_select, async)
  local winnr = vim.api.nvim_get_current_win()
  local select_outer = o.get().operator_outer()

  local function on_select(node_or_range)
    if not node_or_range or type(node_or_range) == "userdata" then
      local node = node_or_range or state.selected_node
      if node then
        utils.select_node(winnr, node, select_outer, "v")
      end
      state.selected_node = node
    else
      utils.select_range(winnr, node_or_range, "v")
    end
  end

  if async then
    get_select(winnr, nil, on_select)
  else
    on_select(get_select(winnr))
  end
end

local function wrap_select_mapping(get_select, name, async)
  if vim.api.nvim_get_mode().mode == "o" then
    pcall(operator_select, get_select, async)
  end

  local function exported_mapping()
    local winnr = state.winnr

    clear_visual_detect_au()
    state.au_id = vim.api.nvim_create_autocmd("ModeChanged", {
      callback = function()
        if not utils.is_visual_mode() then
          reset_select_state()
        end
      end,
    })

    local bufnr = vim.api.nvim_win_get_buf(winnr)

    if not state.in_select then
      state.in_select = true
      vim.cmd("normal! m'") -- set jumplist
    end

    -- set prev_range to rebuild tscursor
    local prev_range = utils.visual_selection_range(bufnr)
    state.prev_range = prev_range

    local function on_select(node_or_range)
      if not node_or_range or type(node_or_range) == "userdata" then
        local node = node_or_range or state.selected_node
        if node then
          utils.select_node(winnr, node, false, state.visual_mode, state.expand)
        end
        state.selected_node = node
      else
        utils.select_range(winnr, node_or_range, state.visual_mode, state.expand)
      end
    end

    if async then
      get_select(winnr, prev_range, on_select)
    else
      on_select(get_select(winnr, prev_range))
    end
  end

  local export_name = "_ts_visual_select_" .. name
  M[export_name] = function()
    local ok = pcall(exported_mapping)
    if not ok then
      reset_select_state()
    end
  end

  return function()
    state.winnr = vim.api.nvim_get_current_win()
    state.visual_mode = vim.api.nvim_get_mode().mode
    clear_visual_detect_au()
    -- TODO: we must exit visual mode to get the last selection range, and that's
    -- why an autocmd is used to determine whether two visual bindings are 'successive'.
    -- see: https://github.com/neovim/neovim/pull/13896
    return string.format("<Esc><Cmd>lua require('nvim-tsteer').%s()<CR>", export_name)
  end
end

function M.get_unit(winnr, range, reverse)
  local tscursor = sync_select_state(winnr, range)
  local function same_scope(a, b)
    if reverse then
      return a:end_() == b:end_()
    else
      return a:start() == b:start()
    end
  end
  while
    (tscursor:deref() and tscursor:parent() and same_scope(tscursor:deref(), tscursor:parent()))
    or not tscursor:deref():named()
  do
    tscursor:to_parent()
  end
  return tscursor:deref()
end

function M.get_unit_incremental(winnr, range, reverse)
  local node = M.get_unit(winnr, range, reverse)
  if not node then
    return
  end

  local tscursor = sync_select_state(winnr, range)
  if tscursor:deref() and utils.range_contains(range, utils.node_range(node)) then
    node = M.get_unit(winnr, utils.node_range(tscursor:to_parent()), reverse)
  end

  return node
end

function M.get_parent(winnr)
  local tcurosr = sync_select_state(winnr)
  local cur = tcurosr:safe_to_parent()
  while cur and tcurosr:parent() and utils.node_contains(cur, tcurosr:parent()) do
    cur = tcurosr:to_parent()
  end
  return cur
end

function M.get_prev_sibling(winnr)
  local tcurosr = sync_select_state(winnr)
  return tcurosr:safe_to_prev_sibling()
end

function M.get_next_sibling(winnr)
  local tcurosr = sync_select_state(winnr)
  return tcurosr:safe_to_next_sibling()
end

function M.get_first_sibling(winnr)
  local tcurosr = sync_select_state(winnr)
  return tcurosr:safe_to_first_sibling()
end

function M.get_last_sibling(winnr)
  local tcurosr = sync_select_state(winnr)
  return tcurosr:safe_to_last_sibling()
end

function M.get_first_child(winnr)
  local tcurosr = sync_select_state(winnr)
  return tcurosr:safe_to_child()
end

---Available mappings

M.swap_next_sibling = wrap_select_mapping(function(winnr)
  winnr = winnr or vim.api.nvim_get_current_win()
  local tcurosr = sync_select_state(winnr)
  local next = tcurosr:next_sibling()
  if next then
    local _, next_range = utils.swap_nodes(tcurosr:deref(), next, vim.api.nvim_win_get_buf(winnr))
    return next_range
  end
end)

M.swap_prev_sibling = wrap_select_mapping(function(winnr)
  winnr = winnr or vim.api.nvim_get_current_win()
  local tcurosr = sync_select_state(winnr)
  local prev = tcurosr:prev_sibling()
  if prev then
    local _, next_range = utils.swap_nodes(tcurosr:deref(), prev, vim.api.nvim_win_get_buf(winnr))
    return next_range
  end
end)

M.select_unit = wrap_select_mapping(M.get_unit, "get_unit", false)

M.select_unit_reverse = wrap_select_mapping(function()
  return M.get_unit(0, nil, true)
end, "get_unit_reverse", false)

M.select_unit_incremental = wrap_select_mapping(M.get_unit_incremental, "get_unit_incremental", false)

M.select_unit_incremental_reverse = wrap_select_mapping(function(winnr, range)
  return M.get_unit_incremental(winnr, range, true)
end, "get_unit_reverse", false)

M.select_next_sibling = wrap_select_mapping(M.get_next_sibling, "next_sibling")

M.select_prev_sibling = wrap_select_mapping(M.get_prev_sibling, "prev_sibling")

M.select_parent = wrap_select_mapping(M.get_parent, "parent")

M.select_first_child = wrap_select_mapping(M.get_first_child, "first_child")

M.select_first_sibling = wrap_select_mapping(M.get_first_sibling, "first_sibling")

M.select_last_sibling = wrap_select_mapping(M.get_last_sibling, "last_sibling")

M.hint_parents = wrap_select_mapping(M.hint_parents, "hint_parents", true)

function M.goto_unit_start()
  local node = M.get_unit(0, nil, true)
  if node then
    local r, c = node:start()
    vim.api.nvim_win_set_cursor(0, { r + 1, c })
  end
end

function M.goto_unit_end()
  local node = M.get_unit(0)
  if node then
    local r, c = node:end_()
    vim.api.nvim_win_set_cursor(0, { r + 1, c })
  end
end

M.setup = o.setup

return M
