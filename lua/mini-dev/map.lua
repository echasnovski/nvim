-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO:
-- Code:
-- - Implement `toggle_focus()`.
-- - Think through integrations API.
-- - Think about using it in Inser mode.
-- - Think about how to make encoding so that change in one place of buffer has
--   small to none effect on the other encoded lines. Probably, is not
--   feasible, but who knows.
-- - Handle all possible/reasonable resolutions in `gen_encode_symbols`.
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

  -- Module behavior
  vim.api.nvim_exec(
    [[augroup MiniStarter
        au!
        au BufEnter,TextChanged,TextChangedI * lua MiniMap.on_content_change()
        au CursorMoved,CursorMovedI,WinScrolled * lua MiniMap.on_view_change()
      augroup END]],
    false
  )

  -- Create highlighting
  vim.api.nvim_exec(
    [[hi default link MiniMapSignView Delimiter
      hi default link MiniMapSignLine Title]],
    false
  )
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Options ~
MiniMap.config = {
  -- Highlight integrations
  integrations = {},

  -- Symbols used to display data
  symbols = {
    current_line = '█',
    current_view = '┃',
    encode = {
      ' ', '🬀', '🬁', '🬂', '🬃', '🬄', '🬅', '🬆', '🬇', '🬈', '🬉', '🬊', '🬋', '🬌', '🬍', '🬎',
      '🬏', '🬐', '🬑', '🬒', '🬓', '▌', '🬔', '🬕', '🬖', '🬗', '🬘', '🬙', '🬚', '🬛', '🬜', '🬝',
      '🬞', '🬟', '🬠', '🬡', '🬢', '🬣', '🬤', '🬥', '🬦', '🬧', '▐', '🬨', '🬩', '🬪', '🬫', '🬬',
      '🬭', '🬮', '🬯', '🬰', '🬱', '🬲', '🬳', '🬴', '🬵', '🬶', '🬷', '🬸', '🬹', '🬺', '🬻', '█',
      resolution = { row = 3, col = 2 },
    },
  },

  -- Window options
  window = {
    side = 'right',
    width = 10,
  },
}
--minidoc_afterlines_end

--- Table with information about current state of map
---
--- At least these keys are supported:
--- - <win_id_tbl> - table of window identifiers used to display map in certain
---   tabpage. Keys: tabpage identifier. Values: window identifier.
--- - <buf_id> - identifier of a buffer used to display map.
--- - <opts> - current options used to control map display. Same structure
---   as |MiniMap.config|.
--- - <encode_details> - table with information used for latest buffer lines
---   encoding. Has same structure as second output of |MiniMap.encode_strings()|
---   (`input_` fields correspond to current buffer lines, `output_` - map lines).
---   Used for quick update of range data on the map.
--- - <view> - table with <from_line> and <to_line> keys representing lines for
---   start and end of current buffer view.
--- - <line> - current line number.
MiniMap.current = {
  buf_id = nil,
  win_id_tbl = {},
  encode_details = {},
  opts = MiniMap.config,
  view = {},
  line = nil,
}

-- Module functionality =======================================================
---@return ... Array of encoded strings and details about the encoding process.
---   Table of details has the following fields:
---     - <input_cols> - maximum string width in input `strings`.
---     - <input_rows> - number of input strings.
---     - <output_cols> - maximum string width in output.
---     - <output_rows> - number of strings in output.
---     - <resolution> - resolution of symbols used. Table with <row> and <col>
---       keys for row and column resolution.
MiniMap.encode_strings = function(strings, opts)
  -- Validate input
  if not H.is_array_of(strings, H.is_string) then
    H.error('`strings` argument of `encode_strings()` should be array of strings.')
  end

  opts = vim.tbl_deep_extend(
    'force',
    { n_rows = math.huge, n_cols = math.huge, symbols = H.get_config().symbols.encode },
    opts or {}
  )
  H.validate_if(H.is_encode_symbols, opts.symbols, 'opts.symbols')
  if type(opts.n_rows) ~= 'number' then H.error('`opts.n_rows` of `encode_strings()` should be number.') end
  if type(opts.n_cols) ~= 'number' then H.error('`opts.n_cols` of `encode_strings()` should be number.') end

  -- Compute encoding
  local mask, details = H.mask_from_strings(strings, opts), nil
  mask, details = H.mask_rescale(mask, opts)
  return H.mask_to_symbols(mask, opts), details
end

