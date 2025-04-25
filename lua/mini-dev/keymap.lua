-- TODO:
--
-- Code:
-- - map_as_combo():
--
-- - map_multi_*():
--     - Follow local todos.
--
-- - map_with_dotrepeat().
--
-- - yank_mapping():
--     - Implement while allowing changing description.
--       See |MiniClue.set_mapping_desc()|
--
-- Docs:
--
-- Tests:
-- - map_as_combo():
--     - Should work when fast typing 'j'-'j'-'k'.
--     - Should work with `xnoremap j gj` style of mappings. On Neovim>=0.11
--       for a regular `jk` left hand side. On Neovim<0.11 for a `gjgk`.
--     - Should recognise `'<<Tab>>'` as three keys (`<`, `\t`, `>`).
--     - With `jjk` and `jk` combos, both should act after typing `jjk`.
--     - Should work inside macros.
--
-- - Multi-step mappings:
--     - Should work with `nil` / `{}` steps and just execute the key.

--- *mini.keymap* Extra key mappings
--- *MiniKeymap*
---
--- MIT License Copyright (c) 2025 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Map special Insert mode keys to perform configurable multi-step actions:
---     - <Tab> and <S-Tab> - navigate completion items, manage snippet session,
---       jump before/after brackets, and more.
---       See |MiniKeymap.map_multi_tab()| and |MiniKeymap.map_multi_shifttab()|.
---     - <CR> - accept or hide completion menu, respect "auto-pairs", and more.
---       See |MiniKeymap.map_multi_cr()|.
---     - <BS> - perform smart indent handling, respect "auto-pairs", and more.
---       See |MiniKeymap.map_multi_bs()|.
---
--- - Map keys as "combo": each key gets executed immediately plus execute extra
---   action if all are typed within configurable delay between each other. For
---   example, this is useful to map insert-able keys in Insert and Command-line
---   mode. Like mapping "jk" to exit into Normal mode.
---   See |MiniKeymap.map_as_combo()|.
---
--- - Map with dot-repeat. See |MiniKeymap.map_with_dotrepeat()|.
---
--- - Copy existing mapping to another key. See |MiniKeymap.yank_mapping()|.
---
--- Sources with more details:
--- - |MiniKeymap-examples|
---
--- # Setup ~
---
--- This module doesn't need setup, but it can be done to improve usability.
--- Setup with `require('mini.keymap').setup({})` (replace `{}` with your `config`
--- table). It will create global Lua table `MiniKeymap` which you can use for
--- scripting or manually (with `:lua MiniKeymap.*`).
---
--- See |MiniKeymap.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.minikeymap_config`
--- will have no effect here.
---
--- # Comparisons ~
---
--- - 'max397574/better-escape.nvim':
---     - Mostly similar to |MiniKeymap.map_as_combo()| with a slightly
---       different approach to creating mappings.
---
--- - 'abecodes/tabout.nvim':
---     - Similar general idea as in 'move_{after,before}_brackets' steps
---       of |MiniKeymap.map_multi_tab()| and |MiniKeymap.map_multi_shifttab()|.
---     - Works only with enabled tree-sitter parser while providing smarter
---       movements. This module doesn't require enabled tree-sitter (as it uses
---       Lua pattern matching) while performing less smart jumps.
---
--- # Disabling ~
---
--- To disable some functionality, set `vim.g.minikeymap_disable` (globally) or
--- `vim.b.minikeymap_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user.
--- See |mini.nvim-disabling-recipes| for common recipes.

