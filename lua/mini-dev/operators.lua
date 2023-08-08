-- TODO:
--
-- Code:
-- - All should respect 'selection=exclusive'.
-- - All should respect forced submode ('v', 'V', '<C-v>')
-- - All should not modify marks.
--
-- - Use output of `getreginfo()` as input for user modifiers (like in `sort`,
--   `evaluate`, etc.).
--
-- - Replace:
--
-- - Exchange:
--     - Should allow exchaning text between two buffers. Ideally, `u` should
--       undo whole exchange and not just latest paste.
--     - Think about taking indent into account when replacing linewise.
--
--
-- Docs:
-- - Document official way to remap in Normal (operator and line) and Visual modes.
--
-- - Replace:
--     - `[count]` in `grr` affects number of pastes.
--     - Respects [count] (in Visual, at first and in dot-repeat).
--       In Normal mode should differentiate between two counts:
--       `[count1]gr[count2]{motion}` (`[count1]` is for pasting,
--       `[count2]` is for textobject/motion).
--
--
-- Tests:
-- - Replace:
--
-- - Exchange:
--     - Should work across buffers.
--     - Should restore all temporary marks and registers.
--

--- *mini.operators* Text edit operators
--- *MiniOperators*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Operators (already mapped and as functions):
---     - Replace textobject with register.
---     - Reput text over different region.
---     - Exchange regions.
---     - Sort text.
---     - Duplicate text.
---     - Evaluate.
---     - ?Change case?
---     - ?Replace textobject with register inside region?.
---
--- - All operators are dot-repeatable and can be applied in Visual mode.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.operators').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniOperators`
--- which you can use for scripting or manually (with `:lua MiniOperators.*`).
---
--- See |MiniOperators.config| for available config settings.
---
--- You can override runtime config settings (but not `config.mappings`) locally
--- to buffer inside `vim.b.minioperators_config` which should have same structure
--- as `MiniOperators.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'gbprod/substitute.nvim':
--- - 'svermeulen/vim-subversive':
--- - 'vim-scripts/ReplaceWithRegister':
--- - 'tommcdo/vim-exchange'
---
--- # Highlight groups ~
---
--- * `MiniOperatorsExchangeFrom` - region to exchange.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- To disable creating triggers, set `vim.g.minioperators_disable` (globally) or
--- `vim.b.minioperators_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
MiniOperators = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniOperators.config|.
---
---@usage `require('mini.operators').setup({})` (replace `{}` with your `config` table).
--- **Neds to have triggers configured**.
MiniOperators.setup = function(config)
  -- Export module
  _G.MiniOperators = MiniOperators

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Create default highlighting
  H.create_default_hl()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Mappings ~
MiniOperators.config = {
  mappings = {
    duplicate  = 'gd',
    evaluate   = 'g=',
    exchange   = 'gx',
    replace    = 'gr',
    reput      = 'g.',
    sort       = 'gs',
  },

  options = {
    make_line_mappings   = true,
    make_visual_mappings = true,
  }
}
--minidoc_afterlines_end

MiniOperators.replace = function(mode)
  if H.is_disabled() or not vim.o.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.replace'
    H.cache.replace = { count = vim.v.count1, register = vim.v.register }

    -- Reset count to allow two counts: first for paste, second for textobject
    return vim.api.nvim_replace_termcodes('<Cmd>echon ""<CR>g@', true, true, true)
  end

  -- If used with 'visual', operate on visual selection
  if mode == 'visual' then
    local cmd = string.format('normal! %d"%sP', vim.v.count1, vim.v.register)
    vim.cmd(cmd)
    return
  end

  if not (mode == 'char' or mode == 'line' or mode == 'block') then
    H.error('Incorrect `mode`: ' .. vim.inspect(mode) .. '.')
  end

  -- Do replace
  local cache = H.cache.replace
  local data =
    { submode = H.get_submode(mode), register = cache.register, count = cache.count, mark_from = '[', mark_to = ']' }
  H.replace_do(data)

  return ''
end