MiniMap.open = function(opts)
  -- Early returns
  if H.is_disabled() then return end

  if H.is_window_open() then
    MiniMap.refresh(opts)
    return
  end

  -- Validate input
  opts = vim.tbl_deep_extend('force', H.get_config(), opts or {})
  H.validate_if(H.is_valid_opts, opts, 'opts')

  -- Open buffer and window
  local buf_id = MiniMap.current.buf_id
  if buf_id == nil or not vim.api.nvim_buf_is_valid(buf_id) then buf_id = vim.api.nvim_create_buf(false, true) end
  MiniMap.current.buf_id = buf_id

  local win_id = vim.api.nvim_open_win(buf_id, false, H.normalize_window_options(opts.window))
  H.set_current_map_win(win_id)

  -- Set buffer and window options. Other important options are handled by
  -- `style = 'minimal'` in `nvim_open_win()`.
  vim.api.nvim_win_call(win_id, function()
    --stylua: ignore
    local options = {
      'buftype=nofile', 'foldcolumn=0', 'foldlevel=999', 'matchpairs=',      'nobuflisted',
      'nomodeline',     'noreadonly',   'noswapfile',    'signcolumn=yes:1', 'synmaxcol&',
    }
    -- Vim's `setlocal` is currently more robust comparing to `opt_local`
    vim.cmd(('silent! noautocmd setlocal %s'):format(table.concat(options, ' ')))
  end)

  -- Refresh content
  MiniMap.refresh(opts)
end

MiniMap.refresh = function(opts)
  if H.is_disabled() or not H.is_window_open() then return end

  local buf_id, win_id = MiniMap.current.buf_id, H.get_current_map_win()

  opts = vim.tbl_deep_extend('force', H.get_config(), MiniMap.current.opts or {}, opts or {})
  H.validate_if(H.is_valid_opts, opts, 'opts')
  MiniMap.current.opts = opts

  H.update_window_config(win_id, opts)
  H.update_encoded_lines(buf_id, win_id, opts)
  H.update_range_signs_definitions(opts)
  H.update_range_signs(buf_id)
end

MiniMap.close = function()
  if H.is_disabled() then return end

  local win_id = H.get_current_map_win()
  pcall(vim.api.nvim_win_close, win_id, true)
  H.set_current_map_win(nil)
end

MiniMap.toggle = function(opts)
  if H.is_window_open() then
    MiniMap.close()
  else
    MiniMap.open(opts)
  end
end

MiniMap.gen_encode_symbols = {}

MiniMap.gen_encode_symbols.block = function(resolution) return H.block_symbols[resolution] end

MiniMap.gen_encode_symbols.dot = function(resolution) return H.dot_symbols[resolution] end

MiniMap.gen_encode_symbols.shade = function(resolution) return H.shade_symbols[resolution] end

MiniMap.on_content_change = function() MiniMap.refresh() end

MiniMap.on_view_change = function()
  if H.is_disabled() or not H.is_window_open() then return end
  H.update_range_signs(MiniMap.current.buf_id)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniMap.config

-- Cache for various operations
H.cache = {}

--stylua: ignore start
H.block_symbols = {}

H.block_symbols['1x2'] = { ' ', '▌', '▐', '█', resolution = { row = 1, col = 2 } }

H.block_symbols['2x1'] = { ' ', '▀', '▄', '█', resolution = { row = 2, col = 1 } }

H.block_symbols['2x2'] = {
  ' ', '▘', '▝', '▀', '▖', '▌', '▞', '▛', '▗', '▚', '▐', '▜', '▄', '▙', '▟', '█',
  resolution = { row = 2, col = 2 },
}

H.block_symbols['3x2'] = vim.deepcopy(MiniMap.config.symbols.encode)

H.dot_symbols = {}

H.dot_symbols['4x2'] = {
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
  resolution = { row = 4, col = 2 },
}

H.dot_symbols['3x2'] = { resolution = { row = 3, col = 2 } }
for i = 1,64 do H.dot_symbols['3x2'][i] = H.dot_symbols['4x2'][i] end

H.shade_symbols = {}

H.shade_symbols['2x1'] = { '░', '▒', '▒', '▓', resolution = { row = 2, col = 1 } }

