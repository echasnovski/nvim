-- TODO:
--
-- Code:
--
-- Docs:
-- - Actually document two-stage execution. First step - for UI necessary to
--   make initial screen draw, second step - everything else.
-- - Add examples of user commands in |MiniDeps-actions|.
-- - Add examples with `depends`.
-- - Clarify distinction in how to use `checkout` and `monitor`. They allow
--   both automated update from some branch and (more importantly) "freezing"
--   plugin at certain commit/tag while allowing to monitor updates waiting for
--   the right time to update `checkout`.
-- - In update reports note that `>`/`<` means commit will be added/reverted.
-- - To freeze plugin from updates use `checkout = 'HEAD'`.
--
-- Tests:
-- - Session:
--     - `get_session()` should return in order user added them. Plus 'start'
--       plugins which are actually in 'runtimepath' at the end.
--
-- - Update:
--     - Should set `origin` remote branch to be `source` even if `offline = true`.
--     - Hooks should be executed in order defined in current session.
--
-- - Snapshot set:
--     - Should **not** update `checkout` data in session.
--       To update that, remove from session and add with proper `checkout`.

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
---     - Add plugin to current session. See |MiniDeps.add()|.
---     - Update with/without confirm, with/without downloading new data.
---       See |MiniDeps.update()|.
---     - Delete unused plugins with/without confirm. See |MiniDeps.clean()|.
---     - Get / set / save / load snapshot. See `MiniDeps.snap_*()` functions.
---
---     All these actions are available both as Lua functions and user commands
---     (see |MiniDeps-commands|).
---
--- - Minimal yet flexible plugin specification:
---     - Plugin source.
---     - Name of target plugin directory.
---     - Checkout target: branch, commit, tag, etc.
---     - Monitor branch to track updates without checking out.
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
--- - Provide ways to completely remove or update plugin's functionality in
---   current session. Although this is partially doable, it can not be done
---   in full (yet) because plugins can have untraceable side effects
---   (autocmmands, mappings, etc.).
---
--- Sources with more details:
--- - |MiniDeps-overview|. !!!!!!!!! TODO !!!!!!!!!
--- - |MiniDeps-examples|.
--- - |MiniDeps-plugin-specification|.
--- - |MiniDeps-commands|.
---
--- # Dependencies ~
---
--- For most of its functionality this plugin relies on `git` CLI tool.
--- See https://git-scm.com/ for more information about how to install it.
--- Actual knowledge of Git is not required but helpful.
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
--- # Highlight groups ~
---
--- Highlight groups are used inside confirmation buffers
--- after |MiniDeps.update()| and |MiniDeps.clean()|.
---
--- * `MiniDepsChangeAdded`   - added change (commit) during update.
--- * `MiniDepsChangeRemoved` - removed change (commit) during update.
--- * `MiniDepsHint`          - various hints.
--- * `MiniDepsInfo`          - various information.
--- * `MiniDepsPlaceholder`   - placeholder when there is no valuable information.
--- * `MiniDepsTitle`         - various titles.
--- * `MiniDepsTitleError`    - title when plugin had errors during update.
--- * `MiniDepsTitleSame`     - title when plugin has no changes to update.
--- * `MiniDepsTitleUpdate`   - title when plugin has changes to update.
---
--- To change any highlight group, modify it directly with |:highlight|.

--- # Directory structure ~
---
--- Uses |packages| as data sctructure.
---
--- # Adding plugins ~
---
--- # Updating plugins ~
---
--- # Removing plugins ~
---
--- # Working with snapshots ~
---
---
---@tag MiniDeps-overview

-- TODO; ?Remove this in favor of linking to |packages| in overview?
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
---@tag MiniDeps-directory-structure

