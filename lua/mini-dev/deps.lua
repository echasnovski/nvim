-- TODO:
--
-- Code:
--
-- - `plugs_checkout()`:
--     - Invesitgate why help tags are recomputed but help page is not updated
--       if previously was displayed after valid `:help` command.
--
-- - Stop using special "session" notion in favor of parsing 'runtimepath' for
--   proper ancestors of `config.path.package` (excluding 'after').
--   Make sure that order is correct.
--
-- - Rethink about making `add()` and `remove()` accept list (of specs/names
--   respectively). This will allow having canonical `opts` as second argument.
--   In `add()` allow either one `source` of `name` to be present.
--   String spec is treated as `source` if it contains at least one '/', as
--   `name` otherwise.
--   Update `remove()` to still accept `delete_dir` as second argument but
--   operate on all target plugins.
--
-- - Implement `depends` spec.
--
-- - Think about renaming `track` in spec to `monitor`.
--
-- Docs:
-- - Add examples of user commands in |MiniDeps-actions|.
-- - Clarify distinction in how to use `checkout` and `track`. They allow both
--   automated update from some branch and (more importantly) "freezing" plugin
--   at certain commit/tag while allowing to track updates waiting for the
--   right time to update `checkout`.
-- - In update reports note that `>`/`<` means commit will be added/reverted.
-- - To freeze plugin from updates use `checkout = 'HEAD'`.
--
-- Tests:
-- - Session:
--     - `get_session()` should return in order user added them.
--
-- - Update:
--     - Should `origin` remote to be `source` even if `remote = false`.
--
-- - Checkout:
--     - Should **not** update `checkout` data in session.
--       To update that, remove from session and add with proper `checkout`.
--     - Hooks should be executed in order defined in current session.

--- *mini.deps* Plugin manager
--- *MiniDeps*
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Manage plugins utilizing Git and built-in |packages| with these actions:
---     - Add / remove plugin in current session.
---       See |MiniDeps.add()| and |MiniDeps.remove()|.
---     - Delete unused plugins. See |MiniDeps.clean()|.
---     - Update with/without confirm, with/without downloading new data.
---       See |MiniDeps.update()|.
---     - Get / set / save / load snapshot. See `MiniDeps.snap_*()` functions.
---     All these actions are available both as Lua functions and user commands
---     (see |MiniDeps-commands|).
---
--- - Minimal yet flexible plugin specification:
---     - Mandatory plugin source.
---     - Name of target plugin directory.
---     - Checkout target: branch, commit, tag, etc.
---     - Tracking branch to monitor updates without checking out.
---     - Dependencies to be set up prior to the target plugin.
---     - Hooks to call before/after plugin is created/changed/deleted.
---
--- - Helpers to implement two-stage startup: |MiniDeps.now()| and |MiniDeps.later()|.
---   See |MiniDeps-examples| for how to implement basic lazy loading with them.
---
--- What it doesn't do:
---
--- - Manage plugins which are developed without Git. The suggested approach is
---   to create a separate package (see |packages|).
---
--- Sources with more details:
--- - |MiniDeps-examples|.
--- - |MiniDeps-plugin-specification|.
--- - |MiniDeps-commands|.
---
--- # Dependencies ~
---
--- For most of its functionality this plugin relies on `git` CLI tool.
--- See https://git-scm.com/ for more information about how to install it.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.deps').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniDeps`
--- which you can use for scripting or manually (with `:lua MiniDeps.*`).
---
--- See |MiniDeps.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minideps_config` which should have same structure as
--- `MiniDeps.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'folke/lazy.nvim':
---
--- - 'savq/paq-nvim':
---     - Main inspiration.
---
--- - 'lewis6991/pckr.nvim' :
---

--- # Directory structure ~
---
--- All module's data is stored in `config.path.package` directory inside
--- "pack/deps" subdirectory. It itself has the following subdirectories:
---
--- - `opt` with optional plugins (sourced after |:packadd|).
---   Creating inside |MiniDeps.add()| uses this directory.
---
--- - `start` with non-optional plugins (sourced at start unconditionally).
---   All its subdirectories are recognized as plugins by this module.
---   To actually use it, move installed plugin from `opt` directory.
---   HOWEVER, there will be less long-term confusion if only `opt` is used.
---
--- - `rollback` with a history of automated snapshots. Those are created
---   with |MiniDeps.snapsave()| before every |MiniDeps.update()| and
---   are used by |MiniDeps.rollback()|.
---@tag MiniDeps-directory-structure

