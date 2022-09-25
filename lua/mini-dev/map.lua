-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO:
-- Code:
-- - Validate options.
-- - Write window logic.
-- - Think through integrations API.
-- - Handle all values of `col_bits` and `row_bits` in `gen_symbols`.
-- - Refactor and add relevant comments.
--
-- Tests:
--
-- Documentation:

-- Documentation ==============================================================
--- Current buffer overview.
---
--- Features:
---
--- # Setup~
---
--- This module needs a setup with `require('mini.map').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniMap`
--- which you can use for scripting or manually (with `:lua MiniMap.*`).
---
--- See |MiniMap.config| for available config settings.
---
--- You can override runtime config settings (like `config.modifiers`) locally
--- to buffer inside `vim.b.minimap_config` which should have same structure
--- as `MiniMap.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons~
---
--- - 'wfxr/minimap.vim':
---
--- # Disabling~
---
--- To disable, set `g:minimap_disable` (globally) or `b:minimap_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.map
---@tag MiniMap

-- Module definition ==========================================================
MiniMap = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniMap.config|.
---
---@usage `require('mini.map').setup({})` (replace `{}` with your `config` table)
MiniMap.setup = function(config)
  -- Export module
  _G.MiniMap = MiniMap

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
MiniMap.config = {
  -- Window options
  window = {},

  -- Other options
  options = {
    symbols = nil,
  },
}
--minidoc_afterlines_end

MiniMap.current = {}

-- Module functionality =======================================================
MiniMap.encode_strings = function(strings, opts)
  if not H.is_array_of(strings, H.is_string) then
    H.error('First argument of `encode_strings()` should be array of strings.')
  end
  opts = vim.tbl_deep_extend('force', { n_rows = math.huge, n_cols = math.huge, trim = true }, opts or {})
  opts.symbols = opts.symbols or MiniMap.gen_symbols.block(2, 3)
  H.validate_symbols(opts.symbols)

  local mask = H.mask_from_strings(strings, opts)
  mask = H.mask_rescale(mask, opts)
  local strings_encoded = H.mask_to_symbols(mask, opts)
  if opts.trim then strings_encoded = vim.tbl_map(function(s) return s:gsub('%s*$', '') end, strings_encoded) end

  return strings_encoded
end

MiniMap.gen_symbols = {}

MiniMap.gen_symbols.block = function(col_bits, row_bits)
  local res = H.block_symbols[col_bits .. 'x' .. row_bits]
  res.col_bits, res.row_bits = col_bits, row_bits
  return res
end

MiniMap.gen_symbols.dot = function(col_bits, row_bits)
  local res = H.dot_symbols[col_bits .. 'x' .. row_bits]
  res.col_bits, res.row_bits = col_bits, row_bits
  return res
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniMap.config

-- Cache for various operations
H.cache = {}

--stylua: ignore start
H.block_symbols = {}

H.block_symbols['2x3'] = {
  ' ', '🬀', '🬁', '🬂', '🬃', '🬄', '🬅', '🬆', '🬇', '🬈', '🬉', '🬊', '🬋', '🬌', '🬍', '🬎',
  '🬏', '🬐', '🬑', '🬒', '🬓', '▌', '🬔', '🬕', '🬖', '🬗', '🬘', '🬙', '🬚', '🬛', '🬜', '🬝',
  '🬞', '🬟', '🬠', '🬡', '🬢', '🬣', '🬤', '🬥', '🬦', '🬧', '▐', '🬨', '🬩', '🬪', '🬫', '🬬',
  '🬭', '🬮', '🬯', '🬰', '🬱', '🬲', '🬳', '🬴', '🬵', '🬶', '🬷', '🬸', '🬹', '🬺', '🬻', '█',
}

H.dot_symbols = {}

