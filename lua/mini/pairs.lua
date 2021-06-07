-- Custom *minimal* autopairs Lua module. This is meant to be a standalone file
-- which when sourced in 'init.*' file provides a working minimal auto pairs.
-- It provides functionality to work with 'paired' characters conditional on
-- cursor's neighborhood (two characters to its left and right; beginning of
-- line is '\r', end of line is `\n`). Its usage should be through making
-- appropriate `<expr>` mappings.
--
-- Details of functionality:
-- - `MiniPairs.open()` is for "open" symbols ('(', '[', etc.). If neighborhood
--   doesn't match supplied pattern, function results into "open" symbol.
--   Otherwise, it pastes whole pair and moving inside pair: `<open>|<close>`,
--   like `(|)`.
-- - `MiniPairs.close()` is for "close" symbols (')', ']', etc.). If
--   neighborhood doesn't match supplied pattern, function results into "close"
--   symbol. Otherwise it jumps over symbol to the right of cursor if it is
--   equal to "close" one and inserts it otherwise.
-- - `MiniPairs.closeopen()` is intended to be mapped to "symmetrical" symbols
--   (from pairs '""', '\'\'', '``'). It tries to perform "closeopen action":
--   move over right character if it is equal to second character from pair or
--   conditionally paste pair otherwise (as in `MiniPairs.open()`).
-- - `MiniPairs.bs()` is intended to be mapped to `<BS>`. It removes whole pair
--   (via `<BS><Del>`) if neighborhood is equal to whole pair.
-- - `MiniPairs.cr()` is intended to be mapped to `<CR>`. It puts "close"
--   symbol on next line (via `<CR><C-o>O`) if neighborhood is equal to whole
--   pair. Should be used only in insert mode.
--
-- What it doesn't do:
-- - It doesn't support multiple characters as "open" and "close" symbols. Use
--   snippets for that.
-- - It doesn't support dependency on filetype. Use `autocmd` command or
--   'after/ftplugin' approach to:
--     - `inoremap <buffer> <*> <*>` : return mapping of '<*>' to its original
--       action, virtually unmapping.
--     - `inoremap <buffer> <expr> <*> v:lua.MiniPairs.?` : make new
--       buffer mapping for '<*>'.
-- NOTES:
-- - Make sure to make proper mapping of `<CR>` in order to support completion
--   plugin of your choice.
-- - Having mapping in terminal mode can conflict with autopairing capabilities
--   of opened interpretators (for example, `radian`).
-- - Sometimes has troubles with multibyte characters (such as icons). This
--   seems to be because detecting characters around cursor uses "byte
--   substring" instead of "symbol substring" operation.

-- Module
local MiniPairs = {}

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

  -- Add '\r' and '\n' to always return 2 characters
  return string.sub('\r' .. line .. '\n', col + 1 + start, col + 1 + finish)
end

local neigh_match = function(pattern)
  return (pattern == nil) or (get_cursor_chars(0, 1):find(pattern) ~= nil)
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

-- Module functionality
-- They are intended to be used inside `_noremap <expr> ...` type of mappings,
-- as they return sequence of keys (instead of other possible approach of
-- simulating them with `nvim_feedkeys()`).
function MiniPairs.open(pair, twochars_pattern)
  if not neigh_match(twochars_pattern) then return pair:sub(1, 1) end

  return pair .. get_arrow_key('left')
end

function MiniPairs.close(pair, twochars_pattern)
  if not neigh_match(twochars_pattern) then return pair:sub(2, 2) end

  local close = pair:sub(2, 2)
  if get_cursor_chars(1, 1) == close then
    return get_arrow_key('right')
  else
    return close
  end
end

function MiniPairs.closeopen(pair, twochars_pattern)
  if get_cursor_chars(1, 1) == pair:sub(2, 2) then
    return get_arrow_key('right')
  else
    return MiniPairs.open(pair, twochars_pattern)
  end
end

---- Each argument should be a pair which triggers extra action
function MiniPairs.bs(pair_set)
  local res = keys.bs

  if is_in_table(get_cursor_chars(0, 1), pair_set) then
    res = res .. keys.del
  end

  return res
end

function MiniPairs.cr(pair_set)
  local res = keys.cr

  if is_in_table(get_cursor_chars(0, 1), pair_set) then
    res = res .. keys.above
  end

  return res
end

function MiniPairs.setup()
  -- Setup mappings in command and insert modes
  for _, mode in pairs({'c', 'i'}) do
    map(mode, '(', [[v:lua.MiniPairs.open('()')]])
    map(mode, '[', [[v:lua.MiniPairs.open('[]')]])
    map(mode, '{', [[v:lua.MiniPairs.open('{}')]])

    map(mode, ')', [[v:lua.MiniPairs.close('()')]])
    map(mode, ']', [[v:lua.MiniPairs.close('[]')]])
    map(mode, '}', [[v:lua.MiniPairs.close('{}')]])

    -- Quotes insert single character if after a letter or `\`
    map(mode, '"', [[v:lua.MiniPairs.closeopen('""', '[^%a\\].')]])
    map(mode, "'", [[v:lua.MiniPairs.closeopen("''", '[^%a\\].')]])
    map(mode, '`', [[v:lua.MiniPairs.closeopen('``', '[^%a\\].')]])

    map(mode, '<BS>', [[v:lua.MiniPairs.bs(['()', '[]', '{}', '""', "''", '``'])]])
  end

  -- Map `<CR>` only in insert mode. Remap this to respect completion plugin.
  map('i', '<CR>', [[v:lua.MiniPairs.cr(['()', '[]', '{}'])]])

  -- In terminal mode map only `<BS>`. Mainly because adding autopairs seems to
  -- bring more trouble in day-to-day usage.
  map('t', '<BS>', [[v:lua.MiniPairs.bs(['()', '[]', '{}', '""', "''", '``'])]])
end

_G.MiniPairs = MiniPairs
return MiniPairs
