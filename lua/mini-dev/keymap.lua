-- TODO:
--
-- Code:
-- - map_combo():
--
-- - map_multistep():
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
-- - map_combo():
--
-- - Multi-step mappings:

--- *mini.keymap* Extra key mappings
--- *MiniKeymap*
---
--- MIT License Copyright (c) 2025 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Map keys to perform configurable multi-step actions: if condition for step
---   one is true - execute step one action, else check step two, etc. until
---   falling back to executing original keys. See |MiniKeymap.map_multistep()|.
---   This is usually referred to as "smart" keys (like "smart tab").
---
---   There are many built-in steps targeted for Insert mode mappings of special
---   keys like <Tab>, <S-Tab>, <CR>, and <BS>:
---   - Navigate and accept |popupmenu-completion|. Useful for |mini.completion|.
---   - Navigate and expand |mini.snippets|.
---   - Execute <CR> and <BS> respecting |mini.pairs|.
---   - Jump before/after current tree-sitter node.
---   - Jump before opening and after closing characters (brackets and quotes).
---   - Increase/descrease indent when inside it.
---   - Delete all whitespace to the left ("hungry backspace").
---   - Navigate |vim.snippet|.
---   - Navigate and accept in 'hrsh7th/nvim-cmp' completion.
---   - Navigate and accept in 'Saghen/blink.cmp' completion.
---   - Navigate and exapnd 'L3MON4D3/LuaSnip' snippets.
---   - Execute <CR> and <BS> respecting 'windwp/nvim-autopairs'.
---
--- - Map keys as "combo": each key gets executed immediately plus execute extra
---   action if all are typed within configurable delay between each other.
---   See |MiniKeymap.map_combo()|. Examples of usage:
---     - Map insert-able keys (like "jk", "kj") in Insert and Command-line exit
---       into Normal mode.
---     - Fight against bad habbits of pressing the same navigation key by showing
---       a notification if there are too many of them pressed in a row.
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
---     - Mostly similar to |MiniKeymap.map_combo()| with a slightly
---       different approach to creating mappings.
---
--- - 'abecodes/tabout.nvim':
---     - Similar general idea as in 'jump_{after,before}_tsnode' steps
---       of |MiniKeymap.map_multistep()|.
---     - Works only with enabled tree-sitter parser. This module provides
---       fallback via 'jump_after_close' and 'jump_before_open' that work
---       without tree-sitter parser.
---     - 'tabout.nvim' has finer control over how moving outside of
---       tree-sitter node is done, while this module only implements "jump
---       outside of current node" behavior.
---
--- # Disabling ~
---
--- To disable some functionality, set `vim.g.minikeymap_disable` (globally) or
--- `vim.b.minikeymap_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user.
--- See |mini.nvim-disabling-recipes| for common recipes.

--- # Multi-step ~
---
--- See |MiniKeymap.map_multistep()| for a general description of how multi-step
--- mappings work and what built-in steps are available.
---
--- Setup that works well with |mini.completion| and |mini.pairs|: >lua
---
---   local map_multistep = require('mini.keymap').map_multistep
---   map_multistep('i', '<Tab>',   { 'pmenu_next' })
---   map_multistep('i', '<S-Tab>', { 'pmenu_prev' })
---   map_multistep('i', '<CR>',    { 'pmenu_accept', 'minipairs_cr' })
---   map_multistep('i', '<BS>',    { 'minipairs_bs' })
--- <
--- Use <Tab> / <S-Tab> to also navigate and expand |mini.snippets|: >lua
---
---   local map_multistep = require('mini.keymap').map_multistep
---
---   local tab_steps = {'minisnippets_next','minisnippets_expand','pmenu_next'}
---   map_multistep('i', '<Tab>',   tab_steps)
---
---   local shifttab_steps = { 'minisnippets_prev', 'pmenu_prev' }
---   map_multistep('i', '<S-Tab>', shifttab_steps)
--- <
--- An extra smart <Tab> and <S-Tab>: >lua
---
---   local map_multistep = require('mini.keymap').map_multistep
---
---   local tab_steps = {
---     'minisnippets_next', 'minisnippets_expand',
---     'pmenu_next',
---     'jump_after_tsnode', 'jump_after_close',
---   }
---   map_multistep('i', '<Tab>',   tab_steps)
---
---   local shifttab_steps = {
---     'minisnippets_prev',
---     'pmenu_next',
---     'jump_before_tsnode', 'jump_before_open',
---   }
---   map_multistep('i', '<S-Tab>', shifttab_steps)
--- <
--- Navigation in active |vim.snippet| session requires mapping in |Select-mode|: >lua
---
---   local map_multistep = require('mini.keymap').map_multistep
---   map_multistep({ 'i', 's' }, '<Tab>',   { 'vimsnippet_next', 'pmenu_next' })
---   map_multistep({ 'i', 's' }, '<S-Tab>', { 'vimsnippet_prev', 'pmenu_prev' })
--- <
--- # Combos ~
---
--- All combos require their left hand side keys to be typed relatively quickly.
--- To adjust the delay between keys, add `{ delay = 500 }` (use custom value) as
--- fourth argument. See |MiniKeymap.map_combo()|.
---
--- ## "Better escape" to Normal mode ~
---
--- Leave into |Normal-mode| without having to reach for <Esc> key: >lua
---
---   -- Support most common modes. This can also contain 't', but would
---   -- work only
---   local mode = { 'i', 'c', 'x', 's' }
---   require('mini.keymap').map_combo(mode, 'jk', '<BS><BS><Esc>')
---
---   -- To not have to worry about the order of keys, also map "kj"
---   require('mini.keymap').map_combo(mode, 'kj', '<BS><BS><Esc>')
---
---   -- Escape into Normal mode from Terminal mode
---   require('mini.keymap').map_combo('t', 'jk', '<BS><BS><C-\\><C-n>')
---   require('mini.keymap').map_combo('t', 'kj', '<BS><BS><C-\\><C-n>')
--- <
--- ## Show bad navigation habits ~
---
--- Show notification if there is too much movement by repeating same key: >lua
---
---   local notify_many_keys = function(key)
---     local lhs = string.rep(key, 5)
---     local action = function() vim.notify('Too many ' .. key) end
---     require('mini.keymap').map_combo({ 'n', 'x' }, lhs, action)
---   end
---   notify_many_keys('h')
---   notify_many_keys('j')
---   notify_many_keys('k')
---   notify_many_keys('l')
--- <
--- ## Fix previous spelling mistake ~
---
--- Fix previous spelling mistake (see |[s| and |z=|) without manually leaving
--- Insert mode: >lua
---
---   local action = '<BS><BS><Esc>[s1z=gi<Right>'
---   require('mini.keymap').map_combo('i', 'kk', action)
--- <
--- ## Hide search highlighting ~
---
--- Use double <Esc><Esc> to execute |:nohlsearch|. Although this can also be
--- done with `nmap <Esc> <Cmd>nohl<CR>`, the combo approach also exists and can
--- be used to free <Esc> mapping in Normal mode for something else. >lua
---
---   local action = function() vim.cmd('nohlsearch') end
---   require('mini.keymap').map_combo({ 'n', 'i', 'x', 'c' }, '<Esc><Esc>', action)
--- <
---@tag MiniKeymap-examples

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniKeymap = {}
local H = {}

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

--- Map multi-step action
---
--- Notes:
--- - Steps should generally prefer to not take care of replacing termcodes,
---   i.e. return `<Tab>` instead of `\t`. To undo already done replacement,
---   use |keytrans()|.
---
--- - This has limitations of |map-expression| (like not allowed text or buffer
---   changes, etc.). To execute a lua code, either use |vim.schedule()| or
---   return the code as string wrapped in |<Cmd>|. For example:
---   -- TODO
---
--- - Might require disabling smart presets in plugins (like
---   'nvim-cmp', 'blink-cmp', 'nvim-autopairs').
---
--- - Can be buffer-local mappings for a finer control per filetype, etc.
---
--- Available built-in steps:
--- - 'minipairs_cr' - if |mini.pairs| is set up, execute |MiniPairs.cr()|.
---   Recommended to be used last, as it has too permissive condition.
--- - 'minipairs_bs' - if |mini.pairs| is set up, execute |MiniPairs.bs()|.
---   Recommended to be used last, as it has too permissive condition.
--- -'vimsnippet_next' - if |vim.snippet.active()|, |vim.snippet.jump()| right.
---   For better coverage should also be mapped in |Select-mode| (`'s'`).
--- -'vimsnippet_prev' - if |vim.snippet.active()|, |vim.snippet.jump()| left.
---   For better coverage should also be mapped in |Select-mode| (`'s'`).
---
MiniKeymap.map_multistep = function(mode, lhs, steps, opts)
  H.check_type('lhs', lhs, 'string')
  local lhs_raw, n_steps = vim.api.nvim_replace_termcodes(lhs, true, true, true), #steps
  local lhs_keycode = vim.fn.keytrans(lhs_raw)
  steps = H.normalize_steps(steps)

  local rhs = function()
    if H.is_disabled() then return lhs_raw end
    for i = 1, n_steps do
      if steps[i].condition() then
        local out = steps[i].action()
        -- Allow custom string as output of expression mapping
        if type(out) == 'string' then return out end
        -- Allow callable output to be properly wrapped in `<Cmd>...<CR>`
        if vim.is_callable(out) then return H.wrap_in_cmd_lua(out) end
        -- Allow `false` output to indicate "keep processing next steps"
        if out ~= false then return '' end
      end
    end
    return lhs_keycode
  end

  local desc = 'Multi ' .. lhs_keycode
  opts = vim.tbl_extend('force', { desc = desc }, opts or {}, { expr = true, replace_keycodes = true })
  vim.keymap.set(mode, lhs, rhs, opts)
end

--- TODO
MiniKeymap.gen_step = {}

--- Search pattern step
---
--- Example of steps that jump before/after all consecutive brackets: >lua
---
---   local tab_step = keymap.gen_step.search_pattern(
---     [[[)\]}]\+]], 'ceW', { side = 'after' }
---   )
---   keymap.map_multistep('i', '<Tab>', { tab_step })
---
---   local stab_step = keymap.gen_step.search_pattern([[[(\[{]\+]], 'bW')
---   keymap.map_multistep({ 'i' }, '<S-Tab>', { stab_step })
---<
---
---@return table Step which searches pattern only in Insert mode.
MiniKeymap.gen_step.search_pattern = function(pattern, flags, opts)
  if type(pattern) ~= 'string' then H.error('`pattern` should be string, not ' .. vim.inspect(type(pattern))) end
  if type(flags) ~= 'string' then H.error('`flags` should be string, not ' .. vim.inspect(type(flags))) end
  opts = vim.tbl_extend('force', { side = 'before' }, opts or {})
  local side = opts.side
  if not (side == 'before' or side == 'after') then H.error('`opts.side` should be one of "before" or "after"') end

  -- NOTEs:
  -- - Using `normal!` doesn't go past the end of line and triggers
  --   mode-change-related events.
  -- - Adjusting pattern with `\zs` prefix doesn't work for consecutive matches
  --   (like `)))`), as it will match every other one (first, third, etc.).
  -- - Using `\@<=` quantifier doesn't work for the last match in consecutive
  --   matches at end of line. Like `)))` at end of line won't put cursor at
  --   end of line. The `[)\]}]\@<=\_.` also doesn't seem to work.
  local adjust_cursor = function()
    local pos = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] + 1 })
  end
  if side == 'before' then adjust_cursor = function() end end

  local act = function()
    vim.fn.search(pattern, flags)
    adjust_cursor()
  end

  return { condition = function() return vim.fn.mode() == 'i' end, action = function() return act end }
end

--- Map combo post action
---
--- TODO: Describe what a "combo" is and why it may be useful.
--- Mention that this is not a "real" mapping, but a tracking |vim.on_key()|.
--- See |MiniKeymap-examples|.
---
--- Notes:
--- - RHS keys are executed with |nvim_input()|, i.e. they will respect custom
---   mappings.
---
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
MiniKeymap.map_combo = function(mode, lhs, action, opts)
  if type(mode) == 'string' then mode = { mode } end
  if not H.is_array_of(mode, H.is_string) then H.error('`mode` should be string or array of strings') end
  local mode_tbl = H.combo_make_mode_tbl(mode)

  local seq = H.combo_lhs_to_seq(lhs)
  seq = vim.tbl_map(function(x) return vim.api.nvim_replace_termcodes(x, true, true, true) end, seq)

  if not (type(action) == 'string' or vim.is_callable(action)) then
    H.error('`action` should be either string of keys or callable')
  end

  -- Cache local values for better speed
  opts = opts or {}
  local delay = opts.delay or 200
  if not (type(delay) == 'number' and delay > 0) then H.error('`opts.delay` should be a positive number') end

  local hrtime, get_key = vim.loop.hrtime, H.combo_get_key
  local i, last_time, n_seq = 0, hrtime(), #seq
  local delay_ns = 1000000 * delay

  local ignore = false
  local unignore = vim.schedule_wrap(function() ignore = false end)

  -- Explicitly ignore keys from action. Otherwise they will be processed
  -- because `nvim_input` mocks "as if typed" approach.
  local input_keys = vim.schedule_wrap(function(keys)
    ignore = true
    vim.api.nvim_input(keys)
    -- NOTE: Can't unignore right away because `nvim_input` is executed later
    unignore()
  end)

  local act
  if type(action) == 'string' then
    local keys = action
    act = function() input_keys(keys) end
  else
    act = vim.schedule_wrap(function()
      -- Allow action to return keys to manually mimic
      local keys = action()
      if type(keys) == 'string' and keys ~= '' then input_keys(keys) end
    end)
  end

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
    act()
  end

  local new_combo_id = #H.ns_id_combo
  local ns_id = vim.api.nvim_create_namespace('MiniKeymap-combo_' .. new_combo_id)
  table.insert(H.ns_id_combo, ns_id)

  H.ensure_mode_tracking()
  return vim.on_key(watcher, ns_id)
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
  local track_mode = function() H.cur_mode = vim.fn.mode() end
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
H.normalize_steps = function(steps)
  if not H.islist(steps) then H.error('`steps` should be array') end
  local res = {}
  for i, step in ipairs(steps) do
    local s = type(step) == 'string' and H.steps_builtin[step] or step
    local is_step = type(s) == 'table' and vim.is_callable(s.condition) and vim.is_callable(s.action)
    if not is_step then H.error('`steps` should contain valid steps, not ' .. vim.inspect(step)) end
    table.insert(res, s)
  end

  return res
end

H.wrap_in_cmd_lua = function(f)
  local needs_global_cleanup = _G.MiniKeymap == nil
  _G.MiniKeymap = _G.MiniKeymap or {}
  _G.MiniKeymap._f = f
  local extra_cleanup = needs_global_cleanup and '; MiniKeymap = nil' or ''
  return '<Cmd>lua MiniKeymap._f(); MiniKeymap._f = nil' .. extra_cleanup .. '<CR>'
end

H.make_cmd_lua_action = function(cmd_string)
  return function() return '<Cmd>lua ' .. cmd_string .. '<CR>' end
end

H.has_module = function(name) return (pcall(require, name)) end

--stylua: ignore start
H.steps_builtin = {}

H.is_visible_pmenu  = function() return vim.fn.pumvisible() == 1 end
H.is_selected_pmenu = function() return vim.fn.complete_info({ 'selected' }).selected ~= -1 end

H.steps_builtin.pmenu_next   = { condition = H.is_visible_pmenu,  action = function() return '<C-n>' end }
H.steps_builtin.pmenu_prev   = { condition = H.is_visible_pmenu,  action = function() return '<C-p>' end }
H.steps_builtin.pmenu_accept = { condition = H.is_selected_pmenu, action = function() return '<C-y>' end }

H.is_minisnippets_session  = function() return _G.MiniSnippets ~= nil and _G.MiniSnippets.session.get() ~= nil end
H.is_minisnippets_matched  = function() return _G.MiniSnippets ~= nil and #_G.MiniSnippets.expand({ insert = false }) > 0 end
H.make_minisnippets_action = function(dir) return H.make_cmd_lua_action('MiniSnippets.session.jump("' .. dir .. '")') end

H.steps_builtin.minisnippets_next   = { condition = H.is_minisnippets_session, action = H.make_minisnippets_action('next') }
H.steps_builtin.minisnippets_prev   = { condition = H.is_minisnippets_session, action = H.make_minisnippets_action('prev') }
H.steps_builtin.minisnippets_expand = { condition = H.is_minisnippets_matched, action = H.make_cmd_lua_action('MiniSnippets.expand()') }

H.has_minipairs = function() return _G.MiniPairs ~= nil end

H.steps_builtin.minipairs_cr = { condition = H.has_minipairs, action = function() return vim.fn.keytrans(_G.MiniPairs.cr()) end }
H.steps_builtin.minipairs_bs = { condition = H.has_minipairs, action = function() return vim.fn.keytrans(_G.MiniPairs.bs()) end }

H.can_jump_tsnode = function()
  -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
  local has_parser, parser = pcall(vim.treesitter.get_parser, 0, nil, { error = false })
  return vim.fn.mode() == 'i' and has_parser and parser ~= nil
end

H.make_jump_tsnode = function(side)
  local act = function()
    local node, pos, new_pos = H.get_tsnode(), vim.api.nvim_win_get_cursor(0), nil
    while node ~= nil do
      -- Output of `get_node_range` is 0-indexed with "from" data inclusive and
      -- "to" data exclusive. This is exactly what is needed here:
      -- - For "before" direction exact left end is needed. This will be used
      --   in Insert mode and cursor weill be between target and its left cell.
      -- - For "after" direction the one cell to right (after normalization) is
      --   needed because cursor in Insert mode will be just after the node.
      local from_row, from_col, to_row, to_col = vim.treesitter.get_node_range(node)
      local row = side == 'before' and from_row or to_row
      local col = side == 'before' and from_col or to_col
      new_pos = H.normalize_pos(row, col)
      -- Iterate up the tree until different position is found. This is mostly
      -- useful for "before" direction.
      if not (new_pos[1] == pos[1] and new_pos[2] == pos[2]) then break end
      node = node:parent()
    end
    pcall(vim.api.nvim_win_set_cursor, 0, new_pos)
  end

  -- Return callable which is wrapped to be executed after expression mapping
  return function() return act end
end

H.steps_builtin.jump_after_tsnode  = { condition = H.can_jump_tsnode, action = H.make_jump_tsnode('after') }
H.steps_builtin.jump_before_tsnode = { condition = H.can_jump_tsnode, action = H.make_jump_tsnode('before') }

H.steps_builtin.jump_after_close = MiniKeymap.gen_step.search_pattern([=[[)\]}"'`]]=], 'cW', { side = 'after' })
H.steps_builtin.jump_before_open = MiniKeymap.gen_step.search_pattern([=[[(\[{"'`]]=], 'bW', { side = 'before' })

H.is_in_indent = function()
  local line, col = vim.api.nvim_get_current_line(), vim.fn.col('.')
  local offset = vim.fn.mode() == 'i' and 1 or 0
  return line:sub(1, col - offset):find('^%s*$') ~= nil
end

H.increase_indent_keys = { i = '<C-t>', v = '>', V = '>', ['\22'] = '>' }
H.decrease_indent_keys = { i = '<C-d>', v = '<', V = '<', ['\22'] = '<' }

H.steps_builtin.increase_indent = { condition = H.is_in_indent, action = function() return H.increase_indent_keys[vim.fn.mode()] or '>>' end }
H.steps_builtin.decrease_indent = { condition = H.is_in_indent, action = function() return H.decrease_indent_keys[vim.fn.mode()] or '<<' end }

H.hungry_bs_condition = function()
  local line, col = vim.api.nvim_get_current_line(), vim.fn.col('.')
  local offset = vim.fn.mode() == 'i' and 1 or 0
  return line:sub(1, col - offset):find('%s+$') ~= nil
end

H.hungry_bs_action = function()
  return function()
    local line, lnum, col = vim.api.nvim_get_current_line(), vim.fn.line('.'), vim.fn.col('.')
    local offset = vim.fn.mode() == 'i' and 1 or 0
    local from_col = line:sub(1, col - offset):match('()%s+$')
    vim.api.nvim_buf_set_text(0, lnum - 1, from_col - 1, lnum - 1, col - offset, {})
    vim.api.nvim_win_set_cursor(0, { lnum, from_col - 1 })
  end
end

H.steps_builtin.hungry_bs = { condition = H.hungry_bs_condition, action = H.hungry_bs_action }

H.make_vimsnippet_condition = function(dir) return function() return vim.snippet.active({ direction = dir }) end end
H.make_vimsnippet_action    = function(dir) return H.make_cmd_lua_action('vim.snippet.jump(' .. dir .. ')') end

H.steps_builtin.vimsnippet_next = { condition = H.make_vimsnippet_condition(1),  action = H.make_vimsnippet_action(1) }
H.steps_builtin.vimsnippet_prev = { condition = H.make_vimsnippet_condition(-1), action = H.make_vimsnippet_action(-1) }

H.is_visible_cmp  = function() return H.has_module('cmp') and require('cmp').visible() end
H.is_selected_cmp = function() return H.has_module('cmp') and require('cmp').get_selected_entry() ~= nil end
H.make_cmp_action = function(action) return H.make_cmd_lua_action('require("cmp").' .. action .. '()') end

H.steps_builtin.cmp_next   = { condition = H.is_visible_cmp,  action = H.make_cmp_action('select_next_item') }
H.steps_builtin.cmp_prev   = { condition = H.is_visible_cmp,  action = H.make_cmp_action('select_prev_item') }
H.steps_builtin.cmp_accept = { condition = H.is_selected_cmp, action = H.make_cmp_action('confirm') }

H.is_visible_blink  = function() return H.has_module('blink.cmp') and require('blink.cmp').is_menu_visible() end
H.is_selected_blink = function() return H.has_module('blink.cmp') and require('blink.cmp').get_selected_item() ~= nil end
H.make_blink_action = function(action) return H.make_cmd_lua_action('require("blink.cmp").' .. action .. '()') end

H.steps_builtin.blink_next   = { condition = H.is_visible_blink,  action = H.make_blink_action('select_next') }
H.steps_builtin.blink_prev   = { condition = H.is_visible_blink,  action = H.make_blink_action('select_prev') }
H.steps_builtin.blink_accept = { condition = H.is_selected_blink, action = H.make_blink_action('accept') }

H.make_luasnip_condition = function(dir) return function() return H.has_module('luasnip') and require('luasnip').jumpable(dir) end end
H.is_luasnip_expandable  = function() return H.has_module('luasnip') and require('luasnip').expandable() end
H.make_luasnip_action    = function(dir) return H.make_cmd_lua_action('require("luasnip").jump(' .. dir .. ')') end

H.steps_builtin.luasnip_next   = { condition = H.make_luasnip_condition(1),  action = H.make_luasnip_action(1) }
H.steps_builtin.luasnip_prev   = { condition = H.make_luasnip_condition(-1), action = H.make_luasnip_action(-1) }
H.steps_builtin.luasnip_expand = { condition = H.is_luasnip_expandable,      action = H.make_cmd_lua_action('require("luasnip").expand()') }

H.has_nvimautopairs         = function() return H.has_module('nvim-autopairs') end
H.make_nvimautopairs_action = function(method) return function() return vim.fn.keytrans(require('nvim-autopairs')[method]()) end end

H.steps_builtin.nvimautopairs_cr = { condition = H.has_nvimautopairs, action = H.make_nvimautopairs_action('autopairs_cr') }
H.steps_builtin.nvimautopairs_bs = { condition = H.has_nvimautopairs, action = H.make_nvimautopairs_action('autopairs_bs') }
--stylua: ignore end

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

H.normalize_pos = function(row, col)
  -- Input is {0,0} indexed, output is {1,0} indexed
  if row < 0 or (row == 0 and col < 0) then return { 1, 0 } end
  local last_row = vim.api.nvim_buf_line_count(0) - 1
  local n_col_last_row = H.get_row_cols(last_row)
  -- Assume this is used in Insert node, so placing just after EOL can be done
  if row > last_row or (row == last_row and col > n_col_last_row) then return { last_row + 1, n_col_last_row } end

  if col < 0 then return { row, H.get_row_cols(row - 1) } end
  if col > H.get_row_cols(row) then return { row + 2, 0 } end
  return { row + 1, col }
end

H.get_row_cols = function(row) return vim.fn.getline(row + 1):len() end

H.get_tsnode = function() return vim.treesitter.get_node() end
if vim.fn.has('nvim-0.9') == 0 then H.get_tsnode = function() return vim.treesitter.get_node_at_cursor() end end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniKeymap
