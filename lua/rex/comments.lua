-- Pending comments. Each one is anchored to its lines by an extmark, so it
-- follows edits to the buffer, and is drawn in the code: a rail in the sign
-- column, tinted lines, and the comment text above the block.
local M = {}

M.ns = vim.api.nvim_create_namespace("rex-comments")
local decor_ns = vim.api.nvim_create_namespace("rex-comments-decor")

vim.api.nvim_set_hl(0, "RexCommentSign", { default = true, link = "DiagnosticSignInfo" })
vim.api.nvim_set_hl(0, "RexCommentLine", { default = true, link = "CursorLine" })
vim.api.nvim_set_hl(0, "RexCommentText", { default = true, link = "DiagnosticVirtualTextInfo" })
vim.api.nvim_set_hl(0, "RexQuestionSign", { default = true, link = "DiagnosticSignHint" })
vim.api.nvim_set_hl(0, "RexQuestionLine", { default = true, link = "CursorLine" })
vim.api.nvim_set_hl(0, "RexQuestionText", { default = true, link = "DiagnosticVirtualTextHint" })

-- Highlight groups and callout mark per kind.
M.style = {
  comment = { sign = "RexCommentSign", line = "RexCommentLine", text = "RexCommentText", mark = "" },
  question = { sign = "RexQuestionSign", line = "RexQuestionLine", text = "RexQuestionText", mark = "? " },
}

local store = {} -- id -> { bufnr, mark, text, kind }
local next_id = 1
local watched = {} -- bufnr -> true once its edits redraw the decorations

local function resolve(id)
  local e = store[id]
  if not e or not vim.api.nvim_buf_is_valid(e.bufnr) then
    return nil
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(e.bufnr, M.ns, e.mark, { details = true })
  if #pos == 0 then
    return nil
  end
  local start_line = pos[1] + 1
  -- end_row is 0-indexed and exclusive, which equals the 1-indexed inclusive end line.
  local end_line = math.max(start_line, pos[3].end_row or start_line)
  return {
    id = id,
    bufnr = e.bufnr,
    file = vim.api.nvim_buf_get_name(e.bufnr),
    start_line = start_line,
    end_line = end_line,
    text = e.text,
    kind = e.kind,
  }
end

--- All comments of a buffer, or of every buffer, ordered by file and line.
function M.list(bufnr)
  local out = {}
  for id, e in pairs(store) do
    local c = (not bufnr or e.bufnr == bufnr) and resolve(id)
    if c then
      table.insert(out, c)
    end
  end
  table.sort(out, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.start_line < b.start_line
  end)
  return out
end

function M.get(id)
  return resolve(id)
end

function M.redraw(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, decor_ns, 0, -1)
  for _, c in ipairs(M.list(bufnr)) do
    local st = M.style[c.kind]
    for line = c.start_line, c.end_line do
      vim.api.nvim_buf_set_extmark(bufnr, decor_ns, line - 1, 0, {
        sign_text = "▌",
        sign_hl_group = st.sign,
        line_hl_group = st.line,
      })
    end
    vim.api.nvim_buf_set_extmark(bufnr, decor_ns, c.start_line - 1, 0, {
      virt_lines = { { { "╭─ " .. st.mark, st.sign }, { c.text, st.text } } },
      virt_lines_above = true,
    })
  end
end

-- Lines added inside a block get its decoration too.
local function watch(bufnr)
  if watched[bufnr] then
    return
  end
  watched[bufnr] = true
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = bufnr,
    callback = function()
      M.redraw(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      watched[bufnr] = nil
    end,
  })
end

--- Comments on lines line1..line2 of a buffer.
---@param kind "comment"|"question"|nil default "comment"
function M.add(bufnr, line1, line2, text, kind)
  local id = next_id
  next_id = next_id + 1
  -- Lines inserted right before the block or right after it stay outside: the
  -- start is pushed down by an insert at its position, the end is not.
  local mark = vim.api.nvim_buf_set_extmark(bufnr, M.ns, line1 - 1, 0, {
    end_row = line2,
    end_col = 0,
    right_gravity = true,
    end_right_gravity = false,
  })
  store[id] = { bufnr = bufnr, mark = mark, text = text, kind = kind or "comment" }
  watch(bufnr)
  M.redraw(bufnr)
  return id
end

function M.edit(id, text)
  local e = store[id]
  if e then
    e.text = text
    M.redraw(e.bufnr)
  end
end

function M.delete(id)
  local e = store[id]
  if not e then
    return
  end
  store[id] = nil
  if vim.api.nvim_buf_is_valid(e.bufnr) then
    vim.api.nvim_buf_del_extmark(e.bufnr, M.ns, e.mark)
    M.redraw(e.bufnr)
  end
end

function M.clear()
  for id in pairs(store) do
    M.delete(id)
  end
end

--- "path:12" or "path:12-20", the path relative to Neovim's current directory.
function M.location(c)
  local path = vim.fn.fnamemodify(c.file, ":.")
  if c.start_line == c.end_line then
    return string.format("%s:%d", path, c.start_line)
  end
  return string.format("%s:%d-%d", path, c.start_line, c.end_line)
end

function M.snippet(c)
  return vim.api.nvim_buf_get_lines(c.bufnr, c.start_line - 1, c.end_line, false)
end

return M
