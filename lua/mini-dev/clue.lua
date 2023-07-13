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
--       -- Insert mode
--       { mode = 'i', keys = '<C-x>' },
--
--       -- For user mappings, built-in mappings, two-char sequence without
--          mappings (like `gb`)
--       { mode = 'n', keys = 'g' },
--
--       -- Built-in completion
--       { mode = 'i', keys = '<C-x>' },
--
--       -- Along 'mini.surround'
--       { mode = 'n', keys = 's' },
--       { mode = 'x', keys = 's' },
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
--       { mode = 'x', keys = 'i' },
--       { mode = 'o', keys = 'i' },
--
--     - Test cases:
--       - `<Space>ff`
--       - `[b`/`]b`
--       - `[i`/`]i` in Normal, Visual, Operator-pending mode (with dot-repeat)
--       - `\h`
--       - `<C-x>` in Insert mode.
--       - 'mini.surround': `saiw)` and `viwsa)`, `sd}`, `sdn}`, `sdl}`
--       - All operators in `:h operator`; editing once should preserve
--         dot-repeat.
--       - `[count]` support
--       - Register support for operator-pending mode.
--       - `gg`, `g~`, `go` from 'mini.basics' with dot-repeat
--       - `g~iw` ("chaining" triggers)
--
--     - Think about allowing nested clues for easier use of possible built-in
--       sets of clues (like for `g`, `z`, `<C-x>` (Insert mode), etc).
--
--     - ?Allow clues to be executable to allow dynamic descriptions? Like for
--       registers and marks.
--
--     - Respect `*_disable` when creating buffer mappings?
--
--     - Fix `cina` issue.
--
-- - Docs:
--     - Mostly designed for nested `<Leader>` keymaps.
--
--     - Can have unexpected behavior in Operator-pending mode.
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
--     - Should query until and execute single "longest" keymap. Like if there
--       are both `]e` and `]eee`, then, `]eee` should be reachable.
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

MiniClue.execute_without_triggers = function(f, triggers)
  if not vim.is_callable(f) then H.error('`f` should be callable.') end
  if H.is_trigger(triggers) then triggers = { triggers } end
  if not H.is_array_of(triggers, H.is_trigger) then H.error('`triggers` should be trigger or array of triggers.') end

  H.disable_triggers(triggers)
  return f()
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

-- Triggers -------------------------------------------------------------------
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

    -- Do not advance if no other clues to query. NOTE: it is `<= 1` and not
    -- `<= 0` because the "init query" mapping should match.
    if vim.tbl_count(H.state.clues) <= 1 then return H.state_exec() end

    H.state_advance()
  end

  -- Use buffer-local mappings and `nowait` to make it a primary source of
  -- keymap execution
  local desc = string.format('Query clues after "%s"', H.keytrans(trigger.keys))
  local opts = { buffer = buf_id, nowait = true, desc = desc }

  -- Create mapping
  vim.keymap.set(trigger.mode, trigger.keys, rhs, opts)
end

H.disable_triggers = function(triggers)
  if not H.is_array_of(triggers, H.is_trigger) then return end

  -- Compute which supplied triggers are actually registered triggers
  local triggers_per_mode = {}
  local config_triggers = H.get_config().triggers
  for _, trigger in ipairs(config_triggers) do
    local mode_triggers = triggers_per_mode[trigger.mode] or {}
    mode_triggers[trigger.keys] = true
    triggers_per_mode[trigger.mode] = mode_triggers
  end

  -- Temporarily disable trigger only if it is actually config
  local buf_id = vim.api.nvim_get_current_buf()
  for _, trigger in ipairs(triggers) do
    local is_config_trigger = (triggers_per_mode[trigger.mode] or {})[trigger.keys]
    if is_config_trigger then
      vim.keymap.del(trigger.mode, trigger.keys, { buffer = buf_id })
      vim.schedule(function() H.map_trigger(buf_id, trigger) end)
    end
  end
end

-- State ----------------------------------------------------------------------
H.state_advance = function()
  -- Show clues: delay (debounce) first show; update immediately if shown
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

H.state_reset = function()
  H.state = { trigger = nil, query = {}, timer = H.state.timer, clues = {} }
  H.state.timer:stop()
  H.window_close()
end

-- TODO: remove when not needed
_G.log = {}
H.state_exec = function()
  -- Compute keys to type
  local keys_to_type = H.compute_exec_keys()
  table.insert(_G.log, keys_to_type)

  -- NOTE: VERY IMPORTANT!
  -- Temporarily disable trigger keymap to work around infinite recursion (like
  -- if `g` is trigger then typing `gg`/`g~` would introduce infinite
  -- recursion). Trigger is remapped after keys are executed.
  H.disable_relevant_triggers(H.state.trigger)

  -- Add extra (redundant) safety flag to try to avoid inifinite recursion
  H.exec_trigger = H.state.trigger
  vim.schedule(function() H.exec_trigger = nil end)

  -- Reset state
  H.state_reset()

  -- Execute keys. Using `i` flag is needed to make "chaining triggers" like
  -- `g~iw` work.
  vim.api.nvim_feedkeys(keys_to_type, 'mit', false)
end

H.state_push = function(keys)
  table.insert(H.state.query, keys)
  H.state.clues = H.clues_filter(H.state.clues, H.state.query)
end

H.state_pop = function()
  H.state.query[#H.state.query] = nil
  H.state.clues = H.clues_filter(H.get_clues(H.state.trigger.mode), H.state.query)
end

H.state_is_at_target =
  function() return vim.tbl_count(H.state.clues) == 1 and H.state.clues[H.query_to_keys(H.state.query)] ~= nil end

H.compute_exec_keys = function()
  local keys_count = vim.v.count > 0 and vim.v.count or ''
  local keys_query = H.query_to_keys(H.state.query)
  local res = keys_count .. keys_query

  -- Currently only Operator-pending mode needs special keys to reproduce
  -- actually used operator (because using `feedkeys()` inside Operator-pending
  -- mode leads to its cancel into Normal/Insert mode)
  if H.state.trigger.mode == 'o' then
    local operator_tweak = H.operator_tweaks[vim.v.operator] or function(x) return x end
    res = operator_tweak(vim.v.operator .. H.get_forced_submode() .. res)
  end

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

H.disable_relevant_triggers = function(trigger)
  local relevant_triggers = { trigger }
  if trigger.mode == 'o' then
    local operator = vim.v.operator

    -- In operator-pending mode operator or its separate characters also can be
    -- triggerable (like `g~`/`gc` if `g` is trigger in Normal mode)
    table.insert(relevant_triggers, { mode = 'n', keys = operator })

    if operator:len() > 1 then
      table.insert(relevant_triggers, { mode = 'n', keys = operator:sub(1, 1) })
      table.insert(relevant_triggers, { mode = 'n', keys = operator:sub(2, 2) })
    end

    -- Quote can also be triggerable which matters for operators using register
    if operator == 'c' or operator == 'd' or operator == 'y' then
      table.insert(relevant_triggers, { mode = 'n', keys = '"' })
    end
  end

  H.disable_triggers(relevant_triggers)
end

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
    if clue.mode == mode then
      local lhsraw = H.replace_termcodes(clue.keys)
      res[lhsraw] = { desc = clue.desc, postkeys = clue.postkeys }
    end
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

H.replace_termcodes = function(x) return vim.api.nvim_replace_termcodes(x, true, false, true) end

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

return MiniClue
