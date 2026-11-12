local subcommands = {
  comment = function(o)
    require("rex").comment(o.line1, o.line2)
  end,
  question = function(o)
    require("rex").question(o.line1, o.line2)
  end,
  send = function()
    require("rex").send(false)
  end,
  submit = function()
    require("rex").send(true)
  end,
  yank = function()
    require("rex").yank()
  end,
  list = function()
    require("rex").list()
  end,
  clear = function()
    require("rex").clear()
  end,
  ref = function(o)
    require("rex").ref(o.line1, o.line2)
  end,
}

vim.api.nvim_create_user_command("Rex", function(o)
  local fn = subcommands[o.args]
  if not fn then
    vim.notify("Rex: unknown subcommand " .. o.args, vim.log.levels.ERROR)
    return
  end
  fn(o)
end, {
  nargs = 1,
  range = true,
  desc = "Comment on code and send the comments to an agent pane in Rex",
  complete = function()
    return vim.tbl_keys(subcommands)
  end,
})
