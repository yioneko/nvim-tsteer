local M = {}

function M.If(bol, thn, els)
  if bol then
    return thn
  end
  return els
end

function M.buf_line(bufnr, lnum)
  return vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, true)[1] or ""
end

function M.line_cols(bufnr, lnum)
  return #M.buf_line(bufnr, lnum)
end

function M.is_visual_mode()
  return string.match(vim.api.nvim_get_mode().mode, "^[vV]") ~= nil
end

function M.has_treesitter(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim._ts_has_language(vim.api.nvim_buf_get_option(bufnr, "filetype"))
end

function M.get_parser(bufnr)
  local ok, nvim_ts_parser = pcall(require, "nvim-treesitter.parsers")
  if ok then
    return nvim_ts_parser.get_parser(bufnr)
  else
    return vim.treesitter.get_parser(bufnr)
  end
end

function M.get_node_for_range(winnr, range, named)
  winnr = winnr or vim.api.nvim_get_current_win()

  local bufnr = vim.api.nvim_win_get_buf(winnr)
  local root_lang_tree = M.get_parser(bufnr)
  if not root_lang_tree then
    return
  end
  if not root_lang_tree:is_valid() then
    root_lang_tree:parse()
  end

  local min_node
  root_lang_tree:for_each_tree(function(tree)
    local root = tree:root()
    if M.range_contains(M.node_range(root), range) then
      local node
      if named then
        node = root:named_descendant_for_range(range[1][1], range[1][2], range[2][1], range[2][2])
      else
        node = root:descendant_for_range(range[1][1], range[1][2], range[2][1], range[2][2])
      end

      if node and (not min_node or M.node_contains(min_node, node)) then
        min_node = node
      end
    end
  end)
  return min_node
end

function M.get_node_at_cursor(winnr, named)
  return M.get_node_for_range(winnr, M.get_cursor_range(winnr), named)
end

function M.get_node_at_pos(winnr, pos, named)
  winnr = winnr or vim.api.nvim_get_current_win()
  local end_pos = vim.deepcopy(pos)
  end_pos[2] = end_pos[2] + 1
  return M.get_node_for_range(winnr, { pos, end_pos }, named)
end

function M.get_cursor_range(winnr)
  winnr = winnr or vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(winnr)
  cursor[1] = cursor[1] - 1
  local end_cursror = vim.deepcopy(cursor)
  end_cursror[2] = end_cursror[2] + 1

  return { cursor, end_cursror }
end

function M.visual_selection_range(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
  local end_pos = vim.api.nvim_buf_get_mark(bufnr, ">")

  start_pos[1] = start_pos[1] - 1
  end_pos[1] = end_pos[1] - 1

  if M.pos_cmp(start_pos, end_pos) >= 0 then
    start_pos[2] = start_pos[2] + 1
    return { end_pos, start_pos }
  else
    end_pos[2] = end_pos[2] + 1
    return { start_pos, end_pos }
  end
end

function M.select_range(winnr, range, selection_mode, expand)
  winnr = winnr or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winnr)
  local start_cursor = { range[1][1] + 1, range[1][2] }
  local end_cursor = { range[2][1] + 1, range[2][2] }

  if end_cursor[2] == 0 then
    end_cursor[1] = end_cursor[1] - 1
    end_cursor[2] = M.line_cols(bufnr, end_cursor[1] - 1)
  else
    end_cursor[2] = end_cursor[2] - 1
  end

  if selection_mode then
    local selection_range = M.visual_selection_range(bufnr)

    if expand then
      start_cursor[1][1] = math.min(start_cursor[1][1], selection_range[1][1])
      start_cursor[1][1] = math.min(start_cursor[1][2], selection_range[1][2])
      end_cursor[2][1] = math.min(end_cursor[2][1], selection_range[2][1])
      end_cursor[2][2] = math.min(end_cursor[2][2], selection_range[2][2])
    end

    local cursor = vim.api.nvim_win_get_cursor(winnr)
    cursor[1] = cursor[1] - 1
    -- preserve relative cursor position (start or end)
    if M.pos_cmp(selection_range[1], cursor) == 0 then
      start_cursor, end_cursor = end_cursor, start_cursor
    end
  end

  vim.api.nvim_win_set_cursor(winnr, start_cursor)
  vim.cmd("normal! " .. vim.api.nvim_replace_termcodes(selection_mode or "v", true, true, true))
  vim.api.nvim_win_set_cursor(winnr, end_cursor)
end

function M.select_node(winnr, node, outer, selection_mode, expand)
  winnr = winnr or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winnr)
  local srow, scol, erow, ecol = node:range()
  if outer then
    if scol > 0 then
      local line = vim.api.nvim_buf_get_lines(bufnr, srow, srow + 1, true)[1]
      scol = scol - #(line:sub(1, scol):match("%s*$") or "")
    end
    if ecol < M.line_cols(bufnr, erow) then
      local line = vim.api.nvim_buf_get_lines(bufnr, erow, erow + 1, true)[1]
      ecol = ecol + #(line:sub(ecol + 1) or "")
    end
  end

  M.select_range(winnr, { { srow, scol }, { erow, ecol } }, selection_mode, expand)
