-- TODO:
--
-- - Code:
--     - Think about "alternative keys": 'langmap' and 'iminsert'.
--
-- - Docs:
--     - Mostly designed for nested `<Leader>` keymaps.
--
--     - If trigger concists from several keys (like `<Leader>f`), it will be
--       treated as single key. Matters for `<BS>`.
--
--     - Will override already present trigger mapping. Example:
--         - 'mini.comment' and `gc`: there are `gcc` and general `gc` (would
--           need `gc<CR>` followed by textobject).
--
--     - Isn't really designed to be used in cases where there are meaningful
--       mappings with one being prefix of another, as it will need extra
--       `<CR>` to execute shorter mapping
--       Examples:
--         - 'mini.surround' and `s`: there are 'next'/'previous' variants.
--           Or disable both 'next'/'previous' mappings.
--
-- - Test:
--     - Should query until and execute single "logn" keymap. Like if there are
--       both `]e` and `]eee`, then, `]eee` should be reachable.
--     - Should leverage `nowait` even if there was new mapping created after
--       triggers mapped. Example: trigger - `]`, new mapping - `]e` (both
--       global and buffer-local).
--     - Should respect `[count]`.
--     - Should work with multibyte characters.
--     - Should respect `vim.b.miniclue_config` being set in `FileType` event.
--

--- *mini.clue* Show mapping clues
--- *MiniClue*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Enable for some subset of keymaps independence from 'timeoutlen'. That
---   is, mapping input is active until:
---     - Valid mapping is complete: executed it.
---     - Latest key makes current key stack not match any mapping: do nothing.
---     - User presses `<CR>`: execute current key stack.
---     - User presses `<Esc>`/`<C-c>`: cancel mapping.
--- - Show window with clues about next available keys.
--- - Allow hydra-like submodes.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.clue').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniClue`
--- which you can use for scripting or manually (with `:lua MiniClue.*`).
---
--- See |MiniClue.config| for available config settings.
---
--- You can override runtime config settings (like mappings or window options)
--- locally to buffer inside `vim.b.miniclue_config` which should have same
--- structure as `MiniClue.config`. See |mini.nvim-buffer-local-config| for
--- more details.
---
--- # Comparisons ~
---
--- - 'folke/which-key.nvim':
--- - 'anuvyklack/hydra.nvim':
---
--- # Highlight groups ~
---
--- * `MiniClueBorder` - window border.
--- * `MiniClueNormal` - basic foreground/background highlighting.
--- * `MiniClueTitle` - window title.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- Once enabled, this module can't be disabled.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
MiniClue = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniClue.config|.
---
---@usage `require('mini.clue').setup({})` (replace `{}` with your `config` table).
MiniClue.setup = function(config)
  -- Export module
  _G.MiniClue = MiniClue

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)

  -- Create default highlighting
  H.create_default_hl()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniClue.config = {
  clues = {},
  submodes = {},
  triggers = {
    { mode = 'n', keys = '<Leader>' },
    { mode = 'n', keys = '[' },
    { mode = 'n', keys = ']' },
    { mode = 'n', keys = [[\]] },
  },
  window = {
    delay = 1000,
    config = {},
  },
}
--minidoc_afterlines_end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniClue.config

-- Namespaces
H.ns_id = {
  highlight = vim.api.nvim_create_namespace('MiniClue'),
}

-- State of user input
H.state = {
  mode = 'n',
  keys = {},
  timer = vim.loop.new_timer(),
  count = 0,
  keymaps = {},
  win_id = nil,
}

H.keys = {
  bs = vim.api.nvim_replace_termcodes('<BS>', true, true, true),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    clues = { config.clues, 'table' },
    submodes = { config.submodes, 'table' },
    triggers = { config.triggers, 'table' },
    window = { config.window, 'table' },
  })

  vim.validate({
    ['window.delay'] = { config.window.delay, 'number' },
    ['window.config'] = { config.window.config, 'table' },
  })

  return config
end

H.apply_config = function(config)
  MiniClue.config = config

  -- Create trigger keymaps for all existing buffers
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.map_triggers({ buf = buf_id })
  end
end

H.create_autocommands = function(config)
  local augroup = vim.api.nvim_create_augroup('MiniClue', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  -- Create buffer-local mappings for triggers to fully utilize `<nowait>`
  -- Use `vim.schedule_wrap` to allow other events to create `vim.b.miniclue_config`
  au('BufCreate', '*', vim.schedule_wrap(H.map_triggers), 'Create buffer-local trigger keymaps')

  -- au('VimResized', '*', MiniClue.refresh, 'Refresh on resize')
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniClueBorder', { link = 'FloatBorder' })
  hi('MiniClueNormal', { link = 'NormalFloat' })
  hi('MiniClueTitle',  { link = 'FloatTitle'  })
end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniClue.config, vim.b.miniclue_config or {}, config or {}) end

-- Autocommands ---------------------------------------------------------------
H.map_triggers = function(data)
  for _, trigger in ipairs(H.get_config().triggers) do
    local mode, keys = trigger.mode, trigger.keys

    -- Use buffer-local mappings and `nowait` to make it a primary source of
    -- keymap execution
    local opts = { buffer = data.buf, nowait = true, desc = 'Query clues after ' .. vim.inspect(keys) }

    vim.keymap.set(mode, keys, H.make_query(mode, keys), opts)
  end
