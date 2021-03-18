local fn = vim.fn

local is_buffer_in_btline = function(bufnum)
  return (fn.buflisted(bufnum) > 0) and (fn.getbufvar(bufnum, '&buftype') ~= 'quickfix')
end

local is_buffer_scratch = function(bufnum)
  local buftype = fn.getbufvar(bufnum, '&buftype')
  return (buftype == 'acwrite') or (buftype == 'nofile')
end

-- vim.api.nvim_exec([[
--   augroup TabLine
--     autocmd!
--     autocmd VimEnter   * lua require'btline':update_tabline()
--     autocmd TabEnter   * lua require'btline':update_tabline()
--     autocmd BufAdd     * lua require'btline':update_tabline()
--     autocmd FileType  qf lua require'btline':update_tabline()
--     autocmd BufDelete  * lua require'btline':update_tabline()
--   augroup END
-- ]], false)

Btline = {}
Btline = setmetatable({}, {
  __call = function(btline) return btline:make_tabline_string() end
})

function Btline:update_tabline()
  if fn.tabpagenr('$') > 1 then
    vim.o.tabline = [[]]
  else
    vim.o.tabline = [[%!v:lua.Btline()]]
  end
end

function Btline:make_tabline_string()
  -- local start = os.clock()

  self:list_tabs()

  local t = {}
  for _, tab in pairs(self.tabs) do
    t[#t + 1] = tab.hl .. tab.tabfunc .. ' ' .. tab.label .. ' '
  end

  -- res = table.concat(t, '') .. '%#TabLineFill#'
  -- print(os.clock() - start)
  -- return res

  return table.concat(t, '') .. '%#TabLineFill#'
end

function Btline:list_tabs()
  t = {}
  for i=1,fn.bufnr('$') do
    if is_buffer_in_btline(i) then
      -- self:ensure_buffer_tracked(i)

      local tab = {}
      tab['bufnum'] = i
      tab['hl'] = self:construct_highlight(i)
      tab['tabfunc'] = self:construct_tabfunc(i)
      tab['label'], tab['full_label'] = self:construct_labels(i)

      t[#t + 1] = tab
    end
  end

  self.tabs = t
end

Btline.n_scratch = 0
Btline.n_unnamed = 0

Btline.buffers = {}

function Btline:ensure_buffer_tracked(bufnum)
  if self.buffers[bufnum] ~= nil then return end

  local bufpath = fn.bufname(bufnum)
  print(bufpath)
  if bufpath ~= '' then
    self.buffers[bufnum] = {label = fn.fnamemodify(bufpath, ':t')}
  elseif is_buffer_scratch(bufnum) then
    self.n_scratch = self.n_scratch + 1
    self.buffers[bufnum] = {id = self.n_scratch}
  else
    self.n_unnamed = self.n_unnamed + 1
    self.buffers[bufnum] = {id = self.n_unnamed}
  end
end


-- Track all scratch and unnamed buffers for disambiguation. These dictionaries
-- are designed to store 'sequential' buffer identifier. This approach allows
-- to have the following behavior:
-- - Create three scratch (or unnamed) buffers.
-- - Delete second one.
-- - Tab label for third one remains the same.
local scratch_tabs = {n_tabs = 0}
local unnamed_tabs = {n_tabs = 0}

-- Tab's highlight group
function Btline:construct_highlight(bufnum)
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

  return string.format('%%#TabLine%s#', hl_type)
end

-- Tab's clickable action (if supported)
---- Is there clickable support?
Btline.tablineat = fn.has('tablineat')

vim.api.nvim_exec([[
  function! BtlineSwitchBuffer(bufnum, clicks, button, mod)
    execute 'buffer' a:bufnum
  endfunction
]], false)

function Btline:construct_tabfunc(bufnum)
  if self.tablineat > 0 then
    return string.format([[%%%d@BtlineSwitchBuffer@]], bufnum)
  else
    return ''
  end
end

-- Tab's label and label deduplicator
local get_nonpath_label = function(bufnum, track_table, basic_label)
  if track_table[bufnum] == nil then
    track_table['n_tabs'] = track_table['n_tabs'] + 1
    track_table[bufnum] = track_table['n_tabs']
  end

  local tab_id = track_table[bufnum]

  -- Only show 'sequential' id starting from second tab
  if tab_id == 1 then
    return basic_label
  else
    return string.format('%s(%d)', basic_label, tab_id)
  end
end

function Btline:construct_labels(bufnum)
  local label, full_label

  local bufpath = fn.bufname(bufnum)
  if bufpath ~= '' then
    -- Process path buffer
    label = fn.fnamemodify(bufpath, ':t')
    full_label = fn.fnamemodify(bufpath, ':p:~:.')
  elseif is_buffer_scratch(bufnum) then
    -- Process scratch buffer
    label = get_nonpath_label(bufnum, scratch_tabs, '!')
    full_label = nil
  else
    -- Process unnamed buffer
    label = get_nonpath_label(bufnum, unnamed_tabs, '*')
    full_label = nil
  end

  return label, full_label
end

-- Track buffers
-- vim.api.nvim_exec([[
--   autocmd BufAdd * lua require'btline':track_buffers()
-- ]], false)

return Btline