--- # Plugin specification ~
---
--- Each plugin dependency is managed based on its specification (a.k.a. "spec").
--- See |MiniDeps-examples| for how it is suggested to be used inside user config.
---
--- Specification can be a single string which is inferred as:
--- - Plugin <name> if it doesn't contain "/".
--- - Plugin <source> otherwise.
---
--- Specification is primarily a table with the following fields:
---
--- - <source> `(string|nil)` - field with URI of plugin source used during creation
---   update. Can be anything allowed by `git clone`.
---   Notes:
---     - As the most common case, URI of the format "user/repo" is transformed
---       into "https://github.com/user/repo".
---     - It is required for creating plugin, but can be omitted afterwards.
---   Default: `nil` to rely on source set up during install.
---
--- - <name> `(string|nil)` - directory basename of where to put plugin source.
---   It is put in "pack/deps/opt" subdirectory of `config.path.package`.
---   Default: basename of <source> if it is present, otherwise should be
---   provided explicitly.
---
--- - <checkout> `(string|nil)` - checkout target used to set state during update.
---   Can be anything supported by `git checkout` - branch, commit, tag, etc.
---   Default: `nil` for default branch (usually "main" or "master").
---
--- - <monitor> `(string|nil)` - monitor branch used to track new changes from
---   different target than `checkout`. Should be a name of present Git branch.
---   Default: `nil` for default branch (usually "main" or "master").
---
--- - <depends> `(table|nil)` - array of plugin specifications (strings or
---   tables) to be added prior to the target.
---   Default: `{}`.
---
--- - <hooks> `(table|nil)` - table with callable hooks to call on certain events.
---   Each hook is executed without arguments. Possible hook names:
---     - <pre_install>  - before creating plugin directory.
---     - <post_install> - after  creating plugin directory.
---     - <pre_change>   - before making update in plugin directory.
---     - <post_change>  - after  making update in plugin directory.
---   Default: empty table for no hooks.
---@tag MiniDeps-plugin-specification

--- # User commands ~
---                                                                       *:DepsAdd*
--- `:DepsAdd user/repo` makes plugin from https://github.com/user/repo available
--- in the current session (also creates it, if it is not present).
--- Accepts only single string |MiniDeps-plugin-specification|.
--- To add plugin in every session, put |MiniDeps.add()| in |init.lua|.
---
---                                                                    *:DepsUpdate*
--- `:DepsUpdate` synchronizes plugins with their session specifications and
--- updates them with new changes from sources. It shows confirmation buffer in
--- a separate |tabpage| with information about an upcoming update to review
--- and (selectively) apply. See |MiniDeps.update()| for more info.
---
--- `:DepsUpdate name` updates plugin with name `name`. Any number of names is allowed.
---
--- `:DepsUpdate!` and `:DepsUpdate! name` update without confirmation.
--- You can see what was done in the log file (|DepsShowLog|).
---
---                                                             *:DepsUpdateOffline*
--- `:DepsUpdateOffline` is same as |:DepsUpdate| but doesn't download new updates
--- from sources. Useful to only synchronize plugin specification in code and
--- on disk without unnecessary downloads.
---
---                                                                   *:DepsShowLog*
--- `:DepsShowLog` opens log file to review.
---
---                                                                     *:DepsClean*
--- `:DepsClean` deletes plugins from disk not added to current session. It shows
--- confirmation buffer in a separate |tabpage| with information about an upcoming
--- deletes to review and (selectively) apply. See |MiniDeps.clean()| for more info.
---
--- `:DepsClean!` deletes plugins without confirmation.
---
---                                                                  *:DepsSnapSave*
--- `:DepsSnapSave` creates snapshot file in default location (see |MiniDeps.config|).
--- `:DepsSnapSave path` creates snapshot file at `path`.
---
---                                                                  *:DepsSnapLoad*
---
--- `:DepsSnapLoad` loads snapshot file from default location (see |MiniDeps.config|).
--- `:DepsSnapLoad path` loads snapshot file at `path`.
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
---       {
---         source = 'nvim-treesitter/nvim-treesitter',
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
---@tag MiniDeps-examples

---@alias __deps_source string Plugin's source. See |MiniDeps-plugin-specification|.
---@alias __deps_spec_opts table|nil Optional spec fields. See |MiniDeps-plugin-specification|.

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

  -- Create default highlighting
  H.create_default_hl()

  -- Create user commands
  H.create_user_commands()
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

    -- Timeout (in ms) for each job before force quit
    timeout = 30000,
  },

  -- Paths describing where to store data
  path = {
    -- Directory for built-in package.
    -- All data is actually stored in the 'pack/deps' subdirectory.
    package = vim.fn.stdpath('data') .. '/site',

    -- Default file path for a snapshot
    snapshot = vim.fn.stdpath('config') .. '/mini-deps-snap',

    -- Update log
    log = vim.fn.stdpath(vim.fn.has('nvim-0.8') == 1 and 'state' or 'data') .. '/mini-deps.log',
  },

  -- Whether to disable showing non-error feedback
  silent = false,
}
--minidoc_afterlines_end

