-- Custom minimal **fast** tabline. This is meant to be a standalone file which
-- when sourced in 'init.*' file provides a working minimal tabline. General
-- idea: show all listed buffers in readable way with minimal total width in
-- case of one vim tab, fall back for deafult otherwise. Inspired by
-- https://github.com/ap/vim-buftabline.
--
-- Main capabilities when displaying buffers:
-- - Different highlight groups for "states" of buffer.
-- - Buffer names are made unique by extending paths to files or appending
--   unique identifier to buffers without name.
-- - Current buffer is displayed "optimally centered" (in center of screen
--   while maximizing the total number of buffers shown) when there are many
--   buffers open.
-- - 'Buffer tabs' are clickable if Neovim allows it.
--
-- Notes about structure:
-- - Main function is `MiniTabline:make_tabline_string()` which describes
--   high-level functional structure when displaying buffers. From there go to
--   respective functions.
local fn = vim.fn

-- Ensure tabline is displayed properly
vim.api.nvim_exec([[
  augroup MiniTabline
    autocmd!
    autocmd VimEnter   * lua require'mini-tabline':update_tabline()
    autocmd TabEnter   * lua require'mini-tabline':update_tabline()
    autocmd BufAdd     * lua require'mini-tabline':update_tabline()
    autocmd FileType  qf lua require'mini-tabline':update_tabline()
    autocmd BufDelete  * lua require'mini-tabline':update_tabline()
  augroup END
]], false)

vim.o.showtabline = 2 -- Always show tabline
vim.o.hidden = true   -- Allow switching buffers without saving them

-- MiniTabline object
local MiniTabline = setmetatable({}, {
  __call = function(minitabline) return minitabline:make_tabline_string() end
})

-- MiniTabline colors (from Gruvbox palette)
vim.api.nvim_exec([[
  hi MiniTablineCurrent         guibg=#7C6F64 guifg=#EBDBB2 gui=bold ctermbg=15 ctermfg=0
  hi MiniTablineActive          guibg=#3C3836 guifg=#EBDBB2 gui=bold ctermbg=7  ctermfg=0
  hi MiniTablineHidden          guifg=#A89984 guibg=#3C3836          ctermbg=8  ctermfg=7

  hi MiniTablineModifiedCurrent guibg=#458588 guifg=#EBDBB2 gui=bold ctermbg=14 ctermfg=0
  hi MiniTablineModifiedActive  guibg=#076678 guifg=#EBDBB2 gui=bold ctermbg=6  ctermfg=0
  hi MiniTablineModifiedHidden  guibg=#076678 guifg=#BDAE93          ctermbg=6  ctermfg=0

  hi MiniTablineFill NONE
]], false)

-- MiniTabline functionality
function MiniTabline:update_tabline()
  if fn.tabpagenr('$') > 1 then
    vim.o.tabline = [[]]
  else
    vim.o.tabline = [[%!v:lua.MiniTabline()]]
  end
end

function MiniTabline:make_tabline_string()
  self:list_tabs()
  self:finalize_labels()
  self:fit_width()

  return self:concat_tabs()
end

