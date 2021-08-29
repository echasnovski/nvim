-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Custom *minimal* and *fast* tabline module. General idea: show all listed
-- buffers in readable way with minimal total width in case of one vim tab,
-- fall back for deafult otherwise. Inspired by
-- https://github.com/ap/vim-buftabline.
--
-- To activate, put this file somewhere into 'lua' folder and call module's
-- `setup()`. For example, put as 'lua/mini/tabline.lua' and execute
-- `require('mini.tabline').setup()` Lua code. It may have `config` argument
-- which should be a table overwriting default values using same structure.
--
-- Default `config`:
-- {
--   -- Whether to set Vim's settings for tabline (make it always shown and
--   -- allow hidden buffers)
--   set_vim_settings = true
-- }
--
-- Main capabilities when displaying buffers:
-- - Different highlight groups for "states" of buffer affecting 'buffer tabs':
--     - MiniTablineCurrent - buffer is current (has cursor in it)
--     - MiniTablineVisible - buffer is visible (displayed in some window)
--     - MiniTablineHidden - buffer is hidden (not displayed)
--     - MiniTablineModifiedCurrent - buffer is modified and current
--     - MiniTablineModifiedVisible - buffer is modified and visible
--     - MiniTablineModifiedHidden - buffer is modified and hidden
--     - MiniTablineFill - unused right space of tabline
--   To change any of them, modify it directly with Vim's `highlight` command.
-- - Buffer names are made unique by extending paths to files or appending
--   unique identifier to buffers without name.
-- - Current buffer is displayed "optimally centered" (in center of screen
--   while maximizing the total number of buffers shown) when there are many
--   buffers open.
-- - 'Buffer tabs' are clickable if Neovim allows it.
--
-- Notes about structure:
-- - Main function is `MiniTabline.make_tabline_string()` which computes actual
--   value of '&tabline' option. It also describes high-level functional
--   structure when displaying buffers. From there go to respective functions.

-- Module and its helper
local MiniTabline = {}
local H = {}

-- Module setup
function MiniTabline.setup(config)
  -- Export module
  _G.MiniTabline = MiniTabline

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Module behavior
  vim.api.nvim_exec(
    [[augroup MiniTabline
        autocmd!
        autocmd VimEnter   * lua MiniTabline.update_tabline()
        autocmd TabEnter   * lua MiniTabline.update_tabline()
        autocmd BufAdd     * lua MiniTabline.update_tabline()
        autocmd FileType  qf lua MiniTabline.update_tabline()
        autocmd BufDelete  * lua MiniTabline.update_tabline()
      augroup END]],
    false
  )

  -- Function to make tabs clickable
  vim.api.nvim_exec(
    [[function! MiniTablineSwitchBuffer(bufnum, clicks, button, mod)
        execute 'buffer' a:bufnum
      endfunction]],
    false
  )

  -- Create highlighting
  vim.api.nvim_exec(
    [[hi link MiniTablineCurrent TabLineSel
      hi link MiniTablineVisible TabLineSel
      hi link MiniTablineHidden  TabLine

      hi link MiniTablineModifiedCurrent StatusLine
      hi link MiniTablineModifiedVisible StatusLine
      hi link MiniTablineModifiedHidden  StatusLineNC

      hi MiniTablineFill NONE]],
    false
  )
end

-- Module settings
-- Whether to set Vim's settings for tabline
MiniTabline.set_vim_settings = true

-- Module functionality
function MiniTabline.update_tabline()
  if vim.fn.tabpagenr('$') > 1 then
    vim.o.tabline = [[]]
  else
    vim.o.tabline = [[%!v:lua.MiniTabline.make_tabline_string()]]
  end
end

function MiniTabline.make_tabline_string()
  H.list_tabs()
  H.finalize_labels()
  H.fit_width()

  return H.concat_tabs()
end

---- Tables to keep track of tabs
MiniTabline.tabs = {}
MiniTabline.tabs_order = {}

-- Helpers
---- Module default config
H.config = { set_vim_settings = MiniTabline.set_vim_settings }

---- Settings
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.config, config or {})

  vim.validate({ set_vim_settings = { config.set_vim_settings, 'boolean' } })

  return config
end

function H.apply_config(config)
  MiniTabline.set_vim_settings = config.set_vim_settings

  -- Set settings to ensure tabline is displayed properly
  if config.set_vim_settings then
    vim.o.showtabline = 2 -- Always show tabline
    vim.o.hidden = true -- Allow switching buffers without saving them
  end
end