MiniOperators.exchange = function(mode)
  if H.is_disabled() or not vim.o.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.exchange'
    return 'g@'
  end

  -- Depending on present cache data, perform exchange step
  if H.cache.exchange.step_one == nil then
    -- Store data about first region
    H.cache.exchange.step_one = H.exchange_set_region_extmark(mode, true)

    -- Temporarily remap `<C-c>` to stop the exchange
    H.exchange_map_stop()
  else
    -- Store data about second region
    H.cache.exchange.step_two = H.exchange_set_region_extmark(mode, false)

    -- Do exchange
    H.exchange_do()

    -- Stop exchange
    H.exchange_stop()
  end
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniOperators.config

-- Namespaces
H.ns_id = {
  exchange = vim.api.nvim_create_namespace('MiniOperatorsExchange'),
}

-- Cache for all operators
H.cache = {
  exchange = {},
  replace = {},
}

-- Submode keys for
H.submode_keys = {
  char = 'v',
  line = 'V',
  block = vim.api.nvim_replace_termcodes('<C-v>', true, true, true),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    mappings = { config.mappings, 'table' },
    options = { config.options, 'table' },
  })

  vim.validate({
    ['mappings.duplicate'] = { config.mappings.duplicate, 'string' },
    ['mappings.exchange'] = { config.mappings.exchange, 'string' },
    ['mappings.replace'] = { config.mappings.replace, 'string' },
    ['mappings.reput'] = { config.mappings.reput, 'string' },
    ['mappings.sort'] = { config.mappings.sort, 'string' },

    ['options.make_line_mappings'] = { config.options.make_line_mappings, 'boolean' },
    ['options.make_visual_mappings'] = { config.options.make_visual_mappings, 'boolean' },
  })

  return config
end

H.apply_config = function(config)
  MiniOperators.config = config

  -- Make mappings
  local mappings, options = config.mappings, config.options

  local map_all = function(operator_name)
    -- Map only valid LHS
    local lhs = mappings[operator_name]
    if type(lhs) ~= 'string' or lhs == '' then return end

    local operator_desc = operator_name:sub(1, 1):upper() .. operator_name:sub(2)

    local expr_opts = { expr = true, replace_keycodes = false, desc = operator_desc }
    H.map('n', lhs, string.format('v:lua.MiniOperators.%s()', operator_name), expr_opts)

    if options.make_line_mappings then
      local line_lhs = lhs .. vim.fn.strcharpart(lhs, vim.fn.strchars(lhs) - 1, 1)
      H.map('n', line_lhs, lhs .. '_', { remap = true, desc = operator_desc .. ' line' })
    end

    if options.make_visual_mappings then
      local visual_rhs = string.format([[<Cmd>lua MiniOperators.%s('visual')<CR>]], operator_name)
      H.map('x', lhs, visual_rhs, { desc = operator_desc .. ' selection' })
    end
  end

  map_all('duplicate')
  map_all('evaluate')
  map_all('exchange')
  map_all('replace')
  map_all('reput')
  map_all('sort')
end

H.is_disabled = function() return vim.g.minioperators_disable == true or vim.b.minioperators_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniOperators.config, vim.b.minioperators_config or {}, config or {})
end

H.create_default_hl =
  function() vim.api.nvim_set_hl(0, 'MiniOperatorsExchangeFrom', { default = true, link = 'IncSearch' }) end

-- Exchange -------------------------------------------------------------------
H.exchange_do = function()
  local step_one, step_two = H.cache.exchange.step_one, H.cache.exchange.step_two

  -- Save temporary registers
  local reg_one, reg_two = vim.fn.getreginfo('1'), vim.fn.getreginfo('2')

  -- Put regions into registers. NOTE: do it before actual exchange to allow
  -- intersecting regions.
  local putting_in_register = function(step, register)
    return function()
      H.exchange_set_step_marks(step, { 'x', 'y' })

      local cmd = string.format('normal! `x"%sy%s`y', register, step.submode)
      vim.cmd(cmd)
    end
  end

  H.with_temp_context({ buf_id = step_one.buf_id, marks = { 'x', 'y' } }, putting_in_register(step_one, '1'))
  H.with_temp_context({ buf_id = step_two.buf_id, marks = { 'x', 'y' } }, putting_in_register(step_two, '2'))

  -- Sequentially replace
  local replacing = function(step, register)
    return function()
      H.exchange_set_step_marks(step, { 'x', 'y' })

      local replace_data = { count = 1, mark_from = 'x', mark_to = 'y', submode = step.submode, register = register }
      H.replace_do(replace_data)
    end
  end

  H.with_temp_context({ buf_id = step_one.buf_id, marks = { 'x', 'y' } }, replacing(step_one, '2'))
  H.with_temp_context({ buf_id = step_two.buf_id, marks = { 'x', 'y' } }, replacing(step_two, '1'))

  -- Restore temporary registers
  vim.fn.setreg('1', reg_one)
  vim.fn.setreg('2', reg_two)
