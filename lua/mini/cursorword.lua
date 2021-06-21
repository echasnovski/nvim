-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Custom *minimal* and *fast* module for highlighting word under cursor.
--
-- To activate, put this file somewhere into 'lua' folder and call module's
-- `setup()`. For example, put as 'lua/mini/cursorword.lua' and execute
-- `require('mini.cursorword').setup()` Lua code. It may have `config` argument
-- which should be a table overwriting default values using same structure.
--
-- Default `config`:
-- {
--     -- On which event highlighting is updated. If default "CursorMoved" is
--     -- too frequent, use "CursorHold"
--     highlight_event = "CursorMoved"
-- }
--
-- Features:
-- - Enable, disable, and toggle module with `enable()`, `disable()`, and
--   `toggle()` functions.
-- - Highlight word under cursor. It is done via Vim's `matchadd()` and
--   `matchdelete()` with low highlighting priority. It is triggered only if
--   current cursor character is 'keyword' (see `help [:keyword:]`). "Word
--   under cursor" is meant as in Vim's `<cword>`: something user would get
--   as 'iw' text object. Highlighting stops in insert and terminal modes.
-- - Highlighting is done according to `MiniCursorword` highlight group. By
--   default, it is a plain underline. To change it, modify it directly with
--   `highlight MiniCursorword` command.

-- Module and its helper
local MiniCursorword = {}
local H = {}

-- Module setup
function MiniCursorword.setup(config)
  -- Export module
  _G.MiniCursorword = MiniCursorword

  -- Module behavior
  highlight_event = (config or {}).highlight_event or H.config.highlight_event
  command = string.format([[
    augroup MiniCursorword
      au!
      au %s                            * lua MiniCursorword.highlight()
      au InsertEnter,TermEnter,QuitPre * lua MiniCursorword.unhighlight()
    augroup END
  ]], highlight_event)
  vim.api.nvim_exec(command, false)

  -- Create highlighting
  vim.api.nvim_exec([[
    hi MiniCursorword term=underline cterm=underline gui=underline
  ]], false)
end

-- Functions to enable/disable whole module
function MiniCursorword.enable()
  H.enabled = true
  MiniCursorword.highlight()
  print('(mini.cursorword) Enabled')
end

function MiniCursorword.disable()
  H.enabled = false
  MiniCursorword.unhighlight()
  print('(mini.cursorword) Disabled')
end

function MiniCursorword.toggle()
  if H.enabled then MiniCursorword.disable() else MiniCursorword.enable() end
end

-- A modified version of https://stackoverflow.com/a/25233145
-- Using `matchadd()` instead of a simpler `:match` to tweak priority of
-- 'current word' highlighting: with `:match` it is higher than for
-- `incsearch` which is not convenient.
function MiniCursorword.highlight()
  if not H.enabled then return end

  -- Highlight word only if cursor is on 'keyword' character
  if not H.is_cursor_on_keyword() then
    -- Stop highlighting immediately when cursor is not on 'keyword'
    MiniCursorword.unhighlight()
    return
  end

  -- Get current information
  local win_id = vim.fn.win_getid()
  local win_match = H.window_matches[win_id] or {}
  local curword = vim.fn.escape(vim.fn.expand('<cword>'), [[\/]])

  -- Don't do anything if currently highlighted word equals one on cursor
  if win_match.word == curword then return end

  -- Stop highlighting previous match (if it exists)
  if win_match.id then vim.fn.matchdelete(win_match.id) end

  -- Make highlighting pattern 'very nomagic' ('\V') and to match whole word
  -- ('\<' and '\>')
  local curpattern = string.format([[\V\<%s\>]], curword)

  -- Add match highlight with very low priority and store match information
  local match_id = vim.fn.matchadd('MiniCursorword', curpattern, -1)
  H.window_matches[win_id] = {word = curword, id = match_id}
end

function MiniCursorword.unhighlight()
  local win_id = vim.fn.win_getid()
  local win_match = H.window_matches[win_id]
  if win_match ~= nil then
    vim.fn.matchdelete(win_match.id)
    H.window_matches[win_id] = nil
  end
end

-- Helpers
---- Module default config
H.config = {highlight_event = "CursorMoved"}

---- Indicator of whether to actually do highlighing
H.enabled = true

---- Information about last match highlighting: word and match id (returned
---- from `vim.fn.matchadd()`). Stored *per window* by its unique identifier.
H.window_matches = {}

function H.is_cursor_on_keyword()
  local col = vim.fn.col('.')
  local curchar = vim.fn.getline('.'):sub(col, col)

  return vim.fn.match(curchar, '[[:keyword:]]') >= 0
end

return MiniCursorword
