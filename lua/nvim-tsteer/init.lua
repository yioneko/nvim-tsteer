-- TODO: 1. multiple nodes selection 2. history
local o = require("nvim-tsteer.config")
local hint = require("nvim-tsteer.hint")
local utils = require("nvim-tsteer.utils")
local TSCursor = require("nvim-tsteer.cursor")

local M = {}

local state = {
  in_select = false,
  winnr = nil,
  visual_mode = nil,
  jump_set = false,
  expand = false, -- TODO
  selected_node = nil,
  prev_range = nil,
  tscurosr = nil,
}

local function reset_select_state()
  state.winnr = nil
  state.in_select = false
  state.jump_set = false
  state.visual_mode = nil
  state.selected_node = nil
  state.prev_range = nil
  state.tscurosr = nil
end

local function get_node_filter(bufnr)
  return function(node)
    return o.get().filter(node, bufnr) and not utils.is_node_text_empty(node, bufnr)
  end
end

local function sync_select_state(winnr, range)
  if winnr == 0 or winnr == nil then
    winnr = vim.api.nvim_get_current_win()
  end
  local bufnr = vim.api.nvim_win_get_buf(winnr)
  range = range or state.prev_range or utils.get_cursor_range(winnr)

  if
    winnr == state.winnr
    and state.tscurosr
    and utils.range_contains(utils.node_range(state.tscurosr:deref()), range)
  then
    return state.tscurosr --[[@as TSCursor]]
  end
  local node = utils.get_node_for_range(winnr, range)
  local parser = utils.get_parser(vim.api.nvim_win_get_buf(winnr))
  local tcurosr = TSCursor:new(node, bufnr, parser, get_node_filter(bufnr))

  -- sift up for node with same range
  -- TODO: not much friendly to child navigation
  while node and tcurosr:parent() and utils.node_contains(node, tcurosr:parent()) do
    node = tcurosr:to_parent()
  end

  -- only update state if in selecet
  if state.in_select then
    state.selected_node = node
    state.tscurosr = tcurosr
    state.winnr = winnr
  end

  return tcurosr
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
  local tcursor = TSCursor:new(cur, bufnr, parser, get_node_filter(bufnr))
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

local function on_operator_select(node_or_range)
  local select_outer = o.get().operator_outer()
  if not node_or_range or type(node_or_range) == "userdata" then
    local node = node_or_range or state.selected_node
    if node then
      utils.select_node(state.winnr, node, select_outer, "v")
    end
    state.selected_node = node
  else
    utils.select_range(state.winnr, node_or_range, "v")
  end
  reset_select_state()
end

local function get_on_visual_select()
  local winnr = state.winnr

  vim.api.nvim_create_autocmd("ModeChanged", {
    once = true,
    callback = function()
      if not utils.is_visual_mode() then
        reset_select_state()
      end
    end,
  })

  if not state.jump_set then
    state.jump_set = true
    if o.get().set_jump then
      vim.cmd("normal! m'") -- set jumplist
    end
  end

  -- set prev_range to rebuild tscursor
  local prev_range = utils.visual_selection_range(winnr)
  state.prev_range = prev_range

  return function(node_or_range)
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
end

local function wrap_select_mapping_async(get_select)
  local function mapping()
    state.winnr = vim.api.nvim_get_current_win()

    local mode = vim.api.nvim_get_mode().mode
    if string.find(mode, "o") ~= nil then
      return get_select(state.winnr, nil, on_operator_select)
    end

    state.visual_mode = mode
    state.in_select = true
    local on_visual_select = get_on_visual_select()
    return get_select(state.winnr, state.prev_range, on_visual_select)
  end

  return function()
    local ok, err = pcall(mapping)
    if not ok then
      reset_select_state()
      vim.schedule(function()
        vim.notify("[tsteer]: error " .. err, vim.log.levels.ERROR)
      end)
    end
  end
end

local function wrap_select_mapping(get_select)
  return wrap_select_mapping_async(function(winnr, range, cb)
    cb(get_select(winnr, range))
  end)
end

function M.get_unit(winnr, range)
  local tscursor = sync_select_state(winnr, range or utils.get_cursor_range(winnr))
  local bufnr = tscursor.bufnr

  local function accept_unit()
    local parent = tscursor:parent()
    if not parent then
      return true
    end
    local cur = tscursor:deref()
    if not o.get().filter(cur, bufnr) then
      return false
    end
    -- fix lua not select first child of block
    if o.get().unit_break(cur, bufnr) then
      return true
    end
    return cur:start() ~= parent:start()
  end

  while not accept_unit() do
    tscursor:to_parent()
  end
  return tscursor:deref()