---- List tabs
function H.list_tabs()
  local tabs = {}
  local tabs_order = {}
  for i = 1, vim.fn.bufnr('$') do
    if H.is_buffer_in_minitabline(i) then
      -- Display tabs in order of increasing buffer number
      tabs_order[#tabs_order + 1] = i

      local tab = {}
      tab['hl'] = H.construct_highlight(i)
      tab['tabfunc'] = H.construct_tabfunc(i)
      tab['label'], tab['label_extender'] = H.construct_label_data(i)

      tabs[i] = tab
    end
  end

  MiniTabline.tabs = tabs
  MiniTabline.tabs_order = tabs_order
end

function H.is_buffer_in_minitabline(bufnum)
  return (vim.fn.buflisted(bufnum) > 0) and (vim.fn.getbufvar(bufnum, '&buftype') ~= 'quickfix')
end

---- Tab's highlight group
function H.construct_highlight(bufnum)
  local hl_type
  if bufnum == vim.fn.winbufnr(0) then
    hl_type = 'Current'
  elseif vim.fn.bufwinnr(bufnum) > 0 then
    hl_type = 'Visible'
  else
    hl_type = 'Hidden'
  end
  if vim.fn.getbufvar(bufnum, '&modified') > 0 then
    hl_type = 'Modified' .. hl_type
  end

  return string.format('%%#MiniTabline%s#', hl_type)
end

---- Tab's clickable action (if supported)
---- Is there clickable support?
H.tablineat = vim.fn.has('tablineat')

function H.construct_tabfunc(bufnum)
  if H.tablineat > 0 then
    return string.format([[%%%d@MiniTablineSwitchBuffer@]], bufnum)
  else
    return ''
  end
end

-- Tab's label and label extender
function H.construct_label_data(bufnum)
  local label, label_extender

  local bufpath = vim.fn.bufname(bufnum)
  if bufpath ~= '' then
    -- Process path buffer
    label = vim.fn.fnamemodify(bufpath, ':t')
    label_extender = H.make_path_extender(bufnum)
  else
    -- Process unnamed buffer
    label = H.make_unnamed_label(bufnum)
    label_extender = function(x)
      return x
    end
  end

  return label, label_extender
end

H.path_sep = package.config:sub(1, 1)

function H.make_path_extender(bufnum)
  return function(label)
    -- Add parent to current label
    local full_path = vim.fn.fnamemodify(vim.fn.bufname(bufnum), ':p')
    local pattern = string.format('[^%s]+%s%s$', H.path_sep, H.path_sep, label)
    return string.match(full_path, pattern) or label
  end
end

---- Work with unnamed buffers
------ Track all initially unnamed buffers for disambiguation. The
------ `unnamed_buffers` table is designed to store 'sequential' buffer
------ identifier. This approach allows to have the following behavior:
------ - Create three unnamed buffers.
------ - Delete second one.
------ - Tab label for third one remains the same.
H.n_unnamed = 0
H.unnamed_buffers = {}

function H.ensure_unnamed_tracked(bufnum)
  if H.unnamed_buffers[bufnum] ~= nil then
    return
  end

  H.n_unnamed = H.n_unnamed + 1
  H.unnamed_buffers[bufnum] = { id = H.n_unnamed }
end

function H.is_buffer_scratch(bufnum)
  local buftype = vim.fn.getbufvar(bufnum, '&buftype')
  return (buftype == 'acwrite') or (buftype == 'nofile')
end

function H.make_unnamed_label(bufnum)
  local label = '*'
  if H.is_buffer_scratch(bufnum) then
    label = '!'
  end

  -- Possibly add tracking id (which is tracked separately for different label
  -- types)
  H.ensure_unnamed_tracked(bufnum)
  local tab_id = H.unnamed_buffers[bufnum].id
  if tab_id > 1 then
    label = string.format('%s(%d)', label, tab_id)
  end

  return label
end

-- Finalize labels
function H.finalize_labels()
  -- Deduplicate
  local nonunique_bufs = H.get_nonunique_buffers()
  while #nonunique_bufs > 0 do
    local nothing_changed = true

    -- Extend labels
    for _, bufnum in ipairs(nonunique_bufs) do
      local tab = MiniTabline.tabs[bufnum]
      local old_label = tab.label
      tab.label = tab.label_extender(tab.label)
      if old_label ~= tab.label then
        nothing_changed = false
      end
    end

    if nothing_changed then
      break
    end

    nonunique_bufs = H.get_nonunique_buffers()
  end

  -- Postprocess: add padding
  for _, tab in pairs(MiniTabline.tabs) do
    -- -- Currently using icons doesn't quite work because later in
    -- -- `H.fit_width()` width of label is computed using `string.len()` which
    -- -- computes number of bytes in string. Correct approach would be to use
    -- -- `utf8.len()`, but it is in Lua 5.3+.
    -- local extension = vim.fn.fnamemodify(tab.label, ':e')
    -- local icon = require'nvim-web-devicons'.get_icon(tab.label, extension, { default = true })
    -- tab.label = string.format('%s %s ', icon, tab.label)
    tab.label = string.format(' %s ', tab.label)
  end
end

function H.get_nonunique_buffers()
  -- Collect buffers per label
  local label_buffers = {}
  for bufnum, tab in pairs(MiniTabline.tabs) do
    local label = tab.label
    if label_buffers[label] == nil then
      label_buffers[label] = { bufnum }
    else
      table.insert(label_buffers[label], bufnum)
    end
  end

  -- Collect buffers with non-unique labels
  local res = {}
  for _, bufnums in pairs(label_buffers) do
    if #bufnums > 1 then
      for _, b in pairs(bufnums) do
        table.insert(res, b)
      end
    end
  end

  return res
end

---- Fit tabline to maximum displayed width
H.centerbuf = vim.fn.winbufnr(0)

function H.fit_width()
  H.update_centerbuf()

  -- Compute label width data
  local center = 1
  local tot_width = 0
  -- Tabs should be processed here in order of their appearance
  for _, bufnum in pairs(MiniTabline.tabs_order) do
    local tab = MiniTabline.tabs[bufnum]
    -- Better to use `utf8.len()` but it is only available in Lua 5.3+
    tab.label_width = tab.label:len()
    tab.chars_on_left = tot_width

    tot_width = tot_width + tab.label_width

    if bufnum == H.centerbuf then
      -- Make end of 'center tab' to be always displayed in center in case of
      -- truncation
      center = tot_width
    end
  end

  local display_interval = H.compute_display_interval(center, tot_width)

  H.truncate_tabs_display(display_interval)
end

function H.update_centerbuf()
  local buf_displayed = vim.fn.winbufnr(0)
  if H.is_buffer_in_minitabline(buf_displayed) then
    H.centerbuf = buf_displayed
  end
end

function H.compute_display_interval(center, tabline_width)
  -- left - first character to be displayed (starts with 1)
  -- right - last character to be displayed
  -- Conditions to be satisfied:
  -- 1) right - left + 1 = math.min(tot_width, tabline_width)
  -- 2) 1 <= left <= tabline_width; 1 <= right <= tabline_width

  local tot_width = vim.o.columns

  -- Usage of `math.ceil` is crucial to avoid non-integer values which might
  -- affect total width of output tabline string
  local right = math.min(tabline_width, math.ceil(center + 0.5 * tot_width))
  local left = math.max(1, right - tot_width + 1)
  right = left + math.min(tot_width, tabline_width) - 1

  return { left, right }