end

function M.is_node_text_empty(node, bufnr)
  local text = vim.treesitter.get_node_text(node, bufnr, { concat = false })
  for _, line in ipairs(text) do
    if vim.trim(line) ~= "" then
      return false
    end
  end
  return true
end

function M.node_to_lsp_range_normalized(node, bufnr)
  local start_line, start_col, end_line, end_col = M.node_range_normalized(node, bufnr)
  local rtn = {}
  rtn.start = { line = start_line, character = start_col }
  rtn["end"] = { line = end_line, character = end_col + 1 }
  return rtn
end

function M.swap_nodes(na, nb, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local na_range = M.node_to_lsp_range_normalized(na, bufnr)
  local nb_range = M.node_to_lsp_range_normalized(nb, bufnr)

  local na_text = vim.treesitter.get_node_text(na, bufnr)
  local nb_text = vim.treesitter.get_node_text(nb, bufnr)

  local edit1 = { range = na_range, newText = nb_text }
  local edit2 = { range = nb_range, newText = na_text }

  vim.lsp.util.apply_text_edits({ edit1, edit2 }, bufnr, "utf-8")

  -- calculate result swapped region
  -- very difficult to explain here...
  local bi = na_range
  local bj = nb_range

  local reverted = M.pos_cmp({ bi.start.line, bi.start.character }, { bj.start.line, bj.start.character }) > 0
  if reverted then
    bi, bj = bj, bi
  end

  local drowi = bi["end"].line - bi.start.line
  local dcoli = bi["end"].character - bi.start.character
  local drowj = bj["end"].line - bj.start.line
  local dcolj = bj["end"].character - bj.start.character

  local ni = {
    { bi.start.line, bi.start.character },
    { bi.start.line + drowj, M.If(drowj == 0, bi.start.character + dcolj, bj["end"].character) },
  }

  local nj_start = {
    bj.start.line - drowi + drowj,
    -- special case:
    --[a
    --    a] ... [b
    -- b],
    M.If(bi["end"].line == bj.start.line, ni[2][2] + bj.start.character - bi["end"].character, bj.start.character),
  }
  local nj = {
    nj_start,
    { nj_start[1] + drowi, M.If(drowi == 0, nj_start[2] + dcoli, bi["end"].character) },
  }

  if reverted then
    ni, nj = nj, ni
  end
  return ni, nj
end

function M.pos_cmp(pos1, pos2)
  if pos1[1] == pos2[1] then
    return pos1[2] - pos2[2]
  else
    return pos1[1] - pos2[1]
  end
end

function M.range_contains(range1, range2)
  return M.pos_cmp(range1[1], range2[1]) <= 0 and M.pos_cmp(range1[2], range2[2]) >= 0
end

function M.node_range(node, inclusive)
  local ecol_diff = 0
  if inclusive then
    ecol_diff = -1
  end
  local srow, scol, erow, ecol = node:range()
  return { { srow, scol }, { erow, ecol + ecol_diff } }
end

-- inclusive
function M.node_range_normalized(node, bufnr)
  local srow, scol, erow, ecol = node:range()
  if ecol == 0 then
    erow = erow - 1
    ecol = M.line_cols(bufnr, erow) - 1
  else
    ecol = ecol - 1
  end
  return srow, scol, erow, ecol
end

function M.node_contains(node1, node2)
  return M.range_contains(M.node_range(node1), M.node_range(node2))
end

return M