end

function M.get_unit_incremental(winnr, range)
  local node = M.get_unit(winnr, range)
  if not node then
    return
  end

  local bufnr = vim.api.nvim_win_get_buf(winnr)
  local tscursor = sync_select_state(winnr, range)
  if
    tscursor:deref()
    and tscursor:parent()
    and utils.range_contains(range, utils.node_range_normalized(node, bufnr))
  then
    node = M.get_unit(winnr, utils.node_range(tscursor:to_parent())) or node
  end

  return node
end

function M.get_parent(winnr, range)
  local tcurosr = sync_select_state(winnr, range)
  local cur = tcurosr:safe_to_parent()
  while cur and tcurosr:parent() and utils.node_contains(cur, tcurosr:parent()) do
    cur = tcurosr:to_parent()
  end
  return cur
end

function M.get_prev_sibling(winnr, range)
  local tcurosr = sync_select_state(winnr, range)
  return tcurosr:safe_to_prev_sibling()
end

function M.get_next_sibling(winnr, range)
  local tcurosr = sync_select_state(winnr, range)
  return tcurosr:safe_to_next_sibling()
end

function M.get_first_sibling(winnr, range)
  local tcurosr = sync_select_state(winnr, range)
  return tcurosr:safe_to_first_sibling()
end

function M.get_last_sibling(winnr, range)
  local tcurosr = sync_select_state(winnr, range)
  return tcurosr:safe_to_last_sibling()
end

function M.get_first_child(winnr, range)
  local tcurosr = sync_select_state(winnr, range)
  return tcurosr:safe_to_child()
end

---Available mappings

M.swap_next_sibling = wrap_select_mapping(function(winnr, range)
  winnr = winnr or vim.api.nvim_get_current_win()
  local tcurosr = sync_select_state(winnr, range)
  local next = tcurosr:next_sibling()
  if next then
    local _, next_range = utils.swap_nodes(tcurosr:deref(), next, vim.api.nvim_win_get_buf(winnr))
    return next_range
  end
end)

M.swap_prev_sibling = wrap_select_mapping(function(winnr, range)
  winnr = winnr or vim.api.nvim_get_current_win()
  local tcurosr = sync_select_state(winnr, range)
  local prev = tcurosr:prev_sibling()
  if prev then
    local _, next_range = utils.swap_nodes(tcurosr:deref(), prev, vim.api.nvim_win_get_buf(winnr))
    return next_range
  end
end)

M.select_unit = wrap_select_mapping(M.get_unit)
M.select_unit_incremental = wrap_select_mapping(M.get_unit_incremental)
M.select_next_sibling = wrap_select_mapping(M.get_next_sibling)
M.select_prev_sibling = wrap_select_mapping(M.get_prev_sibling)
M.select_parent = wrap_select_mapping(M.get_parent)
M.select_first_child = wrap_select_mapping(M.get_first_child)
M.select_first_sibling = wrap_select_mapping(M.get_first_sibling)
M.select_last_sibling = wrap_select_mapping(M.get_last_sibling)
M.hint_parents = wrap_select_mapping_async(M.hint_parents)

local function goto_unit_pos_incremental(winnr, backward)
  local win_cursor = vim.api.nvim_win_get_cursor(winnr)
  local bufnr = vim.api.nvim_win_get_buf(winnr)

  local node = M.get_unit(winnr)

  local function get_node_pos(node)
    local range = utils.node_range_normalized(node, bufnr)
    if backward then
      return range[1][1], range[1][2]
    else
      return range[2][1], range[2][2]
    end
  end

  local row, col = get_node_pos(node)

  while node and row == win_cursor[1] - 1 and col == win_cursor[2] do
    node = node:parent()
    if node then
      row, col = get_node_pos(node)
    end
  end
  node = node and M.get_unit(winnr, utils.node_range(node))
  if not node then
    return
  end

  row, col = get_node_pos(node)
  vim.cmd("normal! m'") -- set jumplist
  vim.api.nvim_win_set_cursor(0, { row + 1, col })
end

function M.goto_unit_start(winnr)
  if winnr == 0 or winnr == nil then
    winnr = vim.api.nvim_get_current_win()
  end
  goto_unit_pos_incremental(winnr, true)
end

function M.goto_unit_end(winnr)
  if winnr == 0 or winnr == nil then
    winnr = vim.api.nvim_get_current_win()
  end
  goto_unit_pos_incremental(winnr, false)
end

M.setup = o.setup

return M