H.dot_symbols['2x4'] = {
  ' ', '⠁', '⠈', '⠉', '⠂', '⠃', '⠊', '⠋', '⠐', '⠑', '⠘', '⠙', '⠒', '⠓', '⠚', '⠛',
  '⠄', '⠅', '⠌', '⠍', '⠆', '⠇', '⠎', '⠏', '⠔', '⠕', '⠜', '⠝', '⠖', '⠗', '⠞', '⠟',
  '⠠', '⠡', '⠨', '⠩', '⠢', '⠣', '⠪', '⠫', '⠰', '⠱', '⠸', '⠹', '⠲', '⠳', '⠺', '⠻',
  '⠤', '⠥', '⠬', '⠭', '⠦', '⠧', '⠮', '⠯', '⠴', '⠵', '⠼', '⠽', '⠶', '⠷', '⠾', '⠿',
  '⡀', '⡁', '⡈', '⡉', '⡂', '⡃', '⡊', '⡋', '⡐', '⡑', '⡘', '⡙', '⡒', '⡓', '⡚', '⡛',
  '⡄', '⡅', '⡌', '⡍', '⡆', '⡇', '⡎', '⡏', '⡔', '⡕', '⡜', '⡝', '⡖', '⡗', '⡞', '⡟',
  '⡠', '⡡', '⡨', '⡩', '⡢', '⡣', '⡪', '⡫', '⡰', '⡱', '⡸', '⡹', '⡲', '⡳', '⡺', '⡻',
  '⡤', '⡥', '⡬', '⡭', '⡦', '⡧', '⡮', '⡯', '⡴', '⡵', '⡼', '⡽', '⡶', '⡷', '⡾', '⡿',
  '⢀', '⢁', '⢈', '⢉', '⢂', '⢃', '⢊', '⢋', '⢐', '⢑', '⢘', '⢙', '⢒', '⢓', '⢚', '⢛',
  '⢄', '⢅', '⢌', '⢍', '⢆', '⢇', '⢎', '⢏', '⢔', '⢕', '⢜', '⢝', '⢖', '⢗', '⢞', '⢟',
  '⢠', '⢡', '⢨', '⢩', '⢢', '⢣', '⢪', '⢫', '⢰', '⢱', '⢸', '⢹', '⢲', '⢳', '⢺', '⢻',
  '⢤', '⢥', '⢬', '⢭', '⢦', '⢧', '⢮', '⢯', '⢴', '⢵', '⢼', '⢽', '⢶', '⢷', '⢾', '⢿',
  '⣀', '⣁', '⣈', '⣉', '⣂', '⣃', '⣊', '⣋', '⣐', '⣑', '⣘', '⣙', '⣒', '⣓', '⣚', '⣛',
  '⣄', '⣅', '⣌', '⣍', '⣆', '⣇', '⣎', '⣏', '⣔', '⣕', '⣜', '⣝', '⣖', '⣗', '⣞', '⣟',
  '⣠', '⣡', '⣨', '⣩', '⣢', '⣣', '⣪', '⣫', '⣰', '⣱', '⣸', '⣹', '⣲', '⣳', '⣺', '⣻',
  '⣤', '⣥', '⣬', '⣭', '⣦', '⣧', '⣮', '⣯', '⣴', '⣵', '⣼', '⣽', '⣶', '⣷', '⣾', '⣿',
}
--stylua: ignore end

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    window = { config.window, 'table' },
    options = { config.options, 'table' },
  })

  return config
end

H.apply_config = function(config) MiniMap.config = config end

H.is_disabled = function() return vim.g.minimap_disable == true or vim.b.minimap_disable == true end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniMap.config, vim.b.minimap_config or {}, config or {}) end

-- Work with mask --------------------------------------------------------------
---@param strings table Array of strings
---@return table Non-whitespace mask, boolean 2d array. Each row corresponds to
---   string, each column - to whether character with that number is a
---   non-whitespace. Respects multibyte characters.
---@private
H.mask_from_strings = function(strings, _)
  local tab_space = string.rep(' ', vim.o.tabstop)

  local res = {}
  for i, s in ipairs(strings) do
    local s_ext = s:gsub('\t', tab_space)
    local n_cols = vim.str_utfindex(s_ext)
    local mask_row = H.tbl_repeat(true, n_cols)
    s_ext:gsub('()%s', function(j) mask_row[vim.str_utfindex(s_ext, j)] = false end)
    res[i] = mask_row
  end

  return res
end

