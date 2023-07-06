-- TODO:
--
-- - Code:
--     - Think about "alternative keys": 'langmap' and 'iminsert'.
--
--     - Make it work for the following triggers:
--       { mode = 'n', keys = '<Leader>' },
--       { mode = 'n', keys = '[' },
--       { mode = 'n', keys = ']' },
--       { mode = 'n', keys = [[\]] },
--
--       -- Along 'mini.surround'
--       { mode = 'n', keys = 's' },
--
--       -- For user mappings, built-in mappings, two-char sequence without
--          mappings (like `gb`)
--       { mode = 'n', keys = 'g' },
--
--       -- For user mappings, built-in mappings, two-char sequence without
--          mappings (like `gb`)
--       { mode = 'x', keys = '[' },
--       { mode = 'o', keys = '[' },
--       { mode = 'x', keys = ']' },
--       { mode = 'o', keys = ']' },
--
--       -- Along 'mini.ai'
--       { mode = 'x', keys = 'a' },
--       { mode = 'o', keys = 'a' },
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
--- - Allow hydra-like submodes via `postkeys`.
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
--- * `MiniClueGroup` - group description in clue window.
--- * `MiniClueNextKey` - next key label in clue window.
--- * `MiniClueNoKeymap` - clue window entry without keymap.
--- * `MiniClueNormal` - basic foreground/background highlighting.
--- * `MiniClueSingle` - single key description in clue window.
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
  -- TODO: Make `postkeys` a field of `clues`
  clues = {},
  postkeys = {},
  triggers = {
    { mode = 'n', keys = '<Leader>' },
    { mode = 'n', keys = '[' },
    { mode = 'n', keys = ']' },
    { mode = 'n', keys = [[\]] },

    { mode = 'n', keys = 's' },
    { mode = 'n', keys = 'g' },

    { mode = 'x', keys = '[' },
    { mode = 'o', keys = '[' },
    { mode = 'x', keys = ']' },
    { mode = 'o', keys = ']' },

    { mode = 'x', keys = 'a' },
    { mode = 'o', keys = 'a' },
  },
  window = {
    delay = 100,
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
  trigger = nil,
  mode = 'n',
  keys = {},
  timer = vim.loop.new_timer(),
  count = 0,
  keymaps = {},
  win_id = nil,
}