function MiniTabline:list_tabs()
  tabs = {}
  tabs_order = {}
  for i=1,fn.bufnr('$') do
    if self:is_buffer_in_minitabline(i) then
      -- Display tabs in order of increasing buffer number
      tabs_order[#tabs_order + 1] = i

      local tab = {}
      tab['hl'] = self:construct_highlight(i)
      tab['tabfunc'] = self:construct_tabfunc(i)
      tab['label'], tab['label_extender'] = self:construct_label_data(i)

      tabs[i] = tab
    end
  end

  self.tabs = tabs
  self.tabs_order = tabs_order
end

function MiniTabline:is_buffer_in_minitabline(bufnum)
  return (fn.buflisted(bufnum) > 0) and
    (fn.getbufvar(bufnum, '&buftype') ~= 'quickfix')
end

-- Tab's highlight group
function MiniTabline:construct_highlight(bufnum)
  local hl_type
  if bufnum == fn.winbufnr(0) then
    hl_type = 'Current'
  elseif fn.bufwinnr(bufnum) > 0 then
    hl_type = 'Active'
  else
    hl_type = 'Hidden'
  end
  if fn.getbufvar(bufnum, '&modified') > 0 then
    hl_type = 'Modified' .. hl_type
  end

  return string.format('%%#MiniTabline%s#', hl_type)
end

-- Tab's clickable action (if supported)
---- Is there clickable support?
MiniTabline.tablineat = fn.has('tablineat')

vim.api.nvim_exec([[
  function! MiniTablineSwitchBuffer(bufnum, clicks, button, mod)
    execute 'buffer' a:bufnum
  endfunction
]], false)

function MiniTabline:construct_tabfunc(bufnum)
  if self.tablineat > 0 then
    return string.format([[%%%d@MiniTablineSwitchBuffer@]], bufnum)
  else
    return ''
  end
end

-- Tab's label and label extender
function MiniTabline:construct_label_data(bufnum)
  local label, label_extender

  local bufpath = fn.bufname(bufnum)
  if bufpath ~= '' then
    -- Process path buffer
    label = fn.fnamemodify(bufpath, ':t')
    label_extender = self:make_path_extender(bufnum)
  else
    -- Process unnamed buffer
    label = self:make_unnamed_label(bufnum)
    label_extender = function(label) return label end
  end

  return label, label_extender
end

MiniTabline.path_sep = package.config:sub(1, 1)

function MiniTabline:make_path_extender(bufnum)
  return function(label)
    -- Add parent to current label
    local full_path = fn.fnamemodify(fn.bufname(bufnum), ':p')
    local pattern = string.format('[^%s]+%s%s$', self.path_sep, self.path_sep, label)
    return string.match(full_path, pattern) or label
  end
end

local is_buffer_scratch = function(bufnum)
  local buftype = fn.getbufvar(bufnum, '&buftype')
  return (buftype == 'acwrite') or (buftype == 'nofile')
end

function MiniTabline:make_unnamed_label(bufnum)
  local label = '*'
  if is_buffer_scratch(bufnum) then label = '!' end

  -- Possibly add tracking id (which is tracked separately for different label
  -- types)
  self:ensure_unnamed_tracked(bufnum)
  local tab_id = self.unnamed_buffers[bufnum].id
  if tab_id > 1 then
    label = string.format('%s(%d)', label, tab_id)
  end

  return label
end

-- Track all initially unnamed buffers for disambiguation. The
-- `unnamed_buffers` table is designed to store 'sequential' buffer identifier.
-- This approach allows to have the following behavior:
-- - Create three unnamed buffers.
-- - Delete second one.
-- - Tab label for third one remains the same.
MiniTabline.n_unnamed = 0
MiniTabline.unnamed_buffers = {}

function MiniTabline:ensure_unnamed_tracked(bufnum)
  if self.unnamed_buffers[bufnum] ~= nil then return end

  self.n_unnamed = self.n_unnamed + 1
  self.unnamed_buffers[bufnum] = {id = self.n_unnamed}
end

-- Finalize labels
function MiniTabline:finalize_labels()
  -- Deduplicate
  local nonunique_bufs = self:get_nonunique_buffers()
  while #nonunique_bufs > 0 do
    nothing_changed = true

    -- Extend labels
    for _, bufnum in ipairs(nonunique_bufs) do
      tab = self.tabs[bufnum]
      old_label = tab.label
      tab.label = tab.label_extender(tab.label)
      if old_label ~= tab.label then nothing_changed = false end
    end

    if nothing_changed then break end

    nonunique_bufs = self:get_nonunique_buffers()
  end

  -- Postprocess: add padding
  for _, tab in pairs(self.tabs) do
    -- -- Currently using icons doesn't quite work because later in
    -- -- `MiniTabline:fit_width()` width of label is computed using `string.len()`
    -- -- which computes number of bytes in string. Correct approach would be to
    -- -- use `utf8.len()`, but it is in Lua 5.3+.
    -- local extension = fn.fnamemodify(tab.label, ':e')
    -- local icon = require'nvim-web-devicons'.get_icon(tab.label, extension, { default = true })
    -- tab.label = string.format('%s %s ', icon, tab.label)
    tab.label = string.format(' %s ', tab.label)
  end
end

function MiniTabline:get_nonunique_buffers()
  -- Collect buffers per label
  local label_buffers = {}
  for bufnum, tab in pairs(self.tabs) do
    local label = tab.label
    if label_buffers[label] == nil then
      label_buffers[label] = {bufnum}
    else
      table.insert(label_buffers[label], bufnum)
    end
  end

  -- Collect buffers with non-unique labels
  local res = {}
  for label, bufnums in pairs(label_buffers) do
    if #bufnums > 1 then
      for _, b in pairs(bufnums) do
        table.insert(res, b)
      end
    end
  end

  return res
end

-- Fit tabline to maximum displayed width
function MiniTabline:fit_width()
  self:update_centerbuf()

  -- Compute label width data
  local center = 1
  local tot_width = 0
  -- Tabs should be processed here in order of their appearance
  for _, bufnum in pairs(self.tabs_order) do
    local tab = self.tabs[bufnum]
    -- Better to use `utf8.len()` but it is only available in Lua 5.3+
    tab.label_width = tab.label:len()
    tab.chars_on_left = tot_width

    tot_width = tot_width + tab.label_width

    if bufnum == self.centerbuf then
      -- Make end of 'center tab' to be always displayed in center in case of
      -- truncation
      center = tot_width
    end
  end

  local display_interval = self:compute_display_interval(center, tot_width)

  self:truncate_tabs_display(display_interval)
end

MiniTabline.centerbuf = fn.winbufnr(0)

function MiniTabline:update_centerbuf()
  buf_displayed = fn.winbufnr(0)
  if self:is_buffer_in_minitabline(buf_displayed) then
    self.centerbuf = buf_displayed
  end
end

function MiniTabline:compute_display_interval(center, tabline_width)
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

  return {left, right}
end

function MiniTabline:truncate_tabs_display(display_interval)
  local display_left, display_right = display_interval[1], display_interval[2]

  local tabs = {}
  local tabs_order = {}
  for _, bufnum in ipairs(self.tabs_order) do
    local tab = self.tabs[bufnum]
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

  self.tabs = tabs
  self.tabs_order = tabs_order
end

-- Concatenate tabs into single tabline string
function MiniTabline:concat_tabs()
  -- NOTE: it is assumed that all padding is incorporated into labels
  local t = {}
  for _, bufnum in ipairs(self.tabs_order) do
    local tab = self.tabs[bufnum]
    -- Escape '%' in labels
    t[#t + 1] = tab.hl .. tab.tabfunc .. tab.label:gsub('%%', '%%%%')
  end

  return table.concat(t, '') .. '%#MiniTablineFill#'
end

_G.MiniTabline = MiniTabline
return MiniTabline
