-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO:
-- Code:
-- - Figure out a way to use `integrations = {}` in default config.
-- - Think about using it in Insert mode.
-- - Handle all possible/reasonable resolutions in `gen_encode_symbols`.
-- - Refactor and add relevant comments.
--
-- Tests:
--
-- Documentation:
-- - How to refresh in Insert mode (add autocommands for for TextChangedI and
--   CursorMovedI).
-- - Suggestions for scrollbar symbols:
--     - View-line pairs:
--         - '🮇▎' - '▐▌' (centered within 2 cells).
--         - '▒' - '█'.
--         - '▒▒' - '██' (span 2 cells).
--     - Line - '🮚', '▶'.
--     - View - '┋'.
-- - Update is done in asynchronous (non-blocking) fashion.
-- - Works best with global statusline. Or use |MiniMap.refresh()|.
-- - Justification of supporting only line highlighting and cursor movement:
--     - Implementation. It is unnecessarily hard to correctly implement column
--       conversion from source to map coordinates. This is mostly because of
--       multibyte characters.
--     - User experience. It usually seemed too unnoticable to highlight single
--       cell (mostly because highlighting was done for foreground). Especially
--       with dot encode symbols.
--     - API. It allows for a simpler interface for integrations.

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
    [[augroup MiniMap
        au!
        au BufEnter,TextChanged,VimResized * lua MiniMap.on_content_change()
        au CursorMoved,WinScrolled * lua MiniMap.on_view_change()
        au CursorMoved * lua MiniMap.on_cursor_change()
        au WinLeave * lua MiniMap.on_winleave()
      augroup END]],
    false
  )

  if vim.fn.exists('##ModeChanged') == 1 then
    -- Refresh on every return to Normal mode
    vim.api.nvim_exec(
      [[augroup MiniMap
          au ModeChanged *:n lua MiniMap.on_content_change()
        augroup END]],
      false
    )
  end

  -- Create highlighting
  vim.api.nvim_exec(
    [[hi default link MiniMapSignView Delimiter
      hi default link MiniMapSignLine Title
      hi default link MiniMapSignMore Special]],
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
  integrations = nil,

  -- Symbols used to display data
  symbols = {
    current_line = '▐▌',
    current_view = '🮇▎',
    encode = {
      ' ', '🬀', '🬁', '🬂', '🬃', '🬄', '🬅', '🬆', '🬇', '🬈', '🬉', '🬊', '🬋', '🬌', '🬍', '🬎',
      '🬏', '🬐', '🬑', '🬒', '🬓', '▌', '🬔', '🬕', '🬖', '🬗', '🬘', '🬙', '🬚', '🬛', '🬜', '🬝',
      '🬞', '🬟', '🬠', '🬡', '🬢', '🬣', '🬤', '🬥', '🬦', '🬧', '▐', '🬨', '🬩', '🬪', '🬫', '🬬',
      '🬭', '🬮', '🬯', '🬰', '🬱', '🬲', '🬳', '🬴', '🬵', '🬶', '🬷', '🬸', '🬹', '🬺', '🬻', '█',
      resolution = { row = 3, col = 2 },
    },
    more_integrations = '•',
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
--- - <buf_id_tbl> - table with buffer identifiers. Field <map> contains
---   identifier of a buffer used to display map. Field <source> - buffer
---   identifier which content map is displaying.
--- - <win_id_tbl> - table of window identifiers used to display map in certain
---   tabpage. Keys: tabpage identifier. Values: window identifier.
--- - <opts> - current options used to control map display. Same structure
---   as |MiniMap.config|.
--- - <encode_details> - table with information used for latest buffer lines
---   encoding. Has same structure as second output of |MiniMap.encode_strings()|
---   (`input_` fields correspond to current buffer lines, `output_` - map lines).
---   Used for quick update of scrollbar.
--- - <view> - table with <from_line> and <to_line> keys representing lines for
---   start and end of current buffer view.
--- - <line> - current line number.
MiniMap.current = {
  buf_id_tbl = {},
  win_id_tbl = {},
  encode_details = {},
  opts = MiniMap.config,
  view = {},
  line = nil,
}

-- Module functionality =======================================================
---@return ... Array of encoded strings and details about the encoding process.
---   Table of details has the following fields:
---     - <source_cols> - maximum string width in input `strings`.
---     - <source_rows> - number of input strings.
---     - <map_cols> - maximum string width in output.
---     - <map_rows> - number of strings in output.
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
  local buf_id = MiniMap.current.buf_id_tbl.map
  if buf_id == nil or not vim.api.nvim_buf_is_valid(buf_id) then buf_id = vim.api.nvim_create_buf(false, true) end
  MiniMap.current.buf_id_tbl.map = buf_id

  local win_id = vim.api.nvim_open_win(buf_id, false, H.normalize_window_options(opts.window))
  H.set_current_map_win(win_id)

  -- Set buffer and window options. Other important options are handled by
  -- `style = 'minimal'` in `nvim_open_win()`.
  vim.api.nvim_win_call(win_id, function()
    --stylua: ignore
    local options = {
      'buftype=nofile',   'foldcolumn=0', 'foldlevel=999', 'matchpairs=',      'nobuflisted',
      'nomodeline',       'noreadonly',   'noswapfile',    'signcolumn=yes:1', 'synmaxcol&',
      'filetype=minimap',
    }
    -- Vim's `setlocal` is currently more robust comparing to `opt_local`
    vim.cmd(('silent! noautocmd setlocal %s'):format(table.concat(options, ' ')))

    -- Make it play nicely with other 'mini.nvim' modules
    vim.b.minicursorword_disable = true
  end)

  -- Make buffer local mappings
  vim.api.nvim_buf_set_keymap(buf_id, 'n', '<CR>', '<Cmd>lua MiniMap.toggle_focus()<CR>', { noremap = false })

  -- Refresh content
  MiniMap.refresh(opts)
end

---@param parts table|nil Which parts to update. Recognised keys with boolean
---   values (all `true` by default):
---   - <integrations> - whether to update integrations highlights.
---   - <lines> - whether to update map lines.
---   - <scrollbar> - whether to update scrollbar.
MiniMap.refresh = function(parts, opts)
  -- Early return
  if H.is_disabled() or not H.is_window_open() then return end

  -- Validate input
  parts = vim.tbl_deep_extend('force', { integrations = true, lines = true, scrollbar = true }, parts or {})

  opts = vim.tbl_deep_extend('force', H.get_config(), MiniMap.current.opts or {}, opts or {})
  H.validate_if(H.is_valid_opts, opts, 'opts')
  MiniMap.current.opts = opts

  -- Update map config
  MiniMap.current.buf_id_tbl.source = vim.api.nvim_get_current_buf()
  H.update_map_config()

  -- Possibly update parts in asynchronous fashion
  if parts.lines then vim.schedule(H.update_map_lines) end
  if parts.scrollbar then vim.schedule(H.update_map_scrollbar) end
  if parts.integrations then vim.schedule(H.update_map_integrations) end
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

MiniMap.toggle_focus = function()
  if not H.is_window_open() then return end
  local cur_win, map_win = vim.api.nvim_get_current_win(), H.get_current_map_win()

  if cur_win == map_win then
    -- Focus on previous window
    vim.cmd('wincmd p')
  else
    -- Put cursor in map window at line indicator
    local map_line = H.sourceline_to_mapline(vim.fn.line('.'))
    vim.api.nvim_win_set_cursor(map_win, { map_line, 0 })

    -- Focus on map window
    vim.api.nvim_set_current_win(map_win)
  end
end

MiniMap.toggle_side = function()
  local cur_side = MiniMap.current.opts.window.side
  MiniMap.refresh(
    { integrations = false, lines = false, scrollbar = false },
    { window = { side = cur_side == 'left' and 'right' or 'left' } }
  )
end

MiniMap.gen_encode_symbols = {}

MiniMap.gen_encode_symbols.block = function(id) return H.block_symbols[id] end

MiniMap.gen_encode_symbols.dot = function(id) return H.dot_symbols[id] end

MiniMap.gen_encode_symbols.shade = function(id) return H.shade_symbols[id] end

MiniMap.gen_integration = {}

MiniMap.gen_integration.diagnostics = function(severity_highlights)
  if severity_highlights == nil then
    local severity = vim.diagnostic.severity
    severity_highlights = {
      { severity = severity.WARN, hl_group = 'DiagnosticFloatingWarn' },
      { severity = severity.ERROR, hl_group = 'DiagnosticFloatingError' },
    }
  end

  vim.cmd([[
    augroup MiniMapDiagnostics
      au!
      au DiagnosticChanged * lua MiniMap.refresh({ lines = false, view = false })
    augroup END]])

  return function()
    if vim.fn.has('nvim-0.6') == 0 then return {} end

    local line_hl = {}
    local diagnostics = vim.diagnostic.get(MiniMap.current.buf_id_tbl.source)
    for _, data in ipairs(severity_highlights) do
      local severity_diagnostics = vim.tbl_filter(function(x) return x.severity == data.severity end, diagnostics)
      for _, diag in ipairs(severity_diagnostics) do
        -- Add all diagnostic lines to highlight
        for i = diag.lnum, diag.end_lnum do
          table.insert(line_hl, { line = i + 1, hl_group = data.hl_group })
        end
      end
    end

    return line_hl
  end
end

MiniMap.gen_integration.builtin_search = function(hl_group)
  hl_group = hl_group or 'Search'

  vim.cmd([[
    augroup MiniMapBuiltinSearch
      au!
      au OptionSet hlsearch lua MiniMap.refresh({ lines = false, view = false })
    augroup END]])

  return function()
    if vim.v.hlsearch == 0 or not vim.o.hlsearch then return {} end

    local win_view = vim.fn.winsaveview()

    MiniMap.search_line_hl = {}
    local cmd = string.format(
      [[silent! g//lua table.insert(MiniMap.search_line_hl, { line = vim.fn.line('.'), hl_group = '%s' })]],
      hl_group
    )
    vim.cmd(cmd)
    vim.fn.winrestview(win_view)

    local res = MiniMap.search_line_hl
    MiniMap.search_line_hl = nil
    return res
  end
end

MiniMap.on_content_change = function()
  local buf_type = vim.bo.buftype
  if not (buf_type == '' or buf_type == 'help') then return end
  MiniMap.refresh()
end

MiniMap.on_view_change = function()
  local buf_type = vim.bo.buftype
  if not (buf_type == '' or buf_type == 'help') then return end
  MiniMap.refresh({ integrations = false, lines = false })
end

MiniMap.on_cursor_change = function()
  -- Synchronize cursors in map and previous window if currently inside map
  local cur_win, map_win = vim.api.nvim_get_current_win(), H.get_current_map_win()
  if cur_win ~= map_win then return end

  local prev_win_id = H.cache.previous_win_id
  if prev_win_id == nil then return end

  local source_line = H.mapline_to_sourceline(vim.fn.line('.'))
  vim.api.nvim_win_set_cursor(prev_win_id, { source_line, 0 })

  -- Open just enough folds and center cursor
  vim.api.nvim_win_call(prev_win_id, function() vim.cmd('normal! zvzz') end)
end

MiniMap.on_winleave = function() H.cache.previous_win_id = vim.api.nvim_get_current_win() end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniMap.config

-- Cache for various operations
H.cache = {}

H.ns_id = {
  integrations = vim.api.nvim_create_namespace('MiniMapIntegrations'),
}

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
  local source_rows = #mask
  local source_cols = 0
  for _, m_row in ipairs(mask) do
    source_cols = math.max(source_cols, #m_row)
  end

  local resolution = opts.symbols.resolution
  local map_rows = math.min(math.ceil(source_rows / resolution.row), opts.n_rows)
  local map_cols = math.min(math.ceil(source_cols / resolution.col), opts.n_cols)

  local res_n_rows = resolution.row * map_rows
  local res_n_cols = resolution.col * map_cols

  -- Downscale
  local res = {}
  for i = 1, res_n_rows do
    res[i] = H.tbl_repeat(false, res_n_cols)
  end

  local rows_coeff, cols_coeff = res_n_rows / source_rows, res_n_cols / source_cols

  for i, m_row in ipairs(mask) do
    for j, m in ipairs(m_row) do
      local res_i = math.floor((i - 1) * rows_coeff) + 1
      local res_j = math.floor((j - 1) * cols_coeff) + 1
      -- Downscaled block value will be `true` if at least a single element
      -- within it is `true`
      res[res_i][res_j] = m or res[res_i][res_j]
    end
  end

  return res, { source_cols = source_cols, source_rows = source_rows, map_cols = map_cols, map_rows = map_rows }
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
  if not H.is_string(x.current_line, 2) then
    return false, H.msg_config(x_name .. '.current_line', 'one or two characters')
  end

  -- Current view
  if not H.is_string(x.current_view, 2) then
    return false, H.msg_config(x_name .. '.current_view', 'one or two characters')
  end

  -- Encode symbols
  local ok_encode, msg_encode = H.is_encode_symbols(x.encode, x_name .. '.encode')
  if not ok_encode then return ok_encode, msg_encode end

  -- Several integration highlights
  if not H.is_string(x.more_integrations, 2) then
    return false, H.msg_config(x_name .. '.more_integrations', 'one or two characters')
  end

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

-- Work with map window --------------------------------------------------------
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
    -- Can be updated at `VimResized` event
    height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0),
  }
  if not full then return res end

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

-- Work with map updates -------------------------------------------------------
H.update_map_config = function()
  local opts = MiniMap.current.opts
  local win_id = H.get_current_map_win()

  -- Window config
  vim.api.nvim_win_set_config(win_id, H.normalize_window_options(opts.window, false))
  -- Ensure important option value, because `nvim_win_set_config()` reapplies
  -- `style = 'minimal'`. See https://github.com/neovim/neovim/issues/20370 .
  vim.api.nvim_win_set_option(win_id, 'signcolumn', 'yes:1')

  -- Scrollbar sign definition
  vim.fn.sign_define('MiniMapView', { text = opts.symbols.current_view, texthl = 'MiniMapSignView' })
  vim.fn.sign_define('MiniMapLine', { text = opts.symbols.current_line, texthl = 'MiniMapSignLine' })
end

H.update_map_lines = function()
  if not H.is_window_open() then return end

  local buf_id, opts = MiniMap.current.buf_id_tbl.map, MiniMap.current.opts
  local win_id = H.get_current_map_win()

  -- Compute output number of rows and columns to fit currently shown window
  local n_cols = vim.api.nvim_win_get_width(win_id) - 2
  local n_rows = vim.api.nvim_win_get_height(win_id)

  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  -- Ensure that current buffer has lines (can be not the case when this is
  -- executed asynchronously during Neovim closing)
  if #buf_lines == 0 then return end

  local encoded_lines, details
  if n_cols <= 0 then
    -- Case of "only scroll indicator"
    encoded_lines = H.tbl_repeat('', n_rows)
    details = { source_rows = #buf_lines, map_rows = n_rows }
  else
    -- Case of "full minimap"
    encoded_lines, details =
      MiniMap.encode_strings(buf_lines, { n_cols = n_cols, n_rows = n_rows, symbols = opts.symbols.encode })
  end

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, encoded_lines)
  MiniMap.current.encode_details = details

  -- Force scrollbar update
  MiniMap.current.view, MiniMap.current.line = {}, nil
end

H.update_map_scrollbar = function()
  if not H.is_window_open() then return end

  local buf_id = MiniMap.current.buf_id_tbl.map
  local cur_view, cur_line = MiniMap.current.view, MiniMap.current.line

  -- View
  local view = { from_line = vim.fn.line('w0'), to_line = vim.fn.line('w$') }
  if not (view.from_line == cur_view.from_line and view.to_line == cur_view.to_line) then
    -- Remove previous view signs
    vim.fn.sign_unplace('MiniMapView', { buffer = buf_id })

    -- Add new view signs
    local map_from_line = H.sourceline_to_mapline(view.from_line)
    local map_to_line = H.sourceline_to_mapline(view.to_line)

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
    local map_line = H.sourceline_to_mapline(current_line)

    -- Set higher priority than view signs to be visible over them
    vim.fn.sign_place(0, 'MiniMapLine', 'MiniMapLine', buf_id, { lnum = map_line, priority = 11 })
    MiniMap.current.line = current_line
  end
end

H.update_map_integrations = function()
  if not H.is_window_open() then return end

  local buf_id = MiniMap.current.buf_id_tbl.map
  local integrations = MiniMap.current.opts.integrations or {}

  -- Remove previous highlights and signs
  local ns_id = H.ns_id.integrations
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
  vim.fn.sign_unplace('MiniMapMore', { buffer = buf_id })

  -- Add line highlights
  local line_counts = {}
  for i, integration in ipairs(integrations) do
    local line_hl = integration()
    for _, lh in ipairs(line_hl) do
      local map_line = H.sourceline_to_mapline(lh.line)
      line_counts[map_line] = (line_counts[map_line] or 0) + 1
      -- Make sure that integration highlights are placed over previous ones
      H.add_line_hl(buf_id, ns_id, lh.hl_group, map_line - 1, 10 + i)
    end
  end

  -- Add "more integrations" signs
  local extmark_opts = {
    virt_text = { { MiniMap.current.opts.symbols.more_integrations, 'MiniMapSignMore' } },
    virt_text_pos = 'right_align',
    hl_mode = 'blend',
  }
  for l, count in pairs(line_counts) do
    -- Make sure signs are displayed over scrollbar
    if count > 1 then vim.api.nvim_buf_set_extmark(buf_id, ns_id, l - 1, 0, extmark_opts) end
  end
end

H.sourceline_to_mapline = function(source_line)
  local details = MiniMap.current.encode_details
  local coef = details.map_rows / details.source_rows
  return math.floor(coef * (source_line - 1)) + 1
end

H.mapline_to_sourceline = function(map_line)
  local details = MiniMap.current.encode_details
  local coef = details.source_rows / details.map_rows
  return math.ceil(coef * (map_line - 1)) + 1
end

-- Predicates ------------------------------------------------------------------
H.is_array_of = function(x, predicate)
  if not vim.tbl_islist(x) then return false end
  for _, v in ipairs(x) do
    if not predicate(v) then return false end
  end
  return true
end

H.is_string = function(x, n)
  n = n or math.huge
  return type(x) == 'string' and H.str_width(x) <= n
end

H.is_encode_symbols = function(x, x_name)
  x_name = x_name or 'symbols'

  if type(x) ~= 'table' then return false, H.msg_config(x_name, 'table') end
  if type(x.resolution) ~= 'table' then return false, H.msg_config(x_name .. '.resolution', 'table') end
  if type(x.resolution.col) ~= 'number' then return false, H.msg_config(x_name .. '.resolution.col', 'number') end
  if type(x.resolution.row) ~= 'number' then return false, H.msg_config(x_name .. '.resolution.row', 'number') end

  local two_power = x.resolution.col * x.resolution.row
  for i = 1, 2 ^ two_power do
    if not H.is_string(x[i]) then return false, H.msg_config(string.format('%s[%d]', x_name, i), 'single character') end
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
H.error = function(msg) error(string.format('(mini.map) %s', msg), 0) end

H.validate_if = function(predicate, x, x_name)
  local is_valid, msg = predicate(x, x_name)
  if not is_valid then H.error(msg) end
end

-- Use `priority` in Neovim 0.7 because of the regression bug (highlights are
-- not stacked properly): https://github.com/neovim/neovim/issues/17358
if vim.fn.has('nvim-0.7') == 1 then
  H.add_line_hl = function(buf_id, ns_id, hl_group, line, priority)
    vim.highlight.range(buf_id, ns_id, hl_group, { line, 0 }, { line, -1 }, { priority = priority })
  end
else
  H.add_line_hl =
    function(buf_id, ns_id, hl_group, line) vim.highlight.range(buf_id, ns_id, hl_group, { line, 0 }, { line, -1 }) end
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
