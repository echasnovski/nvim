-- TODO:
-- - Add in-process LSP server for progress report, `gO`, and future use
-- - Make events built-in and not `User`. Use source as pattern?

-- PRNOTES:
-- - The module name is `vim.pack` because it aligns well with `:packadd`.
--   The question is what to use as filetype and buffer/file names? Currently
--   it is 'nvimpack' which might be confusing. The 'vimpack' is closer, but it
--   doesn't use 'nvim'.
-- - Currently `vim.pack.add()` only installs into 'opt/' directory.
-- - Custom events are better than hooks because they can be used by plugins to
--   tweak install/update/add behavior of *other* plugins. Plus smaller spec.
-- - Left out from this PR but planned:
--     - User commands. Like `:Pack add` or `:PackAdd`. The latter is more
--       natural when it comes to `!` and easier to implement completion.
--     - Packspec. It is rather big and needs discussions about the degree of
--       support vs complexity.
--     - Lockfile. Basically, store state/commit per source and prefer it
--       during initial install over resolving `version`.
--     - More interactive update features:
--         - Code lenses/actions "update this plugin", "skip updating this
--           plugin", maybe "delete" this plugin.
--         - Hover on pending commit to get its diff.
--           Hover on new tag to get its description and/or changelog.
-- - Not planned as `vim.pack` functionality but discussable:
--     - Manage plugins from 'start/' directory. As `vim.pack.add()` only
--       installs in 'opt/' directory (as it is all that is needed), it seems
--       unnecessary to also manage 'start/' from the same package path.
--     - Lazy loading out of the box. This might be more appropriate to combine
--       with `now()` and `later()` (from 'mini.deps'). These are general
--       enough that can live in `vim.func` and useful outside of `vim.pack`.

-- Implementation overview:
-- - `vim.pack` manages plugins only in a dedicated package directory
--   (`:h packages`): '$XDG_DATA_HOME/nvim/site/pack/core/opt'.
--   It is assumed that all plugins in the directory are managed by `vim.pack`.
--   To have customly managed plugins, use different package directory and
--   manual `:packadd`.
--
-- - Each repo is kept in detached HEAD state with commit being inferred from
--   version. No local branches are created, branches from "origin" remote are
--   used directly.
--
-- - `vim.pack.add()` is a "smarter" `:packadd` for plugins meant to be
--   downloaded:
--     - If plugin is not available in a dedicated package - install it in
--       a synchronous way. This makes it possible to assume that plugin is
--       available after any `vim.pack.add()` call.
--       Currently only implemented via `git clone` ("git" backend).
--     - If plugin is available, execute `:packadd[!]`.
--
-- - Each plugin is added following a minimal specification (`vim.pack.Spec`).
--   It is designed towards future automated packspec support, i.e. plugins
--   themselves containing a special 'pkg.json' (or other) file which should
--   contain at least the following information:
--     - Dependencies: links and versions. Without them user can register
--       dependencies manually by explicitly adding them to `vim.pack.add()`.
--     - Hooks: paths to scripts to be executed before/after install/update.
--       Without them user can register hooks by creating autocommand for
--       dedicated events.
--
-- - `vim.pack.update()` updates the local plugin state. Main use cases:
--     - Fetch new updates from source and apply them:
--         - `vim.pack.update()` (to update all plugins managed by `vim.pack`).
--         - Inspect confirmation info. To confirm changes execute `:write`,
--           to discard changes - close the window or wipeout the buffer.
--           More interactivity (like update/skip only a single plugin, hover
--           to see commit details, etc.) are planned later.
--     - Switch to different version. Usually:
--         - Tweak `vim.pack.add()` call in 'init.lua'.
--         - Restart.
--         - `vim.pack.update({ 'plugin-name' }, { offline = true })`, inspect
--           confirmation info and execute `:write`.
--           Or use `force = true` to skip confirm.

local api = vim.api
local uv = vim.uv

local M = {}

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

