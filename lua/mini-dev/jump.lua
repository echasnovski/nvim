-- MIT License Copyright (c) 2021 Evgeni Chasnovski, Adam Blažek

---@brief [[
--- Minimal and fast module for smarter jumping to a single character. Inspired
--- by 'rhysd/clever-f.vim'.
---
--- Features:
--- - Extend f, F, t, T to work on multiple lines.
--- - Repeat jump by pressing f, F, t, T again. It is reset when cursor moved
---   as a result of not jumping.
--- - Highlight (after customizable delay) of all possible target characters.
--- - Normal, visual, and operator-pending (with a reasonable dot-repeat) modes
---   are supported.
---
--- # Setup
---
--- This module needs a setup with `require('mini.jump').setup({})`
--- (replace `{}` with your `config` table).
---
--- Default `config`:
--- <code>
---   {
---     -- Mappings. Use `''` (empty string) to disable one.
---     mappings = {
---       forward = 'f',
---       backward = 'F',
---       forward_till = 't',
---       backward_till = 'T',
---     },
---
---     -- Delay (in ms) between jump and highlighting all possible jumps. Set to a
---     -- very big number (like 10^7) to virtually disable highlighting.
---     highlight_delay = 250,
---   }
--- </code>
--- #Highlight groups
---
--- - `MiniJump` - all possible cursor positions.
---
--- # Disabling
---
--- To disable core functionality, set `g:minijump_disable` (globally) or
--- `b:minijump_disable` (for a buffer) to `v:true`.
---@brief ]]
---@tag MiniJump mini.jump

-- Module and its helper --
local MiniJump = {}
local H = {}

--- Module setup
---
---@param config table: Module config table.
---@usage `require('mini.jump').setup({})` (replace `{}` with your `config` table)
function MiniJump.setup(config)
  -- Export module
  _G.MiniJump = MiniJump

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Module behavior
  vim.cmd([[autocmd CursorMoved * lua MiniJump.on_cursormoved()]])
  vim.cmd([[autocmd BufLeave,InsertEnter * lua MiniJump.stop_jumping()]])

  -- Highlight groups
  vim.cmd([[hi default link MiniJump SpellRare]])
end

-- Module config --
MiniJump.config = {
  mappings = {
    forward = 'f',
    backward = 'F',
    forward_till = 't',
    backward_till = 'T',
  },

  -- Delay (in ms) between jump and highlighting all possible jumps. Set to a
  -- very big number (like 10^7) to virtually disable highlighting.
  highlight_delay = 250,
}

-- Module functionality --
--- Jump to target
---
--- Takes a string and jumps to the first occurrence of it after the cursor.
---
--- @param target string: The string to jump to.
--- @param backward boolean: Whether to jump backward. Default: latest used value.
--- @param till boolean: Whether to jump just before/after the match instead of exactly on target. Also ignore matches that don't have anything before/after them. Default: latest used value.
function MiniJump.jump(target, backward, till)
  if H.is_disabled() then
    return
  end

  H.cache.mode = vim.fn.mode(1)
  H.cache.target = target == nil and H.cache.target or target
  -- Don't use `? and <1> or <2>` because it doesn't work when `<1>` is `false`
  if backward ~= nil then
    H.cache.backward = backward
  end
  if till ~= nil then
    H.cache.till = till
  end

  local flags = H.cache.backward and 'Wb' or 'W'
  local pattern, hl_pattern = [[\V%s]], [[\V%s]]
  if H.cache.till then
    if H.cache.backward then
      pattern, hl_pattern = [[\V\(%s\)\@<=\.]], [[\V%s\.\@=]]
      flags = ('%se'):format(flags)
    else
      pattern, hl_pattern = [[\V\.\(%s\)\@=]], [[\V\.\@<=%s]]
    end
  end

  target = vim.fn.escape(H.cache.target, [[\]])
  pattern, hl_pattern = pattern:format(target), hl_pattern:format(target)

  -- Delay highlighting after stopping previous one
  H.timer:stop()
  H.timer:start(
    MiniJump.config.highlight_delay,
    0,
    vim.schedule_wrap(function()
      H.highlight(hl_pattern)
    end)
  )

  -- Make jump
  H.n_cursor_moved = 0
  H.jumping = true
  vim.fn.search(pattern, flags)

  -- Open enough folds to show jump
  vim.cmd([[normal! zv]])
end