end

function H.truncate_tabs_display(display_interval)
  local display_left, display_right = display_interval[1], display_interval[2]

  local tabs = {}
  local tabs_order = {}
  for _, bufnum in ipairs(MiniTabline.tabs_order) do
    local tab = MiniTabline.tabs[bufnum]
    local tab_left = tab.chars_on_left + 1
    local tab_right = tab.chars_on_left + tab.label_width
    if (display_left <= tab_right) and (tab_left <= display_right) then
      -- Process tab that should be displayed (even partially)
      tabs_order[#tabs_order + 1] = bufnum

      local n_trunc_left = math.max(1, display_left - tab_left + 1)
      local n_trunc_right = math.max(1, tab_right - display_right + 1)
      tab.label = tab.label:sub(n_trunc_left, -n_trunc_right)

      tabs[bufnum] = tab
    end
  end

  MiniTabline.tabs = tabs
  MiniTabline.tabs_order = tabs_order
end

---- Concatenate tabs into single tabline string
function H.concat_tabs()
  -- NOTE: it is assumed that all padding is incorporated into labels
  local t = {}
  for _, bufnum in ipairs(MiniTabline.tabs_order) do
    local tab = MiniTabline.tabs[bufnum]
    -- Escape '%' in labels
    t[#t + 1] = tab.hl .. tab.tabfunc .. tab.label:gsub('%%', '%%%%')
  end

  return table.concat(t, '') .. '%#MiniTablineFill#'
end

return MiniTabline