--- # Plugin specification ~
---
--- Each plugin dependency is managed based on its specification (a.k.a. "spec").
--- See |MiniDeps-examples| for how it is suggested to be used inside user config.
---
--- Mandatory:
--- - <source> `(string)` - field with URI of plugin source.
---   Can be anything allowed by `git clone`.
---   Note: as the most common case, URI of the format "user/repo" is transformed
---   into "https://github.com/user/repo". For relative path use "./user/repo".
---
--- Optional:
--- - <name> `(string|nil)` - directory basename of where to put plugin source.
---   It is put in "pack/deps/opt" subdirectory of `config.path.package`.
---   Default: basename of a <source>.
---
--- - <checkout> `(string|nil)` - checkout target used to set state during update.
---   Can be anything supported by `git checkout` - branch, commit, tag, etc.
---   Default: `nil` for default branch (usually "main" or "master").
---
--- - <track> `(string|nil)` - tracking branch used to show new changes if
---   there is nothing new to checkout. Should be a name of present Git branch.
---   Default: `nil` for default branch (usually "main" or "master").
---
--- - <depends> `(table|nil)` - array of strings with plugin sources. Each plugin
---   will be set up prior to the target. Note: for more configuration of
---   dependencies, set them up separately prior to adding the target.
---   Default: `{}`.
---
--- - <hooks> `(table|nil)` - table with callable hooks to call on certain events.
---   Each hook is executed without arguments. Possible hook names:
---     - <pre_create>  - before creating plugin directory.
---     - <post_create> - after  creating plugin directory.
---     - <pre_change>  - before making update in plugin directory.
---     - <post_change> - after  making update in plugin directory.
---     - <pre_delete>  - before deleting plugin directory.
---     - <post_delete> - after  deleting plugin directory.
---   Default: empty table for no hooks.
---@tag MiniDeps-plugin-specification

--- # User commands ~
---                                                                       *:DepsAdd*
---                                                                    *:DepsRemove*
---                                                                     *:DepsClean*
---                                                                    *:DepsUpdate*
---                                                                  *:DepsSnapSave*
---                                                                  *:DepsSnapLoad*
---@tag MiniDeps-commands

--- # Usage examples ~
---
--- Make sure that `git` CLI tool is installed.
---
--- ## In config (functional style) ~
---
--- Recommended approach to organize config: >
---
---   -- Make sure that code from 'mini.deps' can be executed
---   vim.cmd('packadd mini.nvim') -- or 'packadd mini.deps' if using standalone
---
---   local deps = require('mini.deps')
---   local add, now, later = deps.add, deps.now, deps.later
---
---   -- Tweak setup to your liking
---   deps.setup()
---
---   -- Run code safely with `now()`
---   now(function() vim.cmd('colorscheme randomhue') end)
---   now(function() require('mini.statusline').setup() end)
---   now(function() require('mini.tabline').setup() end)
---
---   -- Delay code execution safely with `later()`
---   later(function()
---     require('mini.pick').setup()
---     vim.ui.select = MiniPick.ui_select
---   end)
---
---   -- Use external plugins
---   now(function()
---     -- If doesn't exist, will create from supplied URI
---     add('nvim-tree/nvim-web-devicons')
---     require('nvim-web-devicons').setup()
---   end)
---
---   later(function()
---     local is_010 = vim.fn.has('nvim-0.10') == 1
---     add(
---       'nvim-treesitter/nvim-treesitter',
---       {
---         checkout = is_010 and 'main' or 'master',
---         hooks = { post_change = function() vim.cmd('TSUpdate') end },
---       }
---     )
---
---     -- Run any code related to plugin's config
---     local parsers = { 'bash', 'python', 'r' }
---     if is_010 then
---       require('nvim-treesitter').setup({ ensure_install = parsers })
---     else
---       require('nvim-treesitter.configs').setup({ ensure_installed = parsers })
---     end
---   end)
--- <
--- ## Plugin management ~
---
--- `:DepsAdd user/repo` makes plugin from https://github.com/user/repo available
--- in the current session (also creates it, if it is not present). See |:DepsAdd|.
--- To add plugin in every session, see previous section.
---
--- `:DepsRemove repo` makes plugin with name "repo" not available in the
--- current session and deletes its directory from disk. Do not forget to
--- update config to not add same plugin in next session. See |:DepsRemove|.
--- Alternatively: manually delete plugin directory (if no hooks are set up).
---
--- `:DepsClean` removes plugins not loaded in current session. See |:DepsClean|.
---
--- `:DepsUpdate` updates all plugins with new changes from their sources.
--- See |:DepsUpdate|.
---
--- `:DepsFetch` fetches new data from plugins sources and not affects code on disk.
--- See |:DepsFetch|.
---
--- `:DepsSnapshot` creates snapshot file in default location (by default,
--- "deps-snapshot" file in config directory). See |:DepsSnapshot|.
---
--- `:DepsCheckout path/to/snapshot` makes present plugins have state from the
--- snapshot file. See |:DepsCheckout|.
---@tag MiniDeps-examples

---@alias __deps_source string Plugin's source. See |MiniDeps-plugin-specification|.
---@alias __deps_spec_opts table|nil Optional spec fields. See |MiniDeps-plugin-specification|.
---@alias __deps_names table Array of plugin names registered in current session
---   with |MiniDeps.add()|. See |MiniDeps.get_session()|.
---   Default: names of all registered plugins.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
MiniDeps = {}
H = {}

--- Module setup
---
--- Calling this function creates all user commands described in |MiniDeps-actions|.
---
---@param config table|nil Module config table. See |MiniDeps.config|.
---
---@usage `require('mini.deps').setup({})` (replace `{}` with your `config` table).
MiniDeps.setup = function(config)
  -- Export module
  _G.MiniDeps = MiniDeps

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_user_commands(config)
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniDeps.config = {
  -- Parameters of CLI jobs
  job = {
    -- Number of parallel threads to use. Default: 80% of all available.
    n_threads = nil,

    -- Timeout (in ms) which each job should take on average
    timeout = 60000,
  },

  -- Paths describing where to store data
  path = {
    -- Directory for built-in package.
    -- All data is actually stored in the 'pack/deps' subdirectory.
    package = vim.fn.stdpath('data') .. '/site',

    -- Default file path for a snapshot
    snapshot = vim.fn.stdpath('config') .. '/mini-deps-snap',

    -- Update log
    log = vim.fn.stdpath('state') .. '/mini-deps.log',
  },

  -- Whether to disable showing non-error feedback
  silent = false,
}
--minidoc_afterlines_end