--- Add plugin to current session
---
--- - Process specification by expanding dependencies into single sepc array.
--- - Install (in parallel) absent (on disk) plugins:
---     - Execute `opts.hooks.pre_install`.
---     - Use `git clone` to clone plugin from its source URI into "pack/deps/opt".
---     - Checkout according to `opts.checkout`.
---     - Execute `opts.hooks.post_install`.
---   Note: If plugin directory is present, no action with it is done (to increase
---   performance during startup). In particular, it does not checkout according
---   to `opts.checkout`. Use |MiniDeps.update()| or |:DepsUpdateOffline| explicitly.
--- - Register spec(s) in current session.
---   Note: Adding plugin several times updates its session specs.
--- - Make sure plugin(s) can be used in current session (see |:packadd|).
---
---@param spec table|string Plugin specification. See |MiniDeps-plugin-specification|.
---@param opts table|nil Options. Not used at the moment.
MiniDeps.add = function(spec, opts)
  opts = opts or {}
  if type(opts) ~= 'table' then H.error('`opts` should be table.') end
  if opts.source or opts.name or opts.checkout then H.error('`add()` accepts only single spec.') end

  -- Normalize
  local plugs = {}
  H.expand_spec(plugs, spec)

  -- Process
  local plugs_to_install = {}
  for i, p in ipairs(plugs) do
    local path, is_present = H.get_plugin_path(p.name)
    p.path = path
    if not is_present then table.insert(plugs_to_install, vim.deepcopy(p)) end
  end

  -- Install
  if #plugs_to_install > 0 then
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
    -- Register in 'mini.deps' session
    table.insert(H.session, p)

    -- Add to 'runtimepath'
    vim.cmd('packadd ' .. p.name)
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
MiniDeps.update = function(names, opts)
  opts = vim.tbl_deep_extend('force', { force = false, offline = false }, opts or {})

  -- Compute array of plugin data to be reused in update. Each contains a CLI
  -- job "assigned" to plugin's path which stops execution after first error.
  local plugs = H.plugs_from_names(names)
  if #plugs == 0 then return H.notify('Nothing to update.') end

  -- Prepare repositories and specifications
  H.plugs_ensure_origin_source(plugs)

  -- Preprocess before downloading
  H.plugs_ensure_target_refs(plugs)
  H.plugs_infer_head(plugs)
  H.plugs_infer_commit(plugs, 'monitor', 'monitor_from')

  -- Download data if asked
  if not opts.offline then H.plugs_download_updates(plugs) end

  -- Process data for update
  H.plugs_infer_commit(plugs, 'checkout', 'checkout_to')
  H.plugs_infer_commit(plugs, 'monitor', 'monitor_to')
  H.plugs_infer_log(plugs, 'head', 'checkout_to', 'checkout_log')
  H.plugs_infer_log(plugs, 'monitor_from', 'monitor_to', 'monitor_log')

  -- Checkout if asked (before feedback to include possible checkout errors)
  if opts.force then H.plugs_checkout(plugs, true) end

  -- Make feedback
  local lines = H.update_compute_feedback_lines(plugs)
  local feedback = opts.force and H.update_feedback_log or H.update_feedback_confirm
  feedback(lines)

  -- Show job errors
  H.plugs_show_job_errors(plugs, 'update')
end

--- Clean plugins
---
--- - Compute absent plugins: not registered in current session
---   (see |MiniDeps.get_session()|) but present on disk in dedicated "deps" package
---   (inside `config.path.package`).
--- - If cleaning is forced, delete all absent plugins from disk.
---   Otherwise show confirmation buffer with instructions on how to proceed.
---
---@param opts table|nil Options. Possible fields:
---   - <force> `(boolean)` - whether to force delete without confirmation.
---     Default: `false`.
MiniDeps.clean = function(opts)
  opts = vim.tbl_deep_extend('force', { force = false }, opts or {})

  -- Compute path candidates to delete
  local is_in_session = {}
  for _, s in ipairs(MiniDeps.get_session()) do
    is_in_session[s.path] = true
  end

  local is_absent_plugin = function(x) return vim.fn.isdirectory(x) == 1 and not is_in_session[x] end
  local absent_paths = vim.tbl_filter(is_absent_plugin, H.get_all_plugin_paths())

  -- Clean
  if #absent_paths == 0 then return H.notify('Nothing to clean.') end
  local clean_fun = opts.force and H.clean_delete or H.clean_confirm
  clean_fun(absent_paths)
end

