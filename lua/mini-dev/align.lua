-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- Documentation ==============================================================
--- Align text.
---
--- Features:
--- - Alignment is done by splitting text into parts (based on Lua pattern
---   separator or with user-supplied function), making each part same width,
---   and then merging them together.
--- - User can control alignment interactively by pressing customizable modifiers
---   (single characters representing how alignment options should change).
--- - Customizable alignment options (see |MiniAlign.align_strings()|):
---     - Justification (left, right, center).
---     - Filtering affected parts based on predicate function (like "align
---       only based on last pair").
---     - Middles to be ensured between parts (like "ensure parts are separated
---       by space").
---     - Pre and post hooks.
---
--- # Setup~
---
--- This module needs a setup with `require('mini.align').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniAlign`
--- which you can use for scripting or manually (with `:lua MiniAlign.*`).
---
--- See |MiniAlign.config| for available config settings.
---
--- You can override runtime config settings (like `config.modifiers`) locally
--- to buffer inside `vim.b.minialign_config` which should have same structure
--- as `MiniAlign.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons~
---
--- - 'junegunn/vim-easy-align':
--- - 'godlygeek/tabular':
--- - `tommcdo/vim-lion`:
---
--- # Disabling~
---
--- To disable, set `g:minialign_disable` (globally) or `b:minialign_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.align
---@tag MiniAlign

--- Algorithm design
---@tag MiniAlign-algorithm

-- Module definition ==========================================================
-- TODO: Make local before release
MiniAlign = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniAlign.config|.
---
---@usage `require('mini.align').setup({})` (replace `{}` with your `config` table)
MiniAlign.setup = function(config)
  -- Export module
  _G.MiniAlign = MiniAlign

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Options ~
MiniAlign.config = {
  mappings = {
    start = 'ga',
  },

  -- Each is a function that either modifies in place and return `nil` or
  -- returns new options table
  modifiers = {
    h = function(opts) opts.justify = 'left' end,
    l = function(opts) opts.justify = 'right' end,
    f = function(opts)
      local input = H.user_input('Enter filter expression')
      if input == nil then return end

      local filter = H.make_expression_filter(input)
      if filter == nil then return end

      opts.filter = filter
    end,
    ['?'] = function(opts)
      local input = H.user_input('Enter splitter Lua pattern')
      if input == nil then return end

      opts.splitter = input
    end,
  },

  options = {
    filter = function(x, data) return true end,
    pre = function(x, data) return x end,
    justify = 'left',
    post = function(x, data) return x end,
    concat = '',
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
MiniAlign.align_strings = function(strings, opts)
  -- Validate arguments
  if not H.is_string_array(strings) then
    H.error('First argument of `MiniAlign.align_strings()` should be array of strings.')
  end
  opts = H.normalize_opts(opts)

  -- Split string
  local splits = vim.tbl_map(H.normalize_splitter(opts.splitter), strings)

  splits = H.apply_justify(splits, opts)

  -- Temporary action for testing
  return vim.tbl_map(function(x) return table.concat(x, '-') end, splits)

  -- Modify string parts

  -- Concatenate splits
  -- return vim.tbl_map(function(x) return table.concat(x, opts.concat) end, splits)
end

MiniAlign.align_interactive = function()
  local modifiers = H.get_config().modifiers

  -- Use cache for dot-repreat
  local opts = H.cache.opts or H.normalize_opts({})
  while opts.splitter == nil do
    local id = H.user_modifier()
    if id == nil then return end

    local mod = modifiers[id]
    if mod == nil then
      -- Use supplied identifier as splitter pattern
      opts.splitter = vim.pesc(id)
    else
      -- Allow modifier to either return new options or change input in place
      local ok, new_opts = pcall(modifiers[id], opts)
      if ok then
        -- Allow both returning table with new options or modification in place
        if type(new_opts) == 'table' then opts = new_opts end
      else
        H.message(string.format('Modifier %s should be properly callable.', vim.inspect(id)))
      end
    end
  end
  H.cache.opts = opts

  -- Process region
  local region = H.get_current_region()
  local reg_type = H.get_current_reg_type()

  local strings = H.region_get_text(region, reg_type)
  local strings_aligned = MiniAlign.align_strings(strings, opts)
  H.region_set_text(region, reg_type, strings_aligned)
end

MiniAlign.action_visual = function()
  H.cache = {}
  vim.cmd('lockmarks lua MiniAlign.align_interactive()')
  -- MiniAlign.align_interactive()

  -- Exit Visual mode
  vim.cmd('normal! \27')
end

MiniAlign.action_normal = function()
  H.cache = {}
  vim.cmd('set operatorfunc=v:lua.MiniAlign.align_interactive')
  return 'g@'
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniAlign.config

-- Cache for various operations
H.cache = {}

-- Module's namespaces
H.ns_id = {
  -- Track user input
  input = vim.api.nvim_create_namespace('MiniAlignInput'),
}

-- Supported justify directions
H.justify_functions = {
  left = function(x, n_spaces) return string.format('%s%s', x, string.rep(' ', n_spaces)) end,
  center = function(x, n_spaces)
    local n_left = math.floor(0.5 * n_spaces)
    return string.format('%s%s%s', string.rep(' ', n_left), x, string.rep(' ', n_spaces - n_left))
  end,
  right = function(x, n_spaces) return string.format('%s%s', string.rep(' ', n_spaces), x) end,
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
    modifiers = { config.modifiers, 'table' },
    options = { config.options, H.is_valid_opts },
  })

  vim.validate({
    ['mappings.start'] = { config.mappings.start, 'string' },

    -- ['options.filter'] = { config.options.filter, 'function' },
    -- ['options.pre'] = { config.options.pre, 'function' },
    -- ['options.justify'] = { config.options.justify, 'string' },
    -- ['options.post'] = { config.options.post, 'function' },
    -- ['options.concat'] = { config.options.concat, 'string' },
  })

  return config
end

H.apply_config = function(config)
  MiniAlign.config = config

  H.map('n', config.mappings.start, 'v:lua.MiniAlign.action_normal()', { expr = true, desc = 'Align' })
  H.map('x', config.mappings.start, '<Cmd>lua MiniAlign.action_visual()<CR>', { desc = 'Align' })
end

H.is_disabled = function() return vim.g.minialign_disable == true or vim.b.minialign_disable == true end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniAlign.config, vim.b.minialign_config or {}, config or {}) end

-- Work with options ----------------------------------------------------------
H.normalize_opts = function(opts)
  local res = vim.tbl_extend('force', H.get_config().options, opts or {})
  H.validate_opts(res)

  return res
end

H.normalize_splitter = function(splitter)
  if vim.is_callable(splitter) then return splitter end
  if type(splitter) ~= 'string' then H.error(H.msg_opts('opts', 'splitter', 'should be string or callable.')) end

  return function(s)
    local res = {}
    local n_total, n = s:len(), 0
    while n <= n_total do
      local sep_left, sep_right = H.string_find(s, splitter, n)
      if sep_left == nil then
        table.insert(res, s:sub(n, n_total))
        break
      end
      table.insert(res, s:sub(n, sep_left - 1))
      table.insert(res, s:sub(sep_left, sep_right))
      n = sep_right + 1
    end

    return res
  end
end

H.normalize_justify = function(justify)
  if vim.is_callable(justify) then return justify end
  if type(justify) == 'string' then justify = { justify } end
  if not H.is_string_array(justify) then
    H.error(H.msg_opts('opts', 'justify', 'should be string, array of strings or callable.'))
  end

  -- return function(splits, opts)
  --   local justify_method = H.slice_mod(justify, data.n_column)
  --   local justify_fun = H.justify_functions[justify_method]
  --
  --   local column_splits = data.splits_column
  --   local width, width_max = H.string_arr_width(column_splits)
  --
  --   local res = {}
  --   for i, s in ipairs(column_splits) do
  --     res[i] = justify_fun(s, width_max - width[i])
  --   end
  --   return res
  -- end
end

H.is_valid_opts = function(x, x_name, check_splitter)
  x_name = x_name or 'config.opts'
  if check_splitter == nil then check_splitter = false end

  if check_splitter and not (type(x.splitter) == 'string' or vim.is_callable(x.splitter)) then
    return false, H.msg_opts(x_name, 'splitter', 'should be string or callable.')
  end

  -- TODO: validate filter

  -- TODO: validate pre
  -- TODO: validate justify
  -- TODO: validate post
  -- TODO: validate concat

  return true
end

H.validate_opts = function(x, x_name, check_sep)
  local is_valid, msg = H.is_valid_opts(x, x_name, check_sep)
  if not is_valid then H.error(msg) end
end

H.msg_opts = function(opts_name, key, msg) H.error(([[`%s.%s` %s]]):format(opts_name, key, msg)) end

-- Work with splits -----------------------------------------------------------
-- TODO: !!!make `splits` class!!!
H.splits_get_width = function(splits)
  local width, width_col = {}, {}
  for i, arr in ipairs(splits) do
    width[i] = {}
    for j, s in ipairs(arr) do
      local w = vim.fn.strdisplaywidth(s)
      width[i][j] = w
      width_col[j] = math.max(width_col[j] or -math.huge, w)
    end
  end

  return { width = width, width_col = width_col }
end

-- Work with justify ----------------------------------------------------------
H.apply_justify = function(splits, opts) end

-- Work with filter -----------------------------------------------------------
H.make_expression_filter = function(expr)
  local is_loaded, f = pcall(function() return assert(loadstring('return ' .. expr)) end)
  if not (is_loaded and vim.is_callable(f)) then
    H.message(vim.inspect(expr) .. ' is not a valid filter expression.')
    return nil
  end

  return function(data)
    local context = setmetatable(
      { n = math.ceil(0.5 * data.n_column), N = math.ceil(0.5 * #data.splits_row) },
      { __index = _G }
    )
    debug.setfenv(f, context)
    return f()
  end
end

-- Work with regions ----------------------------------------------------------
H.get_current_region = function()
  local from_expr, to_expr = "'[", "']"
  if vim.tbl_contains({ 'v', 'V', '\22' }, vim.fn.mode(1)) then
    from_expr, to_expr = '.', 'v'
  end

  -- Add offset (*_pos[4]) to allow position go past end of line
  local from_pos = vim.fn.getpos(from_expr)
  local from = { line = from_pos[2], col = from_pos[3] + from_pos[4] }
  local to_pos = vim.fn.getpos(to_expr)
  local to = { line = to_pos[2], col = to_pos[3] + to_pos[4] }

  -- Ensure correct order
  if to.line < from.line or (to.line == from.line and to.col < from.col) then
    from, to = to, from
  end

  return { from = from, to = to }
end

H.get_current_reg_type = function()
  local mode = vim.fn.mode(1)
  if mode == 'v' or mode == 'no' or mode == 'nov' then return 'char' end
  if mode == '\22' or mode == 'no\22' then return 'block' end
  return 'line'
end

H.region_get_text = function(region, reg_type)
  local from, to = region.from, region.to

  if reg_type == 'char' then
    local to_col_offset = vim.o.selection == 'exclusive' and 1 or 0
    return vim.api.nvim_buf_get_text(0, from.line - 1, from.col - 1, to.line - 1, to.col - to_col_offset, {})
  end

  if reg_type == 'line' then return vim.api.nvim_buf_get_lines(0, from.line - 1, to.line, true) end

  if reg_type == 'block' then
    -- Use virtual columns to respect multibyte characters
    local left_virtcol, right_virtcol = H.region_virtcols(region)
    local n_cols = right_virtcol - left_virtcol + 1

    return vim.tbl_map(
      -- `strcharpart()` returns empty string for out of bounds span, so no
      -- need for extra columns check
      function(l) return vim.fn.strcharpart(l, left_virtcol - 1, n_cols) end,
      vim.api.nvim_buf_get_lines(0, from.line - 1, to.line, true)
    )
  end
end

H.region_set_text = function(region, reg_type, text)
  local from, to = region.from, region.to

  if reg_type == 'char' then
    local to_col_offset = vim.o.selection == 'exclusive' and 1 or 0
    -- vim.api.nvim_buf_set_text(0, from.line - 1, from.col - 1, to.line - 1, to.col - to_col_offset, text)
    H.set_text(from.line - 1, from.col - 1, to.line - 1, to.col - to_col_offset, text)
  end

  if reg_type == 'line' then H.set_lines(from.line - 1, to.line, text) end

  if reg_type == 'block' then
    if #text ~= (to.line - from.line + 1) then
      H.error('Number of replacement lines should fit the region in blockwise mode')
    end

    -- Use virtual columns to respect multibyte characters
    local left_virtcol, right_virtcol = H.region_virtcols(region)
    local lines = vim.api.nvim_buf_get_lines(0, from.line - 1, to.line, true)
    for i, l in ipairs(lines) do
      -- Use zero-based indexes
      local line_num = from.line + i - 2

      local n_virtcols = vim.fn.virtcol({ line_num + 1, '$' }) - 1
      -- Don't set text if all region is past end of line
      if left_virtcol <= n_virtcols then
        -- Make sure to not go past the line end
        local line_left_col, line_right_col = left_virtcol, math.min(right_virtcol, n_virtcols)

        -- Convert back to byte columns (columns are end-exclusive)
        local start_col, end_col = vim.fn.byteidx(l, line_left_col - 1), vim.fn.byteidx(l, line_right_col)
        start_col, end_col = math.max(start_col, 0), math.max(end_col, 0)

        -- vim.api.nvim_buf_set_text(0, line_num, start_col, line_num, end_col, { text[i] })
        H.set_text(line_num, start_col, line_num, end_col, { text[i] })
      end
    end
  end
end

H.region_virtcols = function(region)
  -- Account for multibyte characters and position past the line end
  local from_virtcol = H.pos_to_virtcol(region.from)
  local to_virtcol = H.pos_to_virtcol(region.to)

  local left_virtcol, right_virtcol = math.min(from_virtcol, to_virtcol), math.max(from_virtcol, to_virtcol)
  right_virtcol = right_virtcol - (vim.o.selection == 'exclusive' and 1 or 0)

  return left_virtcol, right_virtcol
end

H.pos_to_virtcol = function(pos)
  -- Account for position past line end
  local eol_col = vim.fn.col({ pos.line, '$' })
  if eol_col < pos.col then return vim.fn.virtcol({ pos.line, '$' }) + pos.col - eol_col end

  return vim.fn.virtcol({ pos.line, pos.col })
end

-- Work with user input -------------------------------------------------------
H.user_modifier = function()
  -- Get from user single character modifier
  local needs_help_msg = true
  vim.defer_fn(function()
    if not needs_help_msg then return end

    H.message('Enter modifier (single character)')
  end, 1000)
  local ok, char = pcall(vim.fn.getchar)
  needs_help_msg = false

  -- Terminate if couldn't get input (like with <C-c>) or it is `<Esc>`
  if not ok or char == 27 then return nil end

  if type(char) == 'number' then char = vim.fn.nr2char(char) end
  return char
end

H.user_input = function(prompt, text)
  -- Register temporary keystroke listener to distinguish between cancel with
  -- `<Esc>` and immediate `<CR>`.
  local on_key = vim.on_key or vim.register_keystroke_callback
  local was_cancelled = false
  on_key(function(key)
    if key == vim.api.nvim_replace_termcodes('<Esc>', true, true, true) then was_cancelled = true end
  end, H.ns_id.input)

  -- Ask for input
  local opts = { prompt = '(mini.align) ' .. prompt .. ': ', default = text or '' }
  -- Use `pcall` to allow `<C-c>` to cancel user input
  local ok, res = pcall(vim.fn.input, opts)

  -- Stop key listening
  on_key(nil, H.ns_id.input)

  if not ok or was_cancelled then return end
  return res
end

-- Predicates -----------------------------------------------------------------
H.is_string_array = function(x)
  if not vim.tbl_islist(x) then return false end
  for _, v in ipairs(x) do
    if type(v) ~= 'string' then return false end
  end
  return true
end

H.is_nonempty_region = function(x)
  if type(x) ~= 'table' then return false end
  local from_is_valid = type(x.from) == 'table' and type(x.from.line) == 'number' and type(x.from.col) == 'number'
  local to_is_valid = type(x.to) == 'table' and type(x.to.line) == 'number' and type(x.to.col) == 'number'
  return from_is_valid and to_is_valid
end

-- Utilities ------------------------------------------------------------------
H.message = function(msg)
  vim.cmd([[echon '']])
  vim.cmd('redraw')
  vim.cmd('echomsg ' .. vim.inspect('(mini.align) ' .. msg))
end

H.error = function(msg) error(string.format('(mini.align) %s', msg), 0) end

H.map = function(mode, key, rhs, opts)
  if key == '' then return end

  opts = vim.tbl_deep_extend('force', { noremap = true, silent = true }, opts or {})

  -- Use mapping description only in Neovim>=0.7
  if vim.fn.has('nvim-0.7') == 0 then opts.desc = nil end

  vim.api.nvim_set_keymap(mode, key, rhs, opts)
end

H.slice_mod = function(x, i) return x[((i - 1) % #x) + 1] end

H.string_arr_width = function(x)
  local width, width_max = {}, -math.huge
  for _, s in ipairs(x) do
    local w = vim.fn.strdisplaywidth(s)
    table.insert(width, w)
    if width_max < w then width_max = w end
  end
  return width, width_max
end

H.string_find = function(s, pattern, init)
  init = init or 1

  -- Match only start of full string if pattern says so.
  -- This is needed because `string.find()` doesn't do this.
  -- Example: `string.find('(aaa)', '^.*$', 4)` returns `4, 5`
  if pattern:sub(1, 1) == '^' and init > 1 then return nil end
  return string.find(s, pattern, init)
end
--- Set text in current buffer without affecting marks
---@private
H.set_text = function(start_row, start_col, end_row, end_col, replacement)
  local cmd = string.format(
    'lockmarks lua vim.api.nvim_buf_set_text(0, %d, %d, %d, %d, %s)',
    start_row,
    start_col,
    end_row,
    end_col,
    vim.inspect(replacement)
  )
  vim.cmd(cmd)
end

--- Set lines in current buffer without affecting marks
---@private
H.set_lines = function(start_row, end_row, replacement)
  local cmd = string.format(
    'lockmarks lua vim.api.nvim_buf_set_lines(0, %d, %d, true, %s)',
    start_row,
    end_row,
    vim.inspect(replacement)
  )
  vim.cmd(cmd)
end

return MiniAlign
