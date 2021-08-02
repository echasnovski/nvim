-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Custom *minimal* and *fast* autopairs Lua module. It provides functionality
-- to work with 'paired' characters conditional on cursor's neighborhood (two
-- characters to its left and right; beginning of line is "\r", end of line is
-- "\n"). Its usage should be through making appropriate `<expr>` mappings.
--
-- To activate, put this file somewhere into 'lua' folder and call module's
-- `setup()`. For example, put as 'lua/mini/pairs.lua' and execute
-- `require('mini.pairs').setup()` Lua code. It may have `config` argument
-- which should be a table overwriting default values using same structure.
--
-- Default `config`:
-- {
--   -- In which modes mappings should be created
--   modes = {insert = true, command = false, terminal = false}
-- }
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
-- - `MiniPairs.setup()` creates the following mappings (all mappings are
--   conditioned on previous character not being '\'):
--     - Open and close symbols: '()', '[]', '{}'.
--     - Closeopen symbol: '"', "'", '`'. Note: "'" doesn't insert pair if
--       previous character is a letter (to be usable in English comments).
--     - `<BS>` for all previous pairs.
--     - `<CR>` in insert mode for '()', '[]', '{}'.
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
-- - Having mapping in terminal mode:
--     - Can conflict with autopairing capabilities of opened interpretators
--       (for example, `radian`).
--     - Adds autopairing in fzf search window. To disable it, setup
--       autocommands like: `au Filetype fzf tnoremap <buffer> ( (`, etc.
-- - Sometimes has troubles with multibyte characters (such as icons). This
--   seems to be because detecting characters around cursor uses "byte
--   substring" instead of "symbol substring" operation.

-- Module and its helper
local MiniPairs = {}
local H = {}

-- Module setup
function MiniPairs.setup(config)
  -- Export module
  _G.MiniPairs = MiniPairs

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

-- Module Settings
---- In which modes mappings should be created
MiniPairs.modes = {insert = true, command = false, terminal = false}

-- Module functionality
function MiniPairs.open(pair, twochars_pattern)
  if not H.neigh_match(twochars_pattern) then return pair:sub(1, 1) end

  return pair .. H.get_arrow_key('left')
end

function MiniPairs.close(pair, twochars_pattern)
  if not H.neigh_match(twochars_pattern) then return pair:sub(2, 2) end

  local close = pair:sub(2, 2)
  if H.get_cursor_neigh(1, 1) == close then
    return H.get_arrow_key('right')
  else
    return close
  end
end

function MiniPairs.closeopen(pair, twochars_pattern)
  if H.get_cursor_neigh(1, 1) == pair:sub(2, 2) then
    return H.get_arrow_key('right')
  else
    return MiniPairs.open(pair, twochars_pattern)
  end
end

---- Each argument should be a pair which triggers extra action
function MiniPairs.bs(pair_set)
  local res = H.keys.bs

  if H.is_in_table(H.get_cursor_neigh(0, 1), pair_set) then
    res = res .. H.keys.del
  end

  return res
end

function MiniPairs.cr(pair_set)
  local res = H.keys.cr

  if H.is_in_table(H.get_cursor_neigh(0, 1), pair_set) then
    res = res .. H.keys.above
  end

  return res
end

-- Helpers
---- Module default config
H.config = {modes = MiniPairs.modes}

---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({config = {config, 'table', true}})
  config = vim.tbl_deep_extend('force', H.config, config or {})

  vim.validate({
    modes = {config.modes, 'table'},
    ['modes.insert'] = {config.modes.insert, 'boolean'},
    ['modes.command'] = {config.modes.command, 'boolean'},
    ['modes.terminal'] = {config.modes.terminal, 'boolean'}
  })

  return config
end

function H.apply_config(config)
  MiniPairs.modes = config.modes

  -- Setup mappings in supplied modes
  local mode_ids = {insert = 'i', command = 'c', terminal = 't'}
  ---- Compute in which modes mapping should be set up
  local mode_list = {}
  for name, to_set in pairs(config.modes) do
    if to_set then table.insert(mode_list, mode_ids[name]) end
  end

  for _, mode in pairs(mode_list) do
    -- Adding pair is disabled if symbol is after `\`
    H.map(mode, '(', [[v:lua.MiniPairs.open('()', "[^\\].")]])
    H.map(mode, '[', [[v:lua.MiniPairs.open('[]', "[^\\].")]])
    H.map(mode, '{', [[v:lua.MiniPairs.open('{}', "[^\\].")]])

    H.map(mode, ')', [[v:lua.MiniPairs.close("()", "[^\\].")]])
    H.map(mode, ']', [[v:lua.MiniPairs.close("[]", "[^\\].")]])
    H.map(mode, '}', [[v:lua.MiniPairs.close("{}", "[^\\].")]])

    H.map(mode, '"', [[v:lua.MiniPairs.closeopen('""', "[^\\].")]])
    ---- Single quote is used in plain English, so disable pair after a letter
    H.map(mode, "'", [[v:lua.MiniPairs.closeopen("''", "[^%a\\].")]])
    H.map(mode, '`', [[v:lua.MiniPairs.closeopen('``', "[^\\].")]])

    H.map(mode, '<BS>', [[v:lua.MiniPairs.bs(['()', '[]', '{}', '""', "''", '``'])]])

    if mode == 'i' then
      H.map('i', '<CR>', [[v:lua.MiniPairs.cr(['()', '[]', '{}'])]])
    end
  end
end

---- Various helpers
function H.map(mode, key, command)
  vim.api.nvim_set_keymap(mode, key, command, {expr = true, noremap = true})
end

function H.get_cursor_neigh(start, finish)
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

function H.neigh_match(pattern)
  return (pattern == nil) or (H.get_cursor_neigh(0, 1):find(pattern) ~= nil)
end

function H.escape(s)
  return vim.api.nvim_replace_termcodes(s, true, true, true)
end

H.keys = {
  above     = H.escape('<C-o>O'),
  bs        = H.escape('<bs>'),
  cr        = H.escape('<cr>'),
  del       = H.escape('<del>'),
  keep_undo = H.escape('<C-g>U'),
  -- NOTE: use `get_arrow_key()` instead of `H.keys.left` or `H.keys.right`
  left      = H.escape('<left>'),
  right     = H.escape('<right>')
}

function H.get_arrow_key(key)
  if vim.fn.mode() == 'i' then
    -- Using left/right keys in insert mode breaks undo sequence and, more
    -- importantly, dot-repeat. To avoid this, use 'i_CTRL-G_U' mapping.
    return H.keys.keep_undo .. H.keys[key]
  else
    return H.keys[key]
  end
end

function H.is_in_table(val, tbl)
  if tbl == nil then return false end
  for _, value in pairs(tbl) do
    if val == value then return true end
  end
  return false
end

return MiniPairs
