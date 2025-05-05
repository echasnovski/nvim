local api = vim.api
local uv = vim.uv

local M = {}
local H = {}

local config = {
  job = {
    -- Number of parallel threads to use. Default: 80% of all available.
    n_threads = math.floor(0.8 * #(uv.cpu_info() or { 1 })),

    -- Timeout (in ms) for each job before force quit
    timeout = 30000,
  },
}

local log_path = vim.fn.stdpath('log') .. '/nvimpack.log'

local git_version = { major = nil, minor = nil }

-- TODO: Move to 'src/nvim/highlight_group.c'
local hi = function(name, opts)
  opts.default = true
  api.nvim_set_hl(0, name, opts)
end

hi('PackChangeAdded', { link = 'Added' })
hi('PackChangeRemoved', { link = 'Removed' })
hi('PackHint', { link = 'DiagnosticHint' })
hi('PackInfo', { link = 'DiagnosticInfo' })
hi('PackMsgBreaking', { link = 'DiagnosticWarn' })
hi('PackPlaceholder', { link = 'Comment' })
hi('PackTitle', { link = 'Title' })
hi('PackTitleError', { link = 'DiffDelete' })
hi('PackTitleSame', { link = 'DiffText' })
hi('PackTitleUpdate', { link = 'DiffAdd' })

--- Add plugin to current session
---
--- - Process specification by expanding dependencies into single spec array.
--- - Ensure plugin is present on disk along with its dependencies by installing
---   (in parallel) absent ones:
---     - Execute `opts.hooks.pre_install`.
---     - Use `git clone` to clone plugin from its source URI into "pack/core/opt".
---     - Set state according to `opts.checkout`.
---     - Execute `opts.hooks.post_install`.
--- - Register spec(s) in current session.
--- - Make sure plugin(s) can be used in current session (see |:packadd|).
--- - If not during startup and is needed, source all "after/plugin/" scripts.
---
--- Notes:
--- - Presence of plugin is checked by its name which is the same as the name
---   of its directory inside "pack/core" package (see |MiniDeps-overview|).
--- - To increase performance, this function only ensures presence on disk and
---   nothing else. In particular, it doesn't ensure `opts.checkout` state.
---   Use |MiniDeps.update()| or |:DepsUpdateOffline| explicitly.
--- - Adding plugin several times updates its session specs.
---
---@param spec table|string Plugin specification. See |MiniDeps-plugin-specification|.
---@param opts table|nil Options. Possible fields:
---   - <bang> `(boolean)` - whether to use `:packadd!` instead of plain |:packadd|.
M.add = function(spec, opts)
  opts = opts or {}
  vim.validate('opts', opts, 'table')

  -- Normalize
  local plugs = {}
  H.expand_spec(plugs, spec)

  -- Process
  local plugs_to_install = {}
  for _, p in ipairs(plugs) do
    local path, is_present = H.get_plugin_path(p.name)
    p.path = path
    if not is_present then
      table.insert(plugs_to_install, vim.deepcopy(p))
    end
  end

  -- Install
  if #plugs_to_install > 0 then
    H.ensure_git_exec()
    for _, p in ipairs(plugs_to_install) do
      p.job = H.cli_new_job({}, vim.fn.getcwd())
    end

    H.notify(string.format('Installing `%s`', plugs[#plugs].name))
    H.plugs_exec_hooks(plugs_to_install, 'pre_install')
    H.plugs_install(plugs_to_install)
    H.plugs_exec_hooks(plugs_to_install, 'post_install')
  end

  -- Add plugins to current session
  for _, p in ipairs(plugs) do
    -- Register in session
    table.insert(H.session, p)

    -- Add to 'runtimepath'
    vim.cmd.packadd({ p.name, bang = opts.bang })
  end

  -- Execute 'after/' scripts if not during startup (when they will be sourced
  -- automatically), as `:packadd` only sources plain 'plugin/' files.
  -- See https://github.com/vim/vim/issues/1994.
  -- Deliberately do so after executing all currently known 'plugin/' files.
  local should_load_after_dir = vim.v.vim_did_enter == 1 and not opts.bang and vim.o.loadplugins
  if not should_load_after_dir then
    return
  end
  local source = function(path)
    pcall(vim.cmd.source, vim.fn.fnameescape(path))
  end

  for _, p in ipairs(plugs) do
    local after_paths = vim.fn.glob(p.path .. '/after/plugin/**/*.{vim,lua}', false, true)
    vim.tbl_map(source, after_paths)
  end
end

--- Update plugins
---
--- - Synchronize specs with state of plugins on disk (set `source`, etc.).
--- - Infer data before downloading updates.
--- - If not offline, download updates (in parallel).
--- - Infer data after downloading updates.
--- - If update is forced, apply all changes immediately while updating log
---   file (at `config.path.log`; use |:DepsShowLog| to review).
---   Otherwise show confirmation buffer with instructions on how to proceed.
---
---@param names table|nil Array of plugin names to update.
---  Default: all plugins from current session (see |MiniDeps.get_session()|).
---@param opts table|nil Options. Possible fields:
---   - <force> `(boolean)` - whether to force update without confirmation.
---     Default: `false`.
---   - <offline> `(boolean)` - whether to skip downloading updates from sources.
---     Default: `false`.
M.update = function(names, opts)
  opts = vim.tbl_deep_extend('force', { force = false, offline = false }, opts or {})

  -- Compute array of plugin data to be reused in update. Each contains a CLI
  -- job "assigned" to plugin's path which stops execution after first error.
  local plugs = H.plugs_from_names(names)
  if #plugs == 0 then
    return H.notify('Nothing to update')
  end

  -- Prepare repositories and specifications
  H.ensure_git_exec()
  H.plugs_ensure_origin_source(plugs)

  -- Preprocess before downloading
  H.plugs_infer_head(plugs)
  H.plugs_ensure_target_refs(plugs)

  -- Download data if asked
  if not opts.offline then
    H.plugs_download_updates(plugs)
  end

  -- Process data for update
  H.plugs_infer_commit(plugs, 'checkout', 'checkout_to')
  H.plugs_infer_log(plugs, 'head', 'checkout_to', 'checkout_log')

  -- Checkout if asked (before feedback to include possible checkout errors)
  if opts.force then
    H.plugs_checkout(plugs)
  end

  -- Make feedback
  local lines = H.update_compute_feedback_lines(plugs)
  local feedback = opts.force and H.update_feedback_log or H.update_feedback_confirm
  feedback(lines)

  -- Show job warnings and errors
  H.plugs_show_job_notifications(plugs, 'update')
end

--- Get session
---
--- Plugin is registered in current session if it either:
--- - Was added with |MiniDeps.add()| (preserving order of calls).
--- - Is a "start" plugin and present in 'runtimpath'.
---
---@return table Array with specifications of all plugins registered in
---   current session.
M.get_session = function()
  -- Normalize `H.session` allowing specs for same plugin
  local res, plugin_ids = {}, {}
  local add_spec = function(spec)
    local id = plugin_ids[spec.path] or (#res + 1)
    -- Treat `depends` differently as it is an array and direct merge is bad
    -- Also: https://github.com/neovim/neovim/pull/15094#discussion_r671663938
    local depends = vim.deepcopy((res[id] or {}).depends or {})
    vim.list_extend(depends, spec.depends or {})
    res[id] = vim.tbl_deep_extend('force', res[id] or {}, spec)
    res[id].depends = depends

    plugin_ids[spec.path] = id
  end
  vim.tbl_map(add_spec, H.session)
  H.session = res

  -- Add 'start/' plugins that are in 'rtp'. NOTE: not whole session concept is
  -- built around presence in 'rtp' to 100% ensure to preserve the order in
  -- which user called `add()`.
  local start_path = H.get_package_path() .. '/start'
  local pattern = string.format('^%s/([^/]+)$', vim.pesc(start_path))
  for _, runtime_path in ipairs(api.nvim_list_runtime_paths()) do
    -- Make sure plugin path is normalized (matters on Windows)
    local path = vim.fs.abspath(runtime_path)
    local name = string.match(path, pattern)
    if name ~= nil then
      add_spec({ path = path, name = name, hooks = {}, depends = {} })
    end
  end

  -- Return copy to not allow modification in place
  return vim.deepcopy(res)
end

-- Helper data ================================================================
-- Array of plugin specs
H.session = {}

-- Git commands ---------------------------------------------------------------
H.git_cmd = function(cmd_name, ...)
  local args = H.git_args[cmd_name](...)
  if args == nil then
    return {}
  end

  -- Use '-c gc.auto=0' to disable `stderr` "Auto packing..." messages
  return { 'git', '-c', 'gc.auto=0', unpack(args) }
end

H.git_args = {
  version = function()
    return { 'version' }
  end,
  clone = function(source, path)
    local res = {
      'clone',
      '--quiet',
      '--filter=blob:none',
      '--recurse-submodules',
      '--also-filter-submodules',
      '--origin',
      'origin',
      source,
      path,
    }
    -- Use `--also-filter-submodules` only with appropriate version
    if not (git_version.major >= 2 and git_version.minor >= 36) then
      table.remove(res, 5)
    end
    return res
  end,
  stash = function(timestamp)
    return {
      'stash',
      '--quiet',
      '--message',
      '(nvimpack) ' .. timestamp .. ' Stash before checkout',
    }
  end,
  checkout = function(target)
    return { 'checkout', '--quiet', target }
  end,
  -- Using '--tags --force' means conflicting tags will be synced with remote
  fetch = function()
    return { 'fetch', '--quiet', '--tags', '--force', '--recurse-submodules=yes', 'origin' }
  end,
  set_origin = function(source)
    return { 'remote', 'set-url', 'origin', source }
  end,
  get_origin = function()
    return { 'remote', 'get-url', 'origin' }
  end,
  get_default_origin_branch = function()
    return { 'rev-parse', '--abbrev-ref', 'origin/HEAD' }
  end,
  is_origin_branch = function(name)
    -- Returns branch's name if it is present
    return { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/' .. name }
  end,
  -- Using `rev-list -1` shows a commit of revision, while `rev-parse` shows
  -- hash of revision. Those are different for annotated tags.
  get_hash = function(rev)
    return { 'rev-list', '-1', rev }
  end,
  log = function(from, to)
    if from == nil or to == nil or from == to then
      return nil
    end
    -- `--topo-order` makes showing divergent branches nicer
    -- `--decorate-refs` shows only tags near commits (not `origin/main`, etc.)
    return {
      'log',
      '--pretty=format:%m %h | %ai | %an%d%n  %s%n',
      '--topo-order',
      '--decorate-refs=refs/tags',
      from .. '...' .. to,
    }
  end,
}

H.ensure_git_exec = function()
  if git_version.major ~= nil then
    return
  end
  local out = vim.system(H.git_cmd('version'), { text = true }):wait()
  if out.stderr ~= '' then
    error('Could not find executable `git` CLI tool')
  end
  local major, minor = string.match(out.stdout, '(%d+)%.(%d+)')
  git_version = { major = tonumber(major), minor = tonumber(minor) }
end

-- Plugin specification -------------------------------------------------------
H.expand_spec = function(target, spec)
  -- Prepare
  if type(spec) == 'string' then
    local field = string.find(spec, '/') ~= nil and 'source' or 'name'
    spec = { [field] = spec }
  end
  if type(spec) ~= 'table' then
    H.error('Plugin spec should be table.')
  end

  local has_min_fields = type(spec.source) == 'string' or type(spec.name) == 'string'
  if not has_min_fields then
    H.error('Plugin spec should have proper `source` or `name`.')
  end

  -- Normalize
  spec = vim.deepcopy(spec)

  if spec.source and type(spec.source) ~= 'string' then
    H.error('`source` in plugin spec should be string.')
  end
  local is_user_repo = type(spec.source) == 'string'
    and spec.source:find('^[%w-]+/[%w-_.]+$') ~= nil
  if is_user_repo then
    spec.source = 'https://github.com/' .. spec.source
  end

  spec.name = spec.name or vim.fn.fnamemodify(spec.source, ':t')
  if type(spec.name) ~= 'string' then
    H.error('`name` in plugin spec should be string.')
  end
  if string.find(spec.name, '/') ~= nil then
    H.error('`name` in plugin spec should not contain "/".')
  end
  if spec.name == '' then
    H.error('`name` in plugin spec should not be empty.')
  end

  if spec.checkout and type(spec.checkout) ~= 'string' then
    H.error('`checkout` in plugin spec should be string.')
  end

  spec.hooks = vim.deepcopy(spec.hooks) or {}
  if type(spec.hooks) ~= 'table' then
    H.error('`hooks` in plugin spec should be table.')
  end
  local hook_names = { 'pre_install', 'post_install', 'pre_checkout', 'post_checkout' }
  for _, hook_name in ipairs(hook_names) do
    local is_not_hook = spec.hooks[hook_name] and not vim.is_callable(spec.hooks[hook_name])
    if is_not_hook then
      H.error('`hooks.' .. hook_name .. '` in plugin spec should be callable.')
    end
  end

  -- Expand dependencies recursively before adding current spec to target
  spec.depends = vim.deepcopy(spec.depends) or {}
  if not vim.islist(spec.depends) then
    H.error('`depends` in plugin spec should be array.')
  end
  for _, dep_spec in ipairs(spec.depends) do
    H.expand_spec(target, dep_spec)
  end

  table.insert(target, spec)
end

-- Plugin operations ----------------------------------------------------------
H.plugs_exec_hooks = function(plugs, name)
  for _, p in ipairs(plugs) do
    local has_error = p.job and #p.job.err > 0
    local should_execute = vim.is_callable(p.hooks[name]) and not has_error
    if should_execute then
      local ok, err = pcall(p.hooks[name], { path = p.path, source = p.source, name = p.name })
      if not ok then
        local msg = string.format('Error executing %s hook in `%s`:\n%s', name, p.name, err)
        H.notify(msg, 'ERROR')
      end
    end
  end
end

H.plugs_install = function(plugs)
  -- Clone
  local prepare = function(p)
    if p.source == nil and #p.job.err == 0 then
      p.job.err = { 'SPECIFICATION HAS NO `source` TO INSTALL PLUGIN.' }
    end
    p.job.cmd = H.git_cmd('clone', p.source or '', p.path)
    p.job.exit_msg = string.format('Installed `%s`', p.name)
  end
  H.plugs_run_jobs(plugs, prepare)

  -- Checkout
  vim.tbl_map(function(p)
    p.job.cwd = p.path
  end, plugs)
  H.plugs_checkout(plugs, { exec_hooks = false, all_helptags = true })

  -- Show warnings and errors
  H.plugs_show_job_notifications(plugs, 'installing plugin')
end

H.plugs_download_updates = function(plugs)
  -- Show actual target number of plugins attempted to fetch
  local n_noerror = 0
  for _, p in ipairs(plugs) do
    if #p.job.err == 0 then
      n_noerror = n_noerror + 1
    end
  end
  if n_noerror == 0 then
    return
  end
  H.notify('Downloading ' .. n_noerror .. ' update' .. (n_noerror > 1 and 's' or ''))

  local prepare = function(p)
    p.job.cmd = H.git_cmd('fetch')
    p.job.exit_msg = string.format('Downloaded update for `%s`', p.name)
  end
  H.plugs_run_jobs(plugs, prepare)
end

H.plugs_checkout = function(plugs, opts)
  opts = vim.tbl_deep_extend('force', { exec_hooks = true, all_helptags = false }, opts or {})

  H.plugs_infer_head(plugs)
  H.plugs_ensure_target_refs(plugs)
  H.plugs_infer_commit(plugs, 'checkout', 'checkout_to')

  -- Operate only on plugins that actually need checkout
  local checkout_plugs = vim.tbl_filter(function(p)
    return p.head ~= p.checkout_to
  end, plugs)

  -- Stash changes
  local stash_cmd = H.git_cmd('stash', H.get_timestamp())
  local prepare = function(p)
    p.job.cmd = stash_cmd
  end
  H.plugs_run_jobs(checkout_plugs, prepare)

  -- Execute pre hooks
  if opts.exec_hooks then
    H.plugs_exec_hooks(checkout_plugs, 'pre_checkout')
  end

  -- Checkout
  prepare = function(p)
    p.job.cmd = H.git_cmd('checkout', p.checkout_to)
    p.job.exit_msg = string.format('Checked out `%s` in `%s`', p.checkout, p.name)
  end
  H.plugs_run_jobs(checkout_plugs, prepare)

  -- Execute post hooks
  if opts.exec_hooks then
    H.plugs_exec_hooks(checkout_plugs, 'post_checkout')
  end

  -- (Re)Generate help tags according to the current help files
  local help_plugs = opts.all_helptags and plugs or checkout_plugs
  for _, p in ipairs(help_plugs) do
    local doc_dir = p.path .. '/doc'
    -- Completely redo tags
    vim.fn.delete(doc_dir .. '/tags')
    local has_help_files = vim.fn.glob(doc_dir .. '/**') ~= ''
    if has_help_files then
      pcall(vim.cmd.helptags, vim.fn.fnameescape(doc_dir))
    end
  end
end

-- Plugin operation helpers ---------------------------------------------------
H.plugs_from_names = function(names)
  if names and not vim.islist(names) then
    H.error('`names` should be array.')
  end
  for _, name in ipairs(names or {}) do
    if type(name) ~= 'string' then
      H.error('`names` should contain only strings.')
    end
  end

  local res = {}
  for _, spec in ipairs(M.get_session()) do
    if names == nil or vim.tbl_contains(names, spec.name) then
      spec.job = H.cli_new_job({}, spec.path)
      table.insert(res, spec)
    end
  end

  return res
end

H.plugs_run_jobs = function(plugs, prepare, process)
  if vim.is_callable(prepare) then
    vim.tbl_map(prepare, plugs)
  end

  H.cli_run(vim.tbl_map(function(p)
    return p.job
  end, plugs))

  if vim.is_callable(process) then
    vim.tbl_map(process, plugs)
  end

  -- Clean jobs. Preserve errors for jobs to be properly reusable.
  for _, p in ipairs(plugs) do
    p.job.cmd, p.job.exit_msg, p.job.out = {}, nil, {}
  end
end

H.plugs_show_job_notifications = function(plugs, action_name)
  for _, p in ipairs(plugs) do
    local warn = H.cli_stream_tostring(p.job.warn)
    if warn ~= '' then
      local msg = string.format('Warnings in `%s` during %s\n%s', p.name, action_name, warn)
      H.notify(msg, 'WARN')
    end
    local err = H.cli_stream_tostring(p.job.err)
    if err ~= '' then
      local msg = string.format('Error in `%s` during %s\n%s', p.name, action_name, err)
      H.notify(msg, 'ERROR')
    end
  end
end

H.plugs_ensure_origin_source = function(plugs)
  local prepare = function(p)
    p.job.cmd = p.source and H.git_cmd('set_origin', p.source) or H.git_cmd('get_origin')
  end
  local process = function(p)
    p.source = p.source or H.cli_stream_tostring(p.job.out)
  end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_ensure_target_refs = function(plugs)
  local prepare = function(p)
    local needs_infer = p.checkout == nil
    p.job.cmd = needs_infer and H.git_cmd('get_default_origin_branch') or {}
  end
  local process = function(p)
    local def_branch = H.cli_stream_tostring(p.job.out):gsub('^origin/', '')
    p.checkout = p.checkout or def_branch
  end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_infer_head = function(plugs)
  local prepare = function(p)
    p.job.cmd = p.head == nil and H.git_cmd('get_hash', 'HEAD') or {}
  end
  local process = function(p)
    p.head = p.head or H.cli_stream_tostring(p.job.out)
  end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_infer_commit = function(plugs, field_ref, field_out)
  -- Determine if reference points to an origin branch (to avoid error later)
  local prepare = function(p)
    -- Don't recompute commit if it is already computed
    p.should_infer = p[field_out] == nil
    p.job.cmd = p.should_infer and H.git_cmd('is_origin_branch', p[field_ref]) or {}
  end
  local process = function(p)
    p.is_ref_origin_branch = H.cli_stream_tostring(p.job.out):find('%S') ~= nil
  end
  H.plugs_run_jobs(plugs, prepare, process)

  -- Infer commit depending on whether it points to origin branch
  prepare = function(p)
    -- Force `checkout = 'HEAD'` to always point to current commit to freeze
    -- updates. This is needed because `origin/HEAD` is also present.
    local is_from_origin = p.is_ref_origin_branch and p[field_ref] ~= 'HEAD'
    local ref = (is_from_origin and 'origin/' or '') .. p[field_ref]
    p.job.cmd = p.should_infer and H.git_cmd('get_hash', ref) or {}
  end
  process = function(p)
    if p.should_infer then
      p[field_out] = H.cli_stream_tostring(p.job.out)
    end
    p.is_ref_origin_branch, p.should_infer = nil, nil
  end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_infer_log = function(plugs, field_from, field_to, field_out)
  local prepare = function(p)
    p.job.cmd = H.git_cmd('log', p[field_from], p[field_to])
  end
  local process = function(p)
    p[field_out] = H.cli_stream_tostring(p.job.out)
  end
  H.plugs_run_jobs(plugs, prepare, process)
end

-- File system ----------------------------------------------------------------
H.get_plugin_path = function(name)
  local package_path = H.get_package_path()

  -- First check for the most common case of name present in 'pack/core/opt'
  local opt_path = string.format('%s/opt/%s', package_path, name)
  if uv.fs_stat(opt_path) ~= nil then
    return opt_path, true
  end

  -- Allow processing 'pack/core/start'
  local start_path = string.format('%s/start/%s', package_path, name)
  if uv.fs_stat(start_path) ~= nil then
    return start_path, true
  end

  -- Use 'opt' directory by default
  return opt_path, false
end

H.get_all_plugin_paths = function()
  local pack_path, res = H.get_package_path(), {}
  vim.list_extend(res, H.readdir(pack_path .. '/opt'))
  vim.list_extend(res, H.readdir(pack_path .. '/start'))
  return res
end

H.get_package_path = function()
  return vim.fs.normalize(vim.fn.stdpath('data') .. '/site/pack/core')
end

-- Update ---------------------------------------------------------------------
H.update_compute_feedback_lines = function(plugs)
  -- Construct lines with metadata for later sort
  local plug_data = {}
  for i, p in ipairs(plugs) do
    local lines = H.update_compute_report_single(p)
    plug_data[i] = {
      lines = lines,
      has_error = p.has_error,
      has_updates = p.has_updates,
      name = p.name,
      index = i,
    }
  end

  -- Sort to put first ones with errors, then with updates, then rest
  local compare = function(a, b)
    if a.has_error and not b.has_error then
      return true
    end
    if not a.has_error and b.has_error then
      return false
    end
    if a.has_updates and not b.has_updates then
      return true
    end
    if not a.has_updates and b.has_updates then
      return false
    end
    return a.index < b.index
  end
  table.sort(plug_data, compare)

  local plug_lines = vim.tbl_map(function(x)
    return x.lines
  end, plug_data)
  return vim.split(table.concat(plug_lines, '\n\n'), '\n')
end

H.update_compute_report_single = function(p)
  p.has_error, p.has_updates = #p.job.err > 0, p.head ~= p.checkout_to

  local err = H.cli_stream_tostring(p.job.err)
  if err ~= '' then
    return string.format('!!! %s !!!\n\n%s', p.name, err)
  end

  -- Compute title surrounding based on whether plugin needs an update
  local surrounding = p.has_updates and '+++' or '---'
  local parts = { string.format('%s %s %s\n', surrounding, p.name, surrounding) }

  if p.head == p.checkout_to then
    table.insert(parts, 'Path:   ' .. p.path .. '\n')
    table.insert(parts, 'Source: ' .. (p.source or '<None>') .. '\n')
    table.insert(parts, string.format('State:  %s (%s)', p.checkout_to, p.checkout))
  else
    table.insert(parts, 'Path:         ' .. p.path .. '\n')
    table.insert(parts, 'Source:       ' .. (p.source or '<None>') .. '\n')
    table.insert(parts, 'State before: ' .. p.head .. '\n')
    table.insert(parts, string.format('State after:  %s (%s)', p.checkout_to, p.checkout))
  end

  -- Show pending updates only if they are present
  if p.has_updates then
    table.insert(parts, string.format('\n\nPending updates from `%s`:\n', p.checkout))
    table.insert(parts, p.checkout_log)
  end

  return table.concat(parts, '')
end

H.update_feedback_confirm = function(lines)
  -- Add helper header
  local report = {
    'This is a confirmation report before an update.',
    '',
    'Line `+++ <plugin_name> +++` means plugin will be updated.',
    'See update details below it.',
    'Changes starting with ">"/"<" will be added/removed.',
    'Remove the line to not update that plugin.',
    '',
    'Line `--- <plugin_name> ---` means plugin has nothing to update.',
    '',
    "Line `!!! <plugin_name> !!!` means plugin had an error and won't be updated.",
    'See error details below it.',
    '',
    'Use regular fold keys (`zM`, `zR`, etc.) to manage shorter view.',
    'To finish update, write this buffer (for example, with `:write` command).',
    'To cancel update, close this window (for example, with `:close` command).',
    '',
  }
  local n_header = #report - 1
  vim.list_extend(report, lines)

  -- Show report in new buffer in separate tabpage
  local finish_update = function(buf_id)
    -- Compute plugin names to update
    local names = {}
    for _, l in ipairs(api.nvim_buf_get_lines(buf_id, 0, -1, false)) do
      local cur_name = string.match(l, '^%+%+%+ (.*) %+%+%+$')
      if cur_name ~= nil then
        table.insert(names, cur_name)
      end
    end

    -- Update and delete buffer (in that order, to show that update is done)
    M.update(names, { force = true, offline = true })
  end

  H.show_confirm_buf(
    report,
    { name = 'confirm-update', exec_on_write = finish_update, setup_folds = true }
  )

  -- Define basic highlighting
  vim.cmd.syntax('region PackHint start="^\\%1l" end="\\%' .. n_header .. 'l$"')
  H.update_add_syntax()
end

H.update_add_syntax = function()
  vim.cmd([[
    syntax match PackTitleError    "^!!! .\+ !!!$"
    syntax match PackTitleUpdate   "^+++ .\+ +++$"
    syntax match PackTitleSame     "^--- .\+ ---$"
    syntax match PackInfo          "^Path: \+\zs[^ ]\+"
    syntax match PackInfo          "^Source: \+\zs[^ ]\+"
    syntax match PackInfo          "^State[^:]*: \+\zs[^ ]\+\ze"
    syntax match PackHint          "\(^State.\+\)\@<=(.\+)$"
    syntax match PackChangeAdded   "^> .*$"
    syntax match PackChangeRemoved "^< .*$"
    syntax match PackMsgBreaking   "^  \S\+!: .*$"
    syntax match PackPlaceholder   "^<.*>$"
  ]])
end

H.update_feedback_log = function(lines)
  local title = string.format('========== Update %s ==========', H.get_timestamp())
  table.insert(lines, 1, title)
  table.insert(lines, '')

  vim.fn.mkdir(vim.fn.fnamemodify(log_path, ':h'), 'p')
  vim.fn.writefile(lines, log_path, 'a')
end

-- Confirm --------------------------------------------------------------------
H.show_confirm_buf = function(lines, opts)
  -- Show buffer
  local buf_id = api.nvim_create_buf(true, true)
  H.set_buf_name(buf_id, opts.name)
  api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.cmd.sbuffer({ buf_id, mods = { tab = vim.fn.tabpagenr('#') } })
  local tab_num, win_id = api.nvim_tabpage_get_number(0), api.nvim_get_current_win()

  local delete_buffer = vim.schedule_wrap(function()
    pcall(api.nvim_buf_delete, buf_id, { force = true })
    pcall(vim.cmd.tabclose, tab_num)
    vim.cmd.redraw()
  end)

  -- Define folding
  local is_title = function(l)
    return l:find('^%-%-%-') or l:find('^%+%+%+') or l:find('^%!%!%!')
  end
  M._confirm_foldexpr = function(lnum)
    if lnum == 1 then
      return 0
    end
    if is_title(vim.fn.getline(lnum - 1)) then
      return 1
    end
    if is_title(vim.fn.getline(lnum + 1)) then
      return 0
    end
    return '='
  end

  -- Possibly set up folding. Use `:setlocal` for these options to not be
  -- inherited if some other buffer is opened in the same window.
  if opts.setup_folds then
    vim.cmd.setlocal('foldenable foldmethod=expr foldlevel=999')
    vim.cmd.setlocal('foldexpr=v:lua.require"vim.pack"._confirm_foldexpr(v:lnum)')
  end

  -- Define action on accepting confirm
  local finish = function()
    M._confirm_foldexpr = nil
    opts.exec_on_write(buf_id)
    delete_buffer()
  end
  -- - Use `nested` to allow other events (useful for statuslines)
  api.nvim_create_autocmd('BufWriteCmd', { buffer = buf_id, nested = true, callback = finish })

  -- Define action to cancel confirm
  local cancel_au_id
  local on_cancel = function(data)
    M._confirm_foldexpr = nil
    if tonumber(data.match) ~= win_id then
      return
    end
    pcall(api.nvim_del_autocmd, cancel_au_id)
    delete_buffer()
  end
  cancel_au_id = api.nvim_create_autocmd('WinClosed', { nested = true, callback = on_cancel })

  -- Set buffer-local options last (so that user autocmmands could override)
  vim.bo.buftype, vim.bo.filetype, vim.bo.modified = 'acwrite', 'nvimpack', false
end

-- CLI ------------------------------------------------------------------------
H.cli_run = function(jobs)
  -- Use only actually runnable jobs
  local should_run = function(job)
    return type(job.cmd) == 'table' and #job.cmd > 0 and #job.err == 0
  end
  jobs = vim.tbl_filter(should_run, jobs)

  local n_total, id_started, n_finished = #jobs, 0, 0
  if n_total == 0 then
    return
  end

  local run_next
  run_next = function()
    if id_started >= n_total then
      return
    end
    id_started = id_started + 1

    local job = jobs[id_started]
    local system_opts = { cwd = job.cwd, text = true, timeout = config.job.timeout }

    local on_exit = function(out)
      -- Process command side effects
      table.insert(job.err, out.stderr)
      table.insert(job.out, out.stdout)

      -- Process exit code: if 0 treat `stderr` as warning; error otherwise
      if out.code == 0 then
        vim.list_extend(job.warn, job.err)
        -- NOTE: This is valid as `err = {}` was true before executing command
        job.err = {}
      elseif out.code == 124 then
        table.insert(job.err, 'PROCESS REACHED TIMEOUT.')
      else
        table.insert(job.err, 1, 'ERROR CODE ' .. out.code .. '\n')
      end

      -- Finalize job
      n_finished = n_finished + 1
      if type(job.exit_msg) == 'string' and #job.err == 0 then
        H.notify(string.format('(%d/%d) %s', n_finished, n_total, job.exit_msg))
      end

      -- Start next parallel job
      run_next()
    end

    vim.system(job.cmd, system_opts, on_exit)
  end

  for _ = 1, config.job.n_threads do
    run_next()
  end

  vim.wait(config.job.timeout * n_total, function()
    return n_total <= n_finished
  end, 1)
end

H.cli_stream_tostring = function(stream)
  return (table.concat(stream):gsub('\n+$', ''))
end

H.cli_new_job = function(cmd, cwd, exit_msg)
  return { cmd = cmd, cwd = cwd, exit_msg = exit_msg, out = {}, warn = {}, err = {} }
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg)
  error('(nvimpack) ' .. msg, 0)
end

H.set_buf_name = function(buf_id, name)
  api.nvim_buf_set_name(buf_id, 'nvimpack://' .. buf_id .. '/' .. name)
end

H.notify = vim.schedule_wrap(function(msg, level)
  level = level or 'INFO'
  msg = type(msg) == 'table' and table.concat(msg, '\n') or msg
  vim.notify(string.format('(nvimpack) %s', msg), vim.log.levels[level])
  vim.cmd.redraw()
end)

H.get_timestamp = function()
  return vim.fn.strftime('%Y-%m-%d %H:%M:%S')
end

H.readdir = function(path)
  if vim.fn.isdirectory(path) ~= 1 then
    return {}
  end
  return vim.tbl_map(function(x)
    return path .. '/' .. x
  end, vim.fn.readdir(path))
end

return M
