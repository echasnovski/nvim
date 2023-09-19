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

MiniExtra.ai_specs = {}

MiniExtra.ai_specs.line = function(ai_type)
  local line_num = vim.fn.line('.')
  local line = vim.fn.getline(line_num)
  -- Select `\n` past the line for `a` to delete it whole
  local from_col, to_col = 1, line:len() + 1
  -- Ignore indentation for `i` textobject and don't remove `\n` past the line
  if ai_type == 'i' then
    from_col, to_col = line:match('^(%s*)'):len(), line:len()
  end

  return { from = { line = line_num, col = from_col }, to = { line = line_num, col = to_col } }
end

MiniExtra.ai_specs.buffer = function(ai_type)
  local start_line, end_line = 1, vim.fn.line('$')
  if ai_type == 'i' then
    -- Skip first and last blank lines for `i` textobject
    local first_nonblank, last_nonblank = vim.fn.nextnonblank(start_line), vim.fn.prevnonblank(end_line)
    start_line = first_nonblank == 0 and start_line or first_nonblank
    end_line = last_nonblank == 0 and end_line or last_nonblank
  end

  local to_col = math.max(vim.fn.getline(end_line):len(), 1)
  return { from = { line = start_line, col = 1 }, to = { line = end_line, col = to_col } }
end

-- - Advise to call |MiniPick.setup()| before calling these. Or at least ensure
--   that highlight groups are defined.
MiniExtra.pickers = {}

MiniExtra.pickers.diagnostic = function(local_opts, opts)
  local pick = H.validate_pick('diagnostic')
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
    pick.default_show(items_to_show, buf_id)

    H.pick_clear_namespace(buf_id)
    for i, item in ipairs(items_to_show) do
      H.pick_highlight_line(buf_id, i, hl_groups_ref[item.severity], 199)
    end
  end

  local default_opts = { source = { name = 'Diagnostic' }, content = { show = show } }
  return H.pick_start(items, default_opts, opts)
end

-- TODO: Use only pure `vim.v.oldfiles` in favor of 'mini.frecency'
MiniExtra.pickers.oldfiles = function(local_opts, opts)
  local pick = H.validate_pick('oldfiles')
  local_opts = vim.tbl_deep_extend('force', { include_current_session = true }, local_opts or {})

  H.oldfiles_normalize()
  local items = H.oldfile_get_array()

  local show = H.pick_get_config().content.show or H.show_with_icons
  local default_opts = { source = { name = 'Oldfiles' }, content = { show = show } }
  return H.pick_start(items, default_opts, opts)
end

MiniExtra.pickers.buf_lines = function(local_opts, opts)
  local pick = H.validate_pick('buf_lines')

  local_opts = vim.tbl_deep_extend('force', { buf_id = nil }, local_opts or {})
  local buffers, all_buffers = {}, true
  if H.is_valid_buf(local_opts.buf_id) then
    buffers, all_buffers = { H.buf_resolve(local_opts.buf_id) }, false
  else
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf_id].buflisted and vim.bo[buf_id].buftype == '' then table.insert(buffers, buf_id) end
    end
  end

  local poke_picker = pick.poke_is_picker_active
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
    pick.set_picker_items(items)
  end
  local items = vim.schedule_wrap(coroutine.wrap(f))

  local show = H.pick_get_config().content.show
  if all_buffers and show == nil then show = H.show_with_icons end
  local default_opts = { source = { name = 'Buffers lines' }, content = { show = show } }
  return H.pick_start(items, default_opts, opts)
end

