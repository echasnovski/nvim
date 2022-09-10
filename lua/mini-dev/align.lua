-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO:
-- - Figure out a way to ignore areas during splitting. Probably, with
--   `gen_step.splitter`.
-- - Consider somehow ignore lines with not enough delimiters (probably won't
--   happen, but still). This can go well with something like `row ~= 2`
--   filtering (which squashes whole row 2 into single split).
-- - Consider explicit stopping instead of "once splitter is defined".
-- - Consider implementing live preview.
-- - Clean up code structure.
--
-- NOTEs:
-- - Filtering by last equal sign usually can be done with `n == (N - 1)`
--   (because there is usually something to the right of it).

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
---     - 'mini.align' doesn't distinguish splits from one another.
---     - 'junegunn/vim-easy-align' implements special filtering by delimiter
---       number in a row. 'mini.align' has builtin filtering based on Lua code
---       supplied by user in modifier phase. See `MiniAlign.config.modifiers.f`.
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
    ['c'] = function(opts) opts.justify = 'center' end,
    ['f'] = function(opts)
      local input = H.user_input('Enter filter expression')
      table.insert(opts.pre_steps, MiniAlign.gen_step.filter(input))
    end,
    ['l'] = function(opts) opts.justify = 'left' end,
    ['m'] = function(opts)
      local input = H.user_input('Enter merger')
      opts.merger = input or opts.merger
    end,
    ['t'] = function(opts) table.insert(opts.pre_steps, MiniAlign.gen_step.trim()) end,
    ['p'] = function(opts) table.insert(opts.pre_steps, MiniAlign.gen_step.pair()) end,
    ['r'] = function(opts) opts.justify = 'right' end,
    ['?'] = function(opts)
      local input = H.user_input('Enter splitter Lua pattern')
      opts.splitter = input or opts.splitter
    end,
    [' '] = function(opts) opts.splitter = '%s+' end,
    [','] = function(opts)
      opts.splitter = ','
      table.insert(opts.pre_steps, MiniAlign.gen_step.trim())
      table.insert(opts.pre_steps, MiniAlign.gen_step.pair())
      opts.merger = ' '
    end,
    ['|'] = function(opts)
      opts.splitter = '|'
      table.insert(opts.pre_steps, MiniAlign.gen_step.trim())
      opts.merger = ' '
    end,
    ['='] = function(opts)
      opts.splitter = '%p*=+[<>~]*'
      table.insert(opts.pre_steps, MiniAlign.gen_step.trim())
      opts.merger = ' '
    end,
  },

  options = {
    pre_steps = {},
    justify = 'left',
    post_steps = {},
    merger = '',
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
MiniAlign.align_strings = function(strings, opts)
  -- Validate arguments
  if not H.is_array_of(strings, H.is_string) then
    H.error('First argument of `MiniAlign.align_strings()` should be array of strings.')
  end
  local norm_opts = H.normalize_opts(opts, 'opts', true)

  -- Split string
  local splits = norm_opts.splitter.action(strings)
  if not H.is_splits(splits) then
    if H.can_be_splits(splits) then
      splits = MiniAlign.as_splits(splits)
    else
      H.error('Output of `splitter` step should be convertable to splits. See `:h MiniAlign.as_splits()`.')
    end
  end

  -- Apply 'pre' steps
  for _, step in ipairs(norm_opts.pre_steps) do
    H.apply_step(step, splits)
  end

  -- Justify
  H.apply_step(norm_opts.justify, splits)

  -- Apply 'post' steps
  for _, step in ipairs(norm_opts.post_steps) do
    H.apply_step(step, splits)
  end

  -- Merge splits
  local new_strings = norm_opts.merger.action(splits)
  if not H.is_array_of(new_strings, H.is_string) then H.error('Output of `merger` step should be array of strings.') end
  return new_strings
end

MiniAlign.align_user = function()
  local modifiers = H.get_config().modifiers

  -- Use cache for dot-repreat
  local opts = H.cache.opts or H.normalize_opts()
  while opts.splitter == nil do
    local id = H.user_modifier(opts)
    if id == nil then return end

    local mod = modifiers[id]
    if mod == nil then
      -- Use supplied identifier as splitter pattern
      opts.splitter = vim.pesc(id)
    else
      -- Modifier should change input `opts` table in place
      local ok, _ = pcall(modifiers[id], opts)
      if not ok then H.message(string.format('Modifier %s should be properly callable.', vim.inspect(id))) end

      -- Normalize options while validating its correctness
      opts = H.normalize_opts(opts)
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

--- Convert 2d array to splits
MiniAlign.as_splits = function(arr2d)
  local ok, msg = H.can_be_splits(arr2d)
  if not ok then H.error('Input of `as_splits()`' .. msg) end

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

  methods.trim = function(direction, indent)
    direction = direction or 'both'
    indent = indent or 'keep'

    -- Verify arguments
    local trim_fun = H.trim_functions[direction]
    if not vim.is_callable(trim_fun) then
      H.error('`direction` should be one of ' .. table.concat(vim.tbl_keys(H.trim_functions), ', ') .. '.')
    end

    local indent_fun = H.indent_functions[indent]
    if not vim.is_callable(indent_fun) then
      H.error('`direction` should be one of ' .. table.concat(vim.tbl_keys(H.indent_functions), ', ') .. '.')
    end

    -- Compute indentation to restore later
    local row_indent = vim.tbl_map(function(row) return row[1]:match('^(%s*)') end, splits)
    row_indent = indent_fun(row_indent)

    -- Trim
    splits.apply_inplace(trim_fun)

    -- Restore indentation
    for i, row in ipairs(splits) do
      row[1] = string.format('%s%s', row_indent[i], row[1])
    end
  end

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

--- Generate common action steps
MiniAlign.gen_step = {}

MiniAlign.gen_step.trim = function(direction, indent)
  return MiniAlign.new_step('trim', function(splits) splits.trim(direction, indent) end)
end

MiniAlign.gen_step.pair = function()
  return MiniAlign.new_step('pair', function(splits) splits.pair() end)
end

MiniAlign.gen_step.filter = function(expr)
  local action = H.make_filter_action(expr)
  if action == nil then return end
  return MiniAlign.new_step('filter', action)
end

--- Create a step
MiniAlign.new_step = function(name, action) return { name = name, action = action } end

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
-- Allow to not add trailing whitespace
H.pad_functions = {
  left = function(x, n_spaces, no_trailing)
    if no_trailing then return x end
    return string.format('%s%s', x, string.rep(' ', n_spaces))
  end,
  center = function(x, n_spaces, no_trailing)
    local n_left = math.floor(0.5 * n_spaces)
    local n_right = no_trailing and 0 or (n_spaces - n_left)
    return string.format('%s%s%s', string.rep(' ', n_left), x, string.rep(' ', n_right))
  end,
  right = function(x, n_spaces) return string.format('%s%s', string.rep(' ', n_spaces), x) end,
}

-- Trim functions
H.trim_functions = {
  left = function(x) return string.gsub(x, '^%s*', '') end,
  right = function(x) return string.gsub(x, '%s*$', '') end,
  both = function(x) return H.trim_functions.left(H.trim_functions.right(x)) end,
}

-- Indentation functions
H.indent_functions = {
  keep = function(indent_arr) return indent_arr end,
  max = function(indent_arr)
    local max_indent = indent_arr[1]
    for i = 2, #indent_arr do
      max_indent = (max_indent:len() < indent_arr[i]:len()) and indent_arr[i] or max_indent
    end
    return vim.tbl_map(function() return max_indent end, indent_arr)
  end,
  min = function(indent_arr)
    local min_indent = indent_arr[1]
    for i = 2, #indent_arr do
      min_indent = (indent_arr[i]:len() < min_indent:len()) and indent_arr[i] or min_indent
    end
    return vim.tbl_map(function() return min_indent end, indent_arr)
  end,
  none = function(indent_arr)
    return vim.tbl_map(function() return '' end, indent_arr)
  end,
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
H.is_valid_opts = function(x, x_name, check_splitter)
  x_name = x_name or 'config.opts'
  if check_splitter == nil then check_splitter = false end

  local is_common_opt = function(y) return H.is_string(y) or H.is_array_of(y, H.is_string) or H.is_step(y) end
  local common_opt_msg = 'should be string, array of strings, or step (see `:h MiniAlign.new_step()`).'

  if check_splitter and not is_common_opt(x.splitter) then
    return false, H.msg_bad_opts(x_name, 'splitter', common_opt_msg)
  end

  if not H.is_array_of(x.pre_steps, H.is_step) then
    return false, H.msg_bad_opts(x_name, 'pre_steps', 'should be array of steps (see `:h MiniAlign.new_step()`).')
  end

  if not is_common_opt(x.justify) then return false, H.msg_bad_opts(x_name, 'justify', common_opt_msg) end

  if not H.is_array_of(x.post_steps, H.is_step) then
    return false, H.msg_bad_opts(x_name, 'post_steps', 'should be array of steps (see `:h MiniAlign.new_step()`).')
  end

  if not is_common_opt(x.merger) then return false, H.msg_bad_opts(x_name, 'merger', common_opt_msg) end

  return true
end

H.validate_opts = function(x, x_name, check_splitter)
  local is_valid, msg = H.is_valid_opts(x, x_name, check_splitter)
  if not is_valid then H.error(msg) end
end

H.normalize_opts = function(opts, opts_name, check_splitter)
  -- Infer all defaults from module config
  local res = vim.tbl_deep_extend('force', H.get_config().options, opts or {})
  -- Deep copy to ensure that table values will not be affected (because if a
  -- table value is present only in one input, it is taken as is).
  res = vim.deepcopy(res)

  H.validate_opts(res, opts_name, check_splitter)

  res.splitter = H.normalize_splitter(res.splitter)
  res.justify = H.normalize_justify(res.justify)
  res.merger = H.normalize_merger(res.merger)

  return res
end

H.normalize_splitter = function(splitter)
  if splitter == nil or H.is_step(splitter) then return splitter end

  local step_name = vim.inspect(splitter)
  if type(splitter) == 'string' then splitter = { splitter } end

  local action = function(string_array, _)
    local res = {}
    for i, s in ipairs(string_array) do
      res[i] = {}
      local n_total, n, j = s:len(), 0, 0
      while n <= n_total do
        -- Take next splitter (recycle `splitter` array)
        j = j + 1
        local cur_splitter = H.slice_mod(splitter, j)
        local sep_left, sep_right = H.string_find(s, cur_splitter, n)

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

  return MiniAlign.new_step(step_name, action)
end

H.normalize_justify = function(justify)
  if justify == nil or H.is_step(justify) then return justify end

  local step_name = vim.inspect(justify)
  if type(justify) == 'string' then justify = { justify } end

  local action = function(splits, _)
    -- Precompute padding functions (recycle `justify` array)
    local dims = splits.get_dims()
    local pad_funs = {}
    for j = 1, dims.col do
      pad_funs[j] = H.pad_functions[H.slice_mod(justify, j)]
    end

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

    -- Pad cells to have same width across columns
    for i, row in ipairs(splits) do
      for j, s in ipairs(row) do
        local n_space = width_col[j] - width[i][j]
        -- Don't add trailing whitespace for last column
        splits[i][j] = pad_funs[j](s, n_space, j == #row)
      end
    end
  end

  return MiniAlign.new_step(step_name, action)
end

H.normalize_merger = function(merger)
  if merger == nil or H.is_step(merger) then return merger end

  local step_name = vim.inspect(merger)
  if type(merger) == 'string' then merger = { merger } end

  local action = function(splits, _)
    -- Precompute combination strings (recycle `merger` array)
    local dims = splits.get_dims()
    local combine_strings = {}
    for j = 1, dims.col - 1 do
      combine_strings[j] = H.slice_mod(merger, j)
    end

    -- Concat non-empty cells (empty cells add nothing but extra merger)
    return vim.tbl_map(function(row)
      local row_no_empty = vim.tbl_filter(function(s) return s ~= '' end, row)
      return H.concat_array(row_no_empty, combine_strings)
    end, splits)
  end

  return MiniAlign.new_step(step_name, action)
end

H.opts_to_string = function(opts)
  -- Assumes `opts` are normalized (all values are converted to steps)
  local res_tbl = {}

  if opts.splitter ~= nil then table.insert(res_tbl, 'Split: ' .. opts.splitter.name) end

  if #opts.pre_steps > 0 then
    local pre_names = vim.tbl_map(function(x) return x.name end, opts.pre_steps)
    table.insert(res_tbl, 'Pre: ' .. table.concat(pre_names, ', '))
  end

  if opts.justify ~= nil then table.insert(res_tbl, 'Justify: ' .. opts.justify.name) end

  if #opts.post_steps > 0 then
    local post_names = vim.tbl_map(function(x) return x.name end, opts.post_steps)
    table.insert(res_tbl, 'Post: ' .. table.concat(post_names, ', '))
  end

  if opts.merger ~= nil and opts.merger.name ~= '""' then table.insert(res_tbl, 'Merger: ' .. opts.merger.name) end

  return table.concat(res_tbl, '; ')
end

H.msg_bad_opts = function(opts_name, key, msg) H.error(('`%s.%s` %s'):format(opts_name, key, msg)) end

-- Work with steps ------------------------------------------------------------
H.apply_step = function(step, splits)
  step.action(splits)

  if not H.is_splits(splits) then
    local msg = string.format(
      'Step `%s` should modify splits in place and preserve their structure. See `:h MiniAlign.as_splits`.',
      step.name
    )
    H.error(msg)
  end
end

-- Work with splits -----------------------------------------------------------
H.is_splits = function(x) return (getmetatable(x) or {}).class == 'splits' end

H.can_be_splits = function(x)
  if type(x) ~= 'table' then return false, 'should be table' end
  for i = 1, #x do
    if not H.is_array_of(x[i], H.is_string) then return false, 'values should be an array of strings' end
  end
  return true
end

-- Work with filter -----------------------------------------------------------
H.make_filter_action = function(expr)
  if expr == nil then return nil end

  local is_loaded, f = pcall(function() return assert(loadstring('return ' .. expr)) end)
  if not (is_loaded and vim.is_callable(f)) then
    H.message(vim.inspect(expr) .. ' is not a valid filter expression.')
    return nil
  end

  local predicate = function(data)
    local context = setmetatable(data, { __index = _G })
    debug.setfenv(f, context)
    return f()
  end

  return function(splits)
    local mask = {}
    local data = { ROW = #splits }
    for i, row in ipairs(splits) do
      data.row = i
      mask[i] = {}
      for j, s in ipairs(row) do
        data.col, data.COL = j, #row
        data.s = s

        -- Current and total number of pairs
        data.n = math.ceil(0.5 * j)
        data.N = math.ceil(0.5 * #row)

        mask[i][j] = predicate(data)
      end
    end

    splits.group(mask)
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
H.user_modifier = function(opts)
  -- Get from user single character modifier
  local needs_help_msg = true
  local delay = H.cache.msg_shown and 0 or 1000
  vim.defer_fn(function()
    if not needs_help_msg then return end

    H.message(H.opts_to_string(opts) .. '. Enter modifier (single character)', true)
    H.cache.msg_shown = true
  end, delay)
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
H.is_array_of = function(x, predicate)
  if not vim.tbl_islist(x) then return false end
  for _, v in ipairs(x) do
    if not predicate(v) then return false end
  end
  return true
end

H.is_step = function(x) return type(x) == 'table' and type(x.name) == 'string' and vim.is_callable(x.action) end

H.is_string = function(v) return type(v) == 'string' end

H.is_nonempty_region = function(x)
  if type(x) ~= 'table' then return false end
  local from_is_valid = type(x.from) == 'table' and type(x.from.line) == 'number' and type(x.from.col) == 'number'
  local to_is_valid = type(x.to) == 'table' and type(x.to.line) == 'number' and type(x.to.col) == 'number'
  return from_is_valid and to_is_valid
end

-- Utilities ------------------------------------------------------------------
H.message = function(msg, avoid_hit_enter_prompt)
  local out = '(mini.align) ' .. msg
  local out_width = vim.fn.strdisplaywidth(out)
  if avoid_hit_enter_prompt and vim.v.echospace <= out_width then
    local target_width = (vim.v.echospace - 1) - 3
    out = '...' .. vim.fn.strcharpart(out, out_width - target_width, target_width)
  end

  vim.cmd([[echon '']])
  vim.cmd('redraw')
  vim.cmd('echomsg ' .. vim.inspect(out))
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

H.concat_array = function(target_arr, concat_arr)
  local ext_arr = {}
  for i = 1, #target_arr - 1 do
    table.insert(ext_arr, target_arr[i])
    table.insert(ext_arr, concat_arr[i])
  end
  table.insert(ext_arr, target_arr[#target_arr])
  return table.concat(ext_arr, '')
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
