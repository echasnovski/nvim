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
  local_opts = vim.tbl_deep_extend('force', { scope = 'all', get_opts = {}, sort_by_severity = true }, local_opts or {})

  local scope = H.pick_validate_scope(local_opts, { 'all', 'current' }, 'diagnostic')

  local plus_one = function(x)
    if x == nil then return nil end
    return x + 1
  end

  local diag_buf_id
  if scope == 'current' then diag_buf_id = vim.api.nvim_get_current_buf() end
  local items = vim.diagnostic.get(diag_buf_id, local_opts.get_opts)

  -- NOTE: Account for output of `vim.diagnostic.get()` being  modifiable:
  -- https://github.com/neovim/neovim/pull/25010
  if vim.fn.has('nvim-0.10') == 0 then items = vim.deepcopy(items) end

  -- Compute final path width
  local path_width = 0
  for _, item in ipairs(items) do
    item.path = H.buf_get_name(item.bufnr) or ''
    path_width = math.max(path_width, vim.fn.strchars(item.path))
  end

  -- Sort
  -- TODO: ?Sort by path?
  if local_opts.sort_by_severity then
    table.sort(items, function(a, b) return (a.severity or 0) < (b.severity or 0) end)
  end

  -- Update items
  for _, item in ipairs(items) do
    local severity = vim.diagnostic.severity[item.severity] or ' '
    local text = item.message:gsub('\n', ' ')
    item.text = string.format('%s │ %s │ %s', severity:sub(1, 1), H.ensure_text_width(item.path, path_width), text)
    item.lnum, item.col, item.end_lnum, item.end_col =
      plus_one(item.lnum), plus_one(item.col), plus_one(item.end_lnum), plus_one(item.end_col)
  end

  local hl_groups_ref = {
    [vim.diagnostic.severity.ERROR] = 'DiagnosticFloatingError',
    [vim.diagnostic.severity.WARN] = 'DiagnosticFloatingWarn',
    [vim.diagnostic.severity.INFO] = 'DiagnosticFloatingInfo',
    [vim.diagnostic.severity.HINT] = 'DiagnosticFloatingHint',
  }

  local show = function(buf_id, items_to_show, query)
    pick.default_show(buf_id, items_to_show, query)

    H.pick_clear_namespace(buf_id)
    for i, item in ipairs(items_to_show) do
      H.pick_highlight_line(buf_id, i, hl_groups_ref[item.severity], 199)
    end
  end

  return H.pick_start(items, { source = { name = 'Diagnostic', show = show } }, opts)
end

MiniExtra.pickers.oldfiles = function(local_opts, opts)
  local pick = H.validate_pick('oldfiles')
  local_opts = local_opts or {}

  local oldfiles = vim.v.oldfiles
  if not vim.tbl_islist(oldfiles) then H.error('`oldfiles` picker needs valid `v:oldfiles`.') end

  local items = {}
  for _, path in ipairs(oldfiles) do
    if vim.fn.filereadable(path) == 1 then table.insert(items, path) end
  end

  local show = H.pick_get_config().source.show or H.show_with_icons
  return H.pick_start(items, { source = { name = 'Oldfiles', show = show } }, opts)
end

MiniExtra.pickers.buf_lines = function(local_opts, opts)
  local pick = H.validate_pick('buf_lines')
  local_opts = vim.tbl_deep_extend('force', { scope = 'all' }, local_opts or {})

  local scope = H.pick_validate_scope(local_opts, { 'all', 'current' }, 'buf_lines')
  local is_scope_all = scope == 'all'

  local buffers = {}
  if is_scope_all then
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf_id].buflisted and vim.bo[buf_id].buftype == '' then table.insert(buffers, buf_id) end
    end
  else
    buffers = { vim.api.nvim_get_current_buf() }
  end

  local poke_picker = pick.poke_is_picker_active
  local f = function()
    local items = {}
    for _, buf_id in ipairs(buffers) do
      if not poke_picker() then return end
      H.buf_ensure_loaded(buf_id)
      local buf_name = H.buf_get_name(buf_id) or ''
      for lnum, l in ipairs(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)) do
        local prefix = is_scope_all and string.format('%s:', buf_name) or ''
        table.insert(items, { text = string.format('%s%s:%s', prefix, lnum, l), bufnr = buf_id, lnum = lnum })
      end
    end
    pick.set_picker_items(items)
  end
  local items = vim.schedule_wrap(coroutine.wrap(f))

  local show = H.pick_get_config().source.show
  if is_scope_all and show == nil then show = H.show_with_icons end
  return H.pick_start(items, { source = { name = string.format('Buffers lines (%s)', scope), show = show } }, opts)
