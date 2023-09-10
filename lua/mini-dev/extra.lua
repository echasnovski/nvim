-- TODO:
--
-- - 'mini.pick':
--     - Try to match with built-ins of Telescope and Fzf-Lua.
--     - Adapter for Telescope "native" sorters.
--     - Adapter for Telescope extensions.
--
-- - 'mini.clue':
--     - Clues for 'mini.surround' and 'mini.ai'.
--
-- - 'mini.surround':
--     - Lua string spec.
--
-- - 'mini.ai':
--     - Line.
--     - Buffer.
--
-- Tests:
--
--
-- Docs:
--

--- *mini.extra* Extra 'mini.nvim' functionality
--- *MiniExtra*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.extra').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniExtra`
--- which you can use for scripting or manually (with `:lua MiniExtra.*`).
---
--- See |MiniExtra.config| for available config settings.
---
--- This module doesn't have runtime options, so using `vim.b.minimisc_config`
--- will have no effect here.
---
--- # Comparisons ~
---
--- - 'chrisgrieser/nvim-various-textobjs':

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
MiniExtra = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniExtra.config|.
---
---@usage `require('mini.pick').setup({})` (replace `{}` with your `config` table).
MiniExtra.setup = function(config)
  -- Export module
  _G.MiniExtra = MiniExtra

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniExtra.config = {}
--minidoc_afterlines_end

MiniExtra.pickers = {}

MiniExtra.pickers.diagnostic = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { buf_id = nil, get_opts = {}, sort_by_severity = true }, local_opts or {})

  local plus_one = function(x)
    if x == nil then return nil end
    return x + 1
  end

  local items = vim.diagnostic.get(local_opts.buf_id, local_opts.get_opts)
  -- NOTE: Account for output of `vim.diagnostic.get()` being  modifiable:
  -- https://github.com/neovim/neovim/pull/25010
  if vim.fn.has('nvim-0.10') == 0 then items = vim.deepcopy(items) end
  if local_opts.sort_by_severity then
    table.sort(items, function(a, b) return (a.severity or 0) < (b.severity or 0) end)
  end

  -- Compute final path width
  local path_width = 0
  for _, item in ipairs(items) do
    item.path = H.buf_get_name(item.bufnr) or ''
    path_width = math.max(path_width, vim.fn.strchars(item.path))
  end

  -- Update items
  for _, item in ipairs(items) do
    local severity = vim.diagnostic.severity[item.severity] or ' '
    local text = item.message:gsub('\n', ' ')
    item.item = string.format('%s │ %s │ %s', severity:sub(1, 1), H.ensure_text_width(item.path, path_width), text)
    item.lnum, item.col, item.end_lnum, item.end_col =
      plus_one(item.lnum), plus_one(item.col), plus_one(item.end_lnum), plus_one(item.end_col)
    item.text = string.format('%s %s', severity, text)
  end

  local hl_groups_ref = {
    [vim.diagnostic.severity.ERROR] = 'DiagnosticFloatingError',
    [vim.diagnostic.severity.WARN] = 'DiagnosticFloatingWarn',
    [vim.diagnostic.severity.INFO] = 'DiagnosticFloatingInfo',
    [vim.diagnostic.severity.HINT] = 'DiagnosticFloatingHint',
  }

  local show = function(items_to_show, buf_id)
    local lines, hl_groups = {}, {}
    for _, item in ipairs(items_to_show) do
      table.insert(lines, item.item)
      table.insert(hl_groups, hl_groups_ref[item.severity])
    end

    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    H.pickers_clear_namespace(buf_id)
    for i = 1, #lines do
      H.pickers_highlight_line(buf_id, i, hl_groups[i], 199)
    end
  end

  local default_opts = { source = { items = items, name = 'Diagnostic' }, content = { show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})
  return MiniPick.start(opts)
end