MiniExtra.pickers.history = function(local_opts, opts)
  local pick = H.validate_pick('history')
  local_opts = vim.tbl_deep_extend('force', { type = 'all' }, local_opts or {})

  -- Validate name
  local history_type = local_opts.type
  --stylua: ignore
  local type_ids = {
    cmd = ':',   search = '/', expr  = '=', input = '@', debug = '>',
    [':'] = ':', ['/']  = '/', ['='] = '=', ['@'] = '@', ['>'] = '>',
    ['?'] = '?',
  }
  if not (history_type == 'all' or type_ids[history_type] ~= nil) then
    H.error('`local_opts.name` in `pickers.history()` should be a valid full name for `:history` command.')
  end

  -- Construct items
  local items = {}
  local all_types = history_type == 'all' and { 'cmd', 'search', 'expr', 'input', 'debug' } or { history_type }
  for _, cur_name in ipairs(all_types) do
    local cmd_output = vim.api.nvim_exec(':history ' .. cur_name, true)
    local lines = vim.split(cmd_output, '\n')
    local id = type_ids[cur_name]
    -- Output of `:history` is sorted from oldest to newest
    for i = #lines, 2, -1 do
      local hist_entry = lines[i]:match('^.-%-?%d+%s+(.*)$')
      table.insert(items, string.format('%s %s', id, hist_entry))
    end
  end

  -- Define source
  local preview = H.pick_make_no_preview('history')

  local choose = function(item)
    if type(item) ~= 'string' then return end
    local id, entry = item:match('^(.) (.*)$')
    if id == ':' then vim.schedule(function() vim.cmd(entry) end) end
    if id == '/' or id == '?' then vim.schedule(function() vim.fn.feedkeys(id .. entry .. '\r', 'nx') end) end
  end

  local default_source = { name = string.format('History (%s)', history_type), preview = preview, choose = choose }
  return H.pick_start(items, { source = default_source }, opts)
end

MiniExtra.pickers.hl_groups = function(local_opts, opts)
  local pick = H.validate_pick('hl_groups')
  local_opts = local_opts or {}

  local group_data = vim.split(vim.api.nvim_exec('highlight', true), '\n')
  local items = {}
  for _, l in ipairs(group_data) do
    local group = l:match('^(%S+)')
    if group ~= nil then table.insert(items, group) end
  end

  local show = function(items_to_show, buf_id)
    H.set_buflines(buf_id, items_to_show)
    H.pick_clear_namespace(buf_id)
    -- Highlight line with highlight group of its item
    for i = 1, #items_to_show do
      H.pick_highlight_line(buf_id, i, items_to_show[i], 300)
    end
  end

  local preview = function(item, buf_id)
    local lines = vim.split(vim.api.nvim_exec('hi ' .. item, true), '\n')
    H.set_buflines(buf_id, lines)
  end

  local choose = function(item)
    local hl_def = vim.split(vim.api.nvim_exec('hi ' .. item, true), '\n')[1]
    hl_def = hl_def:gsub('^(%S+)%s+xxx%s+', '%1 ')
    vim.schedule(function() vim.fn.feedkeys(':hi ' .. hl_def, 'n') end)
  end

  local default_source = { name = 'Highlight groups', preview = preview, choose = choose }
  local default_opts = { source = default_source, content = { show = show } }
  return H.pick_start(items, default_opts, opts)
end

MiniExtra.pickers.commands = function(local_opts, opts)
  local pick = H.validate_pick('commands')
  local_opts = local_opts or {}

  local commands = vim.tbl_deep_extend('force', vim.api.nvim_get_commands({}), vim.api.nvim_buf_get_commands(0, {}))

  local preview = function(item, buf_id)
    local data = commands[item]
    local lines = data == nil and { string.format('No command data for `%s` is yet available.', item) }
      or vim.split(vim.inspect(data), '\n')
    H.set_buflines(buf_id, lines)
  end

  local choose = function(item)
    local data = commands[item] or {}
    -- If no arguments needed, execute immediately
    local keys = string.format(':%s%s', item, data.nargs == '0' and '\r' or ' ')
    vim.schedule(function() vim.fn.feedkeys(keys) end)
  end

  local items = vim.fn.getcompletion('', 'command')
  local default_opts = { source = { name = 'Commands', preview = preview, choose = choose } }
  return H.pick_start(items, default_opts, opts)
end

