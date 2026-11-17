local M = {}

M.known = { "claude", "codex", "pi", "opencode", "gemini", "aider", "amp", "cursor-agent", "crush", "goose", "qwen", "vibe" }

local function root_status(status, fg)
  for _, r in ipairs(status and status.records or {}) do
    if r.id == nil and (type(r.owner) ~= "table" or r.owner.pid == fg.pid) then
      return r
    end
  end
end

-- Discover candidates; command execution stays with the caller.
function M.list(blocks, current, call)
  local out = {}
  for _, b in ipairs(blocks) do
    if b.block_id ~= current then
      local process = call(b.block_id, "process")
      local fg = process and process.foreground
      if type(fg) == "table" then
        local name = (fg.argv0 or fg.name or ""):gsub("^%-", "")
        name = vim.fs.basename(name)
        local status = root_status(call(b.block_id, "program_status"), fg)
        if status or vim.list_contains(M.known, name) then
          local kind = status and status.effective_app or name
          table.insert(out, {
            block_id = b.block_id,
            status = status and status.state or "unknown",
            cwd = fg.cwd or "",
            title = b.label and b.label ~= "" and b.label ~= "shell" and b.label or kind,
          })
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.title < b.title
  end)
  return out
end

return M
