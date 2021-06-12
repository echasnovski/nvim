-- Custom *minimal* and *fast* module for highlighting word under cursor.
--
-- To activate, put this file somewhere into 'lua' folder and call module's
-- `setup()`. For example, put as 'lua/mini/cursorword.lua' and execute
-- `require('mini.cursorword').setup()` Lua code.
--
-- Highlighting is done via Vim's `matchadd()` and `matchdelete()` with low
-- highlighting priority. It is triggered only if current cursor character is
-- 'keyword' (see `help [:keyword:]`). "Word under cursor" is meant as in Vim's
-- `<cword>`: something user would get as 'iw' text object. Highlighting stops
-- in insert and terminal modes. User can also toggle (enable when disabled,
-- disable when enabled) highlighting itself via `MiniCursorword.toggle()`.
--
-- NOTE: currently highlighting is updated on every `CursorMoved` event. If it
-- is too frequent, use `CursorHold` event.

local MiniCursorword = {}
local H = {}

function MiniCursorword.setup()
  _G.MiniCursorword = MiniCursorword

  -- Module behavior
  -- NOTE: if this updates too frequently, use `CursorHold`
  vim.api.nvim_exec([[
    augroup MiniCursorword
      au!
      au CursorMoved                   * lua MiniCursorword.highlight()
      au InsertEnter,TermEnter,QuitPre * lua MiniCursorword.unhighlight()
    augroup END
  ]], false)

  -- Create highlighting
  vim.api.nvim_exec([[
    hi MiniCursorword term=underline cterm=underline gui=underline
  ]], false)
end

-- A modified version of https://stackoverflow.com/a/25233145
-- Using `matchadd()` instead of a simpler `:match` to tweak priority of
-- 'current word' highlighting: with `:match` it is higher than for
-- `incsearch` which is not convenient.
function MiniCursorword.highlight()
  if not H.do_highlight then return end

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

function MiniCursorword.toggle()
  if H.do_highlight then
    H.do_highlight = false
    MiniCursorword.unhighlight()
  else
    H.do_highlight = true
    MiniCursorword.highlight()
  end
end

-- Indicator of whether to actually do highlighing
H.do_highlight = true

-- Information about last match highlighting: word and match id (returned from
-- `vim.fn.matchadd()`). Stored *per window* by its unique identifier.
H.window_matches = {}

function H.is_cursor_on_keyword()
  local col = vim.fn.col('.')
  local curchar = vim.fn.getline('.'):sub(col, col)

  return vim.fn.match(curchar, '[[:keyword:]]') >= 0
end

return MiniCursorword