MiniExtra.pickers.git_files = function(local_opts, opts)
  local pick = H.validate_pick('git_files')
  local_opts = vim.tbl_deep_extend('force', { type = 'tracked' }, local_opts or {})

  --stylua: ignore
  local command = ({
    tracked   = { 'git', 'ls-files', '--cached' },
    modified  = { 'git', 'ls-files', '--modified' },
    untracked = { 'git', 'ls-files', '--others' },
    ignored   = { 'git', 'ls-files', '--others', '--ignored', '--exclude-standard' },
    deleted   = { 'git', 'ls-files', '--deleted' },
  })[local_opts.type]
  if command == nil then H.error('Wrong `local_opts.type` for `pickers.git_files`.') end

  local show = H.pick_get_config().content.show or H.show_with_icons
  local default_source = { name = string.format('Git files (%s)', local_opts.type) }
  opts = vim.tbl_deep_extend('force', { source = default_source, content = { show = show } }, opts or {})
  return pick.builtin.cli({ command = command }, opts)
end

-- `git_commits()` - all commits from parent Git repository of cwd
-- `git_commits({ path = vim.fn.getcwd() })` - commits affecting files from cwd
-- `git_commits({ path = vim.api.nvim_buf_get_name(0) })` - commits affecting
--   file in current buffer
MiniExtra.pickers.git_commits = function(local_opts, opts)
  local pick = H.validate_pick('git_commits')
  local_opts = vim.tbl_deep_extend('force', { path = nil, choose_type = 'checkout' }, local_opts or {})

  -- Normalize target path
  local path = type(local_opts.path) == 'string' and local_opts.path or vim.fn.getcwd()
  if path == '' then H.error('Path in `git_commits` is empty.') end
  path = vim.fn.fnamemodify(path, ':p')
  local path_is_dir, path_is_file = vim.fn.isdirectory(path) == 1, vim.fn.filereadable(path) == 1
  if not (path_is_dir or path_is_file) then H.error('Path ' .. path .. ' is not a valid path.') end

  local command = { 'git', 'log', [[--format=format:%h %s]], '--', path }
  local get_hash = function(item) return (item or ''):match('^(%S+)') end

  -- Compute path to git repo containing target path
  local path_dir = path_is_dir and path or vim.fn.fnamemodify(path, ':h')
  local repo_dir = vim.fn.systemlist('git -C ' .. path_dir .. ' rev-parse --show-toplevel')[1]
  if vim.v.shell_error ~= 0 then H.error('Could not find git repo for ' .. path .. '.') end
  if local_opts.path == nil then path = repo_dir end

  -- Define source
  local show_patch = function(item, buf_id)
    vim.bo[buf_id].syntax = 'diff'
    H.show_cli_output(buf_id, { 'git', '-C', repo_dir, '--no-pager', 'show', get_hash(item) })
  end

  local preview = show_patch

  local choose_show_patch = function(item)
    local win_target = (pick.get_picker_state().windows or {}).target
    if win_target == nil or not H.is_valid_win(win_target) then return end
    local buf_id = vim.api.nvim_create_buf(true, true)
    show_patch(item, buf_id)
    vim.api.nvim_win_set_buf(win_target, buf_id)
  end

  local choose_checkout = function(item)
    vim.schedule(function() vim.fn.system('git -C ' .. repo_dir .. ' checkout ' .. get_hash(item)) end)
  end

  local choose = local_opts.choose_type == 'show_patch' and choose_show_patch or choose_checkout

  local default_source = { name = 'Git commits', cwd = repo_dir, preview = preview, choose = choose }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {})
  return pick.builtin.cli({ command = command }, opts)
end