end

MiniExtra.pickers.history = function(local_opts, opts)
  local pick = H.validate_pick('history')
  local_opts = vim.tbl_deep_extend('force', { scope = 'all' }, local_opts or {})

  local allowed_scope = { 'all', 'cmd', 'search', 'expr', 'input', 'debug', ':', '/', '?', '=', '@', '>' }
  local scope = H.pick_validate_scope(local_opts, allowed_scope, 'history')

  --stylua: ignore
  local type_ids = {
    cmd = ':',   search = '/', expr  = '=', input = '@', debug = '>',
    [':'] = ':', ['/']  = '/', ['='] = '=', ['@'] = '@', ['>'] = '>',
    ['?'] = '?',
  }

  -- Construct items
  local items = {}
  local names = scope == 'all' and { 'cmd', 'search', 'expr', 'input', 'debug' } or { scope }
  for _, cur_name in ipairs(names) do
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

  local default_source = { name = string.format('History (%s)', scope), preview = preview, choose = choose }
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

  local show = function(buf_id, items_to_show, query)
    H.set_buflines(buf_id, items_to_show)
    H.pick_clear_namespace(buf_id)
    -- Highlight line with highlight group of its item
    for i = 1, #items_to_show do
      H.pick_highlight_line(buf_id, i, items_to_show[i], 300)
    end
  end

  local preview = function(buf_id, item)
    local lines = vim.split(vim.api.nvim_exec('hi ' .. item, true), '\n')
    H.set_buflines(buf_id, lines)
  end

  local choose = function(item)
    local hl_def = vim.split(vim.api.nvim_exec('hi ' .. item, true), '\n')[1]
    hl_def = hl_def:gsub('^(%S+)%s+xxx%s+', '%1 ')
    vim.schedule(function() vim.fn.feedkeys(':hi ' .. hl_def, 'n') end)
  end

  local default_source = { name = 'Highlight groups', show = show, preview = preview, choose = choose }
  return H.pick_start(items, { source = default_source }, opts)
end

MiniExtra.pickers.commands = function(local_opts, opts)
  local pick = H.validate_pick('commands')
  local_opts = local_opts or {}

  local commands = vim.tbl_deep_extend('force', vim.api.nvim_get_commands({}), vim.api.nvim_buf_get_commands(0, {}))

  local preview = function(buf_id, item)
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
  local_opts = vim.tbl_deep_extend('force', { scope = 'tracked' }, local_opts or {})

  local allowed_scope = { 'tracked', 'modified', 'untracked', 'ignored', 'deleted' }
  local scope = H.pick_validate_scope(local_opts, allowed_scope, 'git_files')

  --stylua: ignore
  local command = ({
    tracked   = { 'git', 'ls-files', '--cached' },
    modified  = { 'git', 'ls-files', '--modified' },
    untracked = { 'git', 'ls-files', '--others' },
    ignored   = { 'git', 'ls-files', '--others', '--ignored', '--exclude-standard' },
    deleted   = { 'git', 'ls-files', '--deleted' },
  })[local_opts.scope]

  local show = H.pick_get_config().source.show or H.show_with_icons
  local default_source = { name = string.format('Git files (%s)', local_opts.scope), show = show }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {})
  return pick.builtin.cli({ command = command }, opts)
end

