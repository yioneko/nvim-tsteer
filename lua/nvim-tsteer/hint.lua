local o = require("nvim-tsteer.config")

local M = {}

function M.hint(...)
  local provider = o.get().hint_provider
  if provider == "leap" then
    return M.leap_hint(...)
  else
    return M.hop_hint(...)
  end
end

function M.leap_hint(winnr, nodes, callback)
  local leap = require("leap")
  local targets = {}
  for _, node in ipairs(nodes) do
    local srow, scol, erow, ecol = node:range()
    table.insert(targets, {
      pos = { srow + 1, scol + 1 },
      node = node,
    })
    table.insert(targets, {
      pos = { erow + 1, ecol },
      node = node,
    })
  end

  leap.leap({
    targets = targets,
    target_windows = { winnr },
    action = function(target)
      callback(target.node)
    end,
  })
end

function M.hop_hint(winnr, nodes, callback)
  local hop = require("hop")

  local targets = {}
  for _, node in ipairs(nodes) do
    local srow, scol, erow, ecol = node:range()
    table.insert(targets, {
      line = srow,
      column = scol + 1,
      window = winnr,
      node = node,
    })
    table.insert(targets, {
      line = erow,
      column = ecol,
      window = winnr,
      node = node,
    })
  end

  hop.hint_with_callback(
    function()
      return { jump_targets = targets }
    end,
    nil,
    function(target)
      callback(target.node)
    end
  )
end

return M