MiniExtra.pickers.git_branches = function(local_opts, opts)
  local pick = H.validate_pick('git_branches')
  local_opts = vim.tbl_deep_extend('force', { include_remote = false }, local_opts or {})

  local command = { 'git', 'branch', '-v', '--no-color', '--list' }
  if local_opts.include_remote then table.insert(command, 3, '--all') end

  local get_branch_name = function(item) return item:match('^%*?%s*(%S+)') end

  local preview = function(item, buf_id)
    H.show_cli_output(buf_id, { 'git', 'log', get_branch_name(item), '--format=format:%h %s' })
  end

  local choose = function(item)
    vim.schedule(function() vim.fn.system('git checkout ' .. get_branch_name(item)) end)
  end

  local default_source = { name = 'Git branches', preview = preview, choose = choose }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {})
  return pick.builtin.cli({ command = command }, opts)
end

MiniExtra.pickers.options = function(local_opts, opts)
  local pick = H.validate_pick('options')
  local_opts = vim.tbl_deep_extend('force', { scope = 'all' }, local_opts or {})

  local scope, items = local_opts.scope, {}
  for name, info in pairs(vim.api.nvim_get_all_options_info()) do
    if scope == 'all' or scope == info.scope then table.insert(items, { item = name, info = info }) end
  end
  table.sort(items, function(a, b) return a.item < b.item end)

  local show = function(items_to_show, buf_id)
    pick.default_show(items_to_show, buf_id)

    for i, item in ipairs(items_to_show) do
      if not item.info.was_set then H.pick_highlight_line(buf_id, i, 'Comment', 199) end
    end
  end

  local preview = function(item, buf_id)
    local value_source = ({ global = 'o', win = 'wo', buf = 'bo' })[item.info.scope]
    local has_value, value = pcall(function() return vim[value_source][item.info.name] end)
    if not has_value then value = '<Option is disabled (will be removed in later Neovim versions)>' end

    local lines = { 'Value:', unpack(vim.split(vim.inspect(value), '\n')), '', 'Info:' }
    local hl_lines = { 1, #lines }
    lines = vim.list_extend(lines, vim.split(vim.inspect(item.info), '\n'))

    H.set_buflines(buf_id, lines)
    H.pick_highlight_line(buf_id, hl_lines[1], 'MiniPickHeader', 200)
    H.pick_highlight_line(buf_id, hl_lines[2], 'MiniPickHeader', 200)
  end

  local choose = function(item)
    local keys = string.format(':set %s%s', item.info.name, item.info.type == 'boolean' and '' or '=')
    vim.schedule(function() vim.fn.feedkeys(keys) end)
  end

  local name = string.format('Options (%s)', scope)
  local default_opts = { source = { name = name, preview = preview, choose = choose }, content = { show = show } }
  return H.pick_start(items, default_opts, opts)
end

MiniExtra.pickers.keymaps = function(local_opts, opts)
  local pick = H.validate_pick('keymaps')
  local_opts = vim.tbl_deep_extend('force', { mode = 'all', scope = 'all' }, local_opts or {})
  local modes = local_opts.mode == 'all' and { 'n', 'x', 'i', 'o', 'c', 't', 's', 'l' } or { local_opts.mode }
  local scope = local_opts.scope

  -- Create items
  local keytrans = vim.fn.has('nvim-0.8') == 1 and vim.fn.keytrans or function(x) return x end
  local items = {}
  local max_lhs_width = 0
  local populate_items = function(source)
    for _, mode in ipairs(modes) do
      for _, maparg in ipairs(source(mode)) do
        local desc = maparg.desc ~= nil and vim.inspect(maparg.desc) or maparg.rhs
        local lhs_trans = keytrans(maparg.lhsraw or maparg.lhs)
        max_lhs_width = math.max(vim.fn.strchars(lhs_trans), max_lhs_width)
        table.insert(items, { lhs_trans = lhs_trans, desc = desc, maparg = maparg })
      end
    end
  end

  if scope == 'all' or scope == 'buf' then populate_items(function(m) return vim.api.nvim_buf_get_keymap(0, m) end) end
  if scope == 'all' or scope == 'global' then populate_items(vim.api.nvim_get_keymap) end

  for _, item in ipairs(items) do
    local buf_map_indicator = item.maparg.buffer == 0 and ' ' or '@'
    local lhs = H.ensure_text_width(item.lhs_trans, max_lhs_width)
    item.item = string.format('%s %s │ %s │ %s', item.maparg.mode, buf_map_indicator, lhs, item.desc or '')
  end

  -- Define source
  local get_callback_pos = function(maparg)
    if type(maparg.callback) ~= 'function' then return nil, nil end
    local info = debug.getinfo(maparg.callback)
    local path = info.source:gsub('^@', '')
    if vim.fn.filereadable(path) == 0 then return nil, nil end
    return path, info.linedefined
  end

  local preview = function(item, buf_id)
    local path, lnum = get_callback_pos(item.maparg)
    if path ~= nil then
      item.path, item.lnum = path, lnum
      return pick.default_preview(item, buf_id)
    end
    local lines = vim.split(vim.inspect(item.maparg), '\n')
    H.set_buflines(buf_id, lines)
  end

  local choose = function(item)
    local keys = vim.api.nvim_replace_termcodes(item.maparg.lhs, true, true, true)
    vim.schedule(function() vim.fn.feedkeys(keys) end)
  end

  local default_opts = { source = { name = string.format('Keymaps (%s)', scope), preview = preview, choose = choose } }
  return H.pick_start(items, default_opts, opts)
end

MiniExtra.pickers.registers = function(local_opts, opts)
  local pick = H.validate_pick('registers')
  local_opts = local_opts or {}

  local describe_register = function(register)
    local ok, value = pcall(vim.fn.getreg, register, 1)
    if not ok then return '' end
    return value
  end

  local all_registers = vim.split('"*+:.%/#=-0123456789abcdefghijklmnopqrstuvwxyz', '')

  local items = {}
  for _, register in ipairs(all_registers) do
    local item = string.format('%s │ %s', register, describe_register(register))
    table.insert(items, { register = register, item = item })
  end

  local choose = vim.schedule_wrap(function(item)
    local reg, mode = item.register, vim.fn.mode()
    local keys = string.format('"%s%s', reg, reg == '=' and '' or 'P')
    if mode == 'i' or mode == 'c' then keys = '\18' .. reg end
    vim.fn.feedkeys(keys)
  end)

  local preview = H.pick_make_no_preview('Registers')

  return H.pick_start(items, { source = { name = 'Registers', preview = preview, choose = choose } }, opts)
end

MiniExtra.pickers.marks = function(local_opts, opts)
  local pick = H.validate_pick('marks')
  local_opts = vim.tbl_deep_extend('force', { scope = 'all' }, local_opts or {})
  local scope = local_opts.scope

  -- Create items
  local items = {}
  local populate_items = function(mark_list)
    for _, info in ipairs(mark_list) do
      local path
      if type(info.file) == 'string' then path = vim.fn.fnamemodify(info.file, ':p:.') end
      local buf_id
      if path == nil then buf_id = info.pos[1] end

      local line, col = info.pos[2], math.abs(info.pos[3])
      local stritem = string.format('%s │ %s%s:%s', info.mark:sub(2), path == nil and '' or (path .. ':'), line, col)
      table.insert(items, { item = stritem, buf_id = buf_id, path = path, lnum = line, col = col })
    end
  end

  if scope == 'all' or scope == 'buf' then populate_items(vim.fn.getmarklist(vim.api.nvim_get_current_buf())) end
  if scope == 'all' or scope == 'global' then populate_items(vim.fn.getmarklist()) end

  local default_opts = { source = { name = string.format('Marks (%s)', scope) } }
  return H.pick_start(items, default_opts, opts)
end

-- Should be several useful ones: references, document/workspace symbols, other?
-- Basically, everything in `vim.lsp.buf` that has `on_list` option.
-- Notes:
-- - Needs Neovim>=0.8.
-- - Doesn't return anything.
MiniExtra.pickers.lsp = function(local_opts, opts)
  if vim.fn.has('nvim-0.8') == 0 then H.error('`lsp` picker requires Neovim>=0.8.') end
  local pick = H.validate_pick('lsp')
  local_opts = vim.tbl_deep_extend('force', { source = nil }, local_opts or {})

  --stylua: ignore
  local supported_sources = {
    'declaration', 'definition', 'document_symbol', 'implementation', 'references', 'type_definition', 'workspace_symbol',
  }
  local source = local_opts.source
  if source == nil then H.error('`lsp` picker needs explicit source.') end
  if not vim.tbl_contains(supported_sources, source) then
    local msg = string.format(
      '`lsp` picker does not support "%s" source. Should be one of %s.',
      source,
      table.concat(vim.tbl_map(vim.inspect, supported_sources), ', ')
    )
    H.error(msg)
  end

  if source == 'references' then return vim.lsp.buf[source](nil, { on_list = H.lsp_make_on_list(source, opts) }) end
  if source == 'workspace_symbol' then
    return vim.lsp.buf[source]('', { on_list = H.lsp_make_on_list(source, opts) })
  end
  return vim.lsp.buf[source]({ on_list = H.lsp_make_on_list(source, opts) })
end

-- Something with tree-sitter
MiniExtra.pickers.treesitter = function(local_opts, opts)
  if vim.fn.has('nvim-0.8') == 0 then H.error('`treesitter` picker requires Neovim>=0.8.') end
  local pick = H.validate_pick('treesitter')
  local_opts = local_opts or {}

  local buf_id = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(buf_id)
  if parser == nil then H.error('`treesitter` picker requires active tree-sitter parser.') end

  -- Make items by traversing roots of all trees (including injections)
  local items, traverse = {}, nil
  traverse = function(node, depth)
    if depth >= 1000 then return end
    for child in node:iter_children() do
      if child:named() then
        local lnum, col = child:range()
        local stritem = string.format('%s:%s: %s', lnum + 1, col + 1, child:type() or '')
        table.insert(items, { item = stritem, buf_id = buf_id, lnum = lnum + 1, col = col + 1 })

        traverse(child, depth + 1)
      end
    end
  end

  parser:for_each_tree(function(ts_tree, _) traverse(ts_tree:root(), 1) end)

  return H.pick_start(items, { source = { name = 'Tree-sitter nodes' } }, opts)
end

-- "quickfix", "location", "jump", "change"
MiniExtra.pickers.list = function(local_opts, opts)
  local pick = H.validate_pick('list')
  local_opts = vim.tbl_deep_extend('force', { name = 'all' }, local_opts or {})

  -- Validate name
  local name = local_opts.name
  local name_ids = { quickfix = 'Q', location = 'L', jump = 'J', change = 'C', tag = 'T' }
  if not (name == 'all' or name_ids[name] ~= nil) then
    H.error('`local_opts.name` in `pickers.list()` should be one of "quickfix", "location", "jump", "change", "tag".')
  end
end

-- ???Heuristically computed "best" files???
MiniExtra.pickers.frecency = function(local_opts, opts) end

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
H.validate_pick = function(fun_name)
  local has_pick, pick = pcall(require, 'mini-dev.pick')
  if not has_pick then
    H.error(string.format([[`pickers.%s()` requires 'mini.pick' which can not be found.]], fun_name))
  end
  return pick
end

H.pick_start = function(items, default_opts, opts)
  local pick = H.validate_pick()
  local fallback =
    { source = { preview = pick.default_preview, choose = pick.default_choose, choose_all = pick.default_choose_all } }
  local opts_final = vim.tbl_deep_extend('force', fallback, default_opts, opts or {}, { source = { items = items } })
  return pick.start(opts_final)
end

H.pick_highlight_line = function(buf_id, line, hl_group, priority)
  local opts = { end_row = line, end_col = 0, hl_mode = 'blend', hl_group = hl_group, priority = priority }
  vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.pickers, line - 1, 0, opts)