-- TODO: Think about tracking **all** buffers (as in 'mini.bracketed') and not
-- just use current buffers.
MiniExtra.pickers.oldfiles = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { include_current_session = true }, local_opts or {})

  H.oldfiles_normalize()
  local items = H.oldfile_get_array()

  local show = H.pick_get_config().content.show or H.show_with_icons
  local default_opts = { source = { name = 'Oldfiles' }, content = { show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {}, { source = { items = items } })
  MiniPick.start(opts)
end

MiniExtra.pickers.buf_lines = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { buf_id = nil }, local_opts or {})
  local buffers, all_buffers = {}, true
  if H.is_valid_buf(local_opts.buf_id) then
    buffers, all_buffers = { local_opts.buf_id }, false
  else
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf_id].buflisted and vim.bo[buf_id].buftype == '' then table.insert(buffers, buf_id) end
    end
  end

  local poke_picker = MiniPick.poke_is_picker_active
  local f = function()
    local items = {}
    for _, buf_id in ipairs(buffers) do
      if not poke_picker() then return end
      H.buf_ensure_loaded(buf_id)
      local buf_name = H.buf_get_name(buf_id) or ''
      for lnum, l in ipairs(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)) do
        local prefix = all_buffers and string.format('%s:', buf_name) or ''
        local item = { item = string.format('%s%s:%s', prefix, lnum, l), buf_id = buf_id, lnum = lnum }
        table.insert(items, item)
      end
    end
    MiniPick.set_picker_items(items)
  end
  local items = vim.schedule_wrap(coroutine.wrap(f))

  local show = H.pick_get_config().content.show
  if all_buffers and show == nil then show = H.show_with_icons end
  local default_opts = { source = { name = 'Buffers lines' }, content = { show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {}, { source = { items = items } })
  return MiniPick.start(opts)
end

MiniExtra.pickers.history = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { name = 'all' }, local_opts or {})

  -- Validate name
  local name = local_opts.name
  --stylua: ignore
  local name_ids = {
    cmd = ':',   search = '/', expr  = '=', input = '@', debug = '>',
    [':'] = ':', ['/']  = '/', ['='] = '=', ['@'] = '@', ['>'] = '>',
    ['?'] = '?',
  }
  if not (name == 'all' or name_ids[name] ~= nil) then
    H.error('`local_opts.name` in `pickers.history()` should be a valid full name for `:history` command.')
  end

  -- Construct items
  local items = {}
  local all_names = name == 'all' and { 'cmd', 'search', 'expr', 'input', 'debug' } or { name }
  for _, cur_name in ipairs(all_names) do
    local cmd_output = vim.api.nvim_exec(':history ' .. cur_name, true)
    local lines = vim.split(cmd_output, '\n')
    local id = name_ids[cur_name]
    -- Output of `:history` is sorted from oldest to newest
    for i = #lines, 2, -1 do
      local hist_entry = lines[i]:match('^.-%-?%d+%s+(.*)$')
      table.insert(items, string.format('%s %s', id, hist_entry))
    end
  end

  -- Define functions
  local choose = function(item)
    if type(item) ~= 'string' then return end
    local id, entry = item:match('^(.) (.*)$')
    if id == ':' then vim.schedule(function() vim.cmd(entry) end) end
    if id == '/' or id == '?' then vim.schedule(function() vim.fn.feedkeys(id .. entry .. '\r', 'nx') end) end
  end

  local choose_all = H.pickers_make_choose_all_first(choose)
  local preview = H.pickers_make_no_preview('history')
  local default_source =
    { name = string.format('History (%s)', name), preview = preview, choose = choose, choose_all = choose_all }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {}, { source = { items = items } })
  return MiniPick.start(opts)
end