H.shade_symbols['1x2'] = { '░', '▒', '▒', '▓', resolution = { row = 1, col = 2 } }
--stylua: ignore end

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    integrations = { config.integrations, H.is_valid_config_integrations },
    symbols = { config.symbols, H.is_valid_config_symbols },
    window = { config.window, H.is_valid_config_window },
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
    local n_cols = H.str_width(s_ext)
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
  -- `symbols.resolution.row` and `symbols.resolution.col` respectively.
  local n_rows = #mask
  local n_cols = 0
  for _, m_row in ipairs(mask) do
    n_cols = math.max(n_cols, #m_row)
  end

  local resolution = opts.symbols.resolution
  local res_n_rows = resolution.row * math.min(math.ceil(n_rows / resolution.row), opts.n_rows)
  local res_n_cols = resolution.col * math.min(math.ceil(n_cols / resolution.col), opts.n_cols)

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

  return res,
    {
      input_colsmap = n_cols,
      input_rows = n_rows,
      output_cols = res_n_cols,
      output_rows = res_n_rows,
      resolution = resolution,
    }
end

--- Apply sliding window (with `symbols.resolution.col` columns and
--- `symbols.resolution.row` rows) without overlap. Each application converts boolean
--- mask to symbol assuming symbols are sorted as if dark spots (read left to
--- right within row, then top to bottom) are bits in binary notation (`true` -
--- 1, `false` - 0).
---
---@param mask table Boolean 2d array to be shown with symbols.
---@return table Array of strings representing input `mask`.
---@private
H.mask_to_symbols = function(mask, opts)
  local symbols = opts.symbols
  local row_resol, col_resol = symbols.resolution.row, symbols.resolution.col

  local powers_of_two = {}
  for i = 0, (row_resol * col_resol - 1) do
    powers_of_two[i] = 2 ^ i
  end

  local symbols_n_rows = math.ceil(#mask / row_resol)
  -- Assumes rectangular table
  local symbols_n_cols = math.ceil(#mask[1] / col_resol)

  -- Compute symbols array indexes (start from zero)
  local symbol_ind = {}
  for i = 1, symbols_n_rows do
    symbol_ind[i] = H.tbl_repeat(0, symbols_n_cols)
  end

  local rows_coeff, cols_coeff = symbols_n_rows / #mask, symbols_n_cols / #mask[1]

  for i = 0, #mask - 1 do
    local row = mask[i + 1]
    for j = 0, #row - 1 do
      local two_power = (i % row_resol) * col_resol + (j % col_resol)
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

-- Work with config ------------------------------------------------------------
H.is_valid_opts = function(x, x_name)
  x_name = x_name or 'opts'

  local ok_integrations, msg_integrations = H.is_valid_config_integrations(x.integrations, x_name .. '.integrations')
  if not ok_integrations then return ok_integrations, msg_integrations end

  local ok_symbols, msg_symbols = H.is_valid_config_symbols(x.symbols, x_name .. '.symbols')
  if not ok_symbols then return ok_symbols, msg_symbols end

  local ok_window, msg_window = H.is_valid_config_window(x.window, x_name .. '.window')
  if not ok_window then return ok_window, msg_window end

  return true
end

H.is_valid_config_integrations = function(x, x_name)
  x_name = x_name or 'config.integrations'
  -- TODO
  return true
end

H.is_valid_config_symbols = function(x, x_name)
  x_name = x_name or 'config.symbols'

  if type(x) ~= 'table' then return false, H.msg_config(x_name, 'table') end

  -- Current line
  if not H.is_character(x.current_line) then
    return false, H.msg_config(x_name .. '.current_line', 'single character')
  end

  -- Current view
  if not H.is_character(x.current_view) then
    return false, H.msg_config(x_name .. '.current_view', 'single character')
  end

  -- Encode symbols
  local ok_encode, msg_encode = H.is_encode_symbols(x.encode, x_name .. '.encode')
  if not ok_encode then return ok_encode, msg_encode end

  return true
end

H.is_valid_config_window = function(x, x_name)
  x_name = x_name or 'config.window'

  if type(x) ~= 'table' then return false, H.msg_config(x_name, 'table') end

  -- Side
  if not (x.side == 'left' or x.side == 'right') then
    return false, H.msg_config(x_name .. '.side', [[one of 'left', 'right']])
  end

  -- Width
  if not (type(x.width) == 'number' and x.width > 0) then
    return false, H.msg_config(x_name .. '.width', 'positive number')
  end

  return true
end

H.msg_config = function(x_name, msg) return string.format('`%s` should be %s.', x_name, msg) end

-- Work with windows -----------------------------------------------------------
H.normalize_window_options = function(win_opts, full)
  if full == nil then full = true end

  local has_tabline, has_statusline = vim.o.showtabline > 0, vim.o.laststatus > 0
  local anchor, col = 'NE', vim.o.columns
  if win_opts.side == 'left' then
    anchor, col = 'NW', 0
  end

  local res = {
    relative = 'editor',
    anchor = anchor,
    row = has_tabline and 1 or 0,
    col = col,
    width = win_opts.width,
  }
  if not full then return res end

  res.height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  res.zindex = 10
  res.style = 'minimal'
  return res
end

H.get_current_map_win = function() return MiniMap.current.win_id_tbl[vim.api.nvim_get_current_tabpage()] end

H.set_current_map_win = function(win_id) MiniMap.current.win_id_tbl[vim.api.nvim_get_current_tabpage()] = win_id end

H.is_window_open = function()
  local cur_win_id = H.get_current_map_win()
  return cur_win_id ~= nil and vim.api.nvim_win_is_valid(cur_win_id)
end

H.update_window_config = function(win_id, opts)
  vim.api.nvim_win_set_config(win_id, H.normalize_window_options(opts.window, false))
  -- Ensure important option value, because `nvim_win_set_config()` reapplies
  -- `style = 'minimal'`. See https://github.com/neovim/neovim/issues/20370 .
  vim.api.nvim_win_set_option(win_id, 'signcolumn', 'yes:1')
end

H.update_range_signs_definitions = function(opts)
  vim.fn.sign_define('MiniMapView', { text = opts.symbols.current_view, texthl = 'MiniMapSignView' })
  vim.fn.sign_define('MiniMapLine', { text = opts.symbols.current_line, texthl = 'MiniMapSignLine' })
end

H.update_range_signs = function(buf_id)
  local cur_details = MiniMap.current.encode_details
  local cur_view, cur_line = MiniMap.current.view, MiniMap.current.line

  -- View
  local view = { from_line = vim.fn.line('w0'), to_line = vim.fn.line('w$') }
  if not (view.from_line == cur_view.from_line and view.to_line == cur_view.to_line) then
    -- Remove previous view signs
    vim.fn.sign_unplace('MiniMapView', { buffer = buf_id })

    -- Add new view signs
    local map_from_line = H.bufline_to_mapline(view.from_line, cur_details)
    local map_to_line = H.bufline_to_mapline(view.to_line, cur_details)

    local list = {}
    for i = map_from_line, map_to_line do
      table.insert(
        list,
        { buffer = buf_id, group = 'MiniMapView', id = 0, lnum = i, name = 'MiniMapView', priority = 10 }
      )
    end
    vim.fn.sign_placelist(list)

    MiniMap.current.view = view
  end

  -- Current line
  local current_line = vim.fn.line('.')
  if current_line ~= cur_line then
    -- Remove previous line sign
    vim.fn.sign_unplace('MiniMapLine', { buffer = buf_id })

    -- Add new line sign
    local map_line = H.bufline_to_mapline(current_line, cur_details)

    -- Set higher priority than view signs to be visible over them
    vim.fn.sign_place(0, 'MiniMapLine', 'MiniMapLine', buf_id, { lnum = map_line, priority = 11 })
    MiniMap.current.line = current_line
  end
end

H.update_encoded_lines = function(buf_id, win_id, opts)
  local n_cols = vim.api.nvim_win_get_width(win_id) - 2
  local n_rows = vim.api.nvim_win_get_height(win_id)

  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  local encoded_lines, details
  if n_cols <= 0 then
    -- Case of "only scroll indicator"
    encoded_lines = {}
    for _ = 1, n_rows do
      table.insert(encoded_lines, '')
    end
    details = { input_rows = #buf_lines, output_rows = n_rows, resolution = { row = 1, col = 1 } }
  else
    -- Case of "full minimap"
    encoded_lines, details =
      MiniMap.encode_strings(buf_lines, { n_cols = n_cols, n_rows = n_rows, symbols = opts.symbols.encode })
  end

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, encoded_lines)
  MiniMap.current.encode_details = details
end

H.bufline_to_mapline = function(buf_line, details)
  local coef = (details.output_rows / details.input_rows) / details.resolution.row

  -- Lines start from 1
  return math.floor(coef * (buf_line - 1)) + 1
end

H.bufpos_to_mappos = function(buf_pos, details)
  -- NOTE: assumes `output_cols` and `input_cols` are not `nil`
  local coef = (details.output_cols / details.input_cols) / details.resolution.col
  -- Columns start from 0
  local map_col = math.floor(coef * buf_pos[2])

  return { H.bufline_to_mapline(buf_pos[1], details), map_col }
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

H.is_character = function(x) return H.is_string(x) and H.str_width(x) == 1 end

H.is_encode_symbols = function(x, x_name)
  x_name = x_name or 'symbols'

  if type(x) ~= 'table' then return false, H.msg_config(x_name, 'table') end
  if type(x.resolution) ~= 'table' then return false, H.msg_config(x_name .. '.resolution', 'table') end
  if type(x.resolution.col) ~= 'number' then return false, H.msg_config(x_name .. '.resolution.col', 'number') end
  if type(x.resolution.row) ~= 'number' then return false, H.msg_config(x_name .. '.resolution.row', 'number') end

  local two_power = x.resolution.col * x.resolution.row
  for i = 1, 2 ^ two_power do
    if not H.is_character(x[i]) then
      return false, H.msg_config(string.format('%s[%d]', x_name, i), 'single character')
    end
  end

  return true
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.map) %s', msg), 0) end

H.validate_if = function(predicate, x, x_name)
  local is_valid, msg = predicate(x, x_name)
  if not is_valid then H.error(msg) end
end

H.str_width = function(x)
  -- Use first returned value (UTF-32 index, and not UTF-16 one)
  local res = vim.str_utfindex(x)
  return res
end

H.tbl_repeat = function(x, n)
  local res = {}
  for _ = 1, n do
    table.insert(res, x)
  end
  return res
end

return MiniMap