--- Compute snapshot
---
---@return table A snapshot table: plugin names as keys and state as values.
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
---   (`checkout` field in particular). Among others, it means that next call
---   to |MiniDeps.update()| might override the result of this function.
---   To make changes permanent, set `checkout` spec field to state from snapshot.
---
---@param snap table A snapshot table: plugin names as keys and state as values.
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
---@param path string|nil A valid path on disk where to write snapshot computed
---   with |MiniDeps.snap_get()|.
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

  H.notify('Created snapshot at ' .. vim.inspect(path) .. '.')
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

--- Get session
---
--- Plugin is registered in current session if it either:
--- - Was added with |MiniDeps.add()|.
--- - Is a "start" plugin and present in 'runtimpath'.
---
---@return session table Array with specifications of all plugins registered in
---   current session.
MiniDeps.get_session = function()
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

  -- Add 'start/' plugins that are in 'rtp'
  local start_path = H.get_package_path() .. '/pack/deps/start'
  local pattern = string.format('^%s/([^/]+)$', vim.pesc(start_path))
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    local name = string.match(path, pattern)
    if name ~= nil then add_spec({ path = path, name = name, hooks = {}, depends = {} }) end
  end

  -- Return copy to not allow modification in place
  return vim.deepcopy(res)
end

--- Execute function now
---
--- Safely execute function immediately. Errors are shown with |vim.notify()|
--- later, after all queued functions (including with |MiniDeps.later()|)
--- are executed, thus not blocking execution of next code in file.
---
--- Assumed to be used as a first step during two-stage config execution to
--- load plugins immediately during startup.
---
---@param f function Callable to execute.
MiniDeps.now = function(f)
  local ok, err = pcall(f)
  if not ok then table.insert(H.cache.exec_errors, err) end
  H.schedule_finish()
end

--- Execute function later
---
--- Queue function to be safely executed later without blocking execution of
--- next code in file. All queued functions are guaranteed to be executed in
--- order they were added.
--- Errors are shown with |vim.notify()| after all queued functions are executed.
---
--- Assumed to be used as a second step during two-stage config execution to
--- load plugins "lazily" after startup.
---
---@param f function Callable to execute.
MiniDeps.later = function(f)
  table.insert(H.cache.later_callback_queue, f)
  H.schedule_finish()
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniDeps.config

-- Array of plugin specs
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

  -- Reset current session to allow resourcing script with `setup()` call
  H.session = {}

  -- Add target package path to 'packpath'
  local pack_path = H.full_path(config.path.package)
  vim.cmd('set packpath^=' .. vim.fn.fnameescape(pack_path))
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniDeps.config, vim.b.minideps_config or {}, config or {})
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniDepsChangeAdded',   { link = 'diffAdded' })
  hi('MiniDepsChangeRemoved', { link = 'diffRemoved' })
  hi('MiniDepsHint',          { link = 'DiagnosticHint' })
  hi('MiniDepsInfo',          { link = 'DiagnosticInfo' })
  hi('MiniDepsPlaceholder',   { link = 'Comment' })
  hi('MiniDepsTitle',         { link = 'Title' })
  hi('MiniDepsTitleError',    { link = 'DiffDelete' })
  hi('MiniDepsTitleSame',     { link = 'DiffText' })
  hi('MiniDepsTitleUpdate',   { link = 'DiffAdd' })
end

