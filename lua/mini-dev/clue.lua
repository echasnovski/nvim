-- TODO:
--
-- - Code:
--     - Think about "alternative keys": 'langmap' and 'iminsert'.
--
--     - Update logic of configuring clues, i.e. a clue is:
--         - Table with <mode> and <keys> fields. Possibly <desc>, <postkeys>.
--         - An array of such table.
--         - A callable returning either of previous two.
--
--     - Add `gen_clues` table with callables and preconfigured clues:
--         - `g`.
--         - `z`.
--         - `"` with computable register contents.
--         - `'` / ``` with computable marks positions.
--         - `<C-x>` in Insert mode.
--
--     - Autocreate only in listed and help buffers?
--
--     - Try to make "temporary Normal mode" work even for Operator-pending triggers.
--       If not, at least plan to add documentation.
--
-- - Docs:
--     - Mostly designed for nested `<Leader>` keymaps.
--
--     - Can have unexpected behavior in Operator-pending mode.
--
--     - If using |<Leader>| inside config (either as trigger or inside clues),
--       set it prior running |MiniClue.setup()|.
--
--     - Has problems with macros:
--         - All triggers are disabled during recording of macro due to
--           technical reasons. Would be good if
--         - The `@` key is specially mapped to temporarily disable triggers.
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
--- * `MiniClueNormal` - basic foreground/background highlighting.
--- * `MiniClueSingle` - single key description in clue window.
--- * `MiniClueTitle` - window title.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling~
---
--- To disable creating triggers, set `vim.g.miniclue_disable` (globally) or
--- `vim.b.miniclue_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.

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
  -- TODO: Decide on better name and use `clue` instead of `desc`?
  clues = {
    { mode = 'n', keys = 'g~', desc = 'Switch case' },
    { mode = 'n', keys = 'gU', desc = 'Make uppercase' },
    { mode = 'n', keys = 'gu', desc = 'Make lowercase' },
    { mode = 'n', keys = 'g?', desc = 'Rot13 encode' },

    { mode = 'i', keys = '<C-x><C-l>', desc = 'Complete line' },
    { mode = 'i', keys = '<C-x><C-f>', desc = 'Complete file path' },

    { mode = 'c', keys = '<C-r><C-w>', desc = 'Word under cursor' },
    { mode = 'c', keys = '<C-r>=', desc = 'Expression register' },

    { mode = 'n', keys = '<C-w>h', desc = 'Focus left', postkeys = '<C-w>' },
    { mode = 'n', keys = '<C-w>j', desc = 'Focus down', postkeys = '<C-w>' },
    { mode = 'n', keys = '<C-w>k', desc = 'Focus up', postkeys = '<C-w>' },
    { mode = 'n', keys = '<C-w>l', desc = 'Focus right', postkeys = '<C-w>' },

    { mode = 'x', keys = 'iw', desc = 'Word' },
    { mode = 'x', keys = 'if', desc = 'Function call' },
    { mode = 'o', keys = 'iw', desc = 'Word' },
    { mode = 'o', keys = 'iw', desc = 'Function call' },

    { mode = 'x', keys = 'aw', desc = 'Word' },
    { mode = 'x', keys = 'af', desc = 'Function call' },
    { mode = 'o', keys = 'aw', desc = 'Word' },
    { mode = 'o', keys = 'aw', desc = 'Function call' },
  },

  triggers = {
    { mode = 'n', keys = '<Leader>' },
    { mode = 'n', keys = '[' },
    { mode = 'n', keys = ']' },
    { mode = 'n', keys = [[\]] },

    { mode = 'o', keys = "`" },

    { mode = 'i', keys = '<C-x>' },

    { mode = 'c', keys = '<C-r>' },

    { mode = 't', keys = '<C-w>' },
    { mode = 't', keys = '<Space>' },

    { mode = 'n', keys = 's' },
    { mode = 'x', keys = 's' },

    { mode = 'n', keys = 'g' },
    { mode = 'n', keys = '<C-w>' },

    { mode = 'x', keys = '[' },
    { mode = 'o', keys = '[' },
    { mode = 'x', keys = ']' },
    { mode = 'o', keys = ']' },

    { mode = 'x', keys = 'a' },
    { mode = 'o', keys = 'a' },
    { mode = 'x', keys = 'i' },
    { mode = 'o', keys = 'i' },
  },

  window = {
    delay = 100,
    config = {},
  },
}
--minidoc_afterlines_end

