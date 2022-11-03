local M = {}

local config = {
  filter = function(node, bufnr)
    return node:named()
  end,
  operator_outer = function()
    return vim.v.operator == "d"
  end,
  hint_provider = "leap",
}

function M.get()
  return config
end

function M.setup(user_conf)
  if user_conf.filter then
    config.filter = user_conf.filter
  end
  if user_conf.operator_outer then
    config.operator_outer = user_conf.operator_outer
  end
  if user_conf.hint_provider then
    config.hint_provider = user_conf.hint_provider
  end
end

return M