--- # Combos ~
---
--- All combos require their left hand side keys to be typed relatively quickly.
--- To adjust the delay between keys, add `{ delay = 500 }` (use custom value) as
--- fourth argument. See |MiniKeymap.map_as_combo()|.
---
--- ## "Better escape" to Normal mode ~
---
--- Leave into |Normal-mode| without having to reach for <Esc> key: >lua
---
---   -- Support most common modes. This can also contain 't', but would
---   -- work only
---   local mode = { 'i', 'c', 'x', 's' }
---   require('mini.keymap').map_as_combo(mode, 'jk', '<BS><BS><Esc>')
---
---   -- To not have to worry about the order of keys, also map "kj"
---   require('mini.keymap').map_as_combo(mode, 'kj', '<BS><BS><Esc>')
---
---   -- Escape into Normal mode from Terminal mode
---   require('mini.keymap').map_as_combo('t', 'jk', '<BS><BS><C-\\><C-n>')
---   require('mini.keymap').map_as_combo('t', 'kj', '<BS><BS><C-\\><C-n>')
--- <
--- ## Fix previous spelling mistake ~
---
--- Fix previous spelling mistake (see |[s| and |z=|) without manually leaving
--- Insert mode: >lua
---
---   local action = '<BS><BS><Esc>[s1z=gi<Right>'
---   require('mini.keymap').map_as_combo('i', 'kk', action)
--- <
--- ## Hide search highlighting ~
---
--- Use double <Esc><Esc> to execute |:nohlsearch|. Although this can also be
--- done with `nmap <Esc> <Cmd>nohl<CR>`, the combo approach also exists and can
--- be used to free <Esc> mapping in Normal mode for something else. >lua
---
---   local action = function() vim.cmd('nohlsearch') end
---   require('mini.keymap').map_as_combo({ 'n', 'i', 'x', 'c' }, '<Esc><Esc>', action)
--- <
--- # Special keys ~
---
--- >lua
---   local keymap = require('mini.keymap')
---   keymap.map_multi_tab({})
---   keymap.map_multi_shifttab({})
---   keymap.map_multi_cr({})
---   keymap.map_multi_bs({})
--- <

---@tag MiniKeymap-examples

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
-- TODO: Make local
MiniKeymap = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniKeymap.config|.
---
---@usage >lua
---   require('mini.keymap').setup({}) -- replace {} with your config table
---                                    -- needs `keymap` field present
--- <
MiniKeymap.setup = function(config)
  -- TODO: Remove after Neovim=0.8 support is dropped
  if vim.fn.has('nvim-0.9') == 0 then
    vim.notify(
      '(mini.keymap) Neovim<0.9 is soft deprecated (module works but not supported).'
        .. ' It will be deprecated after next "mini.nvim" release (module might not work).'
        .. ' Please update your Neovim version.'
    )
  end

  -- Export module
  _G.MiniKeymap = MiniKeymap

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniKeymap.config = {}
--minidoc_afterlines_end

--- Map as combo
---
--- TODO: Describe what a "combo" is and why it may be useful.
--- See |MiniKeymap-examples|.
---
--- Notes:
--- - Different combos are tracked and act independent of each other. For example,
---   if there are combos for `jjk` and `jk` keys, fast typing `jjk` will
---   execute both actions.
---
--- - Neovim>=0.11 is recommended due |vim.on_key()| improvement to allow
---   watching for keys as they are typed and not as if coming from mappings.
---   For example, this matters when creating a `jk` combo for Visual mode while
---   also having `xnoremap j gj` style of remaps. On Neovim<0.11 the fix is to
---   use `{'g', 'j', 'g', 'k'}` as combo's left hand side, which is bothersome.
---
--- - Adds very small but non-zero overhead on each keystroke for every combo
---   mapping. Usually about 1-3 microseconds (i.e. 0.001-0.003 ms), which
---   should be fast enough for most setups. For a "normal, real world" coding
---   session with a total of ~20000 keystrokes it resulted in extra ~40ms of
---   overhead for a single cretaed combo. Create many such mappings with caution.
MiniKeymap.map_as_combo = function(mode, lhs, action, opts)
  if type(mode) == 'string' then mode = { mode } end
  if not H.is_array_of(mode, H.is_string) then H.error('`mode` should be string or array of strings') end
  local mode_tbl = H.combo_make_mode_tbl(mode)

  -- TODO: Rename `seq` to `lhs` to allow both string and array of keys (as in
  -- 'mini.clue'). Normalize `lhs` to be `seq`.
  local seq = H.combo_lhs_to_seq(lhs)
  seq = vim.tbl_map(function(x) return vim.api.nvim_replace_termcodes(x, true, true, true) end, seq)

  -- Cache local values for better speed
  opts = opts or {}
  local delay = opts.delay or 200
  if not (type(delay) == 'number' and delay > 0) then H.error('`opts.delay` should be a positive number') end

  local hrtime, get_key = vim.loop.hrtime, H.combo_get_key
  local i, last_time, n_seq, ignore = 0, hrtime(), #seq, false
  local delay_ns = 1000000 * delay

  -- Explicitly ignore keys from action. Otherwise they will be processed
  -- because `nvim_input` mocks "as if typed" approach.
  local input_keys = function(keys)
    ignore = true
    vim.api.nvim_input(keys)
    ignore = false
  end

  if type(action) == 'string' then
    local keys = action
    action = function() input_keys(keys) end
  end
  if not vim.is_callable(action) then H.error('`action` should be either string of keys or callable') end
  local act = vim.schedule_wrap(action)

  local watcher = function(key, typed)
    -- Use only keys "as if typed" and in proper mode
    key = get_key(key, typed)
    if key == '' or (i == 0 and not mode_tbl[H.cur_mode]) or ignore then return end

    -- Advance tracking and reset if not in sequence
    i = i + 1
    if seq[i] ~= key then
      -- Allow latest key to start new combo (like during typing 'jjk')
      i = seq[1] == key and 1 or 0
      last_time = i == 0 and last_time or hrtime()
      return
    end

    -- Reset if time between key presses is too big
    local cur_time = hrtime()
    if (cur_time - last_time) > delay_ns and i > 1 then
      i = 0
      return
    end
    last_time = cur_time

    -- Wait for more info if sequence is not exhausted, act otherwise
    if i < n_seq then return end
    i = 0
    -- - Allow action to return keys to manually mimic
    local keys = act()
    if type(keys) == 'string' and keys ~= '' then input_keys(keys) end
  end

  local new_combo_id = #H.ns_id_combo
  local ns_id = vim.api.nvim_create_namespace('MiniKeymap-combo_' .. new_combo_id)
  table.insert(H.ns_id_combo, ns_id)

  H.ensure_mode_tracking()
  return vim.on_key(watcher, ns_id)
end

--- Multistep <Tab>
---
--- Notes:
--- - Steps should take care of replacing termcodes. Use |vim.keycode()|.
MiniKeymap.map_multi_tab = function(steps, opts)
  -- TODO: Built-in steps:
  -- - 'cmp_next'
  -- - 'blink_next'
  -- - 'minisnippet_next'
  -- - 'vimsnippet_next'
  -- - 'luasnip_next'
  -- - 'minisnippet_expand'
  -- - 'luasnip_expand'
  -- - 'jump_after_brackets' (like 'tabout.nvim'; search right for the first
  --   unbalanced closing bracket `)]}>` and possibly move past all consecutive
  --   ones)
  -- - 'smart_indent_set' (if in line's indent which is different from indent
  --   of previous non-blank line, make them the same)

  steps = H.normalize_steps(steps, H.steps_tab)
  H.map_multistep({ 'i', 's' }, '<Tab>', steps, opts)
end

--- Multistep <S-Tab>
MiniKeymap.map_multi_shifttab = function(steps, opts)
  -- TODO: Built-in steps:
  -- - 'cmp_prev'
  -- - 'blink_prev'
  -- - 'minisnippet_prev'
  -- - 'vimsnippet_prev'
  -- - 'luasnip_prev'
  -- - 'minisnippet_expand'
  -- - 'luasnip_expand'
  -- - 'jump_before_brackets' (like 'tabout.nvim'; search left for the first
  --   unbalanced closing bracket `)]}>` and possibly move past all consecutive
  --   ones)

  steps = H.normalize_steps(steps, H.steps_shifttab)
  H.map_multistep({ 'i', 's' }, '<S-Tab>', steps, opts)
end

--- Multistep <CR>
MiniKeymap.map_multi_cr = function(steps, opts)
  -- TODO: Built-in steps:
  -- - 'cmp_accept_selected'
  -- - 'cmp_hide_and_cr'
  -- - 'blink_accept_selected'
  -- - 'blink_hide_and_cr'
  -- - 'nvimautopairs_cr' (`require('nvim-autopairs').autopairs_cr()`)

  steps = H.normalize_steps(steps, H.steps_cr)
  H.map_multistep('i', '<CR>', steps, opts)
end

--- Multistep <BS>
MiniKeymap.map_multi_bs = function(steps, opts)
  -- TODO: Built-in steps:
  -- - 'smart_indent' (see #373 and
  --   https://marketplace.visualstudio.com/items?itemName=jasonlhy.hungry-delete)
  -- - 'nvimautopairs_bs' (`require('nvim-autopairs').autopairs_bs()`)

  steps = H.normalize_steps(steps, H.steps_bs)
  H.map_multistep('i', '<BS>', steps, opts)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniKeymap.config)

-- Namespaces for `on_key`
H.ns_id_combo = {}

-- Current mode used in "combo" mappings, for better speed
H.cur_mode = 'n'

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})
  return config
