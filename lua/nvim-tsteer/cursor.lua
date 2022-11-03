-- Cross tree node cursor
local utils = require("nvim-tsteer.utils")

local function always_true()
  return true
end

local function create_cross_tree_stack(node, bufnr, parser, filter)
  local nrange = utils.node_range(node, false)

  local trees = {}
  parser:for_each_tree(function(tree, lang_tree)
    local root = tree:root()
    local min_capture_node = root:descendant_for_range(nrange[1][1], nrange[1][2], nrange[2][1], nrange[2][2])

    while min_capture_node and not filter(min_capture_node, bufnr) do
      min_capture_node = min_capture_node:parent()
    end
    if min_capture_node and utils.node_contains(min_capture_node, node) then
      table.insert(trees, {
        lang = lang_tree:lang(),
        tstree = tree,
        min_capture_node = min_capture_node,
      })
    end
  end)

  table.sort(trees, function(a, b)
    local is_same = utils.node_contains(a.min_capture_node, b.min_capture_node)
      and utils.node_contains(b.min_capture_node, a.min_capture_node)
    if is_same then
      return utils.node_contains(a.tstree:root(), b.tstree:root())
    end
    return utils.node_contains(a.min_capture_node, b.min_capture_node)
  end)

  return trees
end

---@class TSCursor
---@field node userdata
---@field tree_stack table
---@field bufnr integer
---@field parser table
---@field filter function
local TSCursor = {}

---@return TSCursor
function TSCursor:new(node, bufnr, parser, filter)
  local o = {
    node = node,
    bufnr = bufnr,
    parser = parser,
    filter = filter or always_true,
    tree_stack = {},
  }

  setmetatable(o, { __index = self })

  o.tree_stack = create_cross_tree_stack(node, bufnr, parser, filter)

  return o
end

function TSCursor:deref()
  return self.node
end

function TSCursor:set_filter(filter)
  self.filte = filter
end

local function wrap_move_check(fun)
  return function(self, ...)
    if not self.node then
      return
    end

    local args = { ... }
    local iter = function()
      fun(self, unpack(args))
      return self.node
    end
    for node in iter do
      if self.filter(node) then
        return node
      end
    end
  end
end

function TSCursor:parent()
  if not self.node then
    return
  end
  local cur = self.node:parent()
  local stack_pos = #self.tree_stack - 1
  while not cur or not self.filter(cur) or not utils.node_contains(cur, self.node) do
    if cur then
      cur = cur:parent()
    elseif stack_pos >= 1 then
      cur = self.tree_stack[stack_pos].min_capture_node
      stack_pos = stack_pos - 1
    else
      return
    end
  end
  return cur
end

function TSCursor:prev_sibling()
  if not self.node then
    return
  end
  local cur = self.node:prev_sibling()
  while cur and not self.filter(cur) do
    cur = cur:prev_sibling()
  end
  return cur
end

function TSCursor:next_sibling()
  if not self.node then
    return
  end
  local cur = self.node:next_sibling()
  while cur and not self.filter(cur) do
    cur = cur:next_sibling()
  end
  return cur
end

function TSCursor:first_sibling()
  local parent = self:parent()
  if parent then
    for node in parent:iter_children() do
      if self.filter(node) then
        return node
      end
    end
  end
end

function TSCursor:last_sibling()
  local parent = self:parent()
  if parent then
    local res
    for node in parent:iter_children() do
      if self.filter(node) then
        res = node
      end
    end
    if res then
      return res
    end
  end
end

function TSCursor:child(n)
  if not self.node then
    return
  end
  -- given index, directly return it, ignore filter
  if n ~= nil then
    return self.node:child(n)
  end

  if self.node:child_count() ~= 0 then
    for child in self.node:iter_children() do
      if self.filter(child) then
        return child
      end
    end
    return
  else
    -- local tree = find_max_contained_tree(self)
    -- if tree then
    --   return tree:root()
    -- end
    -- return
  end
end

function TSCursor:to_parent()
  if not self.node then
    return
  end
  local cur = self.node:parent()
  while not cur or not self.filter(cur) or not utils.node_contains(cur, self.node) do
    if cur then
      cur = cur:parent()
    elseif #self.tree_stack > 1 then
      table.remove(self.tree_stack)
      cur = self.tree_stack[#self.tree_stack].min_capture_node
    else
      break
    end
  end
  self.node = cur

  return self.node
end

---@param self TSCursor
local function unchecked_to_child(self, n)
  if n ~= nil then
    self.node = self.node:child(n)
  else
    if self.node:child_count() ~= 0 then
      for child in self.node:iter_children() do
        if self.filter(child) then
          self.node = child
          return
        end
      end
      return
    else
      self.node = nil
      -- local tree = find_max_contained_tree(self)
      -- if tree then
      --   self.tree_stack[#self.tree_stack].min_capture_node = self.node
      --   self.tree_stack[#self.tree_stack + 1] = {
      --     tstree = tree,
      --     min_capture_node = tree:root(), -- meaningless
      --   }
      --   self.node = tree:root()
      -- else
      --   self.node = nil
      -- end
    end
  end
end

---@param self TSCursor
local function unchecked_to_prev_sibling(self)
  self.node = self:prev_sibling()
end

---@param self TSCursor
local function unchecked_to_next_sibling(self)
  self.node = self:next_sibling()
end

---@param self TSCursor
local function unchecked_to_first_sibling(self)
  self.node = self:first_sibling()
end

---@param self TSCursor
local function unchecked_to_last_sibling(self)
  self.node = self:last_sibling()
end

TSCursor.to_child = wrap_move_check(unchecked_to_child)
TSCursor.to_prev_sibling = wrap_move_check(unchecked_to_prev_sibling)
TSCursor.to_next_sibling = wrap_move_check(unchecked_to_next_sibling)
TSCursor.to_first_sibling = wrap_move_check(unchecked_to_first_sibling)
TSCursor.to_last_sibling = wrap_move_check(unchecked_to_last_sibling)

function TSCursor:safe_to_parent()
  if self:parent() then
    return self:to_parent()
  else
    return self.node
  end
end

function TSCursor:safe_to_prev_sibling()
  if self:prev_sibling() then
    return self:to_prev_sibling()
  else
    return self.node
  end
end

function TSCursor:safe_to_next_sibling()
  if self:next_sibling() then
    return self:to_next_sibling()
  else
    return self.node
  end
end

function TSCursor:safe_to_first_sibling()
  if self:first_sibling() then
    return self:to_first_sibling()
  else
    return self.node
  end
end

function TSCursor:safe_to_last_sibling()
  if self:last_sibling() then
    return self:to_last_sibling()
  else
    return self.node
  end
end

function TSCursor:safe_to_child(n)
  if self:child(n) then
    return self:to_child(n)
  else
    return self.node
  end
end

function TSCursor:relocate(new_node, follow_parent)
  if new_node ~= self.node then
    if follow_parent then
      while not utils.node_contains(self.node, new_node) do
        self:to_parent()
      end
    else
      self.node = new_node
      self.tree_stack = create_cross_tree_stack(new_node, self.bufnr, self.parser, self.filter)
    end
  end
  return true
end

return TSCursor