H.create_user_commands = function()
  -- Do not create commands immediately to increase startup time
  local new_cmd = vim.schedule_wrap(vim.api.nvim_create_user_command)

  local complete_session_names = function(arg, _, _)
    local session_names = vim.tbl_map(function(s) return s.name end, MiniDeps.get_session())
    return vim.tbl_filter(function(n) return vim.startswith(n, arg) end, session_names)
  end
  local complete_disk_names = function(arg, _, _)
    local disk_names = vim.tbl_map(function(p) return vim.fn.fnamemodify(p, ':t') end, H.get_all_plugin_paths())
    return vim.tbl_filter(function(n) return vim.startswith(n, arg) end, disk_names)
  end

  local add = function(input) MiniDeps.add(input.fargs[1]) end
  new_cmd('DepsAdd', add, { nargs = '?', complete = complete_disk_names, desc = 'Add plugin to session' })

  local make_update_cmd = function(name, offline, desc)
    local callback = function(input)
      local names
      if #input.fargs > 0 then names = input.fargs end
      MiniDeps.update(names, { force = input.bang, offline = offline })
    end
    local opts = { bang = true, complete = complete_session_names, nargs = '*', desc = desc }
    new_cmd(name, callback, opts)
  end
  make_update_cmd('DepsUpdate', false, 'Update plugins')
  make_update_cmd('DepsUpdateOffline', true, 'Update plugins without downloading from source')

  local show_log = function()
    vim.cmd('edit ' .. vim.fn.fnameescape(H.get_config().path.log))
    H.update_add_syntax()
    vim.cmd([[syntax match MiniDepsTitle "^\(==========\).*\1$"]])
  end
  new_cmd('DepsShowLog', show_log, { desc = 'Show log' })

  local clean = function(input) MiniDeps.clean({ force = input.bang }) end
  new_cmd('DepsClean', clean, { bang = true, desc = 'Delete unused plugins' })

  local snap_save = function(input) MiniDeps.snap_save(input.fargs[1]) end
  new_cmd('DepsSnapSave', snap_save, { nargs = '?', complete = 'file', desc = 'Save plugin snapshot' })

  local snap_load = function(input) MiniDeps.snap_load(input.fargs[1]) end
  new_cmd('DepsSnapLoad', snap_load, { nargs = '?', complete = 'file', desc = 'Load plugin snapshot' })
end