--- Smart jump
---
--- If the last movement was a jump, perform another jump with the same target.
--- Otherwise, wait for a target input (via |getchar()|). Respects |v:count|.
---
--- @param backward boolean: Whether to jump backward. Default: latest used value.
--- @param till boolean: Whether to jump just before/after the match instead of exactly on target. Also ignore matches that don't have anything before/after them. Default: latest used value.
function MiniJump.smart_jump(backward, till)
  if H.is_disabled() then
    return
  end

  -- Keep track of *full* mode (tracks operator-pending case)
  local cur_mode = vim.fn.mode(1)
  if H.cache.mode ~= cur_mode then
    MiniJump.stop_jumping()
  end

  if not H.jumping or H.cache.target == nil then
    local char = vim.fn.getchar()
    -- Allow `<Esc>` to early exit
    if char == 27 then
      return
    end

    H.cache.target = vim.fn.nr2char(char)
  end

  for _ = 1, vim.v.count1 do
    MiniJump.jump(H.cache.target, backward, till)
  end
end

--- Stop jumping
---
--- Removes highlights (if any) and forces the next smart jump to prompt for
--- the target. Automatically called on appropriate Neovim |events|.
function MiniJump.stop_jumping()
  H.timer:stop()
  H.jumping = false
  H.unhighlight()
end

--- Act on every |CursorMoved|
function MiniJump.on_cursormoved()
  -- Check `H.jumping` to avoid unneccessary actions on every CursorMoved
  if H.jumping then
    H.n_cursor_moved = H.n_cursor_moved + 1
    -- Stop jumping only if `CursorMoved` was not a result of smart jump
    if H.n_cursor_moved > 1 then
      MiniJump.stop_jumping()
    end
  end
end

-- Helper data --
-- Module default config
H.default_config = MiniJump.config

-- Cache for the latest jump
H.cache = { mode = nil, target = nil, backward = false, till = false }

-- Indicator of whether inside smart jumping
H.jumping = false

-- Counter of number of CursorMoved events
H.n_cursor_moved = 0

-- Highlight delay timer
H.timer = vim.loop.new_timer()

-- Information about last match highlighting (stored *per window*):
-- - Key: windows' unique buffer identifiers.
-- - Value: table with:
--     - `id` field for match id (from `vim.fn.matchadd()`).
--     - `pattern` field for highlighted pattern.
H.window_matches = {}

-- Settings --
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    mappings = { config.mappings, 'table' },
    ['mappings.forward'] = { config.mappings.forward, 'string' },
    ['mappings.backward'] = { config.mappings.backward, 'string' },
    ['mappings.forward_till'] = { config.mappings.forward_till, 'string' },
    ['mappings.backward_till'] = { config.mappings.backward_till, 'string' },

    highlight_delay = { config.highlight_delay, 'number' },
  })

  return config
end

function H.apply_config(config)
  MiniJump.config = config

  local modes = { 'n', 'o', 'x' }
  H.map_cmd(modes, config.mappings.forward, [[lua MiniJump.smart_jump(false, false)]])
  H.map_cmd(modes, config.mappings.backward, [[lua MiniJump.smart_jump(true, false)]])
  H.map_cmd(modes, config.mappings.forward_till, [[lua MiniJump.smart_jump(false, true)]])
  H.map_cmd(modes, config.mappings.backward_till, [[lua MiniJump.smart_jump(true, true)]])
end

function H.is_disabled()
  return vim.g.minijump_disable == true or vim.b.minijump_disable == true
end

-- Highlighting --
function H.highlight(pattern)
  local win_id = vim.api.nvim_get_current_win()
  local match_info = H.window_matches[win_id]

  -- Don't do anything if already highlighting input pattern
  if match_info and match_info.pattern == pattern then
    return
  end

  -- Stop highlighting possible previous pattern. Needed to adjust highlighting
  -- when inside jumping but a different kind one. Example: first jump with
  -- `till = false` and then, without jumping stop, jump to same character with
  -- `till = true`. If this character is first on line, highlighting should change
  H.unhighlight()

  local match_id = vim.fn.matchadd('MiniJump', pattern)
  H.window_matches[win_id] = { id = match_id, pattern = pattern }
end

function H.unhighlight()
  -- Remove highlighting from all windows as jumping is intended to work only
  -- in current window. This will work also from other (usually popup) window.
  for win_id, match_info in pairs(H.window_matches) do
    if vim.api.nvim_win_is_valid(win_id) then
      -- Use `pcall` because there is an error if match id is not present. It
      -- can happen if something else called `clearmatches`.
      pcall(vim.fn.matchdelete, match_info.id, win_id)
      H.window_matches[win_id] = nil
    end
  end
end

-- Various helpers --
function H.map_cmd(modes, key, command)
  if key == '' then
    return
  end
  for _, mode in ipairs(modes) do
    local prefix = mode == 'o' and 'v' or ''
    local rhs = ('%s<cmd>%s<cr>'):format(prefix, command)
    vim.api.nvim_set_keymap(mode, key, rhs, { noremap = true })
  end
end

return MiniJump