-- `git_commits()` - all commits from parent Git repository of cwd
-- `git_commits({ path = vim.fn.getcwd() })` - commits affecting files from cwd
-- `git_commits({ path = vim.api.nvim_buf_get_name(0) })` - commits affecting
--   file in current buffer
MiniExtra.pickers.git_commits = function(local_opts, opts)
  local pick = H.validate_pick('git_commits')
  local_opts = vim.tbl_deep_extend('force', { path = nil, choose_type = 'checkout' }, local_opts or {})

  local path, path_type = H.git_normalize_path(local_opts.path, 'git_commits')
  local command = { 'git', 'log', [[--format=format:%h %s]], '--', path }
  local get_hash = function(item) return (item or ''):match('^(%S+)') end

  -- Compute path to repo with target path (as it might differ from current)
  local repo_dir = H.git_get_repo_dir(path, path_type)
  if local_opts.path == nil then path = repo_dir end

  -- Define source
  local show_patch = function(buf_id, item)
    vim.bo[buf_id].syntax = 'diff'
    H.show_cli_output(buf_id, { 'git', '-C', repo_dir, '--no-pager', 'show', get_hash(item) })
  end

  local preview = show_patch

  local choose_show_patch = function(item)
    local win_target = (pick.get_picker_state().windows or {}).target
    if win_target == nil or not H.is_valid_win(win_target) then return end
    local buf_id = vim.api.nvim_create_buf(true, true)
    show_patch(buf_id, item)
    vim.api.nvim_win_set_buf(win_target, buf_id)
  end

  local choose_checkout = function(item)
    vim.schedule(function() vim.fn.system('git -C ' .. repo_dir .. ' checkout ' .. get_hash(item)) end)
  end

  local choose = local_opts.choose_type == 'show_patch' and choose_show_patch or choose_checkout

  local name = string.format('Git commits (%s)', local_opts.path == nil and 'all' or 'for path')
  local default_source = { name = name, cwd = repo_dir, preview = preview, choose = choose }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {})
  return pick.builtin.cli({ command = command }, opts)
end

MiniExtra.pickers.git_diff = function(local_opts, opts)
  local pick = H.validate_pick('git_diff')
  local_opts = vim.tbl_deep_extend('force', { path = nil, scope = 'unstaged', n_context = 3 }, local_opts or {})

  local path, path_type = H.git_normalize_path(local_opts.path, 'git_commits')
  local scope = H.pick_validate_scope(local_opts, { 'unstaged', 'staged' }, 'git_diff')
  local ok_context, n_context = pcall(math.floor, local_opts.n_context)
  if not (ok_context and n_context >= 0) then
    H.error('`n_context` option in `git_diff` picker should be non-negative number.')
  end

  local command = { 'git', 'diff', '--patch', '--unified=' .. n_context, '--color=never', '--', path }
  if scope == 'staged' then table.insert(command, 4, '--cached') end

  local repo_dir = H.git_get_repo_dir(path, path_type)
  if local_opts.path == nil then path = repo_dir end

  local postprocess = function(lines) return H.git_difflines_to_hunkitems(lines, n_context) end

  local preview = function(buf_id, item)
    vim.bo[buf_id].syntax = 'diff'
    H.set_buflines(buf_id, item.hunk)
  end

  -- TODO: Think about adding "toggle stage" mapping or choose option

  local name = string.format('Git diff (%s %s)', scope, local_opts.path == nil and 'for path' or 'all')
  local default_source = { name = name, cwd = repo_dir, preview = preview }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {})
  return pick.builtin.cli({ command = command, postprocess = postprocess }, opts)
end

MiniExtra.pickers.git_branches = function(local_opts, opts)
  local pick = H.validate_pick('git_branches')
  local_opts = vim.tbl_deep_extend('force', { scope = 'all' }, local_opts or {})

  local scope = H.pick_validate_scope(local_opts, { 'all', 'local', 'remotes' }, 'git_branches')

  local command = { 'git', 'branch', '-v', '--no-color', '--list' }
  if scope == 'all' or scope == 'remotes' then table.insert(command, 3, '--' .. scope) end

  local get_branch_name = function(item) return item:match('^%*?%s*(%S+)') end

  local preview = function(buf_id, item)
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

  local scope = H.pick_validate_scope(local_opts, { 'all', 'global', 'win', 'buf' }, 'options')

  local items = {}
  for name, info in pairs(vim.api.nvim_get_all_options_info()) do
    if scope == 'all' or scope == info.scope then table.insert(items, { text = name, info = info }) end
  end
  table.sort(items, function(a, b) return a.text < b.text end)

  local show = function(buf_id, items_to_show, query)
    pick.default_show(buf_id, items_to_show, query)

    for i, item in ipairs(items_to_show) do
      if not item.info.was_set then H.pick_highlight_line(buf_id, i, 'Comment', 199) end
    end
  end

  local preview = function(buf_id, item)
    local value_source = ({ global = 'o', win = 'wo', buf = 'bo' })[item.info.scope]
    local has_value, value = pcall(function() return vim[value_source][item.info.name] end)
    if not has_value then value = '<Option is deprecated (will be removed in later Neovim versions)>' end

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
  local default_source = { name = name, show = show, preview = preview, choose = choose }
  return H.pick_start(items, { source = default_source }, opts)
