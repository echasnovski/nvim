-- TODO:
--
-- Code:
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
-- - Exchange:
--     - Works with most cases of intersecting regions, but not officially
--       supported.
--
--
-- Tests:
-- - Replace:
--
-- - Exchange:
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
  evaluate = {
    prefix = 'g=',
    func = nil,
  },

  exchange = {
    prefix = 'gx',
    reindent_linewise = true,
  },

  replace = {
    prefix = 'gr',
    reindent_linewise = true,
  },

  sort = {
    prefix = 'gs',
    func = nil,
  }
}
--minidoc_afterlines_end

MiniOperators.replace = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

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
  local data = {
    count = cache.count,
    mark_from = '[',
    mark_to = ']',
    register = cache.register,
    reindent_linewise = H.get_config().replace.reindent_linewise,
    submode = H.get_submode(mode),
  }
  H.replace_do(data)

  return ''
end

MiniOperators.exchange = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.exchange'
    return 'g@'
  end

  -- Depending on present cache data, perform exchange step
  if not H.exchange_has_step_one() then
    -- Store data about first region
    H.cache.exchange.step_one = H.exchange_set_region_extmark(mode, true)

    -- Temporarily remap `<C-c>` to stop the exchange
    H.exchange_set_stop_mapping()
  else
    -- Store data about second region
    H.cache.exchange.step_two = H.exchange_set_region_extmark(mode, false)

    -- Do exchange
    H.exchange_do()

    -- Stop exchange
    H.exchange_stop()
  end
end

MiniOperators.sort = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.sort'
    return 'g@'
  end

  local submode = H.get_submode(mode)
  if mode == 'visual' then vim.cmd('normal! \27') end
  local mark_from = mode == 'visual' and '<' or '['
  local mark_to = mode == 'visual' and '>' or ']'

  H.with_temp_context({ registers = { 'x' } }, function() H.sort_do(mark_from, mark_to, submode) end)
end

MiniOperators.default_sort_func = function(content, opts)
  opts = vim.tbl_deep_extend('force', { compare_fun = nil, split_patterns = nil }, opts or {})

  local compare_fun = opts.compare_fun or function(a, b) return a < b end
  if not vim.is_callable(compare_fun) then H.error('`opts.compare_fun` should be callable.') end

  local split_patterns = opts.split_patterns or { '%s*,%s*', '%s*;%s*', '%s+' }
  if not vim.tbl_islist(split_patterns) then H.error('`opts.split_patterns` should be array.') end

  -- Prepare lines to sort
  local lines, submode = content.lines, content.submode

  if submode ~= 'v' then
    table.sort(lines, compare_fun)
    return lines
  end

  local parts, seps = H.sort_charwise_split(lines, split_patterns)
  table.sort(parts, compare_fun)
  return H.sort_charwise_unsplit(parts, seps)
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
    evaluate = { config.evaluate, 'table' },
    exchange = { config.exchange, 'table' },
    replace = { config.replace, 'table' },
    sort = { config.sort, 'table' },
  })

  vim.validate({
    ['evaluate.prefix'] = { config.evaluate.prefix, 'string' },
    ['evaluate.func'] = { config.evaluate.func, 'function', true },

    ['exchange.prefix'] = { config.exchange.prefix, 'string' },
    ['exchange.reindent_linewise'] = { config.exchange.reindent_linewise, 'boolean' },

    ['replace.prefix'] = { config.replace.prefix, 'string' },
    ['replace.reindent_linewise'] = { config.replace.reindent_linewise, 'boolean' },

    ['sort.prefix'] = { config.sort.prefix, 'string' },
    ['sort.func'] = { config.sort.func, 'function', true },
  })

  return config
end

