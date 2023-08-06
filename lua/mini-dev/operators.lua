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
--     - Should respect [reigster] (in Visual, at first and in dot-repeat).
--     - Should work in all edge-case places: replace on line end, replace
--       second to line end, replace last line, replace second to last line.
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

_G.log = {}
MiniOperators.replace = function(mode)
  if H.is_disabled() or not vim.o.modifiable then return '' end

  -- If used with 'visual', operate on visual selection
  if mode == 'visual' then
    local cmd = string.format('normal! %d"%sP', vim.v.count1, vim.v.register)
    vim.cmd(cmd)
    return
  end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.replace'
    H.cache.replace = { count = vim.v.count1, register = vim.v.register }

    -- Reset count to allow two counts: first for paste, second for textobject
    return vim.api.nvim_replace_termcodes('<Cmd>echon ""<CR>g@', true, true, true)
  end

  table.insert(_G.log, { mode = mode })
  local cache = H.cache.replace

  -- Do nothing with empty/unknown register
  local register_type = H.get_reg_type(cache.register)
  if register_type == '' then H.error('Register ' .. vim.inspect(cache.register) .. ' is empty or unknown.') end

  -- Allow replacing only matching region submode and register type
  local region_submode = H.submode_keys[mode]
  if region_submode ~= register_type then
    H.error('Replacing is allowed only for region and register with matching submodes (charwise, linewise, blockwise).')
  end

  -- Determine if region is at edge which is needed for the correct paste key
  local to_line = vim.fn.line("']")
  local is_edge_line = mode == 'line' and to_line == vim.fn.line('$')
  local is_edge_col = mode ~= 'line' and vim.fn.col("']") == (vim.fn.col({ to_line, '$' }) - 1)
  local is_edge = is_edge_line or is_edge_col

  -- Delete to black whole register
  local delete_keys = string.format('`["_d%s`]', region_submode)
  H.cmd_normal(delete_keys)

  -- Paste register and adjust cursor
  local paste_keys = string.format('%d"%s%s`[', cache.count, cache.register, (is_edge and 'p' or 'P'))
  H.cmd_normal(paste_keys)

  return ''
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniOperators.config

-- Namespaces
H.ns_id = {
  highlight = vim.api.nvim_create_namespace('MiniOperatorsHighlight'),
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

-- Replace --------------------------------------------------------------------

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.operators) %s', msg), 0) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.get_submode_keys = function(mode)
  if mode == 'visual' then return vim.fn.mode() end
  return H.submode_keys[mode]
end

H.get_reg_type = function(regname) return vim.fn.getregtype(regname):sub(1, 1) end

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
