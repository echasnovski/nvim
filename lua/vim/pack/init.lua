-- TODO:
-- - Implement '*' as default version.
-- - Implement showing available new versions during interactive confirm if
--   there are no updates.
-- - Add "In runtime: true/false" in plugin header during interactive confirm.
-- - Replace `buf_id` with more proper name (`bufnr` or `buf`).
-- - Make events built-in and not `User`. Use source as pattern?

-- PRNOTES:
-- - The module name is `vim.pack` because it aligns well with `:packadd`.
--   The question is what to use as filetype and buffer/file names? Currently
--   it is 'nvimpack' which might be confusing. The 'vimpack' is closer, but it
--   doesn't use 'nvim'.
-- - Currently `vim.pack.add()` only installs into 'opt/' directory.
-- - Intentionally more oriented towards future automated packspec support.
-- - Custom events are better than hooks because they can be used by plugins to
--   tweak install/update/add behavior of *other* plugins. Plus smaller spec.
-- - Left out from this PR but planned:
--     - Packspec. It is rather big and needs discussions about the degree of
--       support vs complexity.
--     - Lockfile. Basically, store state/commit per source and prefer it
--       during initial install over resolving `version`.
--     - More interactive update features:
--         - Code lenses/actions "update this plugin", "skip updating this
--           plugin", maybe "delete" this plugin.
--         - Hover on pending commit to get its diff.
--         - Show available versions: tags that are either newer than current
--           state (`git tag --format=???` with post-processing) or that
--           contain it in history (`git tag --list --contains HEAD`).
--           Can have hover support to get change log.
-- - Not planned as `vim.pack` functionality but discussable:
--     - Manage plugins from 'start/' directory. As `vim.pack.add()` only
--       installs in 'opt/' directory (as it is all that is needed), it seems
--       unnecessary to also manage 'start/' from the same package path.
--     - Lazy loading out of the box. This might be more appropriate to combine
--       with `now()` and `later()` (from 'mini.deps'). These are general
--       enough that can live in `vim.func` and useful outside of `vim.pack`.

local api = vim.api
local uv = vim.uv

M = {}
H = {}

local log_path = vim.fn.stdpath('log') .. '/nvimpack.log'
local default_version = '*'

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

-- Git ------------------------------------------------------------------------
--- @param cmd string[]
--- @param cwd string
local function cli_sync(cmd, cwd)
  local out = vim.system(cmd, { cwd = cwd, text = true, clear_env = true }):wait()
  if out.code ~= 0 then
    error(out.stderr)
  end
  return (out.stdout:gsub('\n+$', ''))
end

local function git_ensure_exec()
  if vim.fn.executable('git') == 0 then
    error('No `git` executable')
  end
end

--- @param cwd string
local function git_get_branches(cwd)
  local stdout, res = cli_sync(H.git_cmd('list_branches'), cwd), {}
  for _, l in ipairs(vim.split(stdout, '\n')) do
    table.insert(res, l:match('^origin/(.+)$'))
  end
  return res
end

--- @param cwd string
local function git_get_tags(cwd)
  local stdout = cli_sync(H.git_cmd('list_tags'), cwd)
  return vim.split(stdout, '\n')
end

-- Plugin operations ----------------------------------------------------------
local get_plug_dir = function()
  return vim.fs.joinpath(vim.fn.stdpath('data'), 'site', 'pack', 'core', 'opt')
end

--- @param msg string|string[]
--- @param level ('DEBUG'|'TRACE'|'INFO'|'WARN'|'ERROR')?
local function notify(msg, level)
  msg = type(msg) == 'table' and table.concat(msg, '\n') or msg
  vim.notify('(vim.pack) ' .. msg, vim.log.levels[level or 'INFO'])
  vim.cmd.redraw()
end
notify = vim.schedule_wrap(notify)

-- PRNOTE: Naming of both `source` and `version` might be improved.
-- Maybe `url`/`uri` and `follow`/`target`/`checkout`?