H.keys = {
  bs = vim.api.nvim_replace_termcodes('<BS>', true, true, true),
  ignore = vim.api.nvim_replace_termcodes('<Ignore>', true, true, true),
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
    postkeys = { config.postkeys, 'table' },
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
    H.map_buf_triggers({ buf = buf_id })
  end
end

H.create_autocommands = function(config)
  local augroup = vim.api.nvim_create_augroup('MiniClue', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  -- Create buffer-local mappings for triggers to fully utilize `<nowait>`
  -- Use `vim.schedule_wrap` to allow other events to create `vim.b.miniclue_config`
  au('BufCreate', '*', vim.schedule_wrap(H.map_buf_triggers), 'Create buffer-local trigger keymaps')

  -- au('VimResized', '*', MiniClue.refresh, 'Refresh on resize')
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniClueBorder',   { link = 'FloatBorder' })
  hi('MiniClueGroup',    { link = 'DiagnosticFloatingWarn' })
  hi('MiniClueNextKey',  { link = 'DiagnosticFloatingHint' })
  hi('MiniClueNoKeymap', { link = 'DiagnosticFloatingError' })
  hi('MiniClueNormal',   { link = 'NormalFloat' })
  hi('MiniClueSingle',   { link = 'DiagnosticFloatingInfo' })
  hi('MiniClueTitle',    { link = 'FloatTitle' })
end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniClue.config, vim.b.miniclue_config or {}, config or {}) end

-- Autocommands ---------------------------------------------------------------
H.map_buf_triggers = function(data)
  for _, trigger in ipairs(H.get_config().triggers) do
    H.map_trigger(data.buf, trigger)
  end
end

H.map_trigger = function(buf_id, trigger)
  local mode, trigger_keys = trigger.mode, trigger.keys

  -- Use buffer-local mappings and `nowait` to make it a primary source of
  -- keymap execution
  local opts = { buffer = buf_id, nowait = true, desc = 'Query clues after ' .. vim.inspect(trigger_keys) }

  vim.keymap.set(mode, trigger_keys, H.make_query(mode, trigger_keys), opts)
end

H.make_query = function(mode, trigger_keys)
  trigger_keys = vim.api.nvim_replace_termcodes(trigger_keys, true, false, true)
  return function()
    H.state_set(mode, trigger_keys, { trigger_keys })
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
  H.state.timer:start(delay, 0, H.window_update)

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
  -- - Execute if reached single target keymap
  if H.state_is_at_target() then return H.state_exec() end

  -- - Reset if there are no keys (like after `<BS>`)
  if #H.state.keys == 0 then return H.state_reset() end

  -- - Query user for more information if there is not enough
  --   NOTE: still advance even if there is single clue because it is still not
  --   a target but can be one.
  if #H.state.keymaps >= 1 then return H.state_advance() end

  -- - Fall back for executing what user typed
  H.state_exec()
end

H.state_set = function(mode, trigger_keys, keys)
  H.state = { mode = mode, trigger_keys = trigger_keys, keys = keys, count = vim.v.count, timer = H.state.timer }
  H.state.keymaps = H.filter_keymaps(H.get_all_keymaps(mode), keys)
end

H.state_reset = function()
  H.state = { mode = 'n', trigger_keys = trigger_keys, keys = {}, count = 0, timer = H.state.timer, keymaps = {} }
  -- H.exit_to_normal_mode()
  H.state.timer:stop()
  H.window_close()
end

H.state_exec = function()
  -- TODO: Add flag to not utilize triggers
  local mode, trigger_keys = H.state.mode, H.state.trigger_keys
  -- local keys_mode = ({ x = 'gv', o = vim.v.operator })[mode] or ''
  local keys_mode = ''
  local keys_count = H.state.count > 0 and H.state.count or ''
  local keys_str = keys_mode .. keys_count .. H.keys_tostring(H.state.keys)

  H.state_reset()

  -- NOTE: expression mapping approach (show clues while user types, and
  -- return them once it is done) can't be used because during expression
  -- mapping evaluation it is prohibited to modify any buffer.

  local buf_id = vim.api.nvim_get_current_buf()
  vim.keymap.del(mode, trigger_keys, { buffer = buf_id })

  -- TODO: Find out which approach is best
  -- vim.api.nvim_feedkeys(H.keys.ignore .. keys_str, 'mt', false)
  vim.api.nvim_feedkeys(keys_str, 'm', false)
  -- vim.cmd('normal ' .. keys_str)
  -- vim.api.nvim_input(keys_str)

  H.map_trigger(buf_id, { mode = mode, keys = trigger_keys })
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
local n = 1
_G.buf_id = vim.api.nvim_create_buf(false, true)

H.window_update = vim.schedule_wrap(function()
  -- Create window if not already created
  if H.state.win_id == nil then H.state.win_id = 1 end

  -- Imitate buffer manipulation
  if not vim.api.nvim_buf_is_valid(_G.buf_id) then _G.buf_id = vim.api.nvim_create_buf(false, true) end
  vim.api.nvim_buf_set_lines(_G.buf_id, 0, -1, false, { 'Hello', 'World', tostring(n) })
  n = n + 1

  -- Update content
  H.echo({ { 'Keys: ' }, { H.keys_tomsg(H.state.keys), 'ModeMsg' }, { ' ' } }, false)
end)

H.window_close = function()
  H.unecho()
  H.state.win_id = nil
end

-- Keymaps --------------------------------------------------------------------
-- TODO: Use `config.clues` to list all available key sequences
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

H.exit_to_normal_mode = function()
  -- Don't use `<C-\><C-n>` in command-line window as they close it
  if vim.fn.getcmdwintype() ~= '' then
    local is_vis, cur_mode = H.is_visual_mode()
    if is_vis then vim.cmd('normal! ' .. cur_mode) end
  else
    -- '\28\14' is an escaped version of `<C-\><C-n>`
    vim.cmd('normal! \28\14')
  end
end

return MiniClue
