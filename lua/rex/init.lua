local comments = require("rex.comments")

local M = {}

local function session()
  return vim.env.REX_SESSION
end

local function rex(args)
  local r = vim.system(vim.list_extend({ "rex" }, args), { text = true }):wait()
  if r.code ~= 0 then
    vim.notify("rex: " .. vim.trim(r.stderr ~= "" and r.stderr or ("exit " .. r.code)), vim.log.levels.ERROR)
    return nil
  end
  return r.stdout
end

-- Last non-empty line of a pane, so panes can be told apart in the picker.
local function tail(block)
  local out = rex({ "capture", "-s", session(), "-b", block }) or ""
  local lines = vim.split(vim.trim(out), "\n")
  return vim.trim(lines[#lines] or "")
end

local function call(block, method)
  local out = rex({ "block", "call", "-s", session(), "-b", block, method })
  return out and vim.json.decode(out)
end

-- The status record reported by the program in the foreground of a pane, if it
-- reports one (Program Status Protocol, OSC 7501). Agents such as Claude Code
-- do; a shell sitting at its prompt doesn't.
local function agent_status(block)
  local process, status = call(block, "process"), call(block, "program_status")
  local fg = process and process.foreground
  for _, r in ipairs(status and status.records or {}) do
    if fg and r.owner and r.owner.pid == fg.pid then
      return r
    end
  end
end

-- Finds the pane of the current Rex session the agent runs in, on every send.
-- Only panes whose program reports its status count; without any, all other
-- panes do. Asks only when there is more than one candidate.
local function with_target(on_choice)
  if not session() then
    vim.notify("rex: not running inside Rex", vim.log.levels.ERROR)
    return
  end
  local out = rex({ "block", "ls", "-s", session(), "--json" })
  if not out then
    return
  end
  local blocks = vim.tbl_filter(function(b)
    return b.block_id ~= vim.env.REX_BLOCK
  end, vim.json.decode(out).blocks)
  if #blocks == 0 then
    vim.notify("rex: no other panes in this session", vim.log.levels.WARN)
    return
  end
  local agents = {}
  for _, b in ipairs(blocks) do
    b.status = agent_status(b.block_id)
    if b.status then
      table.insert(agents, b)
    end
  end
  if #agents > 0 then
    blocks = agents
  end
  if #blocks == 1 then
    return on_choice(blocks[1].block_id)
  end
  vim.ui.select(blocks, {
    prompt = "Send to pane",
    format_item = function(b)
      if b.status then
        local title = call(b.block_id, "title")
        return string.format("%s (%s)  %s", b.status.effective_app or b.label, b.status.state, title and title.title or "")
      end
      return string.format("%s  %s", b.label, tail(b.block_id))
    end,
  }, function(b)
    if b then
      on_choice(b.block_id)
    end
  end)
end

--- Pastes text into the agent pane as a bracketed paste, so newlines don't
--- submit the agent's prompt. With submit, presses Enter after it.
function M.paste(text, submit, on_sent)
  with_target(function(block)
    if not rex({ "send", "-s", session(), "-b", block, "\27[200~" .. text .. "\27[201~" }) then
      return
    end
    if submit and not rex({ "send-key", "-s", session(), "-b", block, "enter" }) then
      return
    end
    if on_sent then
      on_sent()
    end
  end)
end

local function add(kind, line1, line2)
  local bufnr = vim.api.nvim_get_current_buf()
  local where = comments.location({ file = vim.api.nvim_buf_get_name(bufnr), start_line = line1, end_line = line2 })
  vim.ui.input({ prompt = where .. " " .. kind .. ": " }, function(text)
    if text and text ~= "" then
      comments.add(bufnr, line1, line2, text, kind)
      vim.notify(string.format("rex: %d pending comment(s)", #comments.list()))
    end
  end)
end

--- Asks for a review comment on lines line1..line2 of the current buffer: the
--- agent is expected to act on it.
function M.comment(line1, line2)
  add("comment", line1, line2)
end

--- Asks for a question on lines line1..line2 of the current buffer: the agent
--- is expected to answer it and change nothing.
function M.question(line1, line2)
  add("question", line1, line2)
end

-- Questions always come first.
local sections = {
  {
    kind = "question",
    header = "Questions about the code:",
    label = "Question",
    footer = "Please answer each question. Don't change any code because of them.",
  },
  {
    kind = "comment",
    header = "Code review comments:",
    label = "Comment",
    footer = "Please address each comment. Reply with what you changed per item.",
  },
}

--- The message comments are sent as; each item is { loc, lines, text, kind? },
--- kind "comment" (the default) or "question". Questions and comments go into
--- sections of their own, questions first, numbered through.
function M.format(items)
  local out, n = {}, 0
  for _, s in ipairs(sections) do
    local of_kind = vim.tbl_filter(function(c)
      return (c.kind or "comment") == s.kind
    end, items)
    if #of_kind > 0 then
      if #out > 0 then
        table.insert(out, "")
      end
      vim.list_extend(out, { s.header, "" })
      for _, c in ipairs(of_kind) do
        n = n + 1
        table.insert(out, string.format("%d. %s", n, c.loc))
        for j = 1, math.min(3, #c.lines) do
          table.insert(out, "   > " .. c.lines[j])
        end
        table.insert(out, "   " .. s.label .. ": " .. c.text)
        table.insert(out, "")
      end
      table.insert(out, s.footer)
    end
  end
  return table.concat(out, "\n")
end

--- Comments as format() items, with their lines where they are now.
function M.items(list)
  return vim.tbl_map(function(c)
    return { loc = comments.location(c), lines = comments.snippet(c), text = c.text, kind = c.kind }
  end, list)
end

--- Sends all pending comments as one message, where their marks are now, and
--- removes them.
---@param submit boolean press Enter after pasting
function M.send(submit)
  local list = comments.list()
  if #list == 0 then
    vim.notify("rex: no comments to send")
    return
  end
  M.paste(M.format(M.items(list)), submit, function()
    for _, c in ipairs(list) do
      comments.delete(c.id)
    end
    vim.notify(string.format("rex: sent %d comment(s)", #list))
  end)
end

--- Copies the message the pending comments would be sent as into a register
--- (v:register by default, so "ay and 'clipboard' work as with y). The
--- comments stay pending.
---@param register string?
function M.yank(register)
  local list = comments.list()
  if #list == 0 then
    vim.notify("rex: no comments to copy")
    return
  end
  register = register or vim.v.register
  vim.fn.setreg(register, M.format(M.items(list)))
  vim.notify(string.format('rex: copied %d comment(s) to "%s', #list, register))
end

function M.clear()
  comments.clear()
  vim.notify("rex: comments cleared")
end

--- Picker over the pending comments (snacks.nvim).
function M.list()
  require("rex.list").open()
end

--- Pastes a bare "path:12-20 " reference, to carry on typing after it.
function M.ref(line1, line2)
  local c = { file = vim.api.nvim_buf_get_name(0), start_line = line1, end_line = line2 }
  M.paste(comments.location(c) .. " ")
end

return M
