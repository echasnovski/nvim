-- Custom *minimal* autopairs Lua plugin. This is meant to be a standalone file
-- which when sourced in 'init.*' file provides a working minimal auto pairs.
--
-- Initial goal is to setup keybindings for custom pairs in custom modes ('i',
-- 'c', 't'):
-- - "Open" symbols ('(', '[', etc.) should result into pasting whole pair and
--   moving inside pair: `<open>|<close>`, like `(|)`.
-- - "Close" symbols (')', ']', etc.) should jump over symbol to the right of
--   cursor if it is equal to "close" one and insert it otherwise.
-- - "Symmetrical" symbols (from pairs '""', '\'\'', '``') should try perform
--   "closeopen action": jump over right character if it is equal to second
--   character from pair and paste pair otherwise.
-- - `<BS>` and `<CR>`. Both should do extra thing when left character is
--   "open" symbol and right - "close" symbol:
--     - '<BS>' should remove whole pair.
--     - '<CR>' should put "close" symbol on next line leveraging default
--       indentation.
--
-- What it doesn't do:
-- - It doesn't support conditional autopair. Depending on task, Use `<C-v>`
--   plus symbol or some kind of "surround" functionality.
-- - It doesn't support multiple characters as "open" and "close" symbols. Use
--   snippets for that.
-- - It doesn't support excluding filetypes. Use `autocmd` command or
--   'after/ftplugin' approach to:
--     - `inoremap <buffer> <*> <*>` : return mapping of '<*>' to its original
--       action, virtually unmapping.
--     - `inoremap <buffer> <expr> <*> v:lua.MiniPairs.action_...` : make new
--       buffer mapping for '<*>'.
-- NOTES:
-- - To remove autopairing of '""' and add autopairing to "''", use `call
--   luaeval("MiniPairs.remap_quotes()")`.
-- - Currently buffer mapping of `<CR>` is not well supported as there is a
--   global mapping in 'zzz.lua' file. It takes into account completion and
--   snippet extension.
-- - Having mapping in terminal mode can conflict with autopairing capabilities
--   of opened interpretators (notably `radian`).

-- Helpers
local escape = function(s)
  return vim.api.nvim_replace_termcodes(s, true, true, true)
end

local map = function(mode, key, command)
  vim.api.nvim_set_keymap(mode, key, command, {expr = true, noremap = true})
end

local is_in_table = function(val, tbl)
  if tbl == nil then return false end
  for _, value in pairs(tbl) do
    if val == value then return true end
  end
  return false
end

local get_cursor_chars = function(start, finish)
  local line, col
  if vim.fn.mode() == 'c' then
    line = vim.fn.getcmdline()
    col = vim.fn.getcmdpos()
    -- Adjust start and finish because output of `getcmdpos()` starts counting
    -- columns from 1
    start = start - 1
    finish = finish - 1
  else
    line = vim.api.nvim_get_current_line()
    col = vim.api.nvim_win_get_cursor(0)[2]
  end

  return string.sub(line, col + start, col + finish)
end

local table_to_seqstring = function(t)
  return vim.inspect(t):sub(2, -2)
end

local keys = {
  above     = escape('<C-o>O'),
  bs        = escape('<bs>'),
  cr        = escape('<cr>'),
  del       = escape('<del>'),
  keep_undo = escape('<C-g>U'),
  -- NOTE: use `get_arrow_key()` instead of `keys.left` or `keys.right`
  left      = escape('<left>'),
  right     = escape('<right>')
}

-- Using left/right keys in insert mode breaks undo sequence and, more
-- importantly, dot-repeat. To avoid this, use 'i_CTRL-G_U' mapping.
local get_arrow_key = function(key)
  if vim.fn.mode() == 'i' then
    return keys.keep_undo .. keys[key]
  else
    return keys[key]
  end
end

-- Module
MiniPairs = {}

-- Pair actions.
-- They are intended to be used inside `_noremap <expr> ...` type of mappings,
-- as they return sequence of keys (instead of other possible approach of
-- simulating them with `nvim_feedkeys()`).
function MiniPairs.action_open(pair)
  return pair .. get_arrow_key('left')
end