H.apply_config = function(config)
  MiniOperators.config = config

  -- Make mappings
  local map_all = function(operator_name)
    -- Map only valid LHS
    local prefix = config[operator_name].prefix
    if type(prefix) ~= 'string' or prefix == '' then return end

    local operator_desc = operator_name:sub(1, 1):upper() .. operator_name:sub(2)

    local expr_opts = { expr = true, replace_keycodes = false, desc = operator_desc .. ' operator' }
    H.map('n', prefix, string.format('v:lua.MiniOperators.%s()', operator_name), expr_opts)

    local line_lhs = prefix .. vim.fn.strcharpart(prefix, vim.fn.strchars(prefix) - 1, 1)
    H.map('n', line_lhs, prefix .. '_', { remap = true, desc = operator_desc .. ' line' })

    local visual_rhs = string.format([[<Cmd>lua MiniOperators.%s('visual')<CR>]], operator_name)
    H.map('x', prefix, visual_rhs, { desc = operator_desc .. ' selection' })
  end

  map_all('evaluate')
  map_all('exchange')
  map_all('replace')
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

  -- Do nothing if regions are the same
  if H.exchange_is_same_steps(step_one, step_two) then return end

  -- Save temporary registers
  local reg_one, reg_two = vim.fn.getreginfo('1'), vim.fn.getreginfo('2')

  -- Put regions into registers. NOTE: do it before actual exchange to allow
  -- intersecting regions.
  local populating_register = function(step, register)
    return function()
      H.exchange_set_step_marks(step, { 'x', 'y' })

      local cmd = string.format('normal! `x"%sy%s`y', register, step.submode)
      vim.cmd(cmd)
    end
  end

  H.with_temp_context({ buf_id = step_one.buf_id, marks = { 'x', 'y' } }, populating_register(step_one, '1'))
  H.with_temp_context({ buf_id = step_two.buf_id, marks = { 'x', 'y' } }, populating_register(step_two, '2'))

  -- Sequentially replace
  local replacing = function(step, register)
    return function()
      H.exchange_set_step_marks(step, { 'x', 'y' })

      local replace_data = {
        count = 1,
        mark_from = 'x',
        mark_to = 'y',
        register = register,
        reindent_linewise = H.get_config().exchange.reindent_linewise,
        submode = step.submode,
      }
      H.replace_do(replace_data)
    end
  end

  H.with_temp_context({ buf_id = step_one.buf_id, marks = { 'x', 'y' } }, replacing(step_one, '2'))
  H.with_temp_context({ buf_id = step_two.buf_id, marks = { 'x', 'y' } }, replacing(step_two, '1'))

  -- Restore temporary registers
  vim.fn.setreg('1', reg_one)
  vim.fn.setreg('2', reg_two)
end

H.exchange_has_step_one = function()
  local step_one = H.cache.exchange.step_one
  if type(step_one) ~= 'table' then return false end

  if not vim.api.nvim_buf_is_valid(step_one.buf_id) then
    H.exchange_stop()
    return false
  end
  return true
end

