-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Custom *minimal* and *fast* module for working with trailing whitespace.
--
-- To activate, put this file somewhere into 'lua' folder and call module's
-- `setup()`. For example, put as 'lua/mini/trailspace.lua' and execute
-- `require('mini.trailspace').setup()` Lua code. It may have `config` argument
-- which should be a table overwriting default values using same structure.
--
-- Default `config`: {} (currently nothing to configure)
--
-- Features:
-- - Enable, disable, and toggle module with `enable()`, `disable()`, and
--   `toggle()` functions.
-- - Highlighting of trailing space is enabled in every buffer by default.
--   Custom setup is needed to enable it based on some rules.
-- - Highlighting stops in insert mode and when leaving window.
-- - Trim all trailing whitespace with `trim()` function.
-- - Highlighting is done according to `MiniTrailspace` highlight group. To
--   change this, modify it directly with `highlight MiniTrailspace` command.

-- Module and its helper
local MiniTrailspace = {}
local H = {}

-- Module setup
function MiniTrailspace.setup(config)
  -- Export module
  _G.MiniTrailspace = MiniTrailspace

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Module behavior
  vim.api.nvim_exec(
    [[augroup MiniTrailspace
        au!
        au WinEnter,BufWinEnter,InsertLeave * lua MiniTrailspace.highlight()
        au WinLeave,BufWinLeave,InsertEnter * lua MiniTrailspace.unhighlight()
      augroup END]],
    false
  )

  -- Create highlighting
  vim.api.nvim_exec([[hi link MiniTrailspace Error]], false)
end

-- Functions to enable/disable whole module
function MiniTrailspace.enable()
  H.enabled = true
  MiniTrailspace.highlight()
  print('(mini.trailspace) Enabled')
end

function MiniTrailspace.disable()
  H.enabled = false
  MiniTrailspace.unhighlight()
  print('(mini.trailspace) Disabled')
end

function MiniTrailspace.toggle()
  if H.enabled then
    MiniTrailspace.disable()
  else
    MiniTrailspace.enable()
  end
end

-- Functions to perform actions
function MiniTrailspace.highlight()
  -- Do nothing if disabled
  if not H.enabled then
    return
  end

  local win_id = vim.fn.win_getid()
  local win_match = H.window_matches[win_id]

  -- Don't add match id on top of existing one (prevents multiple calls of
  -- `MiniTrailspace.enable()`)
  if win_match == nil then
    H.window_matches[win_id] = vim.fn.matchadd('MiniTrailspace', [[\s\+$]])
  end
end

function MiniTrailspace.unhighlight()
  local win_id = vim.fn.win_getid()
  local win_match = H.window_matches[win_id]
  if win_match ~= nil then
    vim.fn.matchdelete(win_match)
    H.window_matches[win_id] = nil
  end
end

function MiniTrailspace.trim()
  -- Save cursor position to later restore
  local curpos = vim.api.nvim_win_get_cursor(0)
  -- Search and replace trailing whitespace
  vim.cmd([[keeppatterns %s/\s\+$//e]])
  vim.api.nvim_win_set_cursor(0, curpos)
end

-- Helpers
---- Module default config
H.config = {}

---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.config, config or {})

  return config
end

function H.apply_config(config)
  -- There is nothing to do yet
end

---- Indicator of whether to actually do highlighing
H.enabled = true

-- Information about last match highlighting: word and match id (returned from
-- `vim.fn.matchadd()`). Stored *per window* by its unique identifier.
H.window_matches = {}

return MiniTrailspace