-- Git commands ---------------------------------------------------------------
H.git_cmd = {
  clone = function(source, path)
    --stylua: ignore
    return {
      'git', '-c', 'gc.auto=0', 'clone',
      '--quiet', '--filter=blob:none',
      '--recurse-submodules', '--also-filter-submodules', '--origin', 'origin',
      source, path,
    }
  end,
  stash = function(timestamp)
    return { 'git', 'stash', '--quiet', '--message', '(mini.deps) ' .. timestamp .. ' Stash before checkout.' }
  end,
  checkout = function(target) return { 'git', 'checkout', '--quiet', target } end,
  -- Using '--tags --force' means conflicting tags will be synced with remote
  -- Using '-c gc.auto=0' disables `stderr` "packing" messages
  fetch = { 'git', '-c', 'gc.auto=0', 'fetch', '--quiet', '--tags', '--force', '--recurse-submodules=yes', 'origin' },
  set_origin = function(source) return { 'git', 'remote', 'set-url', 'origin', source } end,
  get_origin = { 'git', 'remote', 'get-url', 'origin' },
  get_default_origin_branch = { 'git', 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
  is_origin_branch = function(name)
    -- Returns branch's name if it is present
    return { 'git', 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/' .. name }
  end,
  -- Using `rev-list -1` shows a commit of revision, while `rev-parse` shows
  -- hash of revision. Those are different for annotated tags.
  get_hash = function(rev) return { 'git', 'rev-list', '-1', rev } end,
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
H.expand_spec = function(target, spec)
  -- Prepare
  if type(spec) == 'string' then
    local field = string.find(spec, '/') ~= nil and 'source' or 'name'
    spec = { [field] = spec }
  end
  if type(spec) ~= 'table' then H.error('Plugin spec should be table.') end

  local has_min_fields = type(spec.source) == 'string' or type(spec.name) == 'string'
  if not has_min_fields then H.error('Plugin spec should have either `source` or `name`.') end

  -- Normalize
  spec = vim.deepcopy(spec)

  if spec.source and type(spec.source) ~= 'string' then H.error('`source` in plugin spec should be string.') end
  local is_user_repo = type(spec.source) == 'string' and spec.source:find('^[^/]+/[^/]+$') ~= nil
  if is_user_repo then spec.source = 'https://github.com/' .. spec.source end

  spec.name = spec.name or vim.fn.fnamemodify(spec.source, ':t')
  if type(spec.name) ~= 'string' then H.error('`name` in plugin spec should be string.') end

  if spec.checkout and type(spec.checkout) ~= 'string' then H.error('`checkout` in plugin spec should be string.') end
  if spec.monitor and type(spec.monitor) ~= 'string' then H.error('`monitor` in plugin spec should be string.') end

  spec.hooks = vim.deepcopy(spec.hooks) or {}
  if type(spec.hooks) ~= 'table' then H.error('`hooks` in plugin spec should be table.') end
  local hook_names = { 'pre_install', 'post_install', 'pre_change', 'post_change' }
  for _, hook_name in ipairs(hook_names) do
    local is_not_hook = spec[hook_name] and not vim.is_callable(spec[hook_name])
    if is_not_hook then H.error('`hooks.' .. hook_name .. '` in plugin spec should be callable.') end
  end

  -- Expand dependencies recursively
  spec.depends = vim.deepcopy(spec.depends) or {}
  if not vim.tbl_islist(spec.depends) then H.error('`depends` in plugin spec should be array.') end
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
      local ok, err = pcall(p.hooks[name])
      if not ok then
        local msg = string.format('Error executing %s hook in `%s`:\n%s', name, p.name, err)
        H.notify(msg, 'WARN')
      end
    end
  end
end

H.plugs_install = function(plugs)
  -- Clone
  local prepare = function(p)
    if p.source == nil and #p.job.err == 0 then p.job.err = { 'SPECIFICATION HAS NO `source` TO INSTALL PLUGIN.' } end
    p.job.command = H.git_cmd.clone(p.source or '', p.path)
    p.job.exit_msg = string.format('Installed `%s`', p.name)
  end
  H.plugs_run_jobs(plugs, prepare)

  -- Checkout
  vim.tbl_map(function(p) p.job.cwd = p.path end, plugs)
  H.plugs_checkout(plugs, false)

  -- Show errors
  H.plugs_show_job_errors(plugs, 'installing plugins')
end

H.plugs_download_updates = function(plugs)
  local prepare = function(p)
    p.job.command = H.git_cmd.fetch
    p.job.exit_msg = string.format('Downloaded updates for `%s`', p.name)
  end
  H.notify('Downloading ' .. #plugs .. ' updates')
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
    p.job.command = {}
    if p.needs_checkout then
      p.job.command = H.git_cmd.checkout(p.checkout_to)
      p.job.exit_msg = string.format('Checked out `%s` in `%s`', p.checkout, p.name)
    end
  end
  H.plugs_run_jobs(plugs, prepare)

  -- Execute pre hooks
  if exec_hooks then H.plugs_exec_hooks(plugs, 'post_change') end

  -- (Re)Generate help tags according to the current help files
  for _, p in ipairs(plugs) do
    local doc_dir = p.path .. '/doc'
    vim.fn.delete(doc_dir .. '/tags')
    local has_help_files = vim.fn.glob(doc_dir .. '/**') ~= ''
    if has_help_files then vim.cmd('helptags ' .. vim.fn.fnameescape(doc_dir)) end
    if not has_help_files then vim.fn.delete(doc_dir, 'rf') end
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
      local msg = string.format('Error in `%s` during %s\n%s', p.name, action_name, err)
      H.notify(msg, 'ERROR')
    end
  end
end

H.plugs_ensure_origin_source = function(plugs)
  local prepare = function(p) p.job.command = p.source and H.git_cmd.set_origin(p.source) or H.git_cmd.get_origin end
  local process = function(p) p.source = p.source or H.cli_stream_tostring(p.job.out) end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_ensure_target_refs = function(plugs)
  local prepare = function(p)
    local needs_infer = p.checkout == nil or p.monitor == nil
    p.job.command = needs_infer and H.git_cmd.get_default_origin_branch or {}
  end
  local process = function(p)
    local def_branch = H.cli_stream_tostring(p.job.out):gsub('^origin/', '')
    p.checkout = p.checkout or def_branch
    p.monitor = p.monitor or def_branch
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
    -- Force `checkout = 'HEAD'` to always point to current commit to freeze
    -- updates. This is needed because `origin/HEAD` is also present.
    local is_from_origin = p.is_ref_origin_branch and p[field_ref] ~= 'HEAD'
    local ref = (is_from_origin and 'origin/' or '') .. p[field_ref]
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

H.get_all_plugin_paths = function()
  local deps_path, res = H.get_package_path() .. '/pack/deps', {}
  vim.list_extend(res, H.readdir(deps_path .. '/opt'))
  vim.list_extend(res, H.readdir(deps_path .. '/start'))
  return res
end

H.get_package_path = function() return H.full_path(H.get_config().path.package) end

-- Clean ----------------------------------------------------------------------
H.clean_confirm = function(paths)
  -- Compute lines
  local lines = {
    'This is a confirmation report before a clean.',
    '',
    'Lines `- <plugin>` show plugins to be deleted from disk.',
    'Remove line to not delete that plugin.',
    '',
    'To finish clean, save this buffer (for example, with `:write` command).',
    'To cancel clean, wipe this buffer (for example, with `:quit` command).',
    '',
  }
  local n_header = #lines - 1
  for _, p in ipairs(paths) do
    table.insert(lines, string.format('- %s (%s)', vim.fn.fnamemodify(p, ':t'), p))
  end

  -- Show report in new buffer in separate tabpage
  local finish_clean = function(buf_id)
    -- Compute plugin paths to update
    local paths_to_delete = {}
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)) do
      local cur_path = string.match(l, '^%- .* %((.*)%)$')
      if cur_path ~= nil then table.insert(paths_to_delete, cur_path) end
    end

    if #paths_to_delete == 0 then return H.notify('Nothing to delete.') end
    H.clean_delete(paths_to_delete)
  end
  H.show_confirm_buf(lines, 'mini.deps confirm clean', finish_clean)

  -- Define basic highlighting
  vim.cmd('syntax region MiniDepsHint start="^\\%1l" end="\\%' .. n_header .. 'l$"')

  -- Define conceal to show only name with whole path when cursor is on it
  vim.cmd('syntax conceal on')
  vim.cmd([[syntax match MiniDepsInfo "\s\+(.\{-})$"]])
  vim.cmd('syntax conceal off')
  vim.cmd('setlocal conceallevel=3')
end

H.clean_delete = function(paths)
  local n_to_delete = #paths
  for i, p in ipairs(paths) do
    vim.fn.delete(p, 'rf')
    local msg = string.format('(%d/%d) Deleted `%s` from disk.', i, n_to_delete, vim.fn.fnamemodify(p, ':t'))
    H.notify(msg)
  end
end

-- Update ---------------------------------------------------------------------
H.update_compute_feedback_lines = function(plugs)
  -- Construct lines with metadata for later sort
  local plug_data = {}
  for i, p in ipairs(plugs) do
    local lines = H.update_compute_report_single(p)
    --stylua: ignore
    plug_data[i] = { lines = lines, has_error = p.has_error, has_updates = p.has_updates, has_monitor = p.has_monitor, index = i }
  end

  -- Sort to put first ones with errors, then with updates, then rest
  local compare = function(a, b)
    if a.has_error and not b.has_error then return true end
    if not a.has_error and b.has_error then return false end
    if a.has_updates and not b.has_updates then return true end
    if not a.has_updates and b.has_updates then return false end
    if a.has_monitor and not b.has_monitor then return true end
    if not a.has_monitor and b.has_monitor then return false end
    return a.index < b.index
  end
  table.sort(plug_data, compare)

  local plug_lines = vim.tbl_map(function(x) return x.lines end, plug_data)
  return vim.split(table.concat(plug_lines, '\n\n'), '\n')
end

H.update_compute_report_single = function(p)
  p.has_error, p.has_updates, p.has_monitor = #p.job.err > 0, p.head ~= p.checkout_to, p.checkout ~= p.monitor

  local err = H.cli_stream_tostring(p.job.err)
  if err ~= '' then return string.format('!!! %s !!!\n\n%s', p.name, err) end

  -- Compute title surrounding based on whether plugin needs an update
  local surrounding = p.has_updates and '+++' or '---'
  local parts = { string.format('%s %s %s\n', surrounding, p.name, surrounding) }

  if p.head == p.checkout_to then
    table.insert(parts, 'Source: ' .. (p.source or '<None>') .. '\n')
    table.insert(parts, string.format('State:  %s (%s)', p.checkout_to, p.checkout))
  else
    table.insert(parts, 'Source:       ' .. (p.source or '<None>') .. '\n')
    table.insert(parts, 'State before: ' .. p.head .. '\n')
    table.insert(parts, string.format('State after:  %s (%s)', p.checkout_to, p.checkout))
  end

  -- Show pending updates only if they are present
  if p.has_updates then
    table.insert(parts, string.format('\n\nPending updates from `%s`:\n', p.checkout))
    table.insert(parts, p.checkout_log)
  end

  -- Show monitor updates only if user asked for them
  if p.has_monitor then
    table.insert(parts, string.format('\n\nMonitor updates from `%s`:\n', p.monitor))
    table.insert(parts, p.monitor_log ~= '' and p.monitor_log or '<Nothing>')
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
    'Remove the line to not update that plugin.',
    '',
    "Line `!!! <plugin_name> !!!` means plugin had an error and won't be updated.",
    'See error details below it.',
    '',
    'Line `--- <plugin_name> ---` means plugin has nothing to update.',
    '',
    'To finish update, save this buffer (for example, with `:write` command).',
    'To cancel update, wipe this buffer (for example, with `:quit` command).',
    '',
  }
  local n_header = #report - 1
  vim.list_extend(report, lines)

  -- Show report in new buffer in separate tabpage
  local finish_update = function(buf_id)
    -- Compute plugin names to update
    local names = {}
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)) do
      local cur_name = string.match(l, '^%+%+%+ (.*) %+%+%+$')
      if cur_name ~= nil then table.insert(names, cur_name) end
    end

    -- Update and delete buffer (in that order, to show that update is done)
    MiniDeps.update(names, { force = true, offline = true })
  end

  H.show_confirm_buf(report, 'mini.deps confirm update', finish_update)

  -- Define basic highlighting
  vim.cmd('syntax region MiniDepsHint start="^\\%1l" end="\\%' .. n_header .. 'l$"')
  H.update_add_syntax()