end

H.apply_config = function(config) MiniKeymap.config = config end

H.is_disabled = function() return vim.g.minikeymap_disable == true or vim.b.minikeymap_disable == true end

-- Combo ----------------------------------------------------------------------
H.ensure_mode_tracking = function()
  local gr = vim.api.nvim_create_augroup('MiniKeymapCombo', {})

  local track_mode = function()
    H.cur_mode = vim.fn.mode()
    H.cur_mode = (H.cur_mode == 'V' or H.cur_mode == '\22') and 'v' or H.cur_mode
  end
  vim.api.nvim_create_autocmd('ModeChanged', { group = gr, callback = track_mode, desc = 'Track mode' })
end

H.combo_lhs_to_seq = function(lhs)
  if H.is_array_of(lhs, H.is_string) then return vim.deepcopy(lhs) end
  if type(lhs) ~= 'string' then H.error('`lhs` should be string or array of strings') end

  local res, i = {}, 1
  while i <= lhs:len() do
    local k, new_i = string.match(lhs, '^(%b<>)()', i)
    if k == nil or k:find('^.+<') ~= nil then
      k, new_i = vim.fn.strcharpart(lhs, i - 1, 1), i + 1
    end
    table.insert(res, k)
    i = new_i
  end
  return res
end

H.combo_make_mode_tbl = function(mode)
  local res = {}
  for _, m in ipairs(mode) do
    if m == 'x' then
      res.v, res.V, res['\22'] = true, true, true
    elseif m == 'v' then
      res.s, res.v, res.V, res['\22'] = true, true, true, true
    else
      res[m] = true
    end
  end
  return res