--- Add plugin to current session
---
--- - If there is no directory present with plugin's name, create it:
---     - Execute `opts.hooks.pre_create`.
---     - Use `git clone` to clone plugin from its source URI into "pack/deps/opt".
---     - Checkout according to `opts.checkout`.
---     - Execute `opts.hooks.post_create`.
---   Note: If plugin directory is present, no action with it is done (to increase
---   performance during startup). In particular, it does not checkout according
---   to `opts.checkout`. Use |MiniDeps.checkout()| explicitly.
--- - Register plugin's spec in current session if there is no plugin with the
---   same name already registered.
--- - Make sure it can be used in current session (see |:packadd|).
---
---@param source __deps_source
---@param opts __deps_spec_opts
MiniDeps.add = function(source, opts)
  local spec = H.normalize_spec(source, opts)

  -- Decide whether to create plugin
  local path, is_present = H.get_plugin_path(spec.name)
  spec.path = path
  if not is_present then
    spec.job = H.cli_new_job({}, vim.fn.getcwd())
    local plugs = { spec }
    H.plugs_exec_hooks(plugs, 'pre_create')
    H.plugs_create(plugs)
    H.plugs_exec_hooks(plugs, 'post_create')
  end

  -- Register plugin's spec in current session
  table.insert(H.session, spec)

  -- Add plugin to current session
  vim.cmd('packadd ' .. spec.name)
end

--- Remove plugin from current session
---
--- - Remove plugin path from 'runtimpath'.
--- - Remove plugin spec from current session (if present).
--- - Unload all cached Lua modules from plugin. This enables resetting plugin
---   functionality after possible next |MiniDeps.add()|.
--- - If `delete_dir`, delete plugin directory:
---     - Execute `pre_delete` hook (if plugin with input name is registered).
---     - Delete plugin directory.
---     - Execute `post_delete` hook (if plugin with input name is registered).
---
---@param name string Plugin directory name in |MiniDeps-directory-structure|.
---@param delete_dir boolean|nil Whether to delete plugin directory. Default: `false`.
MiniDeps.remove = function(name, delete_dir)
  if type(name) ~= 'string' then H.error('`name` should be string.') end
  if delete_dir == nil then delete_dir = false end

  local path, is_present = H.get_plugin_path(name)
  if not is_present then return H.error('`' .. name .. '` is not a name of present plugin.') end

  -- Find current session data for plugin
  local session, session_id = MiniDeps.get_session(), nil
  for i, spec in ipairs(session) do
    if spec.name == name then session_id = i end
  end

  -- Remove plugin
  vim.cmd('set rtp-=' .. vim.fn.fnameescape(path))
  if session_id ~= nil then table.remove(H.session, session_id) end
  H.unload_lua_modules(path)

  -- Possibly delete directory
  if not delete_dir then return end

  local spec = session[session_id] or { hooks = {} }
  local plugs = { spec }
  H.plugs_exec_hooks(plugs, 'pre_delete')
  vim.fn.delete(path, 'rf')
  H.plugs_exec_hooks(plugs, 'post_delete')
  H.notify('(1/1) Deleted plugin `' .. name .. '` from disk.')
end

--- Clean plugins
---
--- - Delete plugin directories (based on |MiniDeps-directory-structure|) which
---   are currently not present in 'runtimpath'.
MiniDeps.clean = function()
  -- Get map of all runtime paths
  local is_in_rtp = {}
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    is_in_rtp[path] = true
  end

  -- Get all paths from packages 'opt/' and 'start/'
  local deps_path, all_plugin_paths = H.get_package_path() .. '/pack/deps', {}
  vim.list_extend(all_plugin_paths, H.readdir(deps_path .. '/opt'))
  vim.list_extend(all_plugin_paths, H.readdir(deps_path .. '/start'))

  -- Filter only proper plugin directories which are not present in 'runtime'
  local is_absent_plugin = function(x) return vim.fn.isdirectory(x) == 1 and not is_in_rtp[x] end
  local absent_paths = vim.tbl_filter(is_absent_plugin, all_plugin_paths)
  local n_to_delete = #absent_paths

  for i, path in ipairs(absent_paths) do
    vim.fn.delete(path, 'rf')
    local msg = string.format('(%d/%d) Deleted plugin `%s` from disk.', i, n_to_delete, vim.fn.fnamemodify(path, ':t'))
    H.notify(msg)
  end

  H.notify('Done cleaning plugins.')
end

