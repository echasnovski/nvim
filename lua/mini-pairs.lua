-- Attempt to write *minimal* autopairs Lua plugin.
--
-- Initial goals:
-- - Setup keybindings in custom mode ('i', 'c', 't') for "open" symbol ('(',
--   '[', etc.): should result into `<open>|<close>`, like `(|)`.
-- - Setup keybindings in the same fashion for "close" symbol (')', ']', etc.):
--   should jump over right symbol if it is equal to "close" one and insert it
--   otherwise.
-- - Setup keybindings in the same fashion for "symmetrical" symbols ('"',
--   '\'', '`'): try to jump over right character if it equal to "symmetrical"
--   and paste pair otherwise.
-- - Update '<CR>' and '<BS>'. Both should do extra thing when left character
--   is "open" symbol and right - "close" symbol:
--     - '<CR>' should put "close" symbol on next line leveraging default
--       indentation.
--     - '<BS>' should remove whole pair.
--
-- What it doesn't do:
-- - It doesn't support conditional autopair. For that use `<C-v>` plus symbol
--   or some kind of "surround" functionality.
-- - It doesn't support multiple characters as "open" and "close" symbols. Use
--   snippets for that.
-- - It doesn't support excluding filetypes. Use `autocmd` to `unmap <buffer>`
--   binding.
local escape = function(s)
  return vim.api.nvim_replace_termcodes(s, true, true, true)
end

Minipairs = {}

local brackets = {'()', '[]', '{}'}
local quotes   = {'""', "''", '``'}
local default_pairs = {'()', '[]', '{}', '""', "''", '``'}

Minipairs.pairs = {c = default_pairs, i = default_pairs, t = quotes}
Minipairs.pairs_bs = {i = default_pairs, t = quotes}
Minipairs.pairs_cr = {i = brackets}

Minipairs.key = {
  bs    = escape('<bs>'),
  cr    = escape('<cr>'),
  del   = escape('<del>'),
  left  = escape('<C-g>U<left>'),
  right = escape('<C-g>U<right>')
}

-- Helpers
function Minipairs.is_in_table(val, tbl)
  if tbl == nil then return false end
  for _, value in pairs(tbl) do
    if val == value then return true end
  end
  return false
end

function Minipairs.get_cursor_pair()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  return string.sub(line, col, col + 1)
end

function Minipairs.get_cursor_right()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  return string.sub(line, col + 1, col + 1)
end

-- Pair actions
function Minipairs:action_open(pair)
  vim.api.nvim_feedkeys(pair .. self.key.left, 'n', true)
end

function Minipairs:action_close(close)
  local right = self.get_cursor_right()
  if right == close then
    vim.api.nvim_feedkeys(self.key.right, 'n', true)
  else
    vim.api.nvim_feedkeys(close, 'n', true)
  end
end

function Minipairs:action_closeopen(pair)
  local right = self.get_cursor_right()
  if right == pair:sub(2, 2) then
    vim.api.nvim_feedkeys(self.key.right, 'n', true)
  else
    self:action_open(pair)
  end
end

function Minipairs:action_bs(pair_set)
  vim.api.nvim_feedkeys(self.key.bs, 'n', true)

  local cursor_pair = self.get_cursor_pair()
  if self.is_in_table(cursor_pair, pair_set) then
    vim.api.nvim_feedkeys(self.key.del, 'n', true)
  end
end

function Minipairs:action_bs(pair_set)
  vim.api.nvim_feedkeys(self.key.bs, 'n', true)

  local cursor_pair = self.get_cursor_pair()
  if self.is_in_table(cursor_pair, pair_set) then
    vim.api.nvim_feedkeys(self.key.del, 'n', true)
  end
end

vim.api.nvim_set_keymap(
  'i', '{', [[<cmd>lua Minipairs:action_open('{}')<CR>]],
  {noremap = true}
)
vim.api.nvim_set_keymap(
  'i', '}', [[<cmd>lua Minipairs:action_close('}')<CR>]],
  {noremap = true}
)
vim.api.nvim_set_keymap(
  'i', ')', [[<cmd>lua Minipairs:action_close(')')<CR>]],
  {noremap = true}
)
vim.api.nvim_set_keymap(
  'i', '"', [[<cmd>lua Minipairs:action_closeopen('""')<CR>]],
  {noremap = true}
)
vim.api.nvim_set_keymap(
  'i', '\'', [[<cmd>lua Minipairs:action_closeopen("''")<CR>]],
  {noremap = true}
)
vim.api.nvim_set_keymap(
  'i', '`', [[<cmd>lua Minipairs:action_closeopen('``')<CR>]],
  {noremap = true}
)
vim.api.nvim_set_keymap(
  'i', '<BS>', [[<cmd>lua Minipairs:action_bs(Minipairs.pairs_bs.i)<CR>]],
  {noremap = true}
)

vim.api.nvim_set_keymap(
  'c', '(', [[<cmd>lua Minipairs:action_open('()')<CR>]],
  {noremap = true}
)
vim.api.nvim_set_keymap(
  'c', ')', [[<cmd>lua Minipairs:action_open(')')<CR>]],
  {noremap = true}
)

vim.api.nvim_set_keymap(
  'i', '<M-m>', [[<cmd>lua print(vim.inspect(Minipairs.get_cursor_pair()))<CR>]],
  {noremap = true}
)
