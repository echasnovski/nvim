-- Custom minimal **fast** module for highlighting of word under cursor. This
-- file provides needed functionality, which will be activated when `setup()`
-- function is called.
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
  if H.do_highlight then
    -- Remove current match so that only current word will be highlighted
    -- (otherwise they will add up as a result of `matchadd` calls)
    MiniCursorword.unhighlight()

    -- Highlight word only if cursor is on 'keyword' character
    if H.is_cursor_on_keyword() then
      local curword = vim.fn.escape(vim.fn.expand('<cword>'), [[\/]])
      -- Highlight with 'very nomagic' pattern match ('\V') and for pattern to
      -- match whole word ('\<' and '\>')
      local curpattern = string.format([[\V\<%s\>]], curword)
      -- Add match highlight with very low priority and store match identifier
      -- *per window*
      local win_id = vim.api.nvim_win_get_number(0)
      H.curword_lastmatch[win_id] = vim.fn.matchadd('MiniCursorword', curpattern, -1)
    end
  end
end

function MiniCursorword.unhighlight()
  local win_id = vim.api.nvim_win_get_number(0)
  if H.curword_lastmatch[win_id] ~= nil then
    vim.fn.matchdelete(H.curword_lastmatch[win_id])
    H.curword_lastmatch[win_id] = nil
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

-- Identification number of last match (returned from `vim.fn.matchadd()`)
-- stored *per window*
H.curword_lastmatch = {}

function H.is_cursor_on_keyword()
  local col = vim.fn.col('.')
  local curchar = vim.fn.getline('.'):sub(col, col)

  return vim.fn.match(curchar, '[[:keyword:]]') >= 0
end

return MiniCursorword