end

H.pick_clear_namespace = function(buf_id) pcall(vim.api.nvim_buf_clear_namespace, buf_id, 0, -1) end

H.pick_make_no_preview = function(picker_name)
  local lines = { string.format('No preview available for `%s` picker', picker_name) }
  return function(_, buf_id) H.set_buflines(buf_id, lines) end
end

H.pick_get_config = function()
  return vim.tbl_deep_extend('force', (require('mini-dev.pick') or {}).config or {}, vim.b.minipick_config or {})
end

H.show_with_icons =
  function(items, buf_id) require('mini-dev.pick').default_show(items, buf_id, { show_icons = true }) end

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

-- LSP picker -----------------------------------------------------------------
H.lsp_make_on_list = function(source, opts)
  -- Prepend file position info to item and sort
  local process = function(items)
    if source ~= 'document_symbol' then items = vim.tbl_map(H.lsp_make_file_posistion, items) end
    table.sort(items, H.lsp_items_compare)
    return items
  end

  -- Highlight symbol kind on Neovim>=0.9 (when `@lsp.type` groups introduced)
  local show
  if source == 'document_symbol' or source == 'workspace_symbol' then
    local pick = H.validate_pick()
    show = function(items_to_show, buf_id)
      pick.default_show(items_to_show, buf_id)

      H.pick_clear_namespace(buf_id)
      for i, item in ipairs(items_to_show) do
        -- Highlight using '@...' style highlight group with similar name
        local hl_group = string.format('@%s', string.lower(item.kind or 'unknown'))
        H.pick_highlight_line(buf_id, i, hl_group, 199)
      end
    end
  end

  return function(data)
    local items = data.items
    for _, item in ipairs(data.items) do
      item.item, item.path = item.text or '', item.filename or nil
    end
    items = process(items)

    local default_opts = { source = { name = string.format('LSP (%s)', source) }, content = { show = show } }
    return H.pick_start(items, default_opts, opts)
  end