end

H.exchange_set_region_extmark = function(mode, add_highlight)
  local submode = H.get_submode(mode)
  local ns_id = H.ns_id.exchange

  -- Compute extmark's range
  local mark_from, mark_to = H.get_region_marks(mode)

  local extmark_from = { mark_from[1] - 1, mark_from[2] }
  local extmark_to = { mark_to[1] - 1, mark_to[2] + 1 }
  if submode == 'V' then extmark_to[2] = vim.fn.col({ extmark_to[1] + 1, '$' }) - 1 end

  -- Set extmark to represent region
  local buf_id = vim.api.nvim_get_current_buf()
  local extmark_opts = { end_row = extmark_to[1], end_col = extmark_to[2] }
  local region_mark_id = vim.api.nvim_buf_set_extmark(buf_id, ns_id, extmark_from[1], extmark_from[2], extmark_opts)

  -- Highlight first region to be exchanged. NOTE: Can't be done directly in
  -- mark to account for linewise/blockwise region.
  if add_highlight then
    -- Highlighting blockwise region needs full register type with width
    local is_blockwise = submode == H.submode_keys.block
    local regtype = is_blockwise and H.exchange_get_blockwise_regtype(mark_from, mark_to) or submode
    vim.highlight.range(buf_id, ns_id, 'MiniOperatorsExchangeFrom', extmark_from, extmark_to, { regtype = regtype })
  end

  -- Return data to cache
  return { buf_id = buf_id, submode = submode, mark_id = region_mark_id }
end

H.exchange_set_step_marks = function(step, mark_names)
  local extmark_details =
    vim.api.nvim_buf_get_extmark_by_id(step.buf_id, H.ns_id.exchange, step.mark_id, { details = true })

  H.set_mark(mark_names[1], { extmark_details[1] + 1, extmark_details[2] })
  H.set_mark(mark_names[2], { extmark_details[3].end_row + 1, extmark_details[3].end_col })
end

H.exchange_get_blockwise_regtype = function(mark_from, mark_to)
  local f = function()
    H.set_mark('x', mark_from)
    H.set_mark('y', mark_to)

    -- Move to `x` mark, yank blockwise to register `z` until `y` mark
    vim.cmd('normal! `x"zy\22`y')

    return vim.fn.getregtype('z')
  end

  return H.with_temp_context({ buf_id = 0, marks = { 'x', 'y' }, registers = { 'z' } }, f)
end

H.exchange_stop = function()
  local cur, ns_id = H.cache.exchange, H.ns_id.exchange
  if cur.step_one ~= nil then vim.api.nvim_buf_clear_namespace(cur.step_one.buf_id, ns_id, 0, -1) end
  if cur.step_two ~= nil then vim.api.nvim_buf_clear_namespace(cur.step_two.buf_id, ns_id, 0, -1) end
  H.cache.exchange = {}
end

H.exchange_map_stop = function()
  local target = '<C-c>'
  local cur_ctrlc_map = vim.fn.maparg(target, 'n', false, true)
  local rhs = function()
    H.exchange_stop()
    -- NOTE: Neovim<0.8 doesn't have `mapset()`
    if vim.fn.has('nvim-0.8') == 0 then
      vim.keymap.del('n', target)
      return
    end

    -- Restore previous mapping if it was set
    if vim.tbl_count(cur_ctrlc_map) == 0 then return end
    vim.fn.mapset('n', false, cur_ctrlc_map)
  end
  vim.keymap.set('n', target, rhs, { desc = 'Stop exchange' })
end