end

MiniExtra.pickers.keymaps = function(local_opts, opts)
  local pick = H.validate_pick('keymaps')
  local_opts = vim.tbl_deep_extend('force', { mode = 'all', scope = 'all' }, local_opts or {})

  local mode = H.pick_validate_one_of('mode', local_opts, { 'all', 'n', 'x', 'i', 'o', 'c', 't', 's', 'l' }, 'keymaps')
  local scope = H.pick_validate_scope(local_opts, { 'all', 'global', 'buf' }, 'keymaps')

  -- Create items
  local keytrans = vim.fn.has('nvim-0.8') == 1 and vim.fn.keytrans or function(x) return x end
  local items = {}
  local max_lhs_width = 0
  local populate_items = function(source)
    local modes = mode == 'all' and { 'n', 'x', 'i', 'o', 'c', 't', 's', 'l' } or { mode }
    for _, m in ipairs(modes) do
      for _, maparg in ipairs(source(m)) do
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
    item.text = string.format('%s %s │ %s │ %s', item.maparg.mode, buf_map_indicator, lhs, item.desc or '')
  end

  -- Define source
  local get_callback_pos = function(maparg)
    if type(maparg.callback) ~= 'function' then return nil, nil end
    local info = debug.getinfo(maparg.callback)
    local path = info.source:gsub('^@', '')
    if vim.fn.filereadable(path) == 0 then return nil, nil end
    return path, info.linedefined
  end

  local preview = function(buf_id, item)
    local path, lnum = get_callback_pos(item.maparg)
    if path ~= nil then
      item.path, item.lnum = path, lnum
      return pick.default_preview(buf_id, item)
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
    local text = string.format('%s │ %s', register, describe_register(register))
    table.insert(items, { register = register, text = text })
  end

  local choose = vim.schedule_wrap(function(item)
    local reg, mode = item.register, vim.fn.mode()
    local keys = string.format('"%s%s', reg, reg == '=' and '' or 'P')
    if mode == 'i' or mode == 'c' then keys = '\18' .. reg end
    vim.fn.feedkeys(keys)
  end)

  local preview = H.pick_make_no_preview('registers')

  return H.pick_start(items, { source = { name = 'Registers', preview = preview, choose = choose } }, opts)
end

MiniExtra.pickers.marks = function(local_opts, opts)
  local pick = H.validate_pick('marks')
  local_opts = vim.tbl_deep_extend('force', { scope = 'all' }, local_opts or {})

  local scope = H.pick_validate_scope(local_opts, { 'all', 'global', 'buf' }, 'marks')

  -- Create items
  local items = {}
  local populate_items = function(mark_list)
    for _, info in ipairs(mark_list) do
      local path
      if type(info.file) == 'string' then path = vim.fn.fnamemodify(info.file, ':p:.') end
      local buf_id
      if path == nil then buf_id = info.pos[1] end

      local line, col = info.pos[2], math.abs(info.pos[3])
      local text = string.format('%s │ %s%s:%s', info.mark:sub(2), path == nil and '' or (path .. ':'), line, col)
      table.insert(items, { text = text, bufnr = buf_id, path = path, lnum = line, col = col })
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
  local_opts = vim.tbl_deep_extend('force', { scope = nil }, local_opts or {})

  if local_opts.scope == nil then H.error('`lsp` picker needs explicit scope.') end
  --stylua: ignore
  local allowed_scopes = {
    'declaration', 'definition', 'document_symbol', 'implementation', 'references', 'type_definition', 'workspace_symbol',
  }
  local scope = H.pick_validate_scope(local_opts, allowed_scopes, 'lsp')

  if scope == 'references' then return vim.lsp.buf[scope](nil, { on_list = H.lsp_make_on_list(scope, opts) }) end
  if scope == 'workspace_symbol' then return vim.lsp.buf[scope]('', { on_list = H.lsp_make_on_list(scope, opts) }) end
  return vim.lsp.buf[scope]({ on_list = H.lsp_make_on_list(scope, opts) })
