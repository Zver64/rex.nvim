local agents = require("rex.agents")

local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end

local function discover(panes)
  local calls, by_id = {}, {}
  for _, p in ipairs(panes) do
    by_id[p.block_id] = p
  end
  local list = agents.list(panes, "self", function(id, method)
    calls[id .. ":" .. method] = (calls[id .. ":" .. method] or 0) + 1
    return assert(by_id[id])[method]
  end)
  return list, calls
end

return {
  ["finds known foreground names and arbitrary root-status reporters"] = function()
    local list, calls = discover({
      { block_id = "self", window_id = "tab1" },
      {
        block_id = "known", window_id = "tab1", label = "shell",
        process = { foreground = { pid = 1, name = "node", argv0 = "/usr/local/bin/codex" } },
        program_status = { records = {} },
      },
      {
        block_id = "custom", window_id = "tab2", label = "review",
        process = { foreground = { pid = 2, name = "custom" } },
        program_status = { records = {
          { id = "worker", state = "idle" },
          { effective_app = "custom-agent", state = "working", owner = { pid = 2 } },
        } },
      },
      {
        block_id = "ordinary", window_id = "tab1",
        process = { foreground = { pid = 3, name = "other-program" } },
        program_status = { records = {} },
      },
    })
    eq({ "known", "custom" }, vim.tbl_map(function(a)
      return a.block_id
    end, list))
    eq("review", list[2].title)
    eq("working", list[2].status)
    eq(nil, calls["self:process"])
    for _, count in pairs(calls) do
      eq(1, count)
    end
  end,

  ["ignores nested and stale status records without falling back to other panes"] = function()
    eq({}, discover({
      {
        block_id = "shell",
        process = { foreground = { pid = 1, argv0 = "-zsh" } },
        program_status = { records = {
          { id = "worker", state = "working", owner = { pid = 1 } },
          { state = "done", owner = { pid = 9 } },
        } },
      },
      {
        block_id = "exited",
        process = { foreground = vim.NIL },
        program_status = { records = { { state = "done" } } },
      },
    }))
  end,

  ["accepts a root status without owner metadata"] = function()
    local list = discover({
      {
        block_id = "custom",
        process = { foreground = { pid = 1, name = "custom" } },
        program_status = { records = { { state = "idle", owner = vim.NIL } } },
      },
    })
    eq(1, #list)
  end,
}
