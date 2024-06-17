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
      end_pos = { erow + 1, ecol },
      node = node,
    })
  end

  leap.leap({
    targets = targets,
    target_windows = { winnr },
    action = function(target)
      callback(target.node)
    end,
    opts = {
      on_beacons = function(targets, first_idx, last_idx)
        local hl = require("leap.highlight")
        for i = first_idx or 1, last_idx or #targets do
          local target = targets[i]
          if target.chars then
            goto continue
          end
          local beacon = target.beacon
          local virt_text = beacon[2]
          local bufnr = target.wininfo.bufnr
          local lnum = target.end_pos[1]
          local col = target.end_pos[2]
          local id = vim.api.nvim_buf_set_extmark(bufnr, hl.ns, lnum - 1, col - 1, {
            virt_text = virt_text,
            virt_text_pos = "overlay",
            hl_mode = "combine",
            priority = hl.priority.label,
          })
          -- This way Leap automatically cleans up your stuff together with its own.
          table.insert(hl.extmarks, { bufnr, id })
          ::continue::
        end
        return true
      end,
    },
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
