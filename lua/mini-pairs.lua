-- Attempt to write *minimal* autopairs Lua plugin.
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
-- - It doesn't support excluding filetypes. Use `autocmd` to `unmap <buffer>`
--   binding.

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
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  return string.sub(line, col + start, col + finish)
end

local brackets = {'()', '[]', '{}'}
local quotes   = {'""', "''", '``'}
local default_pairs = {'()', '[]', '{}', '""', "''", '``'}

local keys = {
  above = escape('<C-o>O'),
  bs    = escape('<bs>'),
  cr    = escape('<cr>'),
  del   = escape('<del>'),
  -- Here keys might be prepended with '<C-g>U' to "don't break undo" but then
  -- they can't be used in command mode
  left  = escape('<left>'),
  right = escape('<right>')
}

-- Module
Minipairs = {}

-- Pairs, elements of which will be mapped (in respective mode) to "open",
-- "close", or "closeopen" action
Minipairs.pairs = {c = default_pairs, i = default_pairs, t = quotes}
-- Pairs which will trigger extra action for '<BS>' and '<CR>'
Minipairs.pairs_bs = {i = default_pairs, t = quotes}
---- NOTE: current implementation of `Minipairs.action_cr()` assumes only
---- insert mode mapping as it uses '<C-o>' key
Minipairs.pairs_cr = {i = brackets}

-- Pair actions.
-- They are intended to be used inside `_noremap <expr> ...` type of mappings,
-- as they return sequence of keys (instead of other possible approach of
-- simulating them with `nvim_feedkeys()`).
function Minipairs.action_open(pair)
  return pair .. keys.left
end

---- NOTE: `pair` as argument is used for consistency (when `right` is enough)
function Minipairs.action_close(pair)
  local close = pair:sub(2, 2)
  if get_cursor_chars(1, 1) == close then
    return keys.right
  else
    return close
  end
end

function Minipairs.action_closeopen(pair)
  if get_cursor_chars(1, 1) == pair:sub(2, 2) then
    return keys.right
  else
    return pair .. keys.left
  end
end

---- Each argument should be a pair which triggers extra action
function Minipairs.action_bs(...)
  local res = keys.bs

  if is_in_table(get_cursor_chars(0, 1), {...}) then
    res = res .. keys.del
  end

  return res
end

function Minipairs.action_cr(...)
  local res = keys.cr

  if is_in_table(get_cursor_chars(0, 1), {...}) then
    res = res .. keys.above
  end

  return res
end

-- Mappings setup
function Minipairs:setup_mappings()
  for m, pair_set in pairs(self.pairs) do
    for _, p in pairs(pair_set) do
      self:map_single_pair(m, p)
    end
  end
  for m, pair_set in pairs(self.pairs_bs) do
    self:map_bs_cr(m, pair_set, '<BS>')
  end
  for m, pair_set in pairs(self.pairs_cr) do
    self:map_bs_cr(m, pair_set, '<CR>')
  end
end

function Minipairs:map_single_pair(mode, pair)
  local left = pair:sub(1, 1)
  local right = pair:sub(2, 2)
  local is_symmetrical = left == right
  local pair_quoted = vim.inspect(pair)

  -- Map left
  local action_name_left
  if mode == 'c' then
    -- "Close" action can't be done in command mode as it uses
    -- `vim.api.nvim_get_current_line()`
    action_name_left = 'action_open'
  else
    action_name_left = is_symmetrical and 'action_closeopen' or 'action_open'
  end

  local command_left = string.format(
    'v:lua.Minipairs.%s(%s)',
    action_name_left, pair_quoted
  )
  map(mode, left, command_left)

  -- Map right (for asymmetrical case not in command mode)
  if not ((mode == 'c') or is_symmetrical) then
    local command_right = string.format(
      'v:lua.Minipairs.action_close(%s)',
      pair_quoted
    )
    map(mode, right, command_right)
  end
end

function Minipairs:map_bs_cr(mode, pair_set, key)
  -- Return single string representing a sequence of pair strings
  local pair_set_string = vim.inspect(pair_set):sub(2, -2)
  local action_suffix = (key == '<BS>') and 'bs' or 'cr'
  local command = string.format(
    'v:lua.Minipairs.action_%s(%s)',
    action_suffix, pair_set_string
  )
  map(mode, key, command)
end

Minipairs:setup_mappings()
