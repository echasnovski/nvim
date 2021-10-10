-- MIT License Copyright (c) 2021 Evgeni Chasnovski

---@brief [[
--- Custom minimal and fast module for highlighting word under cursor. It is
--- done via Vim's |matchadd()| and |matchdelete()| with low highlighting
--- priority. It is triggered only if current cursor character is a
--- |[:keyword:]. "Word under cursor" is meant as in Vim's |<cword>|: something
--- user would get as 'iw' text object.  Highlighting stops in insert and
--- terminal modes.
---
--- This module needs a setup with `require('mini.cursorword').setup({})`
--- (replace `{}` with your `config` table).
---
--- Default `config`:
--- <pre>
--- {
---   -- On which event highlighting is updated. If default "CursorMoved" is
---   -- too frequent, use "CursorHold"
---   highlight_event = "CursorMoved"
--- }
--- </pre>
---
--- # Highlight groups
--- 1. `MiniCursorword` - highlight group of cursor word. By default, it is a
---    plain underline.
---
--- To change any highlight group, modify it directly with `highlight
--- MiniCursorword` command (see |:highlight|).
---
--- # Disabling
---
--- To disable core functionality, set `g:minicursorword_disable` (globally) or
--- `b:minicursorword_disable` (for a buffer) to `v:true`. Note: after
--- disabling there might be highlighting left; call `lua
--- MiniCursorword.unhighlight()`.
---@brief ]]
---@tag MiniCursorword

-- Module and its helper
local MiniCursorword = {}
local H = {}

--- Module setup
---
---@param config table: Module config table.
---@usage `require('mini.cursorword').setup({})` (replace `{}` with your `config` table)
function MiniCursorword.setup(config)
  -- Export module
  _G.MiniCursorword = MiniCursorword

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Module behavior
  local command = string.format(
    [[augroup MiniCursorword
        au!
        au %s                            * lua MiniCursorword.highlight()
        au InsertEnter,TermEnter,QuitPre * lua MiniCursorword.unhighlight()
      augroup END]],
    config.highlight_event
  )
  vim.api.nvim_exec(command, false)

  -- Create highlighting
  vim.api.nvim_exec([[hi MiniCursorword term=underline cterm=underline gui=underline]], false)
end

-- Module config
MiniCursorword.config = {
  -- On which event highlighting is updated. If default "CursorMoved" is too
  -- frequent, use "CursorHold"
  highlight_event = 'CursorMoved',
}

--- Highlight word under cursor
---
--- Designed to be used inside |autocmd|.
function MiniCursorword.highlight()
  -- A modified version of https://stackoverflow.com/a/25233145
  -- Using `matchadd()` instead of a simpler `:match` to tweak priority of
  -- 'current word' highlighting: with `:match` it is higher than for
  -- `incsearch` which is not convenient.

  if H.is_disabled() then
    return
  end

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
  if win_match.word == curword then
    return
  end

  -- Stop highlighting previous match (if it exists)
  if win_match.id then
    vim.fn.matchdelete(win_match.id)
  end

  -- Make highlighting pattern 'very nomagic' ('\V') and to match whole word
  -- ('\<' and '\>')
  local curpattern = string.format([[\V\<%s\>]], curword)

  -- Add match highlight with very low priority and store match information
  local match_id = vim.fn.matchadd('MiniCursorword', curpattern, -1)
  H.window_matches[win_id] = { word = curword, id = match_id }
end

--- Unhighlight word under cursor
---
--- Designed to be used inside |autocmd|.
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
H.default_config = MiniCursorword.config

---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    highlight_event = {
      config.highlight_event,
      function(x)
        return x == 'CursorMoved' or x == 'CursorHold'
      end,
      'one of strings: "CursorMoved" or "CursorHold"',
    },
  })

  return config
end

function H.apply_config(config)
  MiniCursorword.config = config
end

function H.is_disabled()
  return vim.g.minicursorword_disable == true or vim.b.minicursorword_disable == true
end

---- Information about last match highlighting: word and match id (returned
---- from `vim.fn.matchadd()`). Stored *per window* by its unique identifier.
H.window_matches = {}

function H.is_cursor_on_keyword()
  local col = vim.fn.col('.')
  local curchar = vim.fn.getline('.'):sub(col, col)

  return vim.fn.match(curchar, '[[:keyword:]]') >= 0
end

return MiniCursorword