end

H.make_query = function(mode, string_keys)
  return function()
    H.state_set(mode, { vim.api.nvim_replace_termcodes(string_keys, true, false, true) })
    -- Do not advance if no other mappings to query
    if #H.state.keymaps <= 1 then return H.state_reset() end
    H.state_advance()
  end
end

-- State ----------------------------------------------------------------------
H.state_advance = function()
  -- Handle showing clues: delay first show; update immediately if shown
  H.state.timer:stop()
  local delay = H.state.win_id == nil and H.get_config().window.delay or 0
  H.state.timer:start(delay, 0, H.window_open)

  -- Query user for new key
  local key = H.getcharstr()

  -- Handle key
  if key == nil then return H.state_reset() end
  if key == '\r' then return H.state_exec() end

  if key == H.keys.bs then
    H.state_pop()
  else
    H.state_push(key)
  end

  -- Advance state
  -- - Execute if reached single target
  if H.state_is_at_target() then return H.state_exec() end

  -- - Reset if there are no keys (like after `<BS>`)
  if #H.state.keys == 0 then return H.state_reset() end

  -- - Query user for more information if there is not enough
  if #H.state.keymaps >= 1 then return H.state_advance() end

  -- - Fall back for reset
  H.state_reset()
end

H.state_set = function(mode, keys)
  H.state = { mode = mode, keys = keys, timer = H.state.timer }
  H.state.count = vim.v.count
  H.state.keymaps = H.filter_keymaps(H.get_all_keymaps(mode), keys)
end

H.state_reset = function()
  H.state = { mode = 'n', keys = {}, count = 0, keymaps = {}, timer = H.state.timer }
  H.state.timer:stop()
  H.window_close()
end

H.state_exec = function()
  local keys_str = (H.state.count > 0 and H.state.count or '') .. H.keys_tostring(H.state.keys)
  H.state_reset()
  vim.api.nvim_feedkeys(keys_str, 'mt', false)
end

H.state_push = function(key)
  table.insert(H.state.keys, key)
  H.state.keymaps = H.filter_keymaps(H.state.keymaps, H.state.keys)
end

H.state_pop = function()
  H.state.keys[#H.state.keys] = nil
  H.state.keymaps = H.filter_keymaps(H.get_all_keymaps(H.state.mode), H.state.keys)
end

H.state_is_at_target =
  function() return #H.state.keymaps == 1 and H.keys_tostring(H.state.keys) == H.state.keymaps[1].lhsraw end

-- Window ---------------------------------------------------------------------
H.window_open = vim.schedule_wrap(function()
  -- Create window if not already created
  if H.state.win_id == nil then H.state.win_id = 1 end

  -- Update content
  H.echo({ { 'Keys: ' }, { H.keys_tomsg(H.state.keys), 'ModeMsg' }, { ' ' } }, false)
end)

H.window_close = function()
  H.unecho()
  H.state.win_id = nil
end

-- Keymaps --------------------------------------------------------------------
H.get_all_keymaps = function(mode)
  local res = {}

  -- Get both non-buffer and buffer keymaps (favoring latter)
  for _, map_data in ipairs(vim.api.nvim_get_keymap(mode)) do
    res[map_data.lhsraw] = map_data
  end
  for _, map_data in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
    res[map_data.lhsraw] = map_data
  end

  return vim.tbl_values(res)
end

H.filter_keymaps = function(keymaps, keys)
  local keys_str = H.keys_tostring(keys)
  local res = {}
  for _, map_data in ipairs(keymaps) do
    if vim.startswith(map_data.lhsraw, keys_str) then table.insert(res, map_data) end
  end
  return res
end

H.escape_leader = function(keys_string)
  local leader = vim.g.mapleader or [[\]]
  local res = keys_string:gsub('<[Ll]eader>', leader)
  return res
end

H.keys_tostring = function(keys) return table.concat(keys, '') end

H.keys_tomsg = function(keys) return vim.fn.keytrans(H.keys_tostring(keys)) end

-- Utilities ------------------------------------------------------------------
H.echo = function(msg, is_important)
  if H.get_config().silent then return end

  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.clue) ', 'WarningMsg' })

  -- Avoid hit-enter-prompt
  local max_width = vim.o.columns * math.max(vim.o.cmdheight - 1, 0) + vim.v.echospace
  local chunks, tot_width = {}, 0
  for _, ch in ipairs(msg) do
    local new_ch = { vim.fn.strcharpart(ch[1], 0, max_width - tot_width), ch[2] }
    table.insert(chunks, new_ch)
    tot_width = tot_width + vim.fn.strdisplaywidth(new_ch[1])
    if tot_width >= max_width then break end
  end

  -- Echo. Force redraw to ensure that it is effective (`:h echo-redraw`)
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(chunks, is_important, {})
end

H.unecho = function() vim.cmd([[echo '' | redraw]]) end

H.message = function(msg) H.echo(msg, true) end
H.error = function(msg) error(string.format('(mini.clue) %s', msg), 0) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.getcharstr = function()
  local ok, char = pcall(vim.fn.getcharstr)

  -- Terminate if couldn't get input (like with <C-c>) or it is `<Esc>`
  if not ok or char == '\27' then return end
  return char
end

return MiniClue