MiniExtra.pickers.hl_groups = function(local_opts, opts)
  local_opts = local_opts or {}

  local group_data = vim.split(vim.api.nvim_exec('highlight', true), '\n')
  local items = {}
  for _, l in ipairs(group_data) do
    local group = l:match('^(%S+)')
    if group ~= nil then table.insert(items, group) end
  end

  local show = function(items_to_show, buf_id)
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, items_to_show)
    H.pickers_clear_namespace(buf_id)
    -- Highlight line with highlight group of its item
    for i = 1, #items_to_show do
      H.pickers_highlight_line(buf_id, i, items_to_show[i], 300)
    end
  end

  local preview = function(item, win_id)
    local buf_id = H.buf_new_scratch()
    local lines = vim.split(vim.api.nvim_exec('hi ' .. item, true), '\n')
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    vim.api.nvim_win_set_buf(win_id, buf_id)
  end

  local choose = function(item)
    local hl_def = vim.split(vim.api.nvim_exec('hi ' .. item, true), '\n')[1]
    hl_def = hl_def:gsub('^(%S+)%s+xxx%s+', '%1 ')
    vim.schedule(function() vim.fn.feedkeys(':hi ' .. hl_def, 'n') end)
  end

  local choose_all = H.pickers_make_choose_all_first(choose)

  local default_source = { name = 'Highlight groups', preview = preview, choose = choose, choose_all = choose_all }
  local default_opts = { source = default_source, content = { show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {}, { source = { items = items } })
  return MiniPick.start(opts)
end

MiniExtra.pickers.commands = function(local_opts, opts)
  local_opts = local_opts or {}

  local commands = vim.tbl_deep_extend('force', vim.api.nvim_get_commands({}), vim.api.nvim_buf_get_commands(0, {}))

  local preview = function(item, win_id)
    local buf_id = H.buf_new_scratch()
    local data = commands[item]
    local lines = data == nil and { string.format('No command data for `%s` is yet available.', item) }
      or vim.split(vim.inspect(data), '\n')
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    vim.api.nvim_win_set_buf(win_id, buf_id)
  end

  local choose = function(item)
    local data = commands[item] or {}
    -- If no arguments needed, execute immediately
    local keys = string.format(':%s%s', item, data.nargs == '0' and '\r' or ' ')
    vim.schedule(function() vim.fn.feedkeys(keys) end)
  end

  local choose_all = H.pickers_make_choose_all_first(choose)

  local items = vim.fn.getcompletion('', 'command')
  local default_source = { name = 'Commands', preview = preview, choose = choose, choose_all = choose_all }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {}, { source = { items = items } })
  return MiniPick.start(opts)
end

MiniExtra.pickers.git_files = function(local_opts, opts) end

MiniExtra.pickers.git_commits = function(local_opts, opts) end

MiniExtra.pickers.git_brances = function(local_opts, opts) end

-- ???Heuristically computed "best" files???
MiniExtra.pickers.frecency = function(local_opts, opts) end

MiniExtra.pickers.options = function(local_opts, opts) end

-- "quickfix", "location", "jump", "change"
MiniExtra.pickers.list = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { name = 'all' }, local_opts or {})

  -- Validate name
  local name = local_opts.name
  local name_ids = { quickfix = 'Q', location = 'L', jump = 'J', change = 'C' }
  if not (name == 'all' or name_ids[name] ~= nil) then
    H.error('`local_opts.name` in `pickers.list()` should be one of "quickfix", "location", "jump", "change".')
  end
end

-- Should be several useful ones: references, document/workspace symbols, other?
MiniExtra.pickers.lsp = function(local_opts, opts) end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniExtra.config

-- Namespaces
H.ns_id = {
  pickers = vim.api.nvim_create_namespace('MiniExtraPickers'),
}

-- Various cache
H.cache = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config) end

H.apply_config = function(config) MiniExtra.config = config end

H.create_autocommands = function()
  local augroup = vim.api.nvim_create_augroup('MiniExtra', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  au('BufEnter', '*', H.track_oldfile, 'Track oldfile')
end

-- Autocommands ---------------------------------------------------------------
H.track_oldfile = function(data)
  -- Track only appropriate buffers (normal buffers with path)
  local path = vim.api.nvim_buf_get_name(data.buf)
  local is_proper_buffer = path ~= '' and vim.bo[data.buf].buftype == ''
  if not is_proper_buffer then return end

  -- Ensure tracking data is initialized
  H.oldfile_ensure_initialized()

  -- Update recency of current path
  H.oldfile_update_recency(path)
end

-- Pickers --------------------------------------------------------------------
H.pickers_highlight_line = function(buf_id, line, hl_group, priority)
  local opts = { end_row = line, end_col = 0, hl_mode = 'blend', hl_group = hl_group, priority = priority }
  vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.pickers, line - 1, 0, opts)