local git_args = {
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
  get_origin = function()
    return { 'remote', 'get-url', 'origin' }
  end,
  -- Using `rev-list -1` shows a commit of revision, while `rev-parse` shows
  -- hash of revision. Those are different for annotated tags.
  get_hash = function(rev)
    return { 'rev-list', '-1', rev }
  end,
  log = function(from, to)
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
  list_new_tags = function(from)
    return { 'tag', '--list', '--contains', from }
  end,
}

local function git_cmd(cmd_name, ...)
  local args = git_args[cmd_name](...)
  if args == nil then
    return {}
  end

  -- Use '-c gc.auto=0' to disable `stderr` "Auto packing..." messages
  return { 'git', '-c', 'gc.auto=0', unpack(args) }
end

--- @param cwd string
local function git_get_branches(cwd)
  local stdout, res = cli_sync(git_cmd('list_branches'), cwd), {}
  for _, l in ipairs(vim.split(stdout, '\n')) do
    table.insert(res, l:match('^origin/(.+)$'))
  end
  return res
end

--- @param cwd string
local function git_get_tags(cwd)
  local stdout = cli_sync(git_cmd('list_tags'), cwd)
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

local function is_version_range(x)
  return (pcall(function()
    x:has('1')
  end))
end

local function get_timestamp()
  return vim.fn.strftime('%Y-%m-%d %H:%M:%S')
end

-- PRNOTE: Naming of both `source` and `version` might be improved.
-- Maybe `url`/`uri` and `follow`/`target`/`checkout`?

-- PRNOTE: Allowing version to be explicit `vim.VersionRange` is needed to avoid
-- conflicts with branch names that look similar to version range ("1.0",
-- "v1.0.0", "0-x", "tmux 3.2a", etc.). If that is not a concern, then only
-- allowing string `version` with trying to parsing it as version range is
-- doable.

--- @class vim.pack.Spec
--- @field source string URI from which to install and pull updates.
--- @field name? string Name of plugin. Will be used as directory name.
---   Default: basename of `source`.
--- @field version? string|vim.VersionRange Version to use for install and updates. One of (from
---   least to most restrictive):
---   - Output of |vim.version.range()| to install the greatest/last semver tag
---     inside the range. Default: `vim.version.range('*')`, i.e. install the
---     greatest available version.
---   - Tag name.
---   - Branch name.
---   - "HEAD" to freeze current state from updates.
---   - Explicit commit hash.

--- @alias vim.pack.SpecResolved { source: string, name: string, version: string|vim.VersionRange }

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
  local version = spec.version or vim.version.range('*')
  local is_version = function(x)
    return type(x) == 'string' or is_version_range(x)
  end
  vim.validate('spec.version', version, is_version, false, 'string or vim.VersionRange')
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

--- @alias vim.pack.Job { cmd: string[], cwd: string, out: string, err: string }

--- @class (private) vim.pack.PlugJobInfo
--- @field warn? string Concatenated job warnings
--- @field version_str? string `spec.version` with resolved version range.
--- @field version_ref? string Resolved version as Git reference (if different
---   from `version_str`).
--- @field sha_head? string Git hash of HEAD.
--- @field sha_target? string Git hash of `version_ref`.
--- @field update_details? string Details about the update:: changelog if HEAD
---   and target are different, available newer tags otherwise.

--- @class (private) vim.pack.PlugJob
--- @field plug vim.pack.Plug
--- @field job { cmd: string[], cwd: string, out: string, err: string }
--- @field info vim.pack.PlugJobInfo

--- @class (private) vim.pack.PlugList List of plugin along with job and info
--- @field list vim.pack.PlugJob[]
local PlugList = {}
PlugList.__index = PlugList

--- @param plugs vim.pack.Plug[]
--- @return vim.pack.PlugList
function PlugList.new(plugs)
  local list = {}
  for i, p in ipairs(plugs) do
    local job = { cmd = {}, cwd = p.path, out = '', err = '' }
    list[i] = { plug = p, job = job, info = { warn = '' } }
  end
  return setmetatable({ list = list }, PlugList)
end