MiniClue.enable_all_triggers = function()
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.map_buf_triggers(buf_id)
  end
end

MiniClue.enable_buf_triggers = function(buf_id)
  if not H.is_valid_buf(buf_id) then H.error('`buf_id` should be a valid buffer identifier.') end
  H.map_buf_triggers(buf_id)
end

MiniClue.disable_all_triggers = function()
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.unmap_buf_triggers(buf_id)
  end
end

MiniClue.disable_buf_triggers = function(buf_id)
  if not H.is_valid_buf(buf_id) then H.error('`buf_id` should be a valid buffer identifier.') end
  H.unmap_buf_triggers(buf_id)
end

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
  -- Array of raw keys
  query = {},
  clues = {},
  timer = vim.loop.new_timer(),
  win_id = nil,
}

-- Precomputed raw keys
H.keys = {
  bs = vim.api.nvim_replace_termcodes('<BS>', true, true, true),
}

-- Undo command which depends on Neovim version
H.undo_autocommand = 'au ModeChanged * ++once undo' .. (vim.fn.has('nvim-0.8') == 1 and '!' or '')

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    clues = { config.clues, 'table' },
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
  MiniClue.enable_all_triggers()

  -- Tweak macro execution
  local macro_keymap_opts = { nowait = true, desc = "Execute macro without 'mini.clue' triggers" }
  local exec_macro = function(keys)
    local register = H.getcharstr()
    if register == nil then return end
    MiniClue.disable_all_triggers()
    vim.schedule(MiniClue.enable_all_triggers)
    pcall(vim.api.nvim_feedkeys, '@' .. register, 'nx', false)
  end
  vim.keymap.set('n', '@', exec_macro, macro_keymap_opts)

  local exec_latest_macro = function(keys)
    MiniClue.disable_all_triggers()
    vim.schedule(MiniClue.enable_all_triggers)
    vim.api.nvim_feedkeys('Q', 'nx', false)
  end
  vim.keymap.set('n', 'Q', exec_latest_macro, macro_keymap_opts)
end

H.is_disabled = function(buf_id)
  local buf_disable = H.get_buf_var(buf_id, 'miniclue_disable')
  return vim.g.miniclue_disable == true or buf_disable == true
end