--- Update plugins
---
---@param opts table|nil Options. Possible fields:
---   - <confirm> `(boolean)` - whether to confirm before making an update.
---     Default: `true`.
---   - <names> `(table)` - array of plugin names to update.
---     Default: all plugins registered in current session with |MiniDeps.add()|.
---   - <remote> `(boolean)` - whether to check for updates at remote source.
---     Default: `true`.
MiniDeps.update = function(opts)
  opts = vim.tbl_deep_extend('force', { confirm = true, names = nil, remote = true }, opts or {})

  -- Compute array of plugin data to be reused in update. Each contains a CLI
  -- job "assigned" to plugin's path which stops execution after first error.
  local plugs = H.plugs_from_names(opts.names)
  if #plugs == 0 then return H.notify('Nothing to update.') end

  -- Prepare repositories
  H.plugs_ensure_origin(plugs)

  -- Preprocess before downloading
  H.plugs_ensure_target_refs(plugs)
  H.plugs_infer_head(plugs)
  H.plugs_infer_commit(plugs, 'track', 'track_from')

  -- Download data if asked
  if opts.remote then H.plugs_download_updates(plugs) end

  -- Process data for update
  H.plugs_infer_commit(plugs, 'checkout', 'checkout_to')
  H.plugs_infer_commit(plugs, 'track', 'track_to')
  H.plugs_infer_log(plugs, 'head', 'checkout_to', 'checkout_log')
  H.plugs_infer_log(plugs, 'track_from', 'track_to', 'track_log')

  -- Checkout if asked (before feedback to include possible checkout errors)
  if not opts.confirm then H.plugs_checkout(plugs, true) end

  -- Make feedback
  local lines = H.update_compute_feedback_lines(plugs)
  local feedback = opts.confirm and H.update_feedback_confirm or H.update_feedback_log
  feedback(lines)

  -- Show job errors
  H.plugs_show_job_errors(plugs, 'update')
end

--- Compute snapshot
---
---@return table A snapshot table: plugin names as keys and string state as values.
---   All plugins in current session are processed.
MiniDeps.snap_get = function()
  local plugs = H.plugs_from_names()
  H.plugs_infer_head(plugs)
  H.plugs_show_job_errors(plugs, 'computing snapshot')

  local snap = {}
  for _, p in ipairs(plugs) do
    if p.head ~= '' then snap[p.name] = p.head end
  end
  return snap
end

--- Apply snapshot
---
--- Notes:
--- - Checking out states from snapshot does not update session plugin spec
---   (`checkout` field in particular). In particular, it means that next call
---   to |MiniDeps.update()| might override the result of this function.
---   To make changes permanent, set `checkout` spec field to state from snapshot.
---
---@param snap table A snapshot table: plugin names as keys and string state as values.
---   Only plugins in current session are processed.
MiniDeps.snap_set = function(snap)
  if type(snap) ~= 'table' then H.error('Snapshot should be a table.') end

  -- Construct current session plugin data with `checkout` from snapshot
  for k, v in pairs(snap) do
    if not (type(k) == 'string' and type(v) == 'string') then snap[k] = nil end
  end
  local plugs = H.plugs_from_names(vim.tbl_keys(snap))
  for _, p in ipairs(plugs) do
    p.checkout = snap[p.name]
  end

  -- Checkout
  H.plugs_checkout(plugs, true)
  H.plugs_show_job_errors(plugs, 'applying snapshot')
end

--- Save snapshot
---
---@param path string|nil A valid path on disk where to write snapshot.
---   Default: `config.path.snapshot`.
MiniDeps.snap_save = function(path)
  path = path or H.full_path(H.get_config().path.snapshot)
  if type(path) ~= 'string' then H.error('`path` should be string.') end

  -- Compute snapshot
  local snap = MiniDeps.snap_get()

  -- Write snapshot
  local lines = vim.split(vim.inspect(snap), '\n')
  lines[1] = 'return ' .. lines[1]
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(lines, path)

  H.notify('Done creating snapshot at ' .. vim.inspect(path) .. '.')
end

--- Load snapshot file
---
--- Notes from |MiniDeps.snap_set()| also apply here.
---
---@param path string|nil A valid path on disk from where to read snapshot.
---   Default: `config.path.snapshot`.
MiniDeps.snap_load = function(path)
  path = path or H.full_path(H.get_config().path.snapshot)
  if vim.fn.filereadable(path) ~= 1 then H.error('`path` should be path to a readable file.') end

  local ok, snap = pcall(dofile, H.full_path(path))
  if not (ok and type(snap) == 'table') then H.error(vim.insepct(path) .. ' is not a path to proper snapshot.') end

  MiniDeps.snap_set(snap)
end

--- Get session data
MiniDeps.get_session = function()
  -- TODO: Use `nvim_list_runtime_paths()` directly.

  -- Normalize `H.session`. Prefere spec (entirely) which was added earlier.
  local session, present_names = {}, {}
  for _, spec in ipairs(H.session) do
    if not present_names[spec.name] then
      table.insert(session, spec)
      present_names[spec.name] = true
    end
  end
  H.session = session

  -- Return copy to not allow modification in place
  return vim.deepcopy(session)
end

MiniDeps.now = function(f)
  local ok, err = pcall(f)
  if not ok then table.insert(H.cache.exec_errors, err) end
  H.schedule_finish()
end

MiniDeps.later = function(f)
  table.insert(H.cache.later_callback_queue, f)
  H.schedule_finish()
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniDeps.config

-- Array of current session plugin specs. NOTE: Having it as array allows to
-- respect order in which plugins were added (at cost of later normalization).
H.session = {}

-- Various cache
H.cache = {
  -- Whether finish of `now()` or `later()` is already scheduled
  finish_is_scheduled = false,

  -- Callback queue for `later()`
  later_callback_queue = {},

  -- Errors during execution of `now()` or `later()`
  exec_errors = {},
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    job = { config.job, 'table' },
    path = { config.path, 'table' },
    silent = { config.silent, 'boolean' },
  })

  vim.validate({
    ['job.n_threads'] = { config.job.n_threads, 'number', true },
    ['job.timeout'] = { config.job.timeout, 'number' },
    ['path.package'] = { config.path.package, 'string' },
    ['path.snapshot'] = { config.path.snapshot, 'string' },
    ['path.log'] = { config.path.log, 'string' },
  })

  return config