end

H.pickers_clear_namespace = function(buf_id) pcall(vim.api.nvim_buf_clear_namespace, buf_id, 0, -1) end

H.pickers_make_no_preview = function(picker_name)
  local msg = string.format('No preview available for `%s` picker', picker_name)
  return function(_, win_id)
    local buf_id = H.buf_new_scratch()
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { msg })
    vim.api.nvim_win_set_buf(win_id, buf_id)
  end
end

H.pickers_make_choose_all_first = function(choose_single)
  return function(items)
    if #items == 0 then return end
    choose_single(items[1])
  end
end

H.pick_get_config =
  function() return vim.tbl_deep_extend('force', (MiniPick or {}).config or {}, vim.b.minipick_config or {}) end

-- Oldfiles picker ------------------------------------------------------------
H.oldfiles_normalize = function()
  -- Ensure that tracking data is initialized
  H.oldfile_ensure_initialized()

  -- Order currently readable paths in decreasing order of recency
  local recency_pairs = {}
  for path, rec in pairs(H.cache.oldfile.recency) do
    if vim.fn.filereadable(path) == 1 then table.insert(recency_pairs, { path, rec }) end
  end
  table.sort(recency_pairs, function(x, y) return x[2] < y[2] end)

  -- Construct new tracking data with recency from 1 to number of entries
  local new_recency = {}
  for i, pair in ipairs(recency_pairs) do
    new_recency[pair[1]] = i
  end

  H.cache.oldfile = { recency = new_recency, max_recency = #recency_pairs }
end

H.oldfile_ensure_initialized = function()
  if H.cache.oldfile ~= nil or vim.v.oldfiles == nil then return end

  local n = #vim.v.oldfiles
  local recency = {}
  for i, path in ipairs(vim.v.oldfiles) do
    if vim.fn.filereadable(path) == 1 then recency[path] = n - i + 1 end
  end

  H.cache.oldfile = { recency = recency, max_recency = n }
end

H.oldfile_get_array = function()
  local res, n_res = {}, vim.tbl_count(H.cache.oldfile.recency)
  for path, i in pairs(H.cache.oldfile.recency) do
    -- Elements with maximum recency should be first
    res[n_res - i + 1] = vim.fn.fnamemodify(path, ':.')
  end
  return res
end

H.oldfile_update_recency = function(path)
  local n = H.cache.oldfile.max_recency + 1
  H.cache.oldfile.recency[path] = n
  H.cache.oldfile.max_recency = n
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.extra) %s', msg), 0) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.buf_ensure_loaded = function(buf_id)
  if type(buf_id) ~= 'number' or vim.api.nvim_buf_is_loaded(buf_id) then return end
  local cache_eventignore = vim.o.eventignore
  vim.o.eventignore = 'BufEnter'
  vim.fn.bufload(buf_id)
  vim.o.eventignore = cache_eventignore
end

H.buf_get_name = function(buf_id)
  if not H.is_valid_buf(buf_id) then return nil end
  local buf_name = vim.api.nvim_buf_get_name(buf_id)
  if buf_name ~= '' then buf_name = vim.fn.fnamemodify(buf_name, ':.') end
  return buf_name
end

H.buf_new_scratch = function()
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.bo[buf_id].bufhidden = 'wipe'
  return buf_id
end

H.ensure_text_width = function(text, width)
  local text_width = vim.fn.strchars(text)
  if text_width <= width then return text .. string.rep(' ', width - text_width) end
  return '…' .. vim.fn.strcharpart(text, text_width - width + 1, width - 1)
end

H.show_with_icons = function(items, buf_id) MiniPick.default_show(items, buf_id, { show_icons = true }) end

return MiniExtra
