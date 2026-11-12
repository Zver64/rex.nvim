local rex = require("rex")
local comments = require("rex.comments")

local function buffer(lines)
  comments.clear()
  vim.cmd("enew!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. ("/tests/tmp_%d.lua"):format(vim.fn.bufnr()))
end

local function answer(text)
  vim.ui.input = function(_, cb)
    cb(text)
  end
end

local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end

local function lines_of(c)
  return { c.start_line, c.end_line }
end

-- Decoration extmarks of the current buffer: lines with a rail, and callout texts.
local function decorations()
  local ns = vim.api.nvim_get_namespaces()["rex-comments-decor"]
  local rails, callouts = {}, {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
    local d = m[4]
    if d.sign_text then
      table.insert(rails, m[2] + 1)
    end
    if d.virt_lines then
      table.insert(callouts, { m[2] + 1, d.virt_lines[1][2][1] })
    end
  end
  return rails, callouts
end

return {
  ["comment on a range keeps its location, lines and text"] = function()
    buffer({ "a", "b", "c", "d" })
    answer("rename")
    vim.cmd("2,3Rex comment")
    local list = comments.list()
    eq(1, #list)
    assert(comments.location(list[1]):match("^tests/tmp_%d+%.lua:2%-3$"), comments.location(list[1]))
    eq({ "b", "c" }, comments.snippet(list[1]))
    eq("rename", list[1].text)
  end,

  ["comment without a range uses the cursor line"] = function()
    buffer({ "a", "b", "c" })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    answer("why")
    vim.cmd("Rex comment")
    eq({ 3, 3 }, lines_of(comments.list()[1]))
  end,

  ["cancelled or empty input adds nothing"] = function()
    buffer({ "a" })
    answer(nil)
    vim.cmd("Rex comment")
    answer("")
    vim.cmd("Rex comment")
    eq(0, #comments.list())
  end,

  ["comments accumulate until cleared"] = function()
    buffer({ "a", "b" })
    answer("one")
    vim.cmd("1Rex comment")
    answer("two")
    vim.cmd("2Rex comment")
    eq(2, #comments.list())
    vim.cmd("Rex clear")
    eq(0, #comments.list())
  end,

  ["a comment moves with lines added or removed above it"] = function()
    buffer({ "a", "b", "c", "d" })
    answer("x")
    vim.cmd("3,4Rex comment")
    vim.api.nvim_buf_set_lines(0, 0, 0, false, { "new1", "new2" })
    eq({ 5, 6 }, lines_of(comments.list()[1]))
    eq({ "c", "d" }, comments.snippet(comments.list()[1]))
    vim.api.nvim_buf_set_lines(0, 0, 3, false, {})
    eq({ 2, 3 }, lines_of(comments.list()[1]))
    -- A line added right before the block stays outside it.
    vim.api.nvim_buf_set_lines(0, 1, 1, false, { "before" })
    eq({ 3, 4 }, lines_of(comments.list()[1]))
  end,

  ["a comment grows with lines added inside it and keeps its end"] = function()
    buffer({ "a", "b", "c", "d" })
    answer("x")
    vim.cmd("2,3Rex comment")
    vim.api.nvim_buf_set_lines(0, 2, 2, false, { "inside" })
    eq({ 2, 4 }, lines_of(comments.list()[1]))
    -- A line added right after the block stays outside it.
    vim.api.nvim_buf_set_lines(0, 4, 4, false, { "after" })
    eq({ 2, 4 }, lines_of(comments.list()[1]))
  end,

  ["a comment on the last line works"] = function()
    buffer({ "a", "b" })
    answer("end")
    vim.cmd("2Rex comment")
    eq({ 2, 2 }, lines_of(comments.list()[1]))
  end,

  ["commented lines get a rail and the comment text above them"] = function()
    buffer({ "a", "b", "c", "d" })
    answer("look here")
    vim.cmd("2,3Rex comment")
    local rails, callouts = decorations()
    eq({ 2, 3 }, rails)
    eq({ { 2, "look here" } }, callouts)
  end,

  ["decorations follow edits, and go away with the comment"] = function()
    buffer({ "a", "b", "c", "d" })
    answer("x")
    vim.cmd("2,3Rex comment")
    vim.api.nvim_buf_set_lines(0, 2, 2, false, { "inside" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    eq({ 2, 3, 4 }, (decorations()))
    comments.delete(comments.list()[1].id)
    local rails, callouts = decorations()
    eq({}, rails)
    eq({}, callouts)
  end,

  ["yank copies the message to a register and keeps the comments"] = function()
    buffer({ "a", "b", "c" })
    answer("first")
    vim.cmd("1Rex comment")
    answer("second")
    vim.cmd("2,3Rex comment")
    vim.api.nvim_buf_set_lines(0, 0, 0, false, { "new" })
    vim.fn.setreg('"', "")
    vim.cmd("Rex yank")
    eq(rex.format(rex.items(comments.list())), vim.fn.getreg('"'))
    assert(vim.fn.getreg('"'):find("1. tests/tmp_%d+%.lua:2\n   > a\n   Comment: first"), vim.fn.getreg('"'))
    eq(2, #comments.list())
    rex.yank("a")
    eq(vim.fn.getreg('"'), vim.fn.getreg("a"))
  end,

  ["a question is kept with its kind and drawn as a question"] = function()
    buffer({ "a", "b", "c" })
    answer("why so?")
    vim.cmd("2Rex question")
    eq("question", comments.list()[1].kind)
    local ns = vim.api.nvim_get_namespaces()["rex-comments-decor"]
    local hls = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      local d = m[4]
      if d.sign_text then
        hls.sign = vim.trim(d.sign_hl_group)
      end
      if d.virt_lines then
        hls.callout = d.virt_lines[1]
      end
    end
    eq("RexQuestionSign", hls.sign)
    eq({ { "╭─ ? ", "RexQuestionSign" }, { "why so?", "RexQuestionText" } }, hls.callout)
  end,

  ["only questions: the message asks to answer and change nothing"] = function()
    eq(
      table.concat({
        "Questions about the code:",
        "",
        "1. a.lua:1",
        "   > x",
        "   Question: why?",
        "",
        "Please answer each question. Don't change any code because of them.",
      }, "\n"),
      rex.format({ { loc = "a.lua:1", lines = { "x" }, text = "why?", kind = "question" } })
    )
  end,

  ["questions come first, then comments, numbered through"] = function()
    eq(
      table.concat({
        "Questions about the code:",
        "",
        "1. b.lua:2",
        "   > y",
        "   Question: why?",
        "",
        "Please answer each question. Don't change any code because of them.",
        "",
        "Code review comments:",
        "",
        "2. a.lua:1",
        "   > x",
        "   Comment: fix",
        "",
        "Please address each comment. Reply with what you changed per item.",
      }, "\n"),
      rex.format({
        { loc = "a.lua:1", lines = { "x" }, text = "fix", kind = "comment" },
        { loc = "b.lua:2", lines = { "y" }, text = "why?", kind = "question" },
      })
    )
  end,

  ["yank carries questions with their kind"] = function()
    buffer({ "a", "b" })
    answer("fix")
    vim.cmd("1Rex comment")
    answer("why?")
    vim.cmd("2Rex question")
    rex.yank("a")
    local msg = vim.fn.getreg("a")
    assert(msg:find("^Questions about the code"), msg)
    assert(msg:find("1. tests/tmp_%d+%.lua:2\n   > b\n   Question: why%?"), msg)
    assert(msg:find("2. tests/tmp_%d+%.lua:1\n   > a\n   Comment: fix"), msg)
  end,

  ["format numbers comments and quotes at most three lines"] = function()
    local text = rex.format({
      { loc = "a.lua:1", lines = { "x" }, text = "first" },
      { loc = "b.lua:2-6", lines = { "1", "2", "3", "4", "5" }, text = "second" },
    })
    eq(
      table.concat({
        "Code review comments:",
        "",
        "1. a.lua:1",
        "   > x",
        "   Comment: first",
        "",
        "2. b.lua:2-6",
        "   > 1",
        "   > 2",
        "   > 3",
        "   Comment: second",
        "",
        "Please address each comment. Reply with what you changed per item.",
      }, "\n"),
      text
    )
  end,
}