end

H.apply_config = function(config)
  MiniDeps.config = config

  -- Remove current plugins to allow resourcing script with `setup()` call
  local session = MiniDeps.get_session()
  for _, spec in ipairs(session) do
    MiniDeps.remove(spec.name)
  end
  H.session = {}

  -- Add target package path to 'packpath'
  local pack_path = H.full_path(config.path.package)
  vim.cmd('set packpath+=' .. vim.fn.fnameescape(pack_path))
end

H.create_user_commands = function(config)
  -- TODO
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniDeps.config, vim.b.minideps_config or {}, config or {})
end

-- Git commands ---------------------------------------------------------------
H.git_cmd = {
  clone = function(source, path)
    --stylua: ignore
    return {
      'git', 'clone', '--quiet', '--filter=blob:none',
      '--recurse-submodules', '--also-filter-submodules', '--origin', 'origin',
      source, path,
    }
  end,
  stash = function(timestamp)
    return { 'git', 'stash', '--quiet', '--message', '(mini.deps) ' .. timestamp .. ' Stash before checkout.' }
  end,
  checkout = function(target) return { 'git', 'checkout', '--quiet', target } end,
  -- Using '--tags --force' means conflicting tags will be synced with remote
  fetch = { 'git', 'fetch', '--quiet', '--tags', '--force', '--recurse-submodules=yes', 'origin' },
  set_origin = function(source) return { 'git', 'remote', 'set-url', 'origin', source } end,
  get_default_origin_branch = { 'git', 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
  is_origin_branch = function(name)
    -- Returns branch's name if it is present
    return { 'git', 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/' .. name }
  end,
  get_hash = function(rev) return { 'git', 'rev-parse', rev } end,
  log = function(from, to)
    -- `--topo-order` makes showing divergent branches nicer
    -- `--decorate-refs` shows only tags near commits (not `origin/main`, etc.)
    --stylua: ignore
    return {
      'git', 'log',
      '--pretty=format:%m %h | %ai | %an%d%n  %s%n', '--topo-order', '--decorate-refs=refs/tags',
      from .. '...' .. to,
    }
  end,
}

-- Plugin specification -------------------------------------------------------
H.normalize_spec = function(source, opts)
  local spec = {}

  if type(source) ~= 'string' then H.error('Plugin source should be string.') end
  -- Allow 'user/repo' as source
  if source:find('^[^/]+/[^/]+$') ~= nil then source = 'https://github.com/' .. source end
  spec.source = source

  opts = opts or {}
  if type(opts) ~= 'table' then H.error([[Plugin's optional spec should be table.]]) end

  spec.name = opts.name or vim.fn.fnamemodify(source, ':t')
  if type(spec.name) ~= 'string' then H.error('`name` in plugin spec should be string.') end

  spec.checkout = opts.checkout
  if spec.checkout and type(spec.checkout) ~= 'string' then H.error('`checkout` in plugin spec should be string.') end

  spec.track = opts.track
  if spec.track and type(spec.track) ~= 'string' then H.error('`track` in plugin spec should be string.') end

  spec.hooks = opts.hooks or {}
  if type(spec.hooks) ~= 'table' then H.error('`hooks` in plugin spec should be table.') end
  local hook_names = { 'pre_create', 'post_create', 'pre_change', 'post_change', 'pre_delete', 'post_delete' }
  for _, hook_name in ipairs(hook_names) do
    if spec[hook_name] and not vim.is_callable(spec[hook_name]) then
      H.error('`hooks.' .. hook_name .. '` in plugin spec should be callable.')
    end
  end

  return spec
end

-- Plugin operations ----------------------------------------------------------
H.plugs_exec_hooks = function(plugs, name)
  for _, p in ipairs(plugs) do
    local has_error = p.job and #p.job.err > 0
    local should_execute = vim.is_callable(p.hooks[name]) and not has_error
    if should_execute then
      local ok, err = pcall(p.hooks[name])
      if not ok then
        local msg = string.format('Error executing %s hook in plugin `%s`:\n%s', name, p.name, err)
        H.notify(msg, 'WARN')
      end
    end
  end
end

H.plugs_create = function(plugs)
  -- Clone
  local prepare = function(p)
    p.job.command = H.git_cmd.clone(p.source, p.path)
    p.job.exit_msg = string.format('Done creating `%s`', p.name)
  end
  H.notify(string.format('(0/%d) Creating plugins', #plugs))
  H.plugs_run_jobs(plugs, prepare)

  -- Checkout
  H.plugs_checkout(plugs, false)

  -- Show errors
  H.plugs_show_job_errors(plugs, 'creating plugins')
end

H.plugs_download_updates = function(plugs)
  local prepare = function(p)
    p.job.command = H.git_cmd.fetch
    p.job.exit_msg = string.format('Done downloading updates for `%s`', p.name)
  end
  H.notify(string.format('(0/%d) Downloading updates', #plugs))
  H.plugs_run_jobs(plugs, prepare)
end

H.plugs_checkout = function(plugs, exec_hooks)
  H.plugs_infer_head(plugs)
  H.plugs_ensure_target_refs(plugs)
  H.plugs_infer_commit(plugs, 'checkout', 'checkout_to')

  -- Stash changes
  local stash_command = H.git_cmd.stash(H.get_timestamp())
  local prepare = function(p)
    p.needs_checkout = p.head ~= p.checkout_to
    p.job.command = p.needs_checkout and stash_command or {}
  end
  H.plugs_run_jobs(plugs, prepare)

  -- Execute pre hooks
  if exec_hooks then H.plugs_exec_hooks(plugs, 'pre_change') end

  -- Checkout
  prepare = function(p)
    -- Use dummy command in order to show "No checkout message"
    p.job.command = p.needs_checkout and H.git_cmd.checkout(p.checkout_to) or { 'git', 'log', '-1' }
    p.job.exit_msg = p.needs_checkout and string.format('Checked out `%s` in plugin `%s`', p.checkout, p.name)
      or string.format('No checkout needed for plugin `%s`', p.name)
  end
  H.plugs_run_jobs(plugs, prepare)

  -- Execute pre hooks
  if exec_hooks then H.plugs_exec_hooks(plugs, 'post_change') end

  -- (Re)Generate help tags
  for _, p in ipairs(plugs) do
    local doc_dir = p.path .. '/doc'
    local has_help_files = vim.fn.glob(doc_dir .. '/**') ~= ''
    if has_help_files then vim.cmd('helptags ' .. vim.fn.fnameescape(doc_dir)) end
  end
end

-- Plugin operation helpers ---------------------------------------------------
H.plugs_from_names = function(names)
  local session = MiniDeps.get_session()
  if names and not vim.tbl_islist(names) then H.error('`names` should be array.') end

  local res = {}
  for _, spec in ipairs(session) do
    if names == nil or vim.tbl_contains(names, spec.name) then
      spec.job = H.cli_new_job({}, spec.path)
      table.insert(res, spec)
    end
  end

  return res
end

H.plugs_run_jobs = function(plugs, prepare, process)
  if vim.is_callable(prepare) then vim.tbl_map(prepare, plugs) end

  H.cli_run(vim.tbl_map(function(p) return p.job end, plugs))

  if vim.is_callable(process) then vim.tbl_map(process, plugs) end

  -- Clean jobs. Preserve errors for jobs to be properly reusable.
  for _, p in ipairs(plugs) do
    p.job.command, p.job.exit_msg, p.job.out = {}, nil, {}
  end
end

H.plugs_show_job_errors = function(plugs, action_name)
  for _, p in ipairs(plugs) do
    local err = H.cli_stream_tostring(p.job.err)
    if err ~= '' then
      local msg = string.format('Error in plugin `%s` during %s\n%s', p.name, action_name, err)
      H.notify(msg, 'ERROR')
    end
  end
end

H.plugs_ensure_origin = function(plugs)
  local prepare = function(p) p.job.command = p.source and H.git_cmd.set_origin(p.source) or {} end
  H.plugs_run_jobs(plugs, prepare)
end

H.plugs_ensure_target_refs = function(plugs)
  local prepare = function(p)
    local needs_infer = p.checkout == nil or p.track == nil
    p.job.command = needs_infer and H.git_cmd.get_default_origin_branch or {}
  end
  local process = function(p)
    local def_branch = H.cli_stream_tostring(p.job.out):gsub('^origin/', '')
    p.checkout = p.checkout or def_branch
    p.track = p.track or def_branch
  end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_infer_head = function(plugs)
  local prepare = function(p) p.job.command = p.head == nil and H.git_cmd.get_hash('HEAD') or {} end
  local process = function(p) p.head = p.head or H.cli_stream_tostring(p.job.out) end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_infer_commit = function(plugs, field_ref, field_out)
  -- Determine if reference points to an origin branch (to avoid error later)
  local prepare = function(p)
    -- Don't recompute commit if it is already computed
    p.job.command = p[field_out] == nil and H.git_cmd.is_origin_branch(p[field_ref]) or {}
  end
  local process = function(p) p.is_ref_origin_branch = H.cli_stream_tostring(p.job.out):find('%S') ~= nil end
  H.plugs_run_jobs(plugs, prepare, process)

  -- Infer commit depending on whether it points to origin branch
  prepare = function(p)
    local ref = (p.is_ref_origin_branch and 'origin/' or '') .. p[field_ref]
    p.job.command = p[field_out] == nil and H.git_cmd.get_hash(ref) or {}
  end
  process = function(p)
    p[field_out] = p[field_out] or H.cli_stream_tostring(p.job.out)
    p.is_ref_origin_branch = nil
  end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_infer_log = function(plugs, field_from, field_to, field_out)
  local prepare = function(p) p.job.command = H.git_cmd.log(p[field_from], p[field_to]) end
  local process = function(p) p[field_out] = H.cli_stream_tostring(p.job.out) end
  H.plugs_run_jobs(plugs, prepare, process)
end

-- File system ----------------------------------------------------------------
H.get_plugin_path = function(name)
  local package_path = H.get_package_path()

  -- First check for the most common case of name present in 'pack/deps/opt'
  local opt_path = string.format('%s/pack/deps/opt/%s', package_path, name)
  if vim.loop.fs_stat(opt_path) ~= nil then return opt_path, true end

  -- Allow processing 'pack/deps/start'
  local start_path = string.format('%s/pack/deps/start/%s', package_path, name)
  if vim.loop.fs_stat(start_path) ~= nil then return start_path, true end

  -- Use 'opt' directory by default
  return opt_path, false
end

H.get_package_path = function() return H.full_path(H.get_config().path.package) end

-- Remove ---------------------------------------------------------------------
H.unload_lua_modules = function(path)
  -- Compute all modules to unload
  local lua_subdir = path .. '/lua/'
  local lua_files = vim.fn.glob(lua_subdir .. '**/*.lua', true, true)
  local modules, n_prefix = {}, lua_subdir:len()
  for _, p in ipairs(lua_files) do
    local m = p:sub(n_prefix + 1):gsub('/init%.lua$', ''):gsub('%.lua$', '')
    modules[m] = true
  end

  -- Get normalized loaded modules (as `require` allows '/' and '.' separators)
  for m, _ in pairs(package.loaded) do
    if modules[m:gsub('%.', '/')] then package.loaded[m] = nil end
  end
end

-- Update ---------------------------------------------------------------------
H.update_compute_feedback_lines = function(plugs)
  -- Construct lines with metadata for later sort
  local plug_data = {}
  for i, p in ipairs(plugs) do
    local lines = H.update_compute_report_single(p)
    plug_data[i] = { lines = lines, has_error = p.has_error, has_updates = p.has_updates, index = i }
  end

  -- Sort to put first ones with errors, then with updates, then rest
  local compare = function(a, b)
    if a.has_error and not b.has_error then return true end
    if not a.has_error and b.has_error then return false end
    if a.has_updates and not b.has_updates then return true end
    if not a.has_updates and b.has_updates then return false end
    return a.index < b.index
  end
  table.sort(plug_data, compare)

  local plug_lines = vim.tbl_map(function(x) return x.lines end, plug_data)
  return vim.split(table.concat(plug_lines, '\n\n'), '\n')
end

H.update_compute_report_single = function(p)
  p.has_error, p.has_updates = #p.job.err > 0, p.head ~= p.checkout_to

  local err = H.cli_stream_tostring(p.job.err)
  if err ~= '' then return string.format('!!! %s !!!\n\n%s', p.name, err) end

  -- Compute title surrounding based on whether plugin needs an update
  local surrounding = p.has_updates and '+++' or '---'
  local parts = {
    string.format('%s %s %s\n', surrounding, p.name, surrounding),
    string.format('Source:              %s\n', p.source),
    string.format('State before update: %s\n', p.head),
    string.format('State after  update: %s', p.checkout_to),
  }

  -- Show pending updates only if they are present
  if p.has_updates then
    table.insert(parts, string.format('\n\nPending updates for `%s`:\n', p.checkout))
    table.insert(parts, p.checkout_log)
  end

  -- Show tracking updates only if user asked for them
  if p.checkout ~= p.track then
    table.insert(parts, string.format('\n\nTracking updates for `%s`:\n', p.track))
    table.insert(parts, p.track_log ~= '' and p.track_log or '<Nothing>')
  end

  return table.concat(parts, '')
end

H.update_feedback_confirm = function(lines)
  -- Add helper header
  local report = {
    'This is a confirmation report before an update.',
    '',
    'Line `+++ <plugin_name> +++` means plugin will be updated.',
    'See update details below the line.',
    'Remove the line to not update that plugin.',
    '',
    "Line `!!! <plugin_name> !!!` means plugin had an error and won't be updated.",
    'See error details below the line.',
    '',
    'Line `--- <plugin_name> ---` means plugin has nothing to update.',
    '',
    'To finish update, save this buffer (for example, with `:write` command).',
    'To abort update, leave this buffer (stop showing it in current window).',
    '',
  }
  local n_header = #report - 1
  vim.list_extend(report, lines)

  -- Show report in new buffer in current window
  local buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf_id, 'mini.deps confirmation report')
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, report)
  vim.bo[buf_id].buftype, vim.bo[buf_id].filetype = 'acwrite', 'minideps-confirm'

  local win_id = vim.api.nvim_get_current_win()
  local init_win_buf_id = vim.api.nvim_win_get_buf(win_id)
  vim.api.nvim_win_set_buf(win_id, buf_id)
  vim.cmd('setlocal wrap')

  -- Define basic highlighting
  vim.cmd('syntax region DiagnosticHint start="^\\%1l" end="\\%' .. n_header .. 'l$"')
  vim.cmd([[
    syntax match DiffDelete     "^!!! .* !!!$"
    syntax match DiffAdd        "^+++ .* +++$"
    syntax match Title          "^--- .* ---$"
    syntax match DiagnosticInfo "^Source.\{-}\zs[^ ]\+$"
    syntax match DiagnosticInfo "^State.\{-}\zs[^ ]\+$"
    syntax match diffRemoved    "^< .*\n  .*$"
    syntax match diffAdded      "^> .*\n  .*$"
    syntax match Comment        "^<.*>$"
  ]])

  -- Create buffer autocommands
  local delete_buffer = vim.schedule_wrap(function() pcall(vim.api.nvim_buf_delete, buf_id, { force = true }) end)

  local finish_update = function()
    -- Compute plugin names to update
    local names = {}
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)) do
      local cur_name = string.match(l, '^%+%+%+ (.*) %+%+%+$')
      if cur_name ~= nil then table.insert(names, cur_name) end
    end

    -- Delete buffer
    pcall(vim.api.nvim_win_set_buf, win_id, init_win_buf_id)
    delete_buffer()

    -- Update
    MiniDeps.update({ confirm = false, names = names, remote = false })
  end

  -- - Use `nested` to allow other events (`WinEnter` for 'mini.statusline')
  vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf_id, nested = true, callback = finish_update })
  vim.api.nvim_create_autocmd('BufWinLeave', { buffer = buf_id, nested = true, callback = delete_buffer })
end

H.update_feedback_log = function(lines)
  local title = string.format('========== Update %s ==========', vim.fn.strftime('%Y-%m-%d %H:%M:%S'))
  table.insert(lines, 1, title)
  table.insert(lines, '')

  local log_path = H.get_config().path.log
  vim.fn.mkdir(vim.fn.fnamemodify(log_path, ':h'), 'p')
  vim.fn.writefile(lines, log_path, 'a')
end

-- CLI ------------------------------------------------------------------------
H.cli_run = function(jobs)
  local config_job = H.get_config().job
  local n_threads = config_job.n_threads or math.floor(0.8 * #vim.loop.cpu_info())
  local timeout = config_job.timeout or 60000

  local n_total, id_started, n_finished = #jobs, 0, 0
  if n_total == 0 then return end

  local run_next
  run_next = function()
    if n_total <= id_started then return end
    id_started = id_started + 1

    local job = jobs[id_started]
    local command, cwd, exit_msg = job.command or {}, job.cwd, job.exit_msg

    if vim.fn.isdirectory(cwd) == 0 and #job.err == 0 then job.err = { vim.inspect(cwd) .. ' is not a directory.' } end

    -- Allow reusing job structure. Do nothing if previously there were errors.
    if not (#job.err == 0 and #command > 0) then
      n_finished = n_finished + 1
      return run_next()
    end

    -- Prepare data for `vim.loop.spawn`
    local executable, args = command[1], vim.list_slice(command, 2, #command)
    local process, stdout, stderr = nil, vim.loop.new_pipe(), vim.loop.new_pipe()
    local spawn_opts = { args = args, cwd = cwd, stdio = { nil, stdout, stderr } }

    -- Register job finish and start a new one from the queue
    local on_exit = function(code)
      if code ~= 0 then table.insert(job.err, 1, 'PROCESS EXITED WITH ERROR CODE ' .. code .. '\n') end
      process:close()
      n_finished = n_finished + 1
      if type(exit_msg) == 'string' then H.notify(string.format('(%d/%d) %s.', n_finished, n_total, exit_msg)) end
      run_next()
    end

    process = vim.loop.spawn(executable, spawn_opts, on_exit)
    H.cli_read_stream(stdout, job.out)
    H.cli_read_stream(stderr, job.err)
  end

  for _ = 1, math.max(n_threads, 1) do
    run_next()
  end

  vim.wait(timeout * n_total, function() return n_total <= n_finished end, 1)
end

H.cli_read_stream = function(stream, feed)
  local callback = function(err, data)
    if err then return table.insert(feed, 1, 'ERROR: ' .. err) end
    if data ~= nil then return table.insert(feed, data) end
    stream:close()
  end
  stream:read_start(callback)
end

H.cli_stream_tostring = function(stream) return (table.concat(stream):gsub('\n+$', '')) end

H.cli_new_job = function(command, cwd, exit_msg)
  return { command = command, cwd = cwd, exit_msg = exit_msg, out = {}, err = {} }
end

-- Two-stage execution --------------------------------------------------------
H.schedule_finish = function()
  if H.cache.finish_is_scheduled then return end
  vim.schedule(H.finish)
  H.cache.finish_is_scheduled = true
end

H.finish = function()
  local timer, step_delay = vim.loop.new_timer(), 1
  local f = nil
  f = vim.schedule_wrap(function()
    local callback = H.cache.later_callback_queue[1]
    if callback == nil then
      H.cache.finish_is_scheduled, H.cache.later_callback_queue = false, {}
      H.report_errors()
      return
    end

    table.remove(H.cache.later_callback_queue, 1)
    MiniDeps.now(callback)
    timer:start(step_delay, 0, f)
  end)
  timer:start(step_delay, 0, f)
end

H.report_errors = function()
  if #H.cache.exec_errors == 0 then return end
  local msg_lines = {
    { '(mini.deps) ', 'WarningMsg' },
    { 'There were errors during two-stage execution:\n\n', 'MoreMsg' },
    { table.concat(H.cache.exec_errors, '\n\n'), 'ErrorMsg' },
  }
  H.cache.exec_errors = {}
  vim.api.nvim_echo(msg_lines, true, {})
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.deps) %s', msg), 0) end

H.notify = vim.schedule_wrap(function(msg, level)
  level = level or 'INFO'
  if H.get_config().silent and level ~= 'ERROR' and level ~= 'WARN' then return end
  if type(msg) == 'table' then msg = table.concat(msg, '\n') end
  vim.notify(string.format('(mini.deps) %s', msg), vim.log.levels[level])
  vim.cmd('redraw')
end)

H.get_timestamp = function() return vim.fn.strftime('%Y%m%d%H%M%S') end

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('\\', '/'):gsub('/+', '/'):gsub('(.)/$', '%1')) end

H.readdir = function(path)
  if vim.fn.isdirectory(path) ~= 1 then return {} end
  return vim.tbl_map(function(x) return path .. '/' .. x end, vim.fn.readdir(path))
end

return MiniDeps