end

H.combo_get_key = function(_, typed) return typed end
if vim.fn.has('nvim-0.11') == 0 then H.combo_get_key = function(key) return key end end

-- Multi-step -----------------------------------------------------------------
H.normalize_steps = function(steps, builtin_steps)
  if not H.islist(steps) then H.error('`steps` should be array') end
  local res = {}
  for i, step in ipairs(steps) do
    local s = type(step) == 'string' and builtin_steps[step] or step
    local is_step = type(s) == 'table' and vim.is_callable(s.condition) and vim.is_callable(s.action)
    if not is_step then H.error('`steps` should contain valid steps, not ' .. vim.inspect(s)) end
    table.insert(res, s)
  end

  return res
end

H.map_multistep = function(mode, lhs, steps, opts)
  local lhs_raw, n_steps = vim.api.nvim_replace_termcodes(lhs, true, true, true), #steps

  local rhs = function()
    if H.is_disabled() then return lhs_raw end
    for i = 1, n_steps do
      if steps[i].condition() then return steps[i].action() end
    end
    return lhs_raw
  end

  opts = vim.tbl_extend('force', { desc = 'Multi ' .. lhs }, opts or {}, { expr = true, replace_keycodes = false })
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.is_pumvisible = function() return vim.fn.pumvisible() == 1 end

H.is_pumselected = function() return vim.fn.complete_info({ 'selected' }).selected ~= -1 end

H.has_minipairs = function() return _G.MiniPairs ~= nil end

H.steps_tab = {
  pmenu_next = { condition = H.is_pumvisible, action = function() return '\14' end },
}

H.steps_shifttab = {
  pmenu_prev = { condition = H.is_pumvisible, action = function() return '\16' end },
}

H.steps_cr = {
  pmenu_accept_or_cr = {
    condition = H.is_pumvisible,
    action = function() return H.is_pumselected() and '\25' or '\25\r' end,
  },
  minipairs_cr = { condition = H.has_minipairs, action = function() return _G.MiniPairs.cr() end },
}

H.steps_bs = {
  minipairs_bs = { condition = H.has_minipairs, action = function() return _G.MiniPairs.bs() end },
}

-- Validators -----------------------------------------------------------------
H.is_string = function(x) return type(x) == 'string' end

H.is_array_of = function(x, predicate)
  if not H.islist(x) then return false end
  for i = 1, #x do
    if not predicate(x[i]) then return false end
  end
  return true
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.keymap) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level_name, silent)
  if not silent then vim.notify('(mini.keymap) ' .. msg, vim.log.levels[level_name]) end
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniKeymap
