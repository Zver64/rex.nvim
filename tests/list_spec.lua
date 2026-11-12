-- The comment list runs in a real snacks.nvim picker (see run.lua for where
-- snacks is looked up); skipped without it.
local comments = require("rex.comments")

local has_snacks = pcall(require, "snacks")

local function answer(text)
  vim.ui.input = function(_, cb)
    cb(text)
  end
end

local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end

local function close_pickers()
  for _, p in ipairs(Snacks.picker.get()) do
    p:close()
  end
  vim.wait(100)
end

-- A code buffer with comments on lines 2 and 5, and the list opened over it.
local function open_list()
  close_pickers()
  comments.clear()
  vim.cmd("silent only | enew!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c", "d", "e", "f" })
  vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. ("/tests/tmp_%d.lua"):format(vim.fn.bufnr()))
  answer("first")
  vim.cmd("2Rex comment")
  answer("second")
  vim.cmd("5Rex comment")
  local code_buf = vim.api.nvim_get_current_buf()
  vim.cmd("Rex list")
  local picker
  assert(vim.wait(2000, function()
    picker = Snacks.picker.get({ source = "rex_comments" })[1]
    return picker and #picker:items() == 2
  end), "picker didn't show the comments")
  return picker, code_buf
end

local function texts(picker)
  return vim.tbl_map(function(item)
    return item.comment.text
  end, picker:items())
end

local function wait_items(picker, n)
  vim.wait(2000, function()
    return #picker:items() == n
  end)
end

local function spec(tests)
  if has_snacks then
    return tests
  end
  return {
    ["skipped: snacks.nvim not found"] = function() end,
  }
end

return spec({
  ["list shows each comment with its file, lines and text"] = function()
    local picker = open_list()
    eq({ "first", "second" }, texts(picker))
    local first = picker:items()[1]
    assert(first.text:match("^tests/tmp_%d+%.lua:2 first$"), first.text)
    eq({ 2, 0 }, first.pos)
    close_pickers()
  end,

  ["the list shows where comments are now, after edits"] = function()
    local _, code_buf = open_list()
    close_pickers()
    vim.api.nvim_buf_set_lines(code_buf, 0, 0, false, { "new" })
    vim.cmd("Rex list")
    local picker
    vim.wait(2000, function()
      picker = Snacks.picker.get({ source = "rex_comments" })[1]
      return picker and #picker:items() == 2
    end)
    eq({ 3, 0 }, picker:items()[1].pos)
    close_pickers()
  end,

  ["delete removes the comment, and the list closes when none are left"] = function()
    local picker = open_list()
    picker:action("rex_comment_delete")
    wait_items(picker, 1)
    eq({ "second" }, vim.tbl_map(function(c)
      return c.text
    end, comments.list()))
    picker:action("rex_comment_delete")
    eq(0, #comments.list())
    assert(vim.wait(1000, function()
      return #Snacks.picker.get({ source = "rex_comments" }) == 0
    end), "picker still open")
  end,

  ["edit changes the comment text"] = function()
    local picker = open_list()
    local input = Snacks.input.input
    Snacks.input.input = function(_, cb)
      cb("changed")
    end
    picker:action("rex_comment_edit")
    Snacks.input.input = input
    eq("changed", comments.list()[1].text)
    vim.wait(2000, function()
      return picker:items()[1] and picker:items()[1].comment.text == "changed"
    end)
    eq({ "changed", "second" }, texts(picker))
    close_pickers()
  end,
})