-- Replace --------------------------------------------------------------------
--- Delete region between two marks and paste from register
---
---@param data table Fields:
---   - <count> (optional) - Number of times to paste.
---   - <mark_from> - Name of "from" mark.
---   - <mark_to> - Name of "to" mark.
---   - <register> - Name of register from which to paste.
---   - <submode> - Region submode. One of 'v', 'V', '\22'.
---@private
H.replace_do = function(data)
  local register, submode = data.register, data.submode

  -- Do nothing with empty/unknown register
  local register_type = H.get_reg_type(register)
  if register_type == '' then H.error('Register ' .. vim.inspect(register) .. ' is empty or unknown.') end

  -- Determine if region is at edge which is needed for the correct paste key
  local to_line = vim.fn.line("']")
  local is_edge_line = submode == 'V' and to_line == vim.fn.line('$')
  local is_edge_col = submode ~= 'V' and vim.fn.col("']") == (vim.fn.col({ to_line, '$' }) - 1)
  local is_edge = is_edge_line or is_edge_col

  -- Delete region to black whole register
  local delete_keys = string.format('`%s"_d%s`%s', data.mark_from, submode, data.mark_to)
  H.cmd_normal(delete_keys)

  -- Paste register (ensuring same submode type as region) and adjust cursor
  H.set_reg_type(register, submode)

  local paste_keys = string.format('%d"%s%s`%s', data.count or 1, register, (is_edge and 'p' or 'P'), data.mark_from)
  H.cmd_normal(paste_keys)

  H.set_reg_type(register, register_type)
end

-- Registers ------------------------------------------------------------------
H.get_reg_type = function(regname) return vim.fn.getregtype(regname):sub(1, 1) end

H.set_reg_type = function(regname, new_regtype)
  local reg_info = vim.fn.getreginfo(regname)
  local cur_regtype, n_lines = reg_info.regtype:sub(1, 1), #reg_info.regcontents

  -- Do nothing if already the same type
  if cur_regtype == new_regtype then return end

  reg_info.regtype = new_regtype
  vim.fn.setreg(regname, reg_info)
end

-- Marks ----------------------------------------------------------------------
H.get_region_marks = function(mode)
  local left, right = '[', ']'
  if mode == 'visual' then
    vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('<Esc>', true, true, true))
    left, right = '<', '>'
  end
  return vim.api.nvim_buf_get_mark(0, left), vim.api.nvim_buf_get_mark(0, right)
end

H.get_mark = function(mark_name) vim.api.nvim_buf_get_mark(0, mark_name) end

H.set_mark = function(mark_name, mark_data) vim.api.nvim_buf_set_mark(0, mark_name, mark_data[1], mark_data[2], {}) end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.operators) %s', msg), 0) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.get_submode = function(mode)
  if mode == 'visual' then return vim.fn.mode() end
  return H.submode_keys[mode]
end

H.with_temp_context = function(context, f)
  local res
  vim.api.nvim_buf_call(context.buf_id or 0, function()
    -- Cache temporary data
    local marks_data = {}
    for _, mark_name in ipairs(context.marks or {}) do
      marks_data[mark_name] = H.get_mark(mark_name)
    end

    local reg_data = {}
    for _, reg_name in ipairs(context.registers or {}) do
      reg_data[reg_name] = vim.fn.getreginfo(reg_name)
    end

    -- Perform action
    res = f()

    -- Restore data
    for mark_name, data in pairs(marks_data) do
      H.set_mark(mark_name, data)
    end
    for reg_name, data in pairs(reg_data) do
      vim.fn.setreg(reg_name, data)
    end
  end)

  return res
end

-- A hack to restore previous dot-repeat action
H.cancel_redo = function() end;
(function()
  local has_ffi, ffi = pcall(require, 'ffi')
  if not has_ffi then return end
  local has_cancel_redo = pcall(ffi.cdef, 'void CancelRedo(void)')
  if not has_cancel_redo then return end
  H.cancel_redo = function() pcall(ffi.C.CancelRedo) end
end)()

H.cmd_normal = function(command, cancel_redo)
  if cancel_redo == nil then cancel_redo = true end
  vim.cmd('silent keepjumps lockmarks normal! ' .. command)
  if cancel_redo then H.cancel_redo() end
end

return MiniOperators