end

H.update_add_syntax = function()
  vim.cmd([[
    syntax match MiniDepsTitleError    "^!!! .\+ !!!$"
    syntax match MiniDepsTitleUpdate   "^+++ .\+ +++$"
    syntax match MiniDepsTitleSame     "^--- .\+ ---$"
    syntax match MiniDepsInfo          "^Source: \+\zs[^ ]\+"
    syntax match MiniDepsInfo          "^State[^:]*: \+\zs[^ ]\+\ze"
    syntax match MiniDepsHint          "\(^State.\+\)\@<=(.\+)$"
    syntax match MiniDepsChangeAdded   "^> .*$"
    syntax match MiniDepsChangeRemoved "^< .*$"
    syntax match MiniDepsPlaceholder   "^<.*>$"
  ]])
end

H.update_feedback_log = function(lines)
  local title = string.format('========== Update %s ==========', vim.fn.strftime('%Y-%m-%d %H:%M:%S'))
  table.insert(lines, 1, title)
  table.insert(lines, '')

  local log_path = H.get_config().path.log
  vim.fn.mkdir(vim.fn.fnamemodify(log_path, ':h'), 'p')
  vim.fn.writefile(lines, log_path, 'a')
end

-- Confirm --------------------------------------------------------------------
H.show_confirm_buf = function(lines, name, exec_on_write)
  -- Show buffer
  local buf_id = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf_id, name)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.bo[buf_id].buftype, vim.bo[buf_id].filetype, vim.bo[buf_id].modified = 'acwrite', 'minideps-confirm', false
  vim.cmd('tab sbuffer ' .. buf_id)
  local tabpage_id = vim.api.nvim_get_current_tabpage()

  -- Define buffer autocommands for leave and write
  local delete_buffer = vim.schedule_wrap(function()
    pcall(function() vim.cmd('tabclose ' .. vim.api.nvim_tabpage_get_number(tabpage_id)) end)
    pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
  end)

  local finish = function()
    exec_on_write(buf_id)
    delete_buffer()
  end

  -- - Use `nested` to allow other events (`WinEnter` for 'mini.statusline')
  vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf_id, nested = true, callback = finish })
  vim.api.nvim_create_autocmd('BufWinLeave', { buffer = buf_id, nested = true, callback = delete_buffer })