---- NOTE: `pair` as argument is used for consistency (when `right` is enough)
function MiniPairs.action_close(pair)
  local close = pair:sub(2, 2)
  if get_cursor_chars(1, 1) == close then
    return get_arrow_key('right')
  else
    return close
  end
end

function MiniPairs.action_closeopen(pair)
  if get_cursor_chars(1, 1) == pair:sub(2, 2) then
    return get_arrow_key('right')
  else
    return pair .. get_arrow_key('left')
  end
end

---- Each argument should be a pair which triggers extra action
function MiniPairs.action_bs(pair_set)
  local res = keys.bs

  if is_in_table(get_cursor_chars(0, 1), pair_set) then
    res = res .. keys.del
  end

  return res
end

function MiniPairs.action_cr(pair_set)
  local res = keys.cr

  if is_in_table(get_cursor_chars(0, 1), pair_set) then
    res = res .. keys.above
  end

  return res
end

function MiniPairs.remap_quotes()
  -- Map '"' to its original action ("remove" its mapping in buffer)
  vim.cmd[[inoremap <buffer> " "]]

  -- Map '\''
  vim.cmd[[inoremap <buffer> <expr> ' v:lua.MiniPairs.action_closeopen("''")]]
end

-- Setup mappings
--- Insert mode
map('i', '(', [[v:lua.MiniPairs.action_open('()')]])
map('i', '[', [[v:lua.MiniPairs.action_open('[]')]])
map('i', '{', [[v:lua.MiniPairs.action_open('{}')]])

map('i', ')', [[v:lua.MiniPairs.action_close('()')]])
map('i', ']', [[v:lua.MiniPairs.action_close('[]')]])
map('i', '}', [[v:lua.MiniPairs.action_close('{}')]])

map('i', '"', [[v:lua.MiniPairs.action_closeopen('""')]])
---- No auto-pair for '\'' because it messes up with plain English used in
---- comments (like can't, etc.)
map('i', '`', [[v:lua.MiniPairs.action_closeopen('``')]])

map('i', '<BS>', [[v:lua.MiniPairs.action_bs(['()', '[]', '{}', '""', "''", '``'])]])
map('i', '<CR>', [[v:lua.MiniPairs.action_cr(['()', '[]', '{}'])]])

--- Command mode
map('c', '(', [[v:lua.MiniPairs.action_open('()')]])
map('c', '[', [[v:lua.MiniPairs.action_open('[]')]])
map('c', '{', [[v:lua.MiniPairs.action_open('{}')]])

map('c', ')', [[v:lua.MiniPairs.action_close('()')]])
map('c', ']', [[v:lua.MiniPairs.action_close('[]')]])
map('c', '}', [[v:lua.MiniPairs.action_close('{}')]])

map('c', '"', [[v:lua.MiniPairs.action_closeopen('""')]])
map('c', "'", [[v:lua.MiniPairs.action_closeopen("''")]])
map('c', '`', [[v:lua.MiniPairs.action_closeopen('``')]])

map('c', '<BS>', [[v:lua.MiniPairs.action_bs(['()', '[]', '{}', '""', "''", '``'])]])

--- Terminal mode
map('t', '(', [[v:lua.MiniPairs.action_open('()')]])
map('t', '[', [[v:lua.MiniPairs.action_open('[]')]])
map('t', '{', [[v:lua.MiniPairs.action_open('{}')]])

map('t', ')', [[v:lua.MiniPairs.action_close('()')]])
map('t', ']', [[v:lua.MiniPairs.action_close('[]')]])
map('t', '}', [[v:lua.MiniPairs.action_close('{}')]])

map('t', '"', [[v:lua.MiniPairs.action_closeopen('""')]])
map('t', "'", [[v:lua.MiniPairs.action_closeopen("''")]])
map('t', '`', [[v:lua.MiniPairs.action_closeopen('``')]])

map('t', '<BS>', [[v:lua.MiniPairs.action_bs(['()', '[]', '{}', '""', "''", '``'])]])

--- Remap quotes in certain filetypes
vim.cmd[[au FileType lua lua MiniPairs.remap_quotes()]]
vim.cmd[[au FileType vim lua MiniPairs.remap_quotes()]]

return MiniPairs