H.create_autocommands = function(config)
  local augroup = vim.api.nvim_create_augroup('MiniClue', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  -- Create buffer-local mappings for triggers to fully utilize `<nowait>`
  -- Use `vim.schedule_wrap` to allow other events to create
  -- `vim.b.miniclue_config` and `vim.b.miniclue_disable`
  local map_buf = vim.schedule_wrap(function(data) H.map_buf_triggers(data.buf) end)
  au('BufAdd', '*', map_buf, 'Create buffer-local trigger keymaps')

  -- Disable all triggers when recording macro as they interfer with what is
  -- actually recorded
  au('RecordingEnter', '*', MiniClue.disable_all_triggers, 'Disable all triggers')
  au('RecordingLeave', '*', MiniClue.enable_all_triggers, 'Enable all triggers')

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
  hi('MiniClueNormal',   { link = 'NormalFloat' })
  hi('MiniClueSingle',   { link = 'DiagnosticFloatingInfo' })
  hi('MiniClueTitle',    { link = 'FloatTitle' })
end

H.get_config = function(config, buf_id)
  config = config or {}
  local buf_config = H.get_buf_var(buf_id, 'miniclue_config') or {}
  local global_config = MiniClue.config

  -- Manually reconstruct to allow array elements to be concatenated
  local res = {
    clues = H.list_concat(global_config.clues, buf_config.clues, config.clues),
    triggers = H.list_concat(global_config.triggers, buf_config.triggers, config.triggers),
    window = vim.tbl_deep_extend('force', global_config.window, buf_config.window or {}, config.window or {}),
  }
  return res
end

H.get_buf_var = function(buf_id, name)
  if not H.is_valid_buf(buf_id) then return nil end
  return vim.b[buf_id or 0][name]
end

-- Triggers -------------------------------------------------------------------
H.map_buf_triggers = function(buf_id)
  if not H.is_valid_buf(buf_id) then return end

  if H.is_disabled(buf_id) then return end

  for _, trigger in ipairs(H.get_config(nil, buf_id).triggers) do
    H.map_trigger(buf_id, trigger)
  end
end

H.unmap_buf_triggers = function(buf_id)
  if not H.is_valid_buf(buf_id) then return end

  for _, trigger in ipairs(H.get_config(nil, buf_id).triggers) do
    H.unmap_trigger(buf_id, trigger)
  end
end

H.map_trigger = function(buf_id, trigger)
  if not H.is_valid_buf(buf_id) then return end

  -- Compute mapping RHS
  trigger.keys = H.replace_termcodes(trigger.keys)

  local rhs = function()
    -- Don't act if for some reason entered the same trigger during state exec
    local is_in_exec = type(H.exec_trigger) == 'table'
      and H.exec_trigger.mode == trigger.mode
      and H.exec_trigger.keys == trigger.keys
    if is_in_exec then
      H.exec_trigger = nil
      return
    end

    -- Start user query
    H.state_set(trigger, { trigger.keys })
    H.state_advance()
  end

  -- Use buffer-local mappings and `nowait` to make it a primary source of
  -- keymap execution
  local desc = string.format('Query clues after "%s"', H.keytrans(trigger.keys))
  local opts = { buffer = buf_id, nowait = true, desc = desc }

  -- Create mapping
  vim.keymap.set(trigger.mode, trigger.keys, rhs, opts)
end

H.unmap_trigger = function(buf_id, trigger)
  if not H.is_valid_buf(buf_id) then return end

  trigger.keys = H.replace_termcodes(trigger.keys)

  -- Delete mapping
  pcall(vim.keymap.del, trigger.mode, trigger.keys, { buffer = buf_id })
end

-- State ----------------------------------------------------------------------
H.state_advance = function()
  -- Do not advance if no other clues to query. NOTE: it is `<= 1` and not
  -- `<= 0` because the "init query" mapping should match.
  if vim.tbl_count(H.state.clues) <= 1 then return H.state_exec() end

  -- Show clues: delay (debounce) first show; update immediately if shown
  H.state.timer:stop()
  local delay = H.state.win_id == nil and H.get_config().window.delay or 0
  H.state.timer:start(delay, 0, H.window_update)

  -- Query user for new key
  local state_before = {
    trigger = vim.deepcopy(H.state.trigger),
    query = vim.deepcopy(H.state.query),
    clues = vim.deepcopy(H.state.clues),
  }
  local key = H.getcharstr()

  -- Handle key
  if key == nil then return H.state_reset() end
  if key == '\r' then return H.state_exec() end

  if key == H.keys.bs then
    H.state_pop()
  else
    H.state_push(key)
  end

  local state_after = {
    trigger = vim.deepcopy(H.state.trigger),
    query = vim.deepcopy(H.state.query),
    clues = vim.deepcopy(H.state.clues),
  }

  -- Advance state
  -- - Execute if reached single target keymap
  if H.state_is_at_target() then return H.state_exec() end

  -- - Reset if there are no keys (like after `<BS>`)
  if #H.state.query == 0 then return H.state_reset() end

  -- - Query user for more information if there is not enough
  --   NOTE: still advance even if there is single clue because it is still not
  --   a target but can be one.
  if vim.tbl_count(H.state.clues) >= 1 then return H.state_advance() end

  -- - Fall back for executing what user typed
  H.state_exec()
end

H.state_set = function(trigger, query)
  H.state = { trigger = trigger, query = query, timer = H.state.timer, win_id = H.state.win_id }
  H.state.clues = H.clues_filter(H.get_clues(trigger.mode), query)
end

H.state_reset = function(keep_window)
  H.state = { trigger = nil, query = {}, timer = H.state.timer, clues = {} }
  H.state.timer:stop()
  if not keep_window then H.window_close() end
end

-- TODO: remove when not needed
_G.log = {}
H.state_exec = function()
  -- Compute keys to type
  local keys_to_type = H.compute_exec_keys()
  table.insert(_G.log, keys_to_type)

  -- Add extra (redundant) safety flag to try to avoid inifinite recursion
  local trigger, clue = H.state.trigger, H.state_get_query_clue()
  H.exec_trigger = trigger
  vim.schedule(function() H.exec_trigger = nil end)

  -- Reset state
  local has_postkeys = (clue or {}).postkeys ~= nil
  H.state_reset(has_postkeys)

  -- Disable trigger !!!VERY IMPORTANT!!!
  -- This is a work around infinite recursion (like if `g` is trigger then
  -- typing `gg`/`g~` would introduce infinite recursion).
  local buf_id = vim.api.nvim_get_current_buf()
  H.unmap_trigger(buf_id, trigger)

  -- Execute keys. The `i` flag is used to fully support Operator-pending mode.
  vim.api.nvim_feedkeys(keys_to_type, 'mit', false)

  -- Enable trigger back after it can no longer harm
  vim.schedule(function() H.map_trigger(buf_id, trigger) end)

  -- Schedule postkeys. Using `state_set()` and `state_advance()` directly does
  -- not work because it doesn't guarantee to be executed **after** keys from
  -- `nvim_feedkeys()`.
  if has_postkeys then vim.schedule(function() vim.api.nvim_feedkeys(clue.postkeys, 'mit', false) end) end
end

H.state_push = function(keys)
  table.insert(H.state.query, keys)
  H.state.clues = H.clues_filter(H.state.clues, H.state.query)
end

H.state_pop = function()
  H.state.query[#H.state.query] = nil
  H.state.clues = H.clues_filter(H.get_clues(H.state.trigger.mode), H.state.query)
end

H.state_is_at_target = function() return vim.tbl_count(H.state.clues) == 1 end

H.state_get_query_clue = function()
  local keys = H.query_to_keys(H.state.query)
  return H.state.clues[keys]
end

H.compute_exec_keys = function()
  local keys_count = vim.v.count > 0 and vim.v.count or ''
  local keys_query = H.query_to_keys(H.state.query)
  local res = keys_count .. keys_query

  local cur_mode = vim.fn.mode(1)

  -- Using `feedkeys()` inside Operator-pending mode leads to its cancel into
  -- Normal/Insert mode so extra work should be done to rebuild all keys
  if cur_mode:find('^no') ~= nil then
    local operator_tweak = H.operator_tweaks[vim.v.operator] or function(x) return x end
    res = operator_tweak(vim.v.operator .. H.get_forced_submode() .. res)
  end

  -- `feedkeys()` inside "temporary" Normal mode is executed **after** it is
  -- already back from Normal mode. Go into it again with `<C-o>` ('\15').
  -- NOTE: This only works when Normal mode trigger is triggered in
  -- "temporary" Normal mode. Still doesn't work when Operator-pending mode is
  -- triggered afterwards (like in `<C-o>gUiw` with 'i' as trigger).
  if cur_mode:find('^ni') ~= nil then res = '\15' .. res end

  return res
end

-- Some operators needs special tweaking due to their nature:
-- - Some operators perform on register. Solution: add register explicitly.
-- - Some operators end up changing mode which affects `feedkeys()`.
--   Solution: explicitly exit to Normal mode with '\28\14' ('<C-\><C-n>').
-- - Some operators still perform some redundant operation before `feedkeys()`
--   takes effect. Solution: add one-shot autocommand undoing that.
H.operator_tweaks = {
  ['c'] = function(keys)
    -- Doing '\28\14' moves cursor one space to left (same as `i<Esc>`).
    -- Solution: add one-shot autocommand correcting cursor position.
    vim.cmd('au InsertLeave * ++once normal! l')
    return '\28\14"' .. vim.v.register .. keys
  end,
  ['d'] = function(keys) return '"' .. vim.v.register .. keys end,
  ['y'] = function(keys) return '"' .. vim.v.register .. keys end,
  ['~'] = function(keys)
    if vim.fn.col('.') == 1 then vim.cmd(H.undo_autocommand) end
    return keys
  end,
  ['g~'] = function(keys)
    if vim.fn.col('.') == 1 then vim.cmd(H.undo_autocommand) end
    return keys
  end,
  ['g?'] = function(keys)
    if vim.fn.col('.') == 1 then vim.cmd(H.undo_autocommand) end
    return keys
  end,
  ['!'] = function(keys) return '\28\14' .. keys end,
  ['>'] = function(keys)
    vim.cmd(H.undo_autocommand)
    return keys
  end,
  ['<'] = function(keys)
    vim.cmd(H.undo_autocommand)
    return keys
  end,
  ['g@'] = function(keys)
    -- Cancelling in-process `g@` operator seems to be particularly hard.
    -- Not even sure why specifically this combination works, but having `x`
    -- flag in `feedkeys()` is crucial.
    vim.api.nvim_feedkeys('\28\14', 'nx', false)
    return '\28\14' .. keys
  end,
}

-- Window ---------------------------------------------------------------------
local n = 1
_G.window_buf_id = vim.api.nvim_create_buf(false, true)

H.window_update = vim.schedule_wrap(function()
  -- Create window if not already created
  if H.state.win_id == nil then H.state.win_id = 1 end

  -- Imitate buffer manipulation
  if not vim.api.nvim_buf_is_valid(_G.window_buf_id) then _G.window_buf_id = vim.api.nvim_create_buf(false, true) end
  vim.api.nvim_buf_set_lines(_G.window_buf_id, 0, -1, false, { 'Hello', 'World', tostring(n) })
  n = n + 1

  -- Update content
  H.echo({ { 'Keys: ' }, { H.query_to_msg(H.state.query), 'ModeMsg' }, { ' ' } }, false)
end)

H.window_close = function()
  H.unecho()
  H.state.win_id = nil
end

-- Clues ----------------------------------------------------------------------
H.get_clues = function(mode)
  local res = {}

  -- Order of clue precedence: global mappings < buffer mappings < config clues
  for _, map_data in ipairs(vim.api.nvim_get_keymap(mode)) do
    local lhsraw = H.replace_termcodes(map_data.lhs)
    res[lhsraw] = { desc = map_data.desc }
  end

  for _, map_data in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
    local lhsraw = H.replace_termcodes(map_data.lhs)
    res[lhsraw] = { desc = map_data.desc }
  end

  local mode_clues = vim.tbl_filter(function(x) return x.mode == mode end, H.get_config().clues)
  for _, clue in ipairs(mode_clues) do
    local lhsraw = H.replace_termcodes(clue.keys)
    local res_clue = res[lhsraw] or {}
    -- Allos clue without `desc` to possibly fall back to keymap's description
    res_clue.desc = clue.desc or res_clue.desc
    res_clue.postkeys = H.replace_termcodes(clue.postkeys)
    res[lhsraw] = res_clue
  end

  return res
end

H.clues_filter = function(clues, query)
  local keys = H.query_to_keys(query)
  for clue_keys, _ in pairs(clues) do
    if not vim.startswith(clue_keys, keys) then clues[clue_keys] = nil end
  end
  return clues
end

H.query_to_keys = function(query) return table.concat(query, '') end

H.query_to_msg = function(query) return H.keytrans(H.query_to_keys(query)) end

-- Predicates -----------------------------------------------------------------
H.is_trigger = function(x) return type(x) == 'table' and type(x.mode) == 'string' and type(x.keys) == 'string' end

H.is_array_of = function(x, predicate)
  if not vim.tbl_islist(x) then return false end
  for _, v in ipairs(x) do
    if not predicate(v) then return false end
  end
  return true
end

-- Utilities ------------------------------------------------------------------
H.echo = function(msg, is_important)
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

H.replace_termcodes = function(x)
  if x == nil then return nil end
  return vim.api.nvim_replace_termcodes(x, true, false, true)
end

H.get_forced_submode = function()
  local mode = vim.fn.mode(1)
  if not mode:sub(1, 2) == 'no' then return '' end
  return mode:sub(3)
end

-- TODO: Remove after compatibility with Neovim=0.7 is dropped
H.keytrans = vim.fn.has('nvim-0.8') == 1 and vim.fn.keytrans or function(x) return x end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.getcharstr = function()
  local ok, char = pcall(vim.fn.getcharstr)

  -- Terminate if couldn't get input (like with <C-c>) or it is `<Esc>`
  if not ok or char == '\27' then return end

  return char
end

H.list_concat = function(...)
  local res = {}
  for i = 1, select('#', ...) do
    for _, x in ipairs(select(i, ...) or {}) do
      table.insert(res, x)
    end
  end
  return res
end

return MiniClue
