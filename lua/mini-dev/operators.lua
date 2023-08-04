-- TODO:
--
-- Code:
-- - All should respect 'selection=exclusive'.
-- - All should respect forced submode ('v', 'V', '<C-v>')
-- - All should not modify marks.
--
-- - Replace:
--     - Should work in all edge-case places: replace on line end, replace
--       second to line end, replace last line, replace second to last line.
--
--
-- Docs:
--
--
--
-- Tests:
--

--- *mini.operators* Operators
--- *MiniOperators*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Operators (already mapped and as functions):
---     - Replace region with register.
---     - Reput text over different region.
---     - Exchange regions.
---     - Sort text.
---     - Duplicate text.
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
--- # Disabling~
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
    exchange   = 'gx',
    replace    = 'gr',
    reput      = 'g.',
    sort       = 'gs',
  },

  options = {
    make_visual_mappings   = true,
    make_linewise_mappings = true,
  }
}
--minidoc_afterlines_end

_G.log = {}
MiniOperators.replace = function(mode)
  if H.is_disabled() or not vim.o.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.replace'
    return 'g@'
  end

  if mode == 'visual' then
    vim.cmd('normal! P')
    return
  end

  -- local ffi = require('ffi')
  -- ffi.cdef([[ char *get_inserted(void) ]])
  -- ffi.cdef([[void CancelRedo(void)]])
  --
  -- ffi.cdef([[
  --   typedef struct buffblock buffblock_T;
  --   typedef struct buffheader buffheader_T;
  --   typedef struct {
  --     buffheader_T sr_redobuff;
  --     buffheader_T sr_old_redobuff;
  --   } save_redo_T;
  --   save_redo_T save_redo
  --   void saveRedobuff(save_redo_T *save_redo)
  --   void restoreRedobuff(save_redo_T *save_redo)
  -- ]])
  --
  -- local get_redo_buffer = function() return ffi.string(ffi.C.get_inserted()) end
  -- local save_redo_buffer = function() return ffi.C.saveRedobuff(ffi.C.save_redo) end
  -- local restore_redo_buffer = function() return ffi.C.restoreRedobuff(ffi.C.save_redo) end
  --
  -- local redo_buffer_before = get_redo_buffer()

  -- Determine if region is at edge which is needed for the correct paste key
  local to_line = vim.fn.line("']")
  local is_edge_line = mode == 'line' and to_line == vim.fn.line('$')
  local is_edge_col = mode ~= 'line' and vim.fn.col("']") == (vim.fn.col({ to_line, '$' }) - 1)
  local is_edge = is_edge_line or is_edge_col

  -- Delete to black whole register and paste from target register
  local delete_keys = '`["_d' .. H.submode_keys[mode] .. '`]'
  H.cmd_normal(delete_keys)

  local paste_keys = '"' .. vim.v.register .. (is_edge and 'p' or 'P')
  H.cmd_normal(paste_keys)

  -- -- Same thing but without "normal!" which messes with dot-repeat
  -- -- Delete
  -- local from_pos = vim.api.nvim_buf_get_mark(0, '[')
  -- local to_pos = vim.api.nvim_buf_get_mark(0, ']')
  -- local delete_region = vim.region(0, from_pos, to_pos, H.submode_keys[mode], true)
  --
  -- local line_num_arr = vim.tbl_keys(delete_region)
  -- -- - Delete from the end to preserve line number meaning
  -- table.sort(line_num_arr, function(a, b) return a > b end)
  -- for _, line_num in ipairs(line_num_arr) do
  --   local line_range = delete_region[line_num]
  --   vim.api.nvim_buf_set_text(0, line_num - 1, line_range[1], line_num - 1, line_range[2], {})
  -- end
  --
  -- -- Paste
  -- local lines = vim.split(vim.fn.getreg(vim.v.register, 1), '\n')
  -- local reg_type = vim.fn.getregtype(vim.v.register)
  -- -- - Convert register type to be suitable for `nvim_put`
  -- local first_char = ({ v = 'c', V = 'l', ['\16'] = 'b' })[reg_type:sub(1, 1)]
  -- reg_type = first_char .. reg_type:sub(2)
  --
  -- vim.api.nvim_win_set_cursor(0, from_pos)
  -- vim.api.nvim_put(lines, reg_type, is_edge, false)

  return ''
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniOperators.config

-- Namespaces
H.ns_id = {
  highlight = vim.api.nvim_create_namespace('MiniOperatorsHighlight'),
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

    ['options.make_visual_mappings'] = { config.options.make_visual_mappings, 'boolean' },
    ['options.make_linewise_mappings'] = { config.options.make_linewise_mappings, 'boolean' },
  })

  return config
end

H.apply_config = function(config)
  MiniOperators.config = config

  -- Make mappings
  local mappings, options = config.mappings, config.options

  local map_all = function(operator_name)
    local lhs = mappings[operator_name]
    local operator_desc = operator_name:sub(1, 1):upper() .. operator_name:sub(2)

    H.map('n', lhs, string.format('v:lua.MiniOperators.%s()', operator_name), { expr = true, desc = operator_desc })

    if options.make_visual_mappings then
      local visual_rhs = string.format([[<Cmd>lua MiniOperators.%s('visual')<CR>]], operator_name)
      H.map('x', lhs, visual_rhs, { desc = operator_desc .. ' selection' })
    end

    if options.make_linewise_mappings then
      local linewise_lhs = lhs .. vim.fn.strcharpart(lhs, vim.fn.strchars(lhs) - 1, 1)
      H.map('n', linewise_lhs, lhs .. '_', { remap = true, desc = operator_desc .. ' line' })
    end
  end

  map_all('duplicate')
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

-- Utilities ------------------------------------------------------------------
H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.get_submode_keys = function(mode)
  if mode == 'visual' then return vim.fn.mode() end
  return H.submode_keys[mode]
end

H.cmd_normal = function(command)
  vim.cmd('silent keepjumps lockmarks normal! ' .. command)
  local ffi = require('ffi')
  ffi.cdef([[void CancelRedo(void)]])
  ffi.C.CancelRedo()
end

H.make_cmd_normal = function(include_undojoin)
  local normal_command = (include_undojoin and 'undojoin | ' or '') .. 'silent keepjumps normal! '

  return function(x)
    -- Caching and restoring data on every command is not necessary but leads
    -- to a nicer implementation

    -- Disable 'mini.bracketed' to avoid unwanted entries to its yank history
    local cache_minibracketed_disable = vim.b.minibracketed_disable
    local cache_unnamed_register = vim.fn.getreg('"')

    -- Don't track possible put commands into yank history
    vim.b.minibracketed_disable = true

    vim.cmd(normal_command .. x)

    vim.b.minibracketed_disable = cache_minibracketed_disable
    vim.fn.setreg('"', cache_unnamed_register)
  end
end

return MiniOperators
