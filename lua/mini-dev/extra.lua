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

  -- Compute recency (the more the less recent) of readable files
  local file_times, oldfiles = {}, vim.v.oldfiles or {}
  for i = 1, #oldfiles do
    if vim.fn.filereadable(oldfiles[i]) == 1 then file_times[oldfiles[i]] = i end
  end

  if local_opts.include_current_session then
    local good_bufs = vim.tbl_filter(
      function(x) return vim.fn.filereadable(x.name) == 1 end,
      vim.fn.getbufinfo({ buflisted = true })
    )
    for _, buf_info in ipairs(good_bufs) do
      file_times[buf_info.name] = -buf_info.lastused
    end
  end

  -- Compute items from most to least recent
  local files_with_times = {}
  for path, time in pairs(file_times) do
    table.insert(files_with_times, { path = path, time = time })
  end
  table.sort(files_with_times, function(a, b) return a.time < b.time end)
  local items = vim.tbl_map(function(x) return vim.fn.fnamemodify(x.path, ':.') end, files_with_times)

  opts = vim.tbl_deep_extend('force', { source = { name = 'Oldfiles' } }, opts or {}, { source = { items = items } })
  MiniPick.start(opts)
end

MiniExtra.pickers.buf_lines = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { buf_id = nil }, local_opts or {})
  local buffers, show_source = {}, true
  if H.is_valid_buf(local_opts.buf_id) then
    buffers, show_source = { local_opts.buf_id }, false
  else
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf_id].buflisted and vim.bo[buf_id].buftype == '' then table.insert(buffers, buf_id) end
    end
  end

  -- TODO: make it async because first loading takes visible time
  local items = {}
  for _, buf_id in ipairs(buffers) do
    H.buf_ensure_loaded(buf_id)
    local buf_name = H.buf_get_name(buf_id) or ''
    for lnum, l in ipairs(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)) do
      local prefix = show_source and string.format('%s:', buf_name) or ''
      local item = { item = string.format('%s%s:%s', prefix, lnum, l), buf_id = buf_id, lnum = lnum }
      table.insert(items, item)
    end
  end

  local show = show_source and H.show_with_icons or nil
  local default_opts = { source = { name = 'Buffer lines' }, content = { show = show } }
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

MiniExtra.pickers.commands = function(local_opts, opts) end

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

-- Helper data ================================================================
-- Module default config
H.default_config = MiniExtra.config

-- Namespaces
H.ns_id = {
  pickers = vim.api.nvim_create_namespace('MiniExtraPickers'),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config) end

H.apply_config = function(config) MiniExtra.config = config end

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