--- Run jobs from plugin list in parallel
---
--- For each plugin that hasn't errored yet:
--- - Execute `prepare`: do side effects and set `job.cmd`.
--- - If set, execute `job.cmd` asynchronously.
--- - After done, preprocess `code`/`stdout`/`stderr`, run `process` to gather
---   useful info, and start next job.
---
--- @param prepare? fun(vim.pack.PlugExtra): nil
--- @param process? fun(vim.pack.PlugExtra): nil
function PlugList:run(prepare, process)
  prepare, process = prepare or function(_) end, process or function(_) end

  -- PRNOTE: Consider making it configurable
  local n_threads = math.max(math.floor(0.8 * #(uv.cpu_info() or {})), 1)
  local timeout = 30000

  -- Use only plugs which didn't error before
  local list_noerror = vim.tbl_filter(function(p)
    return p.job.err == ''
  end, self.list)
  if #list_noerror == 0 then
    return
  end

  -- Prepare for job execution
  local n_total, n_started, n_finished = #list_noerror, 0, 0
  local function run_next()
    if n_started >= n_total then
      return
    end
    n_started = n_started + 1

    local p = list_noerror[n_started]

    local on_exit = function(sys_res)
      n_finished = n_finished + 1

      local stderr = sys_res.stderr:gsub('\n+$', '')
      -- If error, skip custom processing
      if sys_res.code ~= 0 then
        p.job.err = 'Error code ' .. sys_res.code .. '\n' .. stderr
        return run_next()
      end

      -- Process command results. Treat exit code 0 with `stderr` as warning.
      p.job.out = sys_res.stdout:gsub('\n+$', '')
      p.info.warn = p.info.warn .. (stderr == '' and '' or ('\n\n' .. stderr))
      process(p)
      run_next()
    end

    prepare(p)
    if #p.job.cmd == 0 or p.job.err ~= '' then
      n_finished = n_finished + 1
      return run_next()
    end
    local system_opts = { cwd = p.job.cwd, text = true, timeout = timeout, clear_env = true }
    vim.system(p.job.cmd, system_opts, on_exit)
  end

  -- Run jobs async in parallel but wait for all to finish/timeout
  for _ = 1, n_threads do
    run_next()
  end

  local total_wait = timeout * math.ceil(n_total / n_threads)
  vim.wait(total_wait, function()
    return n_finished >= n_total
  end, 1)

  -- Clean up. Preserve errors to stop processing plugin after the first one.
  for _, p in ipairs(list_noerror) do
    p.job.cmd, p.job.cwd, p.job.out = {}, p.plug.path, ''
  end
end

function PlugList:install()
  self:trigger_event('PackInstallPre')

  -- Clone
  -- TODO: Add progress report
  --- @param p vim.pack.PlugJob
  local function prepare(p)
    -- Temporarily change job's cwd because target path doesn't exist yet
    p.job.cwd = vim.fn.getcwd()
    p.job.cmd = git_cmd('clone', p.plug.spec.source, p.plug.path)
  end
  self:run(prepare, nil)

  -- Checkout to target version. Do not skip checkout even if HEAD and target
  -- have same commit hash to have installed repo in expected detached HEAD
  -- state and generated help files.
  self:checkout({ skip_same_sha = false })

  -- NOTE: 'PackInstall' is triggered after 'PackUpdate' intentionally to have
  -- it indicate "plugin is installed in its correct initial version"
  self:trigger_event('PackInstall')
  self:show_notifications('installation')
end

--- @param opts { skip_same_sha: boolean }
function PlugList:checkout(opts)
  opts = vim.tbl_deep_extend('force', { skip_same_sha = true }, opts or {})

  self:infer_head()
  self:infer_target()

  local plug_list = vim.deepcopy(self)
  if opts.skip_same_sha then
    plug_list.list = vim.tbl_filter(function(p)
      return p.info.sha_head ~= p.info.sha_target
    end, plug_list.list)
  end

  -- Stash changes
  local stash_cmd = git_cmd('stash', get_timestamp())
  --- @param p vim.pack.PlugJob
  local function prepare(p)
    p.job.cmd = stash_cmd
  end
  plug_list:run(prepare, nil)

  self:trigger_event('PackUpdatePre')

  -- Checkout
  prepare = function(p)
    p.job.cmd = git_cmd('checkout', p.info.sha_target)
  end
  --- @param p vim.pack.PlugJob
  local function process(p)
    local msg = string.format('Updated state to `%s` in `%s`', p.info.version_str, p.plug.spec.name)
    notify(msg, 'INFO')
  end
  plug_list:run(prepare, process)

  self:trigger_event('PackUpdate')

  -- (Re)Generate help tags according to the current help files
  for _, p in ipairs(plug_list.list) do
    -- Completely redo tags
    local doc_dir = p.plug.path .. '/doc'
    vim.fn.delete(doc_dir .. '/tags')
    -- Use `pcall()` because `:helptags` errors if there is no 'doc/' directory
    -- or if it is empty
    pcall(vim.cmd.helptags, vim.fn.fnameescape(doc_dir))
  end
end

function PlugList:download_updates()
  --- @param p vim.pack.PlugJob
  local function prepare(p)
    -- TODO: Add progress report
    p.job.cmd = git_cmd('fetch')
  end
  self:run(prepare, nil)
end

function PlugList:resolve_version()
  --- @param p vim.pack.PlugJob
  local function prepare(p)
    if p.info.version_str ~= nil then
      return
    end
    local version = p.plug.spec.version

    -- Allow 'HEAD' to mean 'HEAD' (freeze current state from updates)
    if version == 'HEAD' then
      p.info.version_str = 'HEAD'
      return
    end

    -- Allow specifying non-version-range like version: branch or commit.
    if not is_version_range(version) then
      --- @cast version string
      local branches = git_get_branches(p.plug.path)
      p.info.version_str = version
      p.info.version_ref = (vim.tbl_contains(branches, version) and 'origin/' or '') .. version
      return
    end
    --- @cast version vim.VersionRange

    -- Choose the greatest/last version among all matching semver tags
    local last_ver_tag = nil
    for _, tag in ipairs(git_get_tags(p.plug.path)) do
      local ver_tag = vim.version.parse(tag)
      local is_in_range = ver_tag ~= nil and version:has(ver_tag)
      if is_in_range and (last_ver_tag == nil or ver_tag > last_ver_tag) then
        p.info.version_str, last_ver_tag = tag, ver_tag
      end
    end

    if p.info.version_str == nil then
      p.job.err = 'No tags matching version range ' .. vim.inspect
    end
  end
  self:run(prepare, nil)
end

function PlugList:infer_head()
  --- @param p vim.pack.PlugJob
  local function prepare(p)
    p.job.cmd = p.info.sha_head == nil and git_cmd('get_hash', 'HEAD') or {}
  end
  --- @param p vim.pack.PlugJob
  local function process(p)
    p.info.sha_head = p.info.sha_head or p.job.out
  end
  self:run(prepare, process)
end

function PlugList:infer_target()
  self:resolve_version()

  --- @param p vim.pack.PlugJob
  local function prepare(p)
    local target_ref = p.info.version_ref or p.info.version_str
    p.job.cmd = p.info.sha_target == nil and git_cmd('get_hash', target_ref) or {}
  end
  --- @param p vim.pack.PlugJob
  local function process(p)
    p.info.sha_target = p.info.sha_target or p.job.out
  end
  self:run(prepare, process)
end

function PlugList:infer_update_details()
  self:infer_head()
  self:infer_target()

  --- @param p vim.pack.PlugJob
  local function prepare(p)
    local from, to = p.info.sha_head, p.info.sha_target
    p.job.cmd = from ~= to and git_cmd('log', from, to) or git_cmd('list_new_tags', from)
  end
  --- @param p vim.pack.PlugJob
  local function process(p)
    local details = p.job.out
    if p.info.sha_head == p.info.sha_target then
      details = details:gsub(vim.pesc(p.info.version_str) .. '\n?', '')
    end
    p.info.update_details = details
  end
  self:run(prepare, process)
end

--- Trigger event for not yet errored plugin jobs
--- Do so as `PlugList` method to preserve order, which might be important when
--- dealing with dependencies.
--- @param event_name 'PackInstallPre'|'PackInstall'|'PackUpdatePre'|'PackUpdate'
function PlugList:trigger_event(event_name)
  --- @param p vim.pack.PlugJob
  local function prepare(p)
    vim.api.nvim_exec_autocmds('User', { pattern = event_name, data = vim.deepcopy(p.plug) })
    p.job.cmd = {}
  end
  self:run(prepare, nil)
end

--- @param action_name string
function PlugList:show_notifications(action_name)
  for _, p in ipairs(self.list) do
    local name, warn = p.plug.spec.name, p.info.warn
    if warn ~= '' then
      local msg = string.format('Warnings in `%s` during %s:\n%s', name, action_name, warn)
      notify(msg, 'WARN')
    end
    local err = p.job.err
    if err ~= '' then
      local msg = string.format('Error in `%s` during %s:\n%s', name, action_name, err)
      error(msg)
    end
  end
end

--- @type table<string, { plug: vim.pack.Plug, id: integer }>
local added_plugins = {}
local n_added_plugins = 0

--- @param plug vim.pack.Plug
--- @param bang boolean
local function pack_add(plug, bang)
  -- Add plugin only once, i.e. no overriding of spec. This allows users to put
  -- plugin first to fully control its spec.
  if added_plugins[plug.path] ~= nil then
    return
  end

  n_added_plugins = n_added_plugins + 1
  added_plugins[plug.path] = { plug = plug, id = n_added_plugins }

  vim.cmd.packadd({ plug.spec.name, bang = bang })

  -- Execute 'after/' scripts if not during startup (when they will be sourced
  -- automatically), as `:packadd` only sources plain 'plugin/' files.
  -- See https://github.com/vim/vim/issues/15584
  -- Deliberately do so after executing all currently known 'plugin/' files.
  local should_load_after_dir = vim.v.vim_did_enter == 1 and not bang and vim.o.loadplugins
  if should_load_after_dir then
    local after_paths = vim.fn.glob(plug.path .. '/after/plugin/**/*.{vim,lua}', false, true)
    vim.tbl_map(function(path)
      pcall(vim.cmd.source, vim.fn.fnameescape(path))
    end, after_paths)
  end
end

--- Add plugin to current session
---
--- - Ensure each plugin is present on disk by installing (in parallel) absent
---   ones:
---     - Trigger |PackInstallPre| event.
---     - Use `git clone` to clone plugin from its source URI into
---       "pack/core/opt".
---     - Set state according to `opts.version`.
---       Triggers |PackUpdatePre| and |PackUpdate|.
---     - Trigger |PackInstall| event.
--- - Register plugin in current session.
--- - Make sure plugin(s) can be used in current session (see |:packadd|).
--- - If not during startup and is needed, source all "after/plugin/" scripts.
---
--- Notes:
--- - To increase performance, this function only ensures presence on disk and
---   nothing else. In particular, it doesn't ensure `opts.version` state if
---   plugin is already available. Use |M.update()| explicitly.
--- - Adding plugin several second and more times does nothing: only the data
---   from the first adding is registered.
---
--- @param specs (string|vim.pack.Spec)[]
--- @param opts? { bang: boolean }
function M.add(specs, opts)
  vim.validate('specs', specs, vim.islist, false, 'list')
  opts = vim.tbl_extend('force', { bang = false }, opts or {})
  vim.validate('opts', opts, 'table')

  local plugs = vim.tbl_map(new_plug, specs)

  -- Install
  local plugs_to_install = vim.tbl_filter(function(p)
    return uv.fs_stat(p.path) == nil
  end, plugs)
  if #plugs_to_install > 0 then
    git_ensure_exec()
    PlugList.new(plugs_to_install):install()
  end

  -- Register and `:packadd`
  -- PRNOTE: This entire step will be skipped if there was at least one error
  -- during installation (like not wrong source URL or not available version).
  -- Alternatively, it can add plugins that did not error first.
  for _, p in ipairs(plugs) do
    pack_add(p, opts.bang)
  end
end

--- @param p vim.pack.PlugJob
--- @return string
local function compute_feedback_lines_single(p)
  if p.job.err ~= '' then
    return '## ' .. p.plug.spec.name .. '\n\n  ' .. p.job.err:gsub('\n', '\n  ')
  end

  local parts = { '## ' .. p.plug.spec.name .. '\n' }

  -- PRNOTE: Should it contain info about whether plugin was added or not?
  if p.info.sha_head == p.info.sha_target then
    table.insert(parts, 'Path:   ' .. p.plug.path .. '\n')
    table.insert(parts, 'Source: ' .. p.plug.spec.source .. '\n')
    table.insert(parts, 'State:  ' .. p.info.sha_target .. ' (' .. p.info.version_str .. ')')

    table.insert(parts, '\n\nNo pending updates')
    if p.info.update_details ~= '' then
      local details = p.info.update_details:gsub('\n', '\n• ')
      table.insert(parts, '\nAvailable newer tags:\n• ' .. details)
    end
  else
    table.insert(parts, 'Path:         ' .. p.plug.path .. '\n')
    table.insert(parts, 'Source:       ' .. p.plug.spec.source .. '\n')
    table.insert(parts, 'State before: ' .. p.info.sha_head .. '\n')
    table.insert(parts, 'State after:  ' .. p.info.sha_target .. ' (' .. p.info.version_str .. ')')

    table.insert(parts, '\n\nPending updates:\n' .. p.info.update_details)
  end

  return table.concat(parts, '')
end

--- @param plug_list vim.pack.PlugList
--- @param opts { skip_same_sha: boolean }
--- @return string[]
local function compute_feedback_lines(plug_list, opts)
  -- Construct plugin line groups for better report
  local report_err, report_update, report_same = {}, {}, {}
  for _, p in ipairs(plug_list.list) do
    local group_arr = #p.job.err > 0 and report_err
      or (p.info.sha_head ~= p.info.sha_target and report_update or report_same)
    table.insert(group_arr, compute_feedback_lines_single(p))
  end

  local lines = {}
  local append_report = function(header, arr)
    if #arr == 0 then
      return
    end
    header = header .. ' ' .. string.rep('─', 79 - header:len())
    table.insert(lines, header)
    vim.list_extend(lines, arr)
  end
  append_report('# Error', report_err)
  append_report('# Update', report_update)
  if not opts.skip_same_sha then
    append_report('# Same', report_same)
  end

  return vim.split(table.concat(lines, '\n\n'), '\n')
end

--- @param plug_list vim.pack.PlugList
local feedback_log = function(plug_list)
  local lines = compute_feedback_lines(plug_list, { skip_same_sha = true })
  local title = string.format('========== Update %s ==========', get_timestamp())
  table.insert(lines, 1, title)
  table.insert(lines, '')

  local log_path = vim.fn.stdpath('log') .. '/nvimpack.log'
  vim.fn.mkdir(vim.fs.dirname(log_path), 'p')
  vim.fn.writefile(lines, log_path, 'a')
end

local function show_confirm(lines, opts)
  -- Show buffer in a separate tabpage
  local bufnr = api.nvim_create_buf(true, true)
  api.nvim_buf_set_name(bufnr, 'nvimpack://' .. bufnr .. '/confirm-update')
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.cmd.sbuffer({ bufnr, mods = { tab = vim.fn.tabpagenr('#') } })
  local tab_num, win_id = api.nvim_tabpage_get_number(0), api.nvim_get_current_win()

  local delete_buffer = vim.schedule_wrap(function()
    pcall(api.nvim_buf_delete, bufnr, { force = true })
    pcall(vim.cmd.tabclose, tab_num)
    vim.cmd.redraw()
  end)

  -- Define action on accepting confirm
  local finish = function()
    opts.exec_on_write(bufnr)
    delete_buffer()
  end
  -- - Use `nested` to allow other events (useful for statuslines)
  api.nvim_create_autocmd('BufWriteCmd', { buffer = bufnr, nested = true, callback = finish })

  -- Define action to cancel confirm
  local cancel_au_id
  local on_cancel = function(data)
    if tonumber(data.match) ~= win_id then
      return
    end
    pcall(api.nvim_del_autocmd, cancel_au_id)
    delete_buffer()
  end
  cancel_au_id = api.nvim_create_autocmd('WinClosed', { nested = true, callback = on_cancel })

  -- Set buffer-local options last (so that user autocmmands could override)
  vim.bo[bufnr].modified, vim.bo[bufnr].modifiable = false, false
  vim.bo[bufnr].buftype, vim.bo[bufnr].filetype = 'acwrite', 'nvimpack'
end

--- @param plug_list vim.pack.PlugList
local function feedback_confirm(plug_list)
  local finish_update = function()
    -- TODO(echasnovski): Allow to not update all plugins via LSP code actions
    plug_list:checkout({ skip_same_sha = true })
    feedback_log(plug_list)
  end

  -- Show report in new buffer in separate tabpage
  local lines = compute_feedback_lines(plug_list, { skip_same_sha = false })
  show_confirm(lines, { exec_on_write = finish_update })
end

--- Update plugins
---
--- - Synchronize specs with state of plugins on disk (set `source`, etc.).
--- - If not offline, download updates (in parallel).
--- - Infer target state and other update info.
--- - If update is forced, apply all changes immediately while updating log
---   file (at "|$NVIM_LOG_FILE|/nvimpack.log").
---   Otherwise show confirmation buffer.
---
--- TODO: Describe confirmation.
---
--- @param names string[] List of plugin names managed by `vim.pack`.
--- @param opts { force: boolean, offline: boolean }
function M.update(names, opts)
  vim.validate('names', names, vim.islist, true, 'list')
  opts = vim.tbl_extend('force', { force = false, offline = false }, opts or {})

  local plugs_to_update = {}
  for _, p_data in ipairs(M.get()) do
    if names == nil or vim.tbl_contains(names, p_data.spec.name) then
      table.insert(plugs_to_update, { spec = p_data.spec, path = p_data.path })
    end
  end

  if #plugs_to_update == 0 then
    notify('Nothing to update', 'WARN')
    return
  end

  git_ensure_exec()
  local plug_list = PlugList.new(plugs_to_update)

  -- Download data if asked
  if not opts.offline then
    plug_list:download_updates()
  end

  -- Compute change info: changelog if any, new tags if nothing to update
  plug_list:infer_update_details()

  -- Perform update
  if not opts.force then
    feedback_confirm(plug_list)
    return
  end

  plug_list:checkout({ skip_same_sha = true })
  feedback_log(plug_list)
end

--- @class vim.pack.PlugData
--- @field spec { source: string, name: string, version: string|vim.VersionRange }
--- @field path string
--- @field was_added boolean

--- Get data about plugins managed by vim.pack
--- @return vim.pack.PlugData[]
function M.get()
  local res = {}
  for _, p_data in pairs(added_plugins) do
    local plug = p_data.plug
    res[p_data.id] = { spec = vim.deepcopy(plug.spec), path = plug.path, was_added = true }
  end

  local plug_dir = get_plug_dir()
  for n, t in vim.fs.dir(plug_dir, { depth = 1 }) do
    local path = vim.fs.joinpath(plug_dir, n)
    if t == 'directory' and not added_plugins[path] then
      local spec = { name = n, version = vim.version.range('*') }
      spec.source = cli_sync(git_cmd('get_origin'), path)
      table.insert(res, { spec = spec, path = path, was_added = false })
    end
  end

  return res
end

function M._parse_report(bufnr)
  local grouping, cur_h1, cur_h2 = {}, '', ''
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
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

return M