end

H.lsp_items_compare = function(a, b)
  local a_path, b_path = a.path or '', b.path or ''
  if a_path < b_path then return true end
  if a_path > b_path then return false end

  local a_lnum, b_lnum = a.lnum or 1, b.lnum or 1
  if a_lnum < b_lnum then return true end
  if a_lnum > b_lnum then return false end

  local a_col, b_col = a.col or 1, b.col or 1
  if a_col < b_col then return true end
  if a_col > b_col then return false end

  return tostring(a) < tostring(b)
end

H.lsp_make_file_posistion = function(item)
  if item.path == nil then return end
  local path = vim.fn.fnamemodify(item.path, ':p:.')
  item.item = string.format('%s:%s:%s: %s', path, item.lnum or 1, item.col or 1, item.item)
  return item
end

-- CLI ------------------------------------------------------------------------
H.show_cli_output = function(buf_id, command)
  local executable, args = command[1], vim.list_slice(command, 2, #command)
  local process, stdout = nil, vim.loop.new_pipe()
  local spawn_opts = { args = args, stdio = { nil, stdout, nil } }
  process = vim.loop.spawn(executable, spawn_opts, function() process:close() end)

  local data_feed = {}
  stdout:read_start(vim.schedule_wrap(function(err, data)
    assert(not err, err)
    if data then return table.insert(data_feed, data) end
    if not H.is_valid_buf(buf_id) then return end

    local lines = vim.split(table.concat(data_feed), '\n')
    H.set_buflines(buf_id, lines)
  end))
end

-- Buffers --------------------------------------------------------------------
H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.buf_resolve = function(buf_id) return buf_id == 0 and vim.api.nvim_get_current_buf() or buf_id end

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
  if buf_name ~= '' then buf_name = vim.fn.fnamemodify(buf_name, ':~:.') end
  return buf_name
end

H.set_buflines = function(buf_id, lines) vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines) end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.extra) %s', msg), 0) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.ensure_text_width = function(text, width)
  local text_width = vim.fn.strchars(text)
  if text_width <= width then return text .. string.rep(' ', width - text_width) end
  return '…' .. vim.fn.strcharpart(text, text_width - width + 1, width - 1)
end

return MiniExtra
