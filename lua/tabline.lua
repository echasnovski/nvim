utils = require"_utils"

local fn = vim.fn

vim.api.nvim_exec([[
  function! TablineSwitchBuffer(bufnum, clicks, button, mod)
    execute 'buffer' a:bufnum
  endfunction
]], false)

local SID = function()
  return fn.matchstr(fn.expand([[<sfile>]]), [[<SNR>\d\+_]])
end

local tabfunc_name = SID() .. 'TablineSwitchBuffer'
local path_sep = package.config:sub(1,1)
local centerbuf = fn.winbufnr(0)
local tablineat = fn.has('tablineat')

-- Track all scratch and unnamed buffers for disambiguation. These dictionaries
-- are designed to store 'sequential' buffer identifier. This approach allows
-- to have the following behavior:
-- - Create three scratch (or unnamed) buffers.
-- - Delete second one.
-- - Tab label for third one remains the same.
local scratch_tabs = {n_tabs = 0}
local unnamed_tabs = {n_tabs = 0}

-- List all candidate buffers
local construct_highlight = function(bufnum)
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

local construct_tabfunc = function(bufnum)
  if tablineat > 0 then
    return string.format([[%%%d@%s@]], bufnum, tabfunc_name)
  else
    return ''
  end
end

local is_scratch_buffer = function(bufnum)
  local buftype = fn.getbufvar(bufnum, '&buftype')
  return (buftype == 'acwrite') or (buftype == 'nofile')
end

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

local construct_labels = function(bufnum)
  local label, full_label

  local bufpath = fn.bufname(bufnum)
  if fn.strlen(bufpath) > 0 then
    -- Process path buffer
    label = fn.fnamemodify(bufpath, ':t')
    full_label = fn.fnamemodify(bufpath, ':p:~:.')
  elseif is_scratch_buffer(bufnum) then
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

user_buffers = function()
  t = {}
  for i=1,fn.bufnr('$') do
    if (fn.buflisted(i) > 0) and (fn.getbufvar(i, '&buftype') ~= 'quickfix') then
      local tab = {}
      tab['num'] = i
      tab['tabfunc'] = construct_tabfunc(i)
      tab['hl'] = construct_highlight(i)
      tab['label'], tab['full_label'] = construct_labels(i)

      t[#t + 1] = tab
    end
  end
  return t
end

make_tabline = function()
  -- local start = os.clock()

  local buffers = user_buffers()
  local t = {}
  for _, tab in pairs(buffers) do
    t[#t + 1] = tab.hl .. tab.tabfunc .. ' ' .. tab.label .. ' '
  end

  -- res = table.concat(t, '') .. '%#TabLineFill#'
  -- print(os.clock() - start)
  -- return res

  return table.concat(t, '') .. '%#TabLineFill#'
end

tabline_update = function()
  if fn.tabpagenr('$') > 1 then
    vim.o.tabline = [[]]
  else
    vim.o.tabline = [[%!luaeval('make_tabline()')]]
  end
end

-- vim.api.nvim_exec([[
--   augroup TabLine
--     autocmd!
--     autocmd VimEnter   * lua tabline_update()
--     autocmd TabEnter   * lua tabline_update()
--     autocmd BufAdd     * lua tabline_update()
--     autocmd FileType  qf lua tabline_update()
--     autocmd BufDelete  * lua tabline_update()
--   augroup END
-- ]], false)