--- @class vim.pack.Spec
--- @field source string URI from which to install and pull updates.
--- @field name? string Name of plugin. Will be used as directory name.
---   Default: basename of `source`.
--- @field version? string Version to use for install and updates. One of (from
---   least to most restrictive):
---   - "*" for greatest available semantic version tag. Default.
---   - Branch name.
---   - Any version range "spec" (suitable for |vim.version.range()|).
---   - Tag name.
---   - "HEAD" to freeze current state from updates.

--- @alias vim.pack.SpecResolved { source: string, name: string, version: string }

--- @param spec string|vim.pack.Spec
--- @return vim.pack.SpecResolved
local function normalize_spec(spec)
  spec = type(spec) == 'string' and { source = spec } or spec
  vim.validate('spec', spec, 'table')
  vim.validate('spec.source', spec.source, 'string')
  -- PRNOTE: This assumes `source` as full URI. Should 'user/repo' be allowed
  -- and inferred to come from GitHub?
  local name = (spec.name or spec.source):match('[^/]+$')
  vim.validate('spec.name', name, 'string')
  local version = spec.version or default_version
  vim.validate('spec.version', version, 'string')
  return { source = spec.source, name = name, version = version }
end

-- PRNOTE: There is no `depends` field intentionally. Suggest manually putting
-- dependencies before their dependees.

-- PRNOTE: There might be an argument to also omit `version` from being allowed
-- in `add` in favor of lockfile+update. Workflow is as follows:
-- - Initial install either installs "*" version or based on value in lockfile.
-- - Changing target version is only allowed in `vim.pack.update`: either
--   programmatically or interactively via dedicated LSP code action.
--
-- Pros of version-in-init-lua:
--  - Doesn't require lockfile (the whole "source of truth" is in 'init.lua').
-- Cons of version-in-init-lua:
--  - Typical version switch requires the steps "Edit 'init.lua'" - "Restart" -
--    "Update" - "Restart".
--  - No way to see all available versions/branches. Can be solved with special
--    LSP code action or `vim.pack.list_versions()`.
--
-- Pros of version-in-lockfile:
--  - Typical switch is "Start update" - "Choose version" - "Finish update" -
--    "Restart". Can be done programmatically with
--    `vim.pack.update({ 'plugin.nvim', version = '1.2.3' })`.
-- Cons of version-in-lockfile:
--  - Very initial install at specific version/hash requires both
--    `vim.pack.add()` and `vim.pack.update()`. Might be bad for repros.
--  - Having to have both 'init.lua'+lockfile instead of only 'init.lua',
--    which is not quite Neovim-like.
--
-- The current is chosen based on the assumption that target version switch is
-- rather rare and doing two restarts is fine. Having to know all available
-- targets should also be rare (after showing available versions during
-- interactive update) or can be done as "List available targets" code action.

--- @class (private) vim.pack.Plug
--- @field spec vim.pack.SpecResolved
--- @field path string

--- @param spec string|vim.pack.Spec
--- @return vim.pack.Plug
local function new_plug(spec)
  local spec_resolved = normalize_spec(spec)
  local path = vim.fs.joinpath(get_plug_dir(), spec_resolved.name)
  return { spec = spec_resolved, path = path }
end

--- @alias vim.pack.Job { cmd: string[], cwd: string, out: string, warn: string, err: string }

--- @class vim.pack.PlugList Plugin list with aligned job and state arrays
--- @field plugs vim.pack.Plug[]
--- @field jobs vim.pack.Job[]
--- @field states table[]
local PlugList = {}
PlugList.__index = PlugList

--- @param plugs vim.pack.Plug[]
--- @return vim.pack.PlugList
function PlugList.new(plugs)
  local jobs, states = {}, {}
  for i, p in ipairs(plugs) do
    jobs[i] = { cmd = {}, cwd = p.path, out = '', warn = '', err = '' }
    states[i] = {}
  end
  return setmetatable({ plugs = plugs, jobs = jobs, states = states }, PlugList)
end

