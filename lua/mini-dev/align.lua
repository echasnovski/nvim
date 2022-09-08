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
    c = function(opts) opts.justify = 'center' end,
    f = function(opts)
      -- TODO: update to use `pre_justify`
      local input = H.user_input('Enter filter expression')
      if input == nil then return end

      local filter = H.make_expression_filter(input)
      if filter == nil then return end

      opts.filter = filter
    end,
    h = function(opts) opts.justify = 'left' end,
    l = function(opts) opts.justify = 'right' end,
    m = function(opts)
      local input = H.user_input('Enter merger')
      if input == nil then return end
      opts.merger = input
    end,
    t = function(opts)
      -- TODO: simplify this
      local cur_pre_justify = opts.pre_justify
      opts.pre_justify = function(splits, _)
        cur_pre_justify(splits, _)
        splits.trim()
      end
      opts.merger = ' '
    end,
    p = function(opts)
      local cur_pre_justify = opts.pre_justify
      opts.pre_justify = function(splits, _)
        cur_pre_justify(splits, _)
        splits.pair()
      end
    end,
    ['?'] = function(opts)
      local input = H.user_input('Enter splitter Lua pattern')
      if input == nil then return end
      opts.splitter = input
    end,
    -- TODO: Add more pre-defined modifiers for common use cases (`=`, `,`, `<Space>`, '|')
    [' '] = function(opts) opts.splitter = '%s+' end,
    ['='] = function(opts)
      opts.splitter = '%p*=+[<>~]*'
      local cur_pre_justify = opts.pre_justify
      opts.pre_justify = function(splits, _)
        cur_pre_justify(splits, _)
        splits.trim()
      end
      opts.merger = ' '
    end,
  },

  -- TODO: use different data structure for `pre_justify` and `post_justify`
  -- (ideally table, but beware of deep extending during options normalization)
  -- to allow simple building of actions.
  -- Maybe should include step names for a interactive feedback.
  options = {
    pre_justify = function(_, _) end,
    justify = 'left',
    post_justify = function(_, _) end,
    merger = '',
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
  local splits = H.normalize_splitter(opts.splitter)(strings, opts)

  opts.pre_justify(splits, opts)
  H.normalize_justify(opts.justify)(splits, opts)
  opts.post_justify(splits, opts)

  return H.normalize_merger(opts.merger)(splits, opts)
end

MiniAlign.align_user = function()
  local modifiers = H.get_config().modifiers

  -- Use cache for dot-repreat
  local opts = H.cache.opts or H.normalize_opts({})
  -- TODO: Consider explicit stopping instead of "once splitter is defined"
  while opts.splitter == nil do
    -- TODO: Make some visual feedback about current options
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

--- Perfrom action in Normal mode
---
--- Used in Normal mode mapping. No need to use it directly.
MiniAlign.action_normal = function()
  H.cache = {}

  -- Set 'operatorfunc' which will be later called with appropriate marks set
  vim.cmd('set operatorfunc=v:lua.MiniAlign.align_user')
  return 'g@'
end

--- Perfrom action in Visual mode
---
--- Used in Visual mode mapping. No need to use it directly.
MiniAlign.action_visual = function()
  H.cache = {}

  -- Perform action and exit Visual mode
  MiniAlign.align_user()
  vim.cmd('normal! \27')
end

MiniAlign.as_splits = function(arr2d)
  if not H.can_be_splits(arr2d) then H.error('Input of `as_splits()` can not be converted to splits.') end

  local splits = vim.deepcopy(arr2d)
  local methods = {}

  -- Group cells into single string based on boolean mask.
  -- Can be used for filtering separators and sticking separator to its part.
  methods.group = function(mask, direction)
    direction = direction or 'left'
    for i, row in ipairs(splits) do
      local group_tables = H.group_by_mask(row, mask[i], direction)
      splits[i] = vim.tbl_map(table.concat, group_tables)
    end
  end

  methods.pair = function()
    local mask = splits.apply(function(_, data) return data.col % 2 == 0 end)
    splits.group(mask)
  end

  methods.trim = function(direction) splits.apply_inplace(H.trim_functions[direction or 'both']) end

  methods.get_dims = function()
    local n_cols = -math.huge
    for _, row in ipairs(splits) do
      n_cols = math.max(n_cols, #row)
    end
    return { row = #splits, col = n_cols }
  end

  methods.slice_row = function(i) return splits[i] end

  -- NOTE: output might not be an array (some rows can not have input column)
  -- Use `vim.tbl_keys()` and `vim.tbl_values()`
  methods.slice_col = function(j)
    return vim.tbl_map(function(row) return row[j] end, splits)
  end

  methods.apply = function(f)
    local res = {}
    for i, row in ipairs(splits) do
      res[i] = {}
      for j, s in ipairs(row) do
        res[i][j] = f(s, { row = i, col = j })
      end
    end
    return res
  end

  methods.apply_inplace = function(f)
    for i, row in ipairs(splits) do
      for j, s in ipairs(row) do
        splits[i][j] = f(s, { row = i, col = j })
      end
    end
  end

  return setmetatable(splits, { class = 'splits', __index = methods })
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

-- Pad functions for supported justify directions
H.pad_functions = {
  left = function(x, n_spaces) return string.format('%s%s', x, string.rep(' ', n_spaces)) end,
  center = function(x, n_spaces)
    local n_left = math.floor(0.5 * n_spaces)
    return string.format('%s%s%s', string.rep(' ', n_left), x, string.rep(' ', n_spaces - n_left))
  end,
  right = function(x, n_spaces) return string.format('%s%s', string.rep(' ', n_spaces), x) end,
}

-- Pad functions for last row cell (used to save user's trailing whitespace)
H.pad_last_functions = {
  left = function(x, _) return x end,
  center = function(x, n_spaces) return H.pad_functions.right(x, math.floor(0.5 * n_spaces)) end,
  right = H.pad_functions.right,
}

-- Trim functions
H.trim_functions = {
  left = function(x) return string.gsub(x, '^%s*', '') end,
  right = function(x) return string.gsub(x, '%s*$', '') end,
  both = function(x) return H.trim_functions.left(H.trim_functions.right(x)) end,
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

  return function(string_array, _)
    local res = {}
    for i, s in ipairs(string_array) do
      res[i] = {}
      local n_total, n = s:len(), 0
      while n <= n_total do
        local sep_left, sep_right = H.string_find(s, splitter, n)
        if sep_left == nil then
          table.insert(res[i], s:sub(n, n_total))
          break
        end
        table.insert(res[i], s:sub(n, sep_left - 1))
        table.insert(res[i], s:sub(sep_left, sep_right))
        n = sep_right + 1
      end
    end

    return MiniAlign.as_splits(res)
  end
end

H.normalize_justify = function(justify)
  if vim.is_callable(justify) then return justify end
  if type(justify) == 'string' then justify = { justify } end
  if not H.is_string_array(justify) then
    H.error(H.msg_opts('opts', 'justify', 'should be string, array of strings or callable.'))
  end

  return function(splits, _)
    -- Compute both cell width and maximum column widths
    local width, width_col = {}, {}
    for i, row in ipairs(splits) do
      width[i] = {}
      for j, s in ipairs(row) do
        local w = vim.fn.strdisplaywidth(s)
        width[i][j] = w
        width_col[j] = math.max(w, width_col[j] or -math.huge)
      end
    end

    -- Precompute padding functions (recycle `justify` array).
    -- Use separate padding functions for last and non-last cells to not
    -- possibly create extra trailing whitespace but preserve input one.
    local dims = splits.get_dims()
    local pad_funs, pad_last_funs = {}, {}
    for j = 1, dims.col do
      local justify_method = H.slice_mod(justify, j)
      pad_funs[j] = H.pad_functions[justify_method]
      pad_last_funs[j] = H.pad_last_functions[justify_method]
    end

    -- Pad cells to have same width across columns
    for i, row in ipairs(splits) do
      for j, s in ipairs(row) do
        local pad_f = j < #row and pad_funs[j] or pad_last_funs[j]
        local n_space = width_col[j] - width[i][j]
        splits[i][j] = pad_f(s, n_space)
      end
    end
  end
end

H.normalize_merger = function(merger)
  if vim.is_callable(merger) then return merger end
  if type(merger) == 'string' then merger = { merger } end
  if not H.is_string_array(merger) then
    H.error(H.msg_opts('opts', 'merger', 'should be string, array of strings or callable.'))
  end

  return function(splits, _)
    -- Precompute combination strings (recycle `merger` array)
    local dims = splits.get_dims()
    local combine_strings = {}
    for j = 1, dims.col - 1 do
      combine_strings[j] = H.slice_mod(merger, j)
    end

    -- Concat cells
    return vim.tbl_map(function(row) return H.concat_array(row, combine_strings) end, splits)
  end
end

H.is_valid_opts = function(x, x_name, check_splitter)
  x_name = x_name or 'config.opts'
  if check_splitter == nil then check_splitter = false end

  if check_splitter and not (type(x.splitter) == 'string' or vim.is_callable(x.splitter)) then
    return false, H.msg_opts(x_name, 'splitter', 'should be string or callable.')
  end

  -- TODO: validate pre_justify
  -- TODO: validate justify
  -- TODO: validate post_justify
  -- TODO: validate merger

  return true
end

H.validate_opts = function(x, x_name, check_sep)
  local is_valid, msg = H.is_valid_opts(x, x_name, check_sep)
  if not is_valid then H.error(msg) end
end

H.msg_opts = function(opts_name, key, msg) H.error(('`%s.%s` %s'):format(opts_name, key, msg)) end

-- Work with splits -----------------------------------------------------------
H.is_splits = function(x) return (getmetatable(x) or {}).class == 'splits' end

H.can_be_splits = function(x)
  for i = 1, #x do
    if not H.is_string_array(x[i]) then return false end
  end
  return true
end

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

H.group_by_mask = function(arr, mask, direction)
  local res, cur_group = {}, {}

  -- Construct actors based on direction
  local from, to, by = 1, #arr, 1
  local insert = function(t, v) table.insert(t, v) end
  if direction == 'right' then
    from, to, by = to, from, -1
    insert = function(t, v) table.insert(t, 1, v) end
  end

  -- Group
  for i = from, to, by do
    insert(cur_group, arr[i])
    if mask[i] or i == to then
      insert(res, cur_group)
      cur_group = {}
    end
  end

  return res
end

H.concat_array = function(arr, concat)
  local ext_arr = {}
  for i = 1, #arr - 1 do
    table.insert(ext_arr, arr[i])
    table.insert(ext_arr, concat[i])
  end
  table.insert(ext_arr, arr[#arr])
  return table.concat(ext_arr, '')
end

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