---@param mask table Boolean 2d array.
---@return table Boolean 2d array rescaled to be shown by symbols:
---   `opts.n_rows` lines and `opts.n_cols` within a row.
---@private
H.mask_rescale = function(mask, opts)
  -- Infer output number of rows and columns. Should be multiples of
  -- `symbols.row_bits` and `symbols.col_bits` respectively.
  local n_rows = #mask
  local n_cols = 0
  for _, m_row in ipairs(mask) do
    n_cols = math.max(n_cols, #m_row)
  end

  local res_n_rows = opts.symbols.row_bits * math.min(math.ceil(n_rows / opts.symbols.row_bits), opts.n_rows)
  local res_n_cols = opts.symbols.col_bits * math.min(math.ceil(n_cols / opts.symbols.col_bits), opts.n_cols)

  -- Downscale
  local res = {}
  for i = 1, res_n_rows do
    res[i] = H.tbl_repeat(false, res_n_cols)
  end

  local rows_coeff, cols_coeff = res_n_rows / n_rows, res_n_cols / n_cols

  for i, m_row in ipairs(mask) do
    for j, m in ipairs(m_row) do
      local res_i = math.floor((i - 1) * rows_coeff) + 1
      local res_j = math.floor((j - 1) * cols_coeff) + 1
      -- Downscaled block value will be `true` if at least a single element
      -- within it is `true`
      res[res_i][res_j] = m or res[res_i][res_j]
    end
  end

  return res
end

--- Apply sliding window (with `symbols.col_bits` columns and
--- `symbols.row_bits` rows) without overlap. Each application converts boolean
--- mask to symbol assuming symbols are sorted as if dark spots (read left to
--- right within row, then top to bottom) are bits in binary notation (`true` -
--- 1, `false` - 0).
---
---@param mask table Boolean 2d array to be shown with symbols.
---@return table Array of strings representing input `mask`.
---@private
H.mask_to_symbols = function(mask, opts)
  local symbols = opts.symbols
  local row_bits, col_bits = symbols.row_bits, symbols.col_bits

  local powers_of_two = {}
  for i = 0, (row_bits * col_bits - 1) do
    powers_of_two[i] = 2 ^ i
  end

  local symbols_n_rows = math.ceil(#mask / row_bits)
  -- Assumes rectangular table
  local symbols_n_cols = math.ceil(#mask[1] / col_bits)

  -- Compute symbols array indexes (start from zero)
  local symbol_ind = {}
  for i = 1, symbols_n_rows do
    symbol_ind[i] = H.tbl_repeat(0, symbols_n_cols)
  end

  local rows_coeff, cols_coeff = symbols_n_rows / #mask, symbols_n_cols / #mask[1]

  for i = 0, #mask - 1 do
    local row = mask[i + 1]
    for j = 0, #row - 1 do
      local two_power = (i % row_bits) * col_bits + (j % col_bits)
      local to_add = row[j + 1] and powers_of_two[two_power] or 0
      local sym_i = math.floor(i * rows_coeff) + 1
      local sym_j = math.floor(j * cols_coeff) + 1
      symbol_ind[sym_i][sym_j] = symbol_ind[sym_i][sym_j] + to_add
    end
  end

  -- Construct symbols strings
  local res = {}
  for i, row in ipairs(symbol_ind) do
    local syms = vim.tbl_map(function(id) return symbols[id + 1] end, row)
    res[i] = table.concat(syms)
  end

  return res
end

-- Predicates ------------------------------------------------------------------
H.is_array_of = function(x, predicate)
  if not vim.tbl_islist(x) then return false end
  for _, v in ipairs(x) do
    if not predicate(v) then return false end
  end
  return true
end

H.is_string = function(x) return type(x) == 'string' end

H.is_symbols = function(x)
  if type(x) ~= 'table' then return false, '`symbols` should be table.' end
  if type(x.col_bits) ~= 'number' then return false, '`symbols.col_bits` should be number.' end
  if type(x.row_bits) ~= 'number' then return false, '`symbols.row_bits` should be number.' end

  local two_power = x.col_bits * x.row_bits
  for i = 1, 2 ^ two_power do
    if type(x[i]) ~= 'string' then return false, string.format('`symbols[%d]` should be string', i) end
  end

  return true
end

H.validate_symbols = function(x)
  local ok, msg = H.is_symbols(x)
  if not ok then H.error(msg) end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.map) %s', msg), 0) end

H.tbl_repeat = function(x, n)
  local res = {}
  for _ = 1, n do
    table.insert(res, x)
  end
  return res
end

return MiniMap