--- Run jobs from plugin list in parallel
---
--- For each plugin that hasn't errored yet:
--- - Execute `prepare`.
--- - Execute `job.cmd` asynchronously.
--- - After done, process `code`/`stdout`/`stderr`, run `process`, and start
---   next job.
---
--- @param prepare? fun(plug: vim.pack.Plug, job: vim.pack.Job, state: table): nil
--- @param process? fun(plug: vim.pack.Plug, job: vim.pack.Job, state: table): nil
function PlugList:run_jobs(prepare, process)
  prepare, process = prepare or function(_, _, _) end, process or function(_, _, _) end

  -- PRNOTE: Consider making it configurable
  local n_threads = math.max(math.floor(0.8 * #(uv.cpu_info() or {})), 1)
  local timeout = 30000

  -- Use only plugs which didn't error before
  local id_to_run = {}
  for i = 1, #self.plugs do
    if self.jobs[i].err == '' then
      table.insert(id_to_run, i)
    end
  end
  if #id_to_run == 0 then
    return
  end

  -- Prepare for job execution
  local n_total, n_started, n_finished = #id_to_run, 0, 0
  local run_next
  run_next = function()
    if n_started >= n_total then
      return
    end
    n_started = n_started + 1

    local id = id_to_run[n_started]
    local plug, job, state = self.plugs[id], self.jobs[id], self.states[id]

    local on_exit = function(out)
      -- Process command results. Treat exit code 0 with `stderr` as warning.
      n_finished = n_finished + 1
      job.out = out.stdout:gsub('\n+$', '')

      if out.code == 0 then
        job.warn = job.warn .. (job.warn == '' and '' or '\n\n') .. out.stderr
      else
        job.err = 'Error code ' .. out.code .. '\n' .. out.stderr:gsub('\n+$', '')
      end

      process(plug, job, state)

      run_next()
    end

    prepare(plug, job, state)
    local system_opts = { cwd = job.cwd, text = true, timeout = timeout, clear_env = true }
    -- TODO: Maybe allow omitting execution if `cmd` is empty?
    vim.system(job.cmd, system_opts, on_exit)
  end

  -- Run jobs async in parallel but wait for all to finish/timeout
  for _ = 1, n_threads do
    run_next()
  end

  local total_wait = timeout * math.ceil(n_total / n_threads)
  vim.wait(total_wait, function()
    return n_total <= n_finished
  end, 1)

  -- Clean up. Preserve errors and warnings for jobs to be properly reusable.
  for _, i in ipairs(id_to_run) do
    self.jobs[i].cmd, self.jobs[i].out = {}, ''
  end
end

function PlugList:install()
  -- Clone
  local function prepare(plug, job, _)
    vim.api.nvim_exec_autocmds('User', { pattern = 'PackInstallPre', data = vim.deepcopy(plug) })

    -- Temporarily change job's cwd because target path doesn't exist yet
    job.cwd = vim.fn.getcwd()
    job.cmd = H.git_cmd('clone', plug.spec.source, plug.path)
  end
  local function process(plug, job, _)
    job.cwd = plug.path
  end
  self:run_jobs(prepare, process)

  -- Checkout
  -- TODO: Trigger 'PackInstall' event
  -- TODO: Trigger 'PackUpdatePre' and 'PackUpdate' events. The 'PackUpdate'
  -- should be usable as a single "build" entry.
end

--- @type vim.pack.Plug[]
local added_plugins = {}

--- @param specs (string|vim.pack.Spec)[]
function M.add2(specs, opts)
  vim.validate('specs', specs, vim.islist, 'list')
  opts = opts or {}
  vim.validate('opts', opts, 'table')

  local plugs = vim.tbl_map(new_plug, specs)

  -- Install which needs to be installed
  local plugs_to_install = vim.tbl_filter(function(p)
    return uv.fs_stat(p.path) == nil
  end, plugs)
  if #plugs_to_install > 0 then
    git_ensure_exec()
    local plug_list = PlugList.new(plugs_to_install)
    -- TODO: Add progress report
    plug_list:install()
  end

  -- TODO: Be more careful and avoid duplicates
  vim.list_extend(added_plugins, plugs)
end

--- @class vim.pack.PlugData
--- @field spec vim.pack.Spec
--- @field path string
--- @field was_added boolean
--- @field refs string[]

--- Get data about plugins managed by vim.pack
--- @return vim.pack.PlugData[]
M.get = function()
  local res, names_added = {}, {}
  for _, plug in ipairs(added_plugins) do
    names_added[plug.spec.name] = true
    table.insert(res, { spec = vim.deepcopy(plug.spec), path = plug.path, was_added = true })
  end

  local plug_dir = get_plug_dir()
  for n, t in vim.fs.dir(plug_dir, { depth = 1 }) do
    if t == 'directory' and not names_added[n] then
      local path = vim.fs.joinpath(plug_dir, n)
      local spec = { name = n, version = default_version }
      spec.source = cli_sync(H.git_cmd('get_origin'), path)
      table.insert(res, { spec = spec, path = path, was_added = false })
    end
  end

  for _, data in ipairs(res) do
    local refs = git_get_tags(data.path)
    vim.list_extend(refs, git_get_branches(data.path))
    data.refs = refs
  end

  return res
end

--- Add plugin to current session
---
--- - Process specification by expanding dependencies into single spec array.
--- - Ensure plugin is present on disk along with its dependencies by installing
---   (in parallel) absent ones:
---     - Trigger |PackInstallPre| event.
---     - Use `git clone` to clone plugin from its source URI into "pack/core/opt".
---     - Set state according to `opts.checkout`.
---     - Trigger |PackInstall| event.
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

    notify(string.format('Installing `%s`', plugs[#plugs].name))
    H.plugs_exec_events(plugs_to_install, 'PackInstallPre')
    H.plugs_install(plugs_to_install)
    H.plugs_exec_events(plugs_to_install, 'PackInstall')
  end

  -- Add plugins to current session
  -- PRNOTE: Maybe also trigger `PackAddPre` and `PackAdd` events?
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
--- @param names? string[] List of plugin names to update.
---   Default: all plugins from current session (see |MiniDeps.get_session()|).
--- @param opts table|nil Options. Possible fields:
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
    return notify('Nothing to update')
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

  -- Perform update
  if not opts.force then
    H.update_feedback_confirm(plugs)
    return
  end

  H.plugs_checkout(plugs)
  H.update_feedback_log(plugs)
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
  --TODO: Include all plugins from package path in order:
  -- - Registered in session.
  -- - From 'start/' that are not in session, alphabetically.
  -- - From 'opt/' that are not in session, alphabetically.

  -- Normalize `H.session` allowing specs for same plugin
  local res, plugin_ids = {}, {}
  local add_spec = function(spec)
    local id = plugin_ids[spec.path] or (#res + 1)
    res[id] = vim.tbl_deep_extend('force', res[id] or {}, spec)
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
      add_spec({ path = path, name = name })
    end
  end

  -- Return copy to not allow modification in place
  return vim.deepcopy(res)
end

function M._parse_report(buf_id)
  local grouping, cur_h1, cur_h2 = {}, '', ''
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  for i, l in ipairs(lines) do
    local group_name = l:match('^# (.+)$')
    local plug_name = l:match('^## (.+)$')
    cur_h1 = group_name or cur_h1
    cur_h2 = plug_name or (group_name and '' or cur_h2)
    local h1_start, h2_start = group_name ~= nil, plug_name ~= nil
    grouping[i] = { h1 = cur_h1, h1_start = h1_start, h2 = cur_h2, h2_start = h2_start }
  end
  return grouping
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
    return {
      'clone',
      '--quiet',
      '--filter=blob:none',
      '--recurse-submodules',
      '--also-filter-submodules', -- requires Git>=2.36
      '--origin',
      'origin',
      source,
      path,
    }
  end,
  stash = function(timestamp)
    return {
      'stash',
      '--quiet',
      '--message',
      '(vim.pack) ' .. timestamp .. ' Stash before checkout',
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
    local pretty = '--pretty=format:%m %h │ %s%d'
    -- `--topo-order` makes showing divergent branches nicer
    -- `--decorate-refs` shows only tags near commits (not `origin/main`, etc.)
    return { 'log', pretty, '--topo-order', '--decorate-refs=refs/tags', from .. '...' .. to }
  end,
  list_branches = function()
    return { 'branch', '--remote', '--list', '--format=%(refname:short)', '--', 'origin/**' }
  end,
  list_tags = function()
    return { 'tag', '--list' }
  end,
}

H.ensure_git_exec = function()
  if vim.fn.executable('git') == 0 then
    error('No `git` executable')
  end
end

-- Plugin specification -------------------------------------------------------
H.expand_spec = function(target, spec)
  -- Prepare
  if type(spec) == 'string' then
    local field = string.find(spec, '/') ~= nil and 'source' or 'name'
    spec = { [field] = spec }
  end
  if type(spec) ~= 'table' then
    error('Plugin spec should be table.')
  end

  local has_min_fields = type(spec.source) == 'string' or type(spec.name) == 'string'
  if not has_min_fields then
    error('Plugin spec should have proper `source` or `name`.')
  end

  -- Normalize
  spec = vim.deepcopy(spec)

  if spec.source and type(spec.source) ~= 'string' then
    error('`source` in plugin spec should be string.')
  end
  local is_user_repo = type(spec.source) == 'string'
    and spec.source:find('^[%w-]+/[%w-_.]+$') ~= nil
  if is_user_repo then
    spec.source = 'https://github.com/' .. spec.source
  end

  spec.name = spec.name or vim.fn.fnamemodify(spec.source, ':t')
  if type(spec.name) ~= 'string' then
    error('`name` in plugin spec should be string.')
  end
  if string.find(spec.name, '/') ~= nil then
    error('`name` in plugin spec should not contain "/".')
  end
  if spec.name == '' then
    error('`name` in plugin spec should not be empty.')
  end

  if spec.checkout and type(spec.checkout) ~= 'string' then
    error('`checkout` in plugin spec should be string.')
  end

  table.insert(target, spec)
end

-- Plugin operations ----------------------------------------------------------
H.plugs_exec_events = function(plugs, name)
  for _, p in ipairs(plugs) do
    if not (p.job and #p.job.err > 0) then
      -- TODO: Make it built-in event and not `User`. Use source as pattern?
      local data = { path = p.path, source = p.source, name = p.name }
      vim.api.nvim_exec_autocmds('User', { pattern = name, data = data })
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
  H.plugs_checkout(plugs, { all_helptags = true })

  -- Show warnings and errors
  H.plugs_show_job_notifications(plugs, 'installing plugin')
end

H.plugs_download_updates = function(plugs)
  -- Show actual target number of plugins attempted to fetch
  local n_noerror = 0
  for _, p in ipairs(plugs) do
    n_noerror = n_noerror + (#p.job.err == 0 and 1 or 0)
  end
  if n_noerror == 0 then
    return
  end
  notify('Downloading ' .. n_noerror .. ' update' .. (n_noerror > 1 and 's' or ''))

  local prepare = function(p)
    p.job.cmd = H.git_cmd('fetch')
    p.job.exit_msg = string.format('Downloaded update for `%s`', p.name)
  end
  H.plugs_run_jobs(plugs, prepare)
end

H.plugs_checkout = function(plugs, opts)
  opts = vim.tbl_deep_extend('force', { all_helptags = false }, opts or {})

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

  -- Trigger pre event
  H.plugs_exec_events(checkout_plugs, 'PackUpdatePre')

  -- Checkout
  prepare = function(p)
    p.job.cmd = H.git_cmd('checkout', p.checkout_to)
    p.job.exit_msg = string.format('Checked out `%s` in `%s`', p.checkout, p.name)
  end
  H.plugs_run_jobs(checkout_plugs, prepare)

  -- Trigger post event
  H.plugs_exec_events(checkout_plugs, 'PackUpdate')

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
    error('`names` should be list.')
  end
  for _, name in ipairs(names or {}) do
    if type(name) ~= 'string' then
      error('`names` should contain only strings.')
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
      notify(msg, 'WARN')
    end
    local err = H.cli_stream_tostring(p.job.err)
    if err ~= '' then
      local msg = string.format('Error in `%s` during %s\n%s', p.name, action_name, err)
      notify(msg, 'ERROR')
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
  -- Construct plugin line groups for better report
  local report_err, report_update, report_same = {}, {}, {}
  for _, p in ipairs(plugs) do
    local group_arr = #p.job.err > 0 and report_err
      or (p.head ~= p.checkout_to and report_update or report_same)
    table.insert(group_arr, H.update_compute_report_single(p))
  end

  local lines = {}
  local append_report = function(header, arr)
    if #arr > 0 then
      table.insert(lines, header)
      vim.list_extend(lines, arr)
    end
  end
  append_report('# Errors', report_err)
  append_report('# Updates', report_update)
  append_report('# No updates', report_same)

  return vim.split(table.concat(lines, '\n\n'), '\n')
end

H.update_compute_report_single = function(p)
  local has_updates = p.head ~= p.checkout_to

  local err = H.cli_stream_tostring(p.job.err)
  if err ~= '' then
    return '## ' .. p.name .. '\n\n  ' .. err:gsub('\n', '\n  ')
  end

  local parts = { '## ' .. p.name .. '\n' }

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
  if has_updates then
    table.insert(parts, string.format('\n\nPending updates from `%s`:\n\n', p.checkout))
    table.insert(parts, p.checkout_log)
  end

  return table.concat(parts, '')
end

H.update_feedback_confirm = function(plugs)
  -- Define how update should be finished
  -- TODO(echasnovski): Allow to not update all plugins via LSP code action
  local finish_update = function()
    local plugs_to_update = vim.tbl_filter(function(p)
      return #p.job.err == 0 and p.head ~= p.checkout_to
    end, plugs)

    H.plugs_checkout(plugs_to_update)
    H.update_feedback_log(plugs_to_update)
    H.plugs_show_job_notifications(plugs_to_update, 'update')
  end

  -- Show report in new buffer in separate tabpage
  local lines = H.update_compute_feedback_lines(plugs)
  H.show_confirm_buf(lines, { exec_on_write = finish_update, setup_folds = true })
end

H.update_feedback_log = function(plugs)
  local lines = H.update_compute_feedback_lines(plugs)
  local title = string.format('========== Update %s ==========', H.get_timestamp())
  table.insert(lines, 1, title)
  table.insert(lines, '')

  vim.fn.mkdir(vim.fs.dirname(log_path), 'p')
  vim.fn.writefile(lines, log_path, 'a')
end

-- Confirm --------------------------------------------------------------------
H.show_confirm_buf = function(lines, opts)
  -- Show buffer
  local buf_id = api.nvim_create_buf(true, true)
  api.nvim_buf_set_name(buf_id, 'nvimpack://' .. buf_id .. '/confirm-update')
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
    -- TODO: Use just vim.pack._confirm_foldexpr after moving to Neovim
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
  vim.bo[buf_id].modified, vim.bo[buf_id].modifiable = false, false
  vim.bo[buf_id].buftype, vim.bo[buf_id].filetype = 'acwrite', 'nvimpack'
end

-- CLI ------------------------------------------------------------------------
H.cli_run = function(jobs)
  -- PRNOTE: Consider making it configurable
  local n_threads = math.max(math.floor(0.8 * #(uv.cpu_info() or {})), 1)
  local timeout = 30000

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
    local system_opts = { cwd = job.cwd, text = true, timeout = timeout }

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
        notify(string.format('(%d/%d) %s', n_finished, n_total, job.exit_msg))
      end

      -- Start next parallel job
      run_next()
    end

    vim.system(job.cmd, system_opts, on_exit)
  end

  for _ = 1, n_threads do
    run_next()
  end

  local total_wait = timeout * math.ceil(n_total / n_threads)
  vim.wait(total_wait, function()
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
