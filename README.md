# rex.nvim

Leave review comments and questions on code in Neovim, then send them all at
once to a coding agent in another pane of your Rex session.

Inspired by [herdr-nvim](https://github.com/ChmaraX/herdr-nvim), and kept
deliberately small: it only takes comments from Neovim to the agent. Opening
Neovim from the agent's side is left to Rex.

Comments stay on their lines while you edit, and go out as one message:

```
Code review comments:

1. lua/rex/init.lua:12-14
   > local function rex(args)
   > ...
   Comment: name this better

Please address each comment. Reply with what you changed per item.
```

Questions go into the same queue and the same message, in a section of their
own before the comments that asks the agent to answer them without changing any
code.

## Requirements

- Neovim 0.11+
- [snacks.nvim](https://github.com/folke/snacks.nvim) for `:Rex list`
- Neovim running inside Rex (`REX_SESSION` set), with `rex` in `PATH`
- An agent that understands bracketed paste (Claude Code, Codex and the like),
  so a multi-line message is pasted as a whole instead of being submitted at the
  first newline

## Installation

With the built-in `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/Zver64/rex.nvim" })
```

No `setup()` call is needed.

## Usage

```vim
:Rex comment   " add a review comment on the line or range: the agent acts on it
:Rex question  " add a question on the line or range: the agent only answers it
:Rex send      " paste all pending comments into the agent's prompt
:Rex submit    " paste them and press Enter
:Rex yank      " copy that message to a register instead (v:register, as with y)
:Rex list      " pick from the pending comments (snacks.nvim picker)
:Rex clear     " drop the pending comments
:Rex ref       " paste a bare path:12-20 reference for the line or range
```

On every send the plugin looks for the agent pane: a pane whose program reports
its status to Rex (Program Status Protocol, OSC 7501), as Claude Code does. A
shell sitting at its prompt doesn't count. With a single agent it sends right
away; with several it asks. When no pane reports a status, all other panes are
candidates.

In the list, `<CR>` jumps to a comment, `<c-e>` edits it, and `dd` (or `<c-x>`
in the input) deletes it.

The decorations use the highlight groups `RexCommentSign`, `RexCommentLine` and
`RexCommentText`, and `RexQuestionSign`, `RexQuestionLine` and `RexQuestionText`
for questions.

Paths are relative to Neovim's current directory, so the agent should run in
the same directory.

The plugin sets no keymaps. Here is an example of how it could be mapped:

```lua
vim.keymap.set("n", "<leader>ac", "<cmd>Rex comment<cr>", { desc = "Rex: add comment" })
vim.keymap.set("x", "<leader>ac", ":Rex comment<cr>", { desc = "Rex: add comment" })
vim.keymap.set("n", "<leader>aq", "<cmd>Rex question<cr>", { desc = "Rex: add question" })
vim.keymap.set("x", "<leader>aq", ":Rex question<cr>", { desc = "Rex: add question" })
vim.keymap.set("n", "<leader>as", "<cmd>Rex send<cr>", { desc = "Rex: paste comments to agent" })
vim.keymap.set("n", "<leader>aS", "<cmd>Rex submit<cr>", { desc = "Rex: send comments to agent" })
vim.keymap.set("n", "<leader>ay", "<cmd>Rex yank<cr>", { desc = "Rex: copy comments message" })
vim.keymap.set("n", "<leader>al", "<cmd>Rex list<cr>", { desc = "Rex: list comments" })
vim.keymap.set("n", "<leader>ax", "<cmd>Rex clear<cr>", { desc = "Rex: clear comments" })
vim.keymap.set("n", "<leader>ar", "<cmd>Rex ref<cr>", { desc = "Rex: reference to agent" })
vim.keymap.set("x", "<leader>ar", ":Rex ref<cr>", { desc = "Rex: reference to agent" })
```

## Tests

```sh
nvim --clean -l tests/run.lua
```

The end-to-end tests start a throwaway Rex session and are skipped without `rex`.
The list tests use snacks.nvim from `SNACKS_PATH`, or from where `vim.pack`
installs it, and are skipped without it.
