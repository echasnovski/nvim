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

  -- Temporary action for testing
  return vim.tbl_map(function(x) return table.concat(x, '-') end, splits)

  -- Modify string parts

  -- Concatenate splits
  -- return vim.tbl_map(function(x) return table.concat(x, opts.concat) end, splits)
end

MiniAlign.align_region = function(region, reg_type, opts)
  -- Validate arguments
  region = region or H.get_default_region()
  if not H.is_nonempty_region(region) then
    H.error('First argument of `MiniAlign.align_region()` should be non-empty region.')
  end

  reg_type = reg_type or H.get_default_reg_type()
  if not vim.tbl_contains({ 'char', 'line', 'block' }, reg_type) then
    H.error([[Second argument of `MiniAlign.align_region()` should be one of 'char', 'line', 'block'.]])
  end

  opts = H.normalize_opts(opts)

  -- Process region
  local strings = H.region_get_text(region, reg_type)
  local strings_aligned = MiniAlign.align_strings(strings, opts)
  H.region_set_text(region, reg_type, strings_aligned)
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

  -- H.map('n', config.mappings.start, 'v:lua.MiniAlign.operator()', { expr = true, desc = 'Align' })
  H.map(
    'x',
    config.mappings.start,
    [[<Cmd>lua MiniAlign.align_region(); vim.cmd('normal! \27')<CR>]],
    { desc = 'Align' }
  )
end

H.is_disabled = function() return vim.g.minialign_disable == true or vim.b.minialign_disable == true end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniAlign.config, vim.b.minialign_config or {}, config or {}) end

-- Work with filter -----------------------------------------------------------
H.make_expression_filter = function(expr)
  local is_loaded, f = pcall(function() return assert(loadstring('return ' .. expr)) end)
  if not (is_loaded and vim.is_callable(f)) then
    H.message(vim.inspect(expr) .. ' is not a valid filter expression.')
    return nil
  end

  return function(data)
    local context = setmetatable(
      { n = math.ceil(0.5 * data.n_current), N = math.ceil(0.5 * data.n_total) },
      { __index = _G }
    )
    debug.setfenv(f, context)
    return f()
  end
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

-- Work with options ----------------------------------------------------------
H.normalize_opts = function(opts)
  local res = vim.tbl_extend('force', H.get_config().options, opts or {})
  H.validate_opts(res)

  return res
end

H.normalize_splitter = function(splitter)
  if vim.is_callable(splitter) then return splitter end
  if type(splitter) ~= 'string' then H.error(H.msg_opts('opts', 'splitter', 'should be string or function.')) end

  return function(s)
    local res = {}
    local n_total, n = s:len(), 0
    while n <= n_total do
      local sep_left, sep_right = s:find(splitter, n)
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

-- Work with regions ----------------------------------------------------------
H.get_default_region = function()
  local from_expr, to_expr = "'[", "']"
  if vim.tbl_contains({ 'v', 'V', '\22' }, vim.fn.mode(1)) then
    from_expr, to_expr = '.', 'v'
  end

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

H.get_default_reg_type = function()
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
    -- TODO: Implement. Should respect multibyte characters
    return {}
  end
  return {}
end

H.region_set_text = function(region, reg_type, text)
  -- TODO: Should not remove marks (see 'mini.comment' and `lockmarks`)
  local from, to = region.from, region.to
  if reg_type == 'char' then
    local to_col_offset = vim.o.selection == 'exclusive' and 1 or 0
    return vim.api.nvim_buf_set_text(0, from.line - 1, from.col - 1, to.line - 1, to.col - to_col_offset, text)
  end
  if reg_type == 'line' then return vim.api.nvim_buf_set_lines(0, from.line - 1, to.line, true, text) end
  if reg_type == 'block' then
    -- TODO: Implement. Should respect multibyte characters
    return
  end
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

return MiniAlign
