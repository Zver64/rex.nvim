-- The pending comments in a snacks.nvim picker: preview of the code, <CR>
-- jumps to it, <c-e> edits the comment, dd / <c-x> deletes it.
local comments = require("rex.comments")

local M = {}

local function finder()
  return vim.tbl_map(function(c)
    local where = comments.location(c)
    return {
      text = where .. " " .. (c.kind == "question" and "? " or "") .. c.text,
      comment = c,
      file = c.file,
      buf = c.bufnr,
      pos = { c.start_line, 0 },
      end_pos = { c.end_line, 0 },
    }
  end, comments.list())
end

local function format(item)
  local c = item.comment
  local lines = c.start_line == c.end_line and tostring(c.start_line) or (c.start_line .. "-" .. c.end_line)
  return {
    { vim.fn.fnamemodify(c.file, ":t"), "SnacksPickerFile" },
    { ":", "SnacksPickerDelim" },
    { lines, "SnacksPickerRow" },
    { "  " },
    { comments.style[c.kind].mark, comments.style[c.kind].sign },
    { c.text, comments.style[c.kind].text },
  }
end

local actions = {
  rex_comment_delete = function(picker)
    for _, item in ipairs(picker:selected({ fallback = true })) do
      comments.delete(item.comment.id)
    end
    if #comments.list() == 0 then
      return picker:close()
    end
    picker:refresh()
  end,
  rex_comment_edit = function(picker, item)
    if not item then
      return
    end
    Snacks.input.input({ prompt = "Edit comment", default = item.comment.text }, function(text)
      if text and text ~= "" then
        comments.edit(item.comment.id, text)
        picker:refresh()
      end
    end)
  end,
}

function M.open()
  if not package.loaded.snacks and not pcall(require, "snacks") then
    vim.notify("rex: the comment list needs snacks.nvim", vim.log.levels.ERROR)
    return
  end
  if #comments.list() == 0 then
    vim.notify("rex: no comments")
    return
  end
  Snacks.picker.pick({
    source = "rex_comments",
    title = "Rex comments",
    finder = finder,
    format = format,
    actions = actions,
    win = {
      input = {
        keys = {
          ["<c-x>"] = { "rex_comment_delete", mode = { "n", "i" } },
          ["<c-e>"] = { "rex_comment_edit", mode = { "n", "i" } },
        },
      },
      list = {
        keys = {
          ["dd"] = "rex_comment_delete",
          ["<c-e>"] = "rex_comment_edit",
        },
      },
    },
  })
end

return M