end

-- CLI ------------------------------------------------------------------------
H.cli_run = function(jobs)
  local config_job = H.get_config().job
  local n_threads = config_job.n_threads or math.floor(0.8 * #vim.loop.cpu_info())
  local timeout = config_job.timeout or 30000

  local n_total, id_started, n_finished = #jobs, 0, 0
  if n_total == 0 then return end
  local is_finished = function() return n_total <= n_finished end

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
      if not process:is_closing() then process:close() end
      n_finished = n_finished + 1
      if type(exit_msg) == 'string' then H.notify(string.format('(%d/%d) %s', n_finished, n_total, exit_msg)) end
      run_next()
    end

    process = vim.loop.spawn(executable, spawn_opts, on_exit)
    H.cli_read_stream(stdout, job.out)
    H.cli_read_stream(stderr, job.err)
    vim.defer_fn(function()
      if is_finished() then return end
      pcall(vim.loop.process_kill, process, 15)
      if #job.err == 0 then job.err = { 'PROCESS REACHED TIMEOUT.' } end
    end, timeout)
  end

  for _ = 1, math.max(n_threads, 1) do
    run_next()
  end

  vim.wait(timeout * n_total, is_finished, 1)
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
  local error_lines = table.concat(H.cache.exec_errors, '\n\n')
  H.cache.exec_errors = {}
  H.notify('There were errors during two-stage execution:\n\n' .. error_lines, 'ERROR')
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