H.exchange_set_region_extmark = function(mode, add_highlight)
  local submode = H.get_submode(mode)
  local ns_id = H.ns_id.exchange

  -- Compute regular marks for target region
  if mode == 'visual' then vim.cmd('normal! \27') end
  local mark_from, mark_to = H.get_region_marks(mode)

  -- Compute extmark's range for target region
  local extmark_from = { mark_from[1] - 1, mark_from[2] }
  local extmark_to = { mark_to[1] - 1, mark_to[2] + 1 }
  -- - Tweak columns for linewise marks
  if submode == 'V' then
    extmark_from[2] = 0
    extmark_to[2] = vim.fn.col({ extmark_to[1] + 1, '$' }) - 1
  end

  -- Set extmark to represent region. Add highlighting inside of it only if
  -- needed and not in blockwise submode (can't highlight that way).
  local buf_id = vim.api.nvim_get_current_buf()

  local extmark_hl_group
  if add_highlight and submode ~= H.submode_keys.block then extmark_hl_group = 'MiniOperatorsExchangeFrom' end

  local extmark_opts = {
    end_row = extmark_to[1],
    end_col = extmark_to[2],
    hl_group = extmark_hl_group,
    -- Using this gravity is better for handling empty lines in linewise mode
    end_right_gravity = mode == 'line',
  }
  local region_extmark_id = vim.api.nvim_buf_set_extmark(buf_id, ns_id, extmark_from[1], extmark_from[2], extmark_opts)

  -- - Possibly add highlighting for blockwise mode
  if add_highlight and extmark_hl_group == nil then
    -- Highlighting blockwise region needs full register type with width
    local opts = { regtype = H.exchange_get_blockwise_regtype(mark_from, mark_to) }
    vim.highlight.range(buf_id, ns_id, 'MiniOperatorsExchangeFrom', extmark_from, extmark_to, opts)
  end

  -- Return data to cache
  return { buf_id = buf_id, submode = submode, extmark_id = region_extmark_id }
end

H.exchange_get_region_extmark = function(step)
  return vim.api.nvim_buf_get_extmark_by_id(step.buf_id, H.ns_id.exchange, step.extmark_id, { details = true })
end

H.exchange_set_step_marks = function(step, mark_names)
  local extmark_details = H.exchange_get_region_extmark(step)

  H.set_mark(mark_names[1], { extmark_details[1] + 1, extmark_details[2] })
  H.set_mark(mark_names[2], { extmark_details[3].end_row + 1, extmark_details[3].end_col - 1 })
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
  H.exchange_del_stop_mapping()

  local cur, ns_id = H.cache.exchange, H.ns_id.exchange
  if cur.step_one ~= nil then pcall(vim.api.nvim_buf_clear_namespace, cur.step_one.buf_id, ns_id, 0, -1) end
  if cur.step_two ~= nil then pcall(vim.api.nvim_buf_clear_namespace, cur.step_two.buf_id, ns_id, 0, -1) end
  H.cache.exchange = {}
end

H.exchange_set_stop_mapping = function()
  local lhs = '<C-c>'
  H.cache.exchange.stop_restore_map_data = vim.fn.maparg(lhs, 'n', false, true)
  vim.keymap.set('n', lhs, H.exchange_stop, { desc = 'Stop exchange' })
end

H.exchange_del_stop_mapping = function()
  local map_data = H.cache.exchange.stop_restore_map_data
  if map_data == nil then return end

  -- Try restore previous mapping if it was set. NOTE: Neovim<0.8 doesn't have
  -- `mapset()`, so resort to deleting.
  if vim.tbl_count(map_data) > 0 and vim.fn.has('nvim-0.8') == 1 then
    vim.fn.mapset('n', false, map_data)
  else
    vim.keymap.del('n', map_data.lhs or '<C-c>')
  end
end

H.exchange_is_same_steps = function(step_one, step_two)
  if step_one.buf_id ~= step_two.buf_id or step_one.submode ~= step_two.submode then return false end
  -- Region's start and end should be the same
  local one, two = H.exchange_get_region_extmark(step_one), H.exchange_get_region_extmark(step_two)
  return one[1] == two[1] and one[2] == two[2] and one[3].end_row == two[3].end_row and one[3].end_col == two[3].end_col
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
  -- NOTE: Ideally, implementation would leverage "Visually select - press `P`"
  -- approach, but it has issues with dot-repeat. The `cancel_redo()` approach
  -- doesn't work probably because `P` implementation uses more than one
  -- dot-repeat overwrite.
  local register, submode = data.register, data.submode
  local mark_from, mark_to = data.mark_from, data.mark_to

  -- Do nothing with empty/unknown register
  local register_type = H.get_reg_type(register)
  if register_type == '' then H.error('Register ' .. vim.inspect(register) .. ' is empty or unknown.') end

  -- Determine if region is at edge which is needed for the correct paste key
  local from_line, _ = unpack(H.get_mark(mark_from))
  local to_line, to_col = unpack(H.get_mark(mark_to))

  local is_edge_line = submode == 'V' and to_line == vim.fn.line('$')
  local is_edge_col = submode ~= 'V' and to_col == (vim.fn.col({ to_line, '$' }) - 2)
  local is_edge = is_edge_line or is_edge_col

  local covers_linewise_all_buffer = is_edge_line and from_line == 1

  -- Compute current indent if needed
  local init_indent
  local should_reindent = data.reindent_linewise and data.submode == 'V' and vim.o.equalprg == ''
  if should_reindent then init_indent = H.get_region_indent(mark_from, mark_to) end

  -- Delete region to black whole register
  -- - Delete single character in blockwise submode with inclusive motion.
  --   See https://github.com/neovim/neovim/issues/24613
  local is_blockwise_single_cell = submode == H.submode_keys.block
    and vim.deep_equal(H.get_mark(mark_from), H.get_mark(mark_to))
  local forced_motion = is_blockwise_single_cell and 'v' or submode
  local delete_keys = string.format('`%s"_d%s`%s', mark_from, forced_motion, mark_to)
  H.cmd_normal(delete_keys)

  -- Paste register (ensuring same submode type as region)
  H.with_temp_context({ registers = { register } }, function()
    H.set_reg_type(register, submode)

    -- Possibly reindent
    if should_reindent then H.set_reg_indent(register, init_indent) end

    local paste_keys = string.format('%d"%s%s', data.count or 1, register, (is_edge and 'p' or 'P'))
    H.cmd_normal(paste_keys)
  end)

  -- Adjust cursor to be at paste start
  H.cmd_normal('`[', false)

  -- Adjust for extra empty line after pasting inside empty buffer
  if covers_linewise_all_buffer then vim.api.nvim_buf_set_lines(0, 0, 1, true, {}) end
end

-- Sort -----------------------------------------------------------------------
H.sort_do = function(mark_from, mark_to, submode)
  -- Extract effective region content into "x" register.
  local yank_keys = string.format('`%s"xy%s`%s', mark_from, submode, mark_to)

  -- Make sure that `[` and `]` marks don't change after yank
  H.with_temp_context(
    { marks = { '[', ']' } },
    -- - Cancel one redo if `y` is dot-repeatable.
    function() H.cmd_normal(yank_keys, vim.o.cpoptions:find('y') ~= nil) end
  )

  -- Sort register content
  local sort_fun = H.get_config().sort.func or MiniOperators.default_sort_func
  local reg_info = vim.fn.getreginfo('x')
  local content_init = { lines = reg_info.regcontents, submode = submode }
  reg_info.regcontents = sort_fun(content_init)
  vim.fn.setreg('x', reg_info)

  -- Replace region with new register content
  local replace_data = {
    count = 1,
    mark_from = mark_from,
    mark_to = mark_to,
    register = 'x',
    reindent_linewise = false,
    submode = submode,
  }
  H.replace_do(replace_data)
end

H.sort_charwise_split = function(lines, split_patterns)
  local lines_str = table.concat(lines, '\n')

  local pat
  for _, pattern in ipairs(split_patterns) do
    if lines_str:find(pattern) ~= nil then
      pat = pattern
      break
    end
  end

  if pat == nil then return lines end

  -- Split while keeping separators
  local parts, seps = {}, {}
  local init, n = 1, lines_str:len()
  while init < n do
    local sep_from, sep_to = string.find(lines_str, pat, init)
    if sep_from == nil then break end
    table.insert(parts, lines_str:sub(init, sep_from - 1))
    table.insert(seps, lines_str:sub(sep_from, sep_to))
    init = sep_to + 1
  end
  table.insert(parts, lines_str:sub(init, n))

  return parts, seps
end

H.sort_charwise_unsplit = function(parts, seps)
  local all = {}
  for i = 1, #parts do
    table.insert(all, parts[i])
    table.insert(all, seps[i] or '')
  end

  return vim.split(table.concat(all, ''), '\n')
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

H.set_reg_indent = function(regname, new_indent)
  local reg_info = vim.fn.getreginfo(regname)
  reg_info.regcontents = H.update_indent(reg_info.regcontents, new_indent)
  vim.fn.setreg(regname, reg_info)
end

-- Marks ----------------------------------------------------------------------
H.get_region_marks = function(mode)
  local left = mode == 'visual' and '<' or '['
  local right = mode == 'visual' and '>' or ']'
  return vim.api.nvim_buf_get_mark(0, left), vim.api.nvim_buf_get_mark(0, right)
end

H.get_region_indent = function(mark_from, mark_to)
  local l_from, l_to = H.get_mark(mark_from)[1], H.get_mark(mark_to)[1]
  local lines = vim.api.nvim_buf_get_lines(0, l_from - 1, l_to, true)
  return H.compute_indent(lines)
end

H.get_mark = function(mark_name) return vim.api.nvim_buf_get_mark(0, mark_name) end

H.set_mark = function(mark_name, mark_data) vim.api.nvim_buf_set_mark(0, mark_name, mark_data[1], mark_data[2], {}) end

-- Indent ---------------------------------------------------------------------
H.compute_indent = function(lines)
  local res_indent, res_indent_width = nil, math.huge
  for _, l in ipairs(lines) do
    local cur_indent = l:match('^%s*')
    local cur_indent_width = cur_indent:len()
    if cur_indent_width < l:len() and cur_indent_width < res_indent_width then
      res_indent, res_indent_width = cur_indent, cur_indent_width
    end
  end

  return res_indent or ''
end

H.update_indent = function(lines, new_indent)
  -- Replace current indent with new indent without affecting blank lines
  local n_cur_indent = H.compute_indent(lines):len()
  return vim.tbl_map(function(l)
    if l:find('^%s*$') ~= nil then return l end
    return new_indent .. l:sub(n_cur_indent + 1)
  end, lines)
end

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
  vim.cmd('silent keepjumps normal! ' .. command)
  if cancel_redo then H.cancel_redo() end
end

return MiniOperators