end

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
        local lnum, col, end_lnum, end_col = child:range()
        lnum, col, end_lnum, end_col = lnum + 1, col + 1, end_lnum + 1, end_col + 1
        local indent = string.rep(' ', depth)
        local text = string.format('%s%s (%s:%s - %s:%s)', indent, child:type() or '', lnum, col, end_lnum, end_col)
        local item = { text = text, bufnr = buf_id, lnum = lnum, col = col, end_lnum = end_lnum, end_col = end_col }
        table.insert(items, item)

        traverse(child, depth + 1)
      end
    end
  end

  parser:for_each_tree(function(ts_tree, _) traverse(ts_tree:root(), 0) end)

  return H.pick_start(items, { source = { name = 'Tree-sitter nodes' } }, opts)
end

MiniExtra.pickers.list = function(local_opts, opts)
  local pick = H.validate_pick('list')
  local_opts = vim.tbl_deep_extend('force', { scope = nil }, local_opts or {})

  if local_opts.scope == nil then H.error('`list` picker needs explicit scope.') end
  local allowed_scopes = { 'quickfix', 'location', 'jump', 'change' }
  local scope = H.pick_validate_scope(local_opts, allowed_scopes, 'list')

  local has_items, items = pcall(H.list_get[scope])
  if not has_items then items = {} end

  items = vim.tbl_filter(function(x) return H.is_valid_buf(x.bufnr) end, items)
  items = vim.tbl_map(H.list_enhance_item, items)

  local choose = function(item)
    pick.default_choose(item)

    -- Force 'buflisted' on opened item
    local win_target = pick.get_picker_state().windows.target
    local buf_id = vim.api.nvim_win_get_buf(win_target)
    add_to_log('list choose', win_target, buf_id, vim.api.nvim_buf_get_name(buf_id))
    vim.bo[buf_id].buflisted = true
  end

  return H.pick_start(items, { source = { name = string.format('List (%s)', scope), choose = choose } }, opts)
end

-- Register in 'mini.pick'
if type(MiniPick) == 'table' then
  for name, f in pairs(MiniExtra.pickers) do
    MiniPick.registry[name] = function(local_opts) return f(local_opts) end
  end
end

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
  local fallback = {
    source = {
      preview = pick.default_preview,
      choose = pick.default_choose,
      choose_marked = pick.default_choose_marked,
    },
  }
  local opts_final = vim.tbl_deep_extend('force', fallback, default_opts, opts or {}, { source = { items = items } })
  return pick.start(opts_final)
end

H.pick_highlight_line = function(buf_id, line, hl_group, priority)
  local opts = { end_row = line, end_col = 0, hl_mode = 'blend', hl_group = hl_group, priority = priority }
  vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.pickers, line - 1, 0, opts)
end

H.pick_prepend_position = function(item)
  local path
  if item.path ~= nil then
    path = item.path
  elseif H.is_valid_buf(item.bufnr) then
    local name = vim.api.nvim_buf_get_name(item.bufnr)
    if name ~= '' then path = name end
  end
  if path == nil then return item end

  path = vim.fn.fnamemodify(path, ':p:.')
  local cur_text = item.text
  local suffix = (cur_text == nil or cur_text == '') and '' or (': ' .. item.text)
  item.text = string.format('%s:%s:%s%s', path, item.lnum or 1, item.col or 1, suffix)
  return item
end

H.pick_clear_namespace = function(buf_id) pcall(vim.api.nvim_buf_clear_namespace, buf_id, 0, -1) end

H.pick_make_no_preview = function(picker_name)
  local lines = { string.format('No preview available for `%s` picker', picker_name) }
  return function(buf_id, _) H.set_buflines(buf_id, lines) end
end

H.pick_validate_one_of = function(target, opts, values, picker_name)
  if vim.tbl_contains(values, opts[target]) then return opts[target] end
  local msg = string.format(
    '`pickers.%s` has wrong "%s" local option (%s). Should be one of %s.',
    picker_name,
    target,
    vim.inspect(opts[target]),
    table.concat(vim.tbl_map(vim.inspect, values), ', ')
  )
  H.error(msg)
end

H.pick_validate_scope = function(...) return H.pick_validate_one_of('scope', ...) end

H.pick_get_config = function()
  return vim.tbl_deep_extend('force', (require('mini-dev.pick') or {}).config or {}, vim.b.minipick_config or {})
