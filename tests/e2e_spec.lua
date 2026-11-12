-- Sends to a real pane: a throwaway Rex session running `cat -v`, which shows
-- what arrived, bracketed paste markers included.
local comments = require("rex.comments")

local function run(args)
  local r = vim.system(args, { text = true }):wait()
  assert(r.code == 0, table.concat(args, " ") .. ": " .. r.stderr)
  return r.stdout
end

local function with_session(fn)
  local s = vim.json.decode(run({ "rex", "new", "--json", "--", "cat", "-v" })).session_id
  local env_session, env_block = vim.env.REX_SESSION, vim.env.REX_BLOCK
  vim.env.REX_SESSION, vim.env.REX_BLOCK = s, "none"
  comments.clear()
  local ok, err = pcall(fn, function(block)
    vim.wait(500)
    return run({ "rex", "capture", "-s", s, block and "-b" or nil, block })
  end, s)
  vim.env.REX_SESSION, vim.env.REX_BLOCK = env_session, env_block
  vim.system({ "rex", "kill", s }):wait()
  assert(ok, err)
end

local function buffer()
  vim.cmd("enew!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local x = 1", "local y = 2", "return x + y" })
  vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. ("/tests/tmp_%d.lua"):format(vim.fn.bufnr()))
end

return {
  ["submit pastes all comments, where they are now, as one message, presses Enter and clears them"] = function()
    if vim.fn.executable("rex") == 0 then
      return print("      skipped: rex not installed")
    end
    with_session(function(capture)
      buffer()
      vim.ui.input = function(_, cb)
        cb("first")
      end
      vim.cmd("1Rex comment")
      vim.ui.input = function(_, cb)
        cb("second")
      end
      vim.cmd("2,3Rex comment")
      -- Edited after commenting: the message has to point at the lines' new place.
      vim.api.nvim_buf_set_lines(0, 0, 0, false, { "-- header" })
      vim.cmd("Rex submit")
      assert(#comments.list() == 0, "comments not cleared")

      local screen = capture()
      assert(screen:find("^[[200~Code review comments:", 1, true), screen)
      assert(screen:find("1. tests/tmp_%d+%.lua:2\n   > local x = 1\n   Comment: first"), screen)
      assert(screen:find("2. tests/tmp_%d+%.lua:3%-4\n   > local y = 2\n   > return x %+ y\n   Comment: second"), screen)
      -- cat prints the line back only after Enter, so it shows up twice.
      local _, count = screen:gsub("Code review comments:", "")
      assert(count == 2, "expected Enter to be pressed:\n" .. screen)
    end)
  end,

  ["ref pastes a bare reference without Enter"] = function()
    if vim.fn.executable("rex") == 0 then
      return print("      skipped: rex not installed")
    end
    with_session(function(capture)
      buffer()
      vim.cmd("2,3Rex ref")
      local screen = capture()
      assert(screen:find("^%^%[%[200~tests/tmp_%d+%.lua:2%-3 %^%[%[201~"), screen)
    end)
  end,

  ["picks the pane whose program reports its status, skipping plain shells"] = function()
    if vim.fn.executable("rex") == 0 then
      return print("      skipped: rex not installed")
    end
    with_session(function(capture, s)
      local plain = vim.trim(run({ "rex", "block", "ls", "-s", s, "-q", "--short=false" }))
      -- A stand-in for an agent: reports a status (OSC 7501), then stays in the foreground.
      local agent = vim.json.decode(run({
        "rex", "split", "-s", s, "-b", plain, "--json", "--shell=none", "--",
        "sh", "-c", [[printf '\033]7501;state=idle:app=fakeagent\033\\'; exec cat -v]],
      })).block_ids[1]
      vim.wait(500)
      vim.ui.select = function()
        error("asked to pick a pane")
      end
      buffer()
      vim.cmd("Rex ref")
      assert(capture(agent):find("tests/tmp_%d+%.lua:1 "), capture(agent))
      assert(not capture(plain):find("tmp_"), capture(plain))
    end)
  end,
}