end

H.show_with_icons =
  function(buf_id, items, query) require('mini-dev.pick').default_show(buf_id, items, query, { show_icons = true }) end

-- Git picker -----------------------------------------------------------------
H.git_normalize_path = function(path, picker_name)
  local path = type(path) == 'string' and path or vim.fn.getcwd()
  if path == '' then H.error(string.format('Path in `%s` is empty.', picker_name)) end
  path = vim.fn.fnamemodify(path, ':p')
  local path_is_dir, path_is_file = vim.fn.isdirectory(path) == 1, vim.fn.filereadable(path) == 1
  if not (path_is_dir or path_is_file) then H.error('Path ' .. path .. ' is not a valid path.') end
  return path, path_is_dir and 'directory' or 'file'
end

H.git_get_repo_dir = function(path, path_type)
  local path_dir = path_type == 'directory' and path or vim.fn.fnamemodify(path, ':h')
  local repo_dir = vim.fn.systemlist('git -C ' .. path_dir .. ' rev-parse --show-toplevel')[1]
  if vim.v.shell_error ~= 0 then H.error('Could not find git repo for ' .. path .. '.') end
  return repo_dir
end

H.git_difflines_to_hunkitems = function(lines, n_context)
  local header_pattern = '^diff %-%-git'
  local hunk_pattern = '^@@ %-%d+,%d+ %+(%d+),%d+ @@'
  local to_path_pattern = '^%+%+%+ b/(.*)$'

  local cur_path, is_in_hunk = nil, false
  local items = {}
  for i, l in ipairs(lines) do
    if l:find(header_pattern) ~= nil then is_in_hunk = false end

    cur_path = l:match(to_path_pattern) or cur_path

    local hunk_start = l:match(hunk_pattern)
    if hunk_start ~= nil then
      is_in_hunk = true
      local lnum = tonumber(hunk_start) + n_context
      table.insert(items, { text = cur_path .. ':' .. lnum, path = cur_path, lnum = lnum, hunk = {} })
    end

    if is_in_hunk then table.insert(items[#items].hunk, l) end
  end

  -- TODO: Think about more useful text for better eyeballing from main list.
  -- Like adding first line of hunk (after paths align like in `diagnostic`).

  return items
end

-- LSP picker -----------------------------------------------------------------
H.lsp_make_on_list = function(source, opts)
  -- Prepend file position info to item and sort
  local process = function(items)
    if source ~= 'document_symbol' then items = vim.tbl_map(H.pick_prepend_position, items) end
    table.sort(items, H.lsp_items_compare)
    return items
  end

  -- Highlight symbol kind on Neovim>=0.9 (when `@lsp.type` groups introduced)
  local show
  if source == 'document_symbol' or source == 'workspace_symbol' then
    local pick = H.validate_pick()
    show = function(buf_id, items_to_show, query)
      pick.default_show(buf_id, items_to_show, query)

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
      item.text, item.path = item.text or '', item.filename or nil
    end
    items = process(items)

    return H.pick_start(items, { source = { name = string.format('LSP (%s)', source), show = show } }, opts)
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

-- List picker ----------------------------------------------------------------
H.list_get = {
  quickfix = function() return vim.tbl_map(H.list_enhance_qf_loc, vim.fn.getqflist()) end,

  location = function() return vim.tbl_map(H.list_enhance_qf_loc, vim.fn.getloclist(0)) end,

  jump = function()
    local raw = vim.fn.getjumplist()[1]
    -- Tweak output: reverse for more relevance; make 1-based column
    local res, n = {}, #raw
    for i, x in ipairs(raw) do
      x.col = x.col + 1
      res[n - i + 1] = x
    end
    return res
  end,

  change = function()
    local res = vim.fn.getchangelist()[1]
    local cur_buf = vim.api.nvim_get_current_buf()
    for _, x in ipairs(res) do
      res.bufnr = cur_buf
    end
    return res
  end,
}

H.list_enhance_qf_loc = function(item)
  if item.end_lnum == 0 then item.end_lnum = nil end
  if item.end_col == 0 then item.end_col = nil end
  return item
end

H.list_enhance_item = function(item)
  if vim.fn.filereadable(item.filename) == 1 then item.path = item.filename end
  return H.pick_prepend_position(item)
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
