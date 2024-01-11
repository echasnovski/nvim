-- TODO:
--
-- Code:
--
-- - Implement one-stop `update()`.
--
-- - Check if `git rev-parse <tag>` works if tag was only fetched from remote.
--
-- - Add `track` to spec as source branch to get updates from.
--   Keep treating `checkout` as the checkout target. This distinction
--   allows to both automated update from some branch or (more importantly)
--   "freezing" plugin at certain commit/tag while allowing to track updates
--   waiting for the right time to update `checkout`.
--   Both are `nil` by default meaning assuming default branch.
--
-- - Make sure that `update_checkout()` stashes changes.
--
-- - Consider moving `now()` and `later()` to 'mini.misc'.
--
-- - Think about relevance and effect of `rollback()`.
--
-- - Implement `depends` spec.
--
-- - Generate help tags after create and change. Basically, in `do_checkout()`.
--
-- Docs:
-- - Add examples of user commands in |MiniDeps-actions|.
--
-- Tests:
-- - Fetch:
--     - Update `origin` remote to be `source`.
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
---     - Add / remove / clean.
---     - Update / rollback.
---     - Fetch / preview / checkout.
---     - Save snapshot / load snapshot.
---     All these actions are available both as Lua functions and user commands
---     (see |MiniDeps.setup()).
---
--- - Minimal yet flexible plugin specification:
---     - Mandatory plugin source.
---     - Name of target plugin directory.
---     - Checkout target: branch, commit, tag, etc.
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
---     - <pre_change>  - before making change in plugin directory.
---     - <post_change> - after  making change in plugin directory.
---     - <pre_delete>  - before deleting plugin directory.
---     - <post_delete> - after  deleting plugin directory.
---   Default: empty table for no hooks.
---@tag MiniDeps-plugin-specification

--- # User commands ~
---                                                                       *:DepsAdd*
---                                                                    *:DepsRemove*
---                                                                     *:DepsClean*
---                                                                    *:DepsUpdate*
---                                                                  *:DepsRollback*
---                                                                     *:DepsFetch*
---                                                                   *:DepsPreview*
---                                                                  *:DepsCheckout*
---                                                                  *:DepsSnapsave*
---                                                                  *:DepsSnapload*
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
    snapshot = vim.fn.stdpath('config') .. '/deps-snapshot',

    -- Update log
    log = vim.fn.stdpath('state') .. '/deps-update-log',
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
    H.maybe_exec(spec.hooks.pre_create)
    H.do_create(spec)
    H.maybe_exec(spec.hooks.post_create)
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
--- - If `delete_dir`, delete plugin directory:
---     - Execute `pre_delete` hook (if plugin with input name is registered).
---     - Delete plugin directory.
---     - Execute `post_delete` hook (if plugin with input name is registered).
---
--- Note: if plugin directory can not be found, nothing is done.
---
---@param name string Plugin directory name in |MiniDeps-directory-structure|.
---@param delete_dir boolean|nil Whether to delete plugin directory. Default: `false`.
MiniDeps.remove = function(name, delete_dir)
  if type(name) ~= 'string' then H.error('`name` should be string.') end
  if delete_dir == nil then delete_dir = false end

  local path, is_present = H.get_plugin_path(name)
  if not is_present then return end

  -- Find current session data for plugin
  local session, session_id = MiniDeps.get_session(), nil
  for i, spec in ipairs(session) do
    if spec.name == name then session_id = i end
  end

  -- Remove plugin
  vim.cmd('set rtp-=' .. vim.fn.fnameescape(path))
  if session_id ~= nil then table.remove(H.session, session_id) end

  -- Possibly delete directory
  if not delete_dir then return end

  local spec = session[session_id] or { hooks = {} }
  H.maybe_exec(spec.hooks.pre_delete)
  vim.fn.delete(path, 'rf')
  H.maybe_exec(spec.hooks.post_delete)
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
  local deps_path, all_plugin_paths = H.get_package_path() .. '/pack/deps/', {}
  vim.list_extend(all_plugin_paths, H.readdir(deps_path .. 'opt'))
  vim.list_extend(all_plugin_paths, H.readdir(deps_path .. 'start'))

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

  -- Compute target specs and reusable jobs (are not run if there was an error)
  local specs = H.convert_names_to_specs(opts.names)
  if #specs == 0 then return H.notify('Nothing to update.') end
  local jobs = vim.tbl_map(function(s) return H.cli_new_job({}, s.path) end, specs)

  -- Prepare repositories
  H.update_prepare(jobs, specs)

  -- Preprocess before downloading (updates `specs` in place)
  H.update_preprocess(jobs, specs)

  -- Download data if asked
  if opts.remote then H.update_download(jobs, specs) end

  -- Process data for update
  H.update_process(jobs, specs)

  -- Checkout if asked
  if not opts.confirm then H.update_checkout(jobs, specs) end

  -- Show job errors
  for i, job in ipairs(jobs) do
    H.cli_job_show_err(job, 'updating plugin `' .. specs[i].name .. '`')
  end

  -- Compute report lines
  local lines = H.update_compute_report(specs, opts.confirm)

  add_to_log('post update', { jobs = jobs, lines = lines, specs = specs })

  -- Show report
  H.update_show_report(specs, opts)

  -- Proceed based on whether this should need confirmation or not
  if opts.confirm then
    -- Show report lines in new buffer in current window
    local buf_id = vim.api.nvim_create_buf(false, true)
    vim.bo[buf_id].buftype = 'acwrite'
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    vim.api.nvim_win_set_buf(0, buf_id)

    -- Create
  end
end

--- Fetch new data of plugins
---
--- - Use `git fetch` to fetch data from source URI.
--- - Use `git log` to get newly fetched data and save output to the file in
---   fetch history.
--- - Create and show scratch buffer with the log.
---
--- Notes:
--- - This function is executed asynchronously.
--- - This does not affect actual plugin code. Run |MiniDeps.checkout()| for that.
---
---@param names __deps_names
MiniDeps.fetch = function(names)
  local spec_arr = H.convert_names_to_specs(names)
  local jobs = vim.tbl_map(function(spec) return H.cli_new_job({}, spec.path) end, spec_arr)

  -- Get current `FETCH_HEAD` for proper log of newly fetched data
  for _, job in ipairs(jobs) do
    job.command = H.git_commands.get_fetch_head
  end

  H.cli_run(jobs)

  local fetch_heads = {}
  for i, job in ipairs(jobs) do
    -- NOTE: FETCH_HEAD can be not present just after `clone`
    fetch_heads[i] = #job.err == 0 and H.cli_stream_tostring(job.out) or 'HEAD'
    job.err, job.out = {}, {}
  end

  -- Ensure `origin` is set to `source`
  for i, job in ipairs(jobs) do
    job.command = H.git_commands.set_origin(spec_arr[i].source)
  end
  H.cli_run(jobs)
  for _, job in ipairs(jobs) do
    job.out = {}
  end

  -- Fetch
  for i, job in ipairs(jobs) do
    job.command = H.git_commands.fetch
    job.exit_msg = string.format('Done fetching `%s`', spec_arr[i].name)
  end
  H.cli_run(jobs)
  for _, job in ipairs(jobs) do
    job.exit_msg, job.out = nil, {}
  end

  -- Get log of fetched data
  for i, job in ipairs(jobs) do
    job.command = H.git_commands.get_fetch_log(fetch_heads[i])
  end
  H.cli_run(jobs)

  -- Postprocess
  local fetched_log = {}
  for i, job in ipairs(jobs) do
    if i > 1 then table.insert(fetched_log, '') end

    local spec = spec_arr[i]
    local lines = H.cli_job_to_lines(job, spec.name, 'FETCH LOG')
    vim.list_extend(fetched_log, lines)

    -- Notify about errors explicitly
    local action_name = string.format('fetching `%s` from `%s`', spec.name, spec.source)
    H.cli_job_show_err(job, action_name)
  end

  -- Write fetch log and show it in new buffer
  local fetch_dir = H.get_package_path() .. '/pack/deps/fetch/'
  vim.fn.mkdir(fetch_dir, 'p')
  local log_path = fetch_dir .. 'fetch-' .. H.get_timestamp()
  vim.fn.writefile(fetched_log, log_path)

  vim.cmd('edit ' .. vim.fn.fnameescape(log_path))
  vim.bo.modifiable = false
end

--- Create snapshot file
---
--- - Get commit of all plugins registered via |MiniDeps.add()| in current session.
--- - Create a snapshot: table with plugin names as keys and commits as values.
--- - Write the table to `path` file in the form of a Lua code ready for |dofile()|.
---
---@param path string|nil A valid path on disk where to write snapshot file.
---   Default: `config.path.snapshot`.
MiniDeps.snapshot = function(path)
  path = path or H.full_path(H.get_config().path.snapshot)
  if type(path) ~= 'string' then H.error('`path` should be string.') end

  -- Create snapshot
  local plugin_paths = vim.tbl_map(function(x) return x.path end, MiniDeps.get_session())
  local jobs = vim.tbl_map(function(p) return H.cli_new_job(H.git_commands.get_hash('HEAD'), p) end, plugin_paths)
  H.cli_run(jobs)

  local snapshot = {}
  for i, job in ipairs(jobs) do
    local name = vim.fn.fnamemodify(plugin_paths[i], ':t')
    H.cli_job_show_err(job, 'creating snapshot for `' .. name .. '`')
    local head_commit = H.cli_stream_tostring(job.out)
    if #job.err == 0 and head_commit ~= '' then snapshot[name] = head_commit end
  end

  -- Write snapshot
  if vim.tbl_count(snapshot) == 0 then return end
  local lines = vim.split(vim.inspect(snapshot), '\n')
  lines[1] = 'return ' .. lines[1]
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(lines, path)

  H.notify('Created snapshot at ' .. vim.inspect(path) .. '.')
end

--- Checkout plugins
---
--- - Create rollback snapshot with |MiniDeps.snapshot()|. It is created inside
---   "rollback" directory (see |MiniDeps-directory-structure|) with current
---   timestamp in file name. Note: rollback snapshot is not created if checkout
---   `target` is itself a path to a rollback snapshot file.
---
--- - Checkout according to `target`. For all proper entries:
---     - Execute all `pre_change` hooks.
---     - Use `git checkout` to do checkouts.
---     - Use `git merge` to possibly sync with local copy of remote branch,
---       making results of |MiniDeps.fetch()| present in code on disk.
---     - Execute all `post_change` hooks.
---
---   Notes:
---     - Checkout only entries for plugin names registered with |MiniDeps.add()|.
---     - If plugin is registered with `checkout = false`, it is not checked out.
---     - Hooks and checkout are done in order of the current session.
---
--- Checkout `target` can take several forms:
--- - If table, treat it as a map of checkout targets for plugin names.
---   Fields are plugin names and values are checkout targets as
---   in |MiniDeps-plugin-specification|.
---
---   Example of table checkout target: >
---     { ['plugin_1.nvim'] = true, ['nvim-plugin_2'] = 'main' }
--- <
--- - If string, treat as snapshot file path (as after |MiniDeps.snapshot()|).
---   Source the file expecting returned table and apply previous step.
---
--- - If `nil`, checkout all plugins added to current session with |MiniDeps.add()|
---   according to their specs. See |MiniDeps.get_session()|.
---
---@param target table|string|nil A checkout target. Default: `nil`.
MiniDeps.checkout = function(target)
  -- Convert checkout target to spec array with relevant `checkout`
  local spec_arr = H.convert_checkout_target_to_spec_arr(target)

  -- Infer default checkout targets early to call only needed `*_change` hooks
  H.infer_repo_data(spec_arr)
  spec_arr = vim.tbl_filter(function(x) return type(x.checkout) == 'string' end, spec_arr)
  if #spec_arr == 0 then return end

  -- Create rollback snapshot
  local rollback_dir = H.get_package_path() .. '/pack/deps/rollback/'
  local is_target_rollback = type(target) == 'string' and vim.startswith(H.full_path(target), rollback_dir)
  if not is_target_rollback then
    vim.fn.mkdir(rollback_dir, 'p')
    local snapshot_path = rollback_dir .. 'snapshot-' .. H.get_timestamp()
    MiniDeps.snapshot(snapshot_path)
  end

  -- Checkout
  for _, spec in ipairs(spec_arr) do
    H.maybe_exec(spec.hooks.pre_change)
  end

  H.do_checkout(spec_arr)

  for _, spec in ipairs(spec_arr) do
    H.maybe_exec(spec.hooks.post_change)
  end
end

--- Get session data
MiniDeps.get_session = function()
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

  -- Clear current session to allow resourcing script with `setup()` call
  -- TODO: Use `remove()` on every present entry in `H.session`?
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
H.git_commands = {
  clone = function(source, path)
    --stylua: ignore
    return {
      'git', 'clone',
      '--quiet', '--filter=blob:none',
      '--recurse-submodules', '--also-filter-submodules',
      '--origin', 'origin',
      source, path,
    }
  end,
  stash = function(timestamp)
    return { 'git', 'stash', '--quiet', '--message', '(mini.deps) ' .. timestamp .. ' Stash before checkout.' }
  end,
  checkout = function(target) return { 'git', 'checkout', '--quiet', target } end,
  sync_with_local_remote = { 'git', 'merge', '--quiet', '--ff-only' },
  sync_fetch_head = { 'git', 'update-ref', 'FETCH_HEAD', 'HEAD' },
  fetch = { 'git', 'fetch', '--quiet', '--tags', '--recurse-submodules=yes', 'origin' },
  get_fetch_head = { 'git', 'rev-parse', 'FETCH_HEAD' },
  set_origin = function(source) return { 'git', 'remote', 'set-url', 'origin', source } end,
  get_default_origin_branch = { 'git', 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
  is_origin_branch = function(name)
    -- Returns branch's name if it is present
    return { 'git', 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/' .. name }
  end,
  get_hash = function(rev) return { 'git', 'rev-parse', rev } end,
  get_remote_branches = { 'git', 'branch', '--remotes', '--format=%(refname:short)' },
  get_fetch_log = function(from) return { 'git', 'log', from .. '..FETCH_HEAD' } end,
  log = function(range)
    -- `--topo-order` makes showing divergent branches nicer
    -- `--decorate-refs` shows only tags near commits (not `origin/main`, etc.)
    --stylua: ignore
    return { 'git', 'log', '--pretty=format:%m %h | %ai | %an%d%n  %s%n', '--topo-order', '--decorate-refs=refs/tags', range }
  end,
  snapshot = { 'git', 'rev-parse', 'HEAD' },
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
  if not (spec.checkout == nil or type(spec.checkout) == 'string') then
    H.error('`checkout` in plugin spec should be string.')
  end

  spec.track = opts.track
  if not (spec.track == nil or type(spec.track) == 'string') then
    H.error('`track` in plugin spec should be string.')
  end

  spec.hooks = opts.hooks or {}
  if type(spec.hooks) ~= 'table' then H.error('`hooks` in plugin spec should be table.') end
  local hook_names = { 'pre_create', 'post_create', 'pre_change', 'post_change', 'pre_delete', 'post_delete' }
  for _, hook_name in ipairs(hook_names) do
    if not (spec[hook_name] == nil or vim.is_callable(spec[hook_name])) then
      H.error('`hooks.' .. hook_name .. '` in plugin spec should be callable.')
    end
  end

  return spec
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

-- Create ---------------------------------------------------------------------
H.do_create = function(spec)
  -- Clone
  local command = H.git_commands.clone(spec.source, spec.path)
  local exit_msg = 'Done creating `' .. spec.name .. '`'
  local job = H.cli_new_job(command, vim.fn.getcwd(), exit_msg)

  H.notify('(0/1) Start creating `' .. spec.name .. '`.')
  H.cli_run({ job })

  -- Stop if there were errors
  H.cli_job_show_err(job, string.format('creation of `%s`', spec.name))
  if #job.err > 0 then return end

  -- Checkout. Don't use `MiniDeps.checkout` to skip rollback making and hooks.
  local spec_arr = { spec }
  H.infer_repo_data(spec_arr)
  H.do_checkout(spec_arr)
end

-- Update ---------------------------------------------------------------------
H.convert_names_to_specs = function(x)
  local session = MiniDeps.get_session()
  if x == nil then return session end
  if not vim.tbl_islist(x) then H.error('`names` should be array.') end

  local res = {}
  for _, spec in ipairs(session) do
    if vim.tbl_contains(x, spec.name) then table.insert(res, spec) end
  end

  return res
end

H.update_prepare = function(jobs, specs)
  -- Ensure `origin` is set to `source`
  for i, job in ipairs(jobs) do
    job.command = H.git_commands.set_origin(specs[i].source)
  end
  H.cli_run(jobs)
  H.cli_job_clean(jobs)
end

H.update_preprocess = function(jobs, specs)
  -- Commit of current head
  for i, job in ipairs(jobs) do
    job.command, job.out = H.git_commands.get_hash('HEAD'), {}
  end
  H.cli_run(jobs)
  for i, s in ipairs(specs) do
    s.head = H.cli_stream_tostring(jobs[i].out)
  end

  -- Default branch
  for i, job in ipairs(jobs) do
    job.command, job.out = H.git_commands.get_default_origin_branch, {}
  end
  H.cli_run(jobs)
  for i, s in ipairs(specs) do
    s.def_branch = H.cli_stream_tostring(jobs[i].out):gsub('^origin/', '')
    s.checkout = s.checkout or s.def_branch
    s.track = s.track or s.def_branch
  end

  -- Commit from which to track
  H.update_get_track_commit(jobs, specs, 'track_from')
end

H.update_download = function(jobs, specs)
  for i, job in ipairs(jobs) do
    job.command = H.git_commands.fetch
    job.exit_msg = string.format('Done downloading remote updates for `%s`', specs[i].name)
  end

  H.notify('Started downloading remote updates')
  H.cli_run(jobs)

  -- Clean reusable jobs
  H.cli_job_clean(jobs)
end

H.update_process = function(jobs, specs)
  -- Target checkout commit
  for i, job in ipairs(jobs) do
    job.command, job.out = H.git_commands.is_origin_branch(specs[i].checkout), {}
  end
  H.cli_run(jobs)
  for i, job in ipairs(jobs) do
    local is_branch = H.cli_stream_tostring(job.out):find('%S') ~= nil
    local checkout = specs[i].checkout
    job.command = is_branch and H.git_commands.get_hash('origin/' .. checkout) or H.git_commands.get_hash(checkout)
    job.out = {}
  end
  H.cli_run(jobs)
  for i, s in ipairs(specs) do
    s.checkout_to = H.cli_stream_tostring(jobs[i].out)
  end

  -- Target track commit
  H.update_get_track_commit(jobs, specs, 'track_to')

  -- Checkout log: what will be added after checkout (reverted commits omitted)
  H.update_get_log(jobs, specs, 'head', 'checkout_to', 'checkout_log')

  -- Track log: what has changed in track branch during this download
  H.update_get_log(jobs, specs, 'track_from', 'track_to', 'track_log')
end

H.update_get_track_commit = function(jobs, specs, field)
  for i, job in ipairs(jobs) do
    job.command, job.out = H.git_commands.is_origin_branch(specs[i].track), {}
  end
  H.cli_run(jobs)
  for i, job in ipairs(jobs) do
    local is_branch = H.cli_stream_tostring(job.out):find('%S') ~= nil
    job.command = is_branch and H.git_commands.get_hash('origin/' .. specs[i].track) or {}
    job.out = {}
  end
  H.cli_run(jobs)
  for i, s in ipairs(specs) do
    local out = H.cli_stream_tostring(jobs[i].out)
    s[field] = out ~= '' and out or s.head
  end

  H.cli_job_clean(jobs)
end

H.update_get_log = function(jobs, specs, field_from, field_to, field_out)
  for i, job in ipairs(jobs) do
    -- Use `...` to include both branches in case they diverge
    local range = specs[i][field_from] .. '...' .. specs[i][field_to]
    job.command, job.out = H.git_commands.log(range), {}
  end
  H.cli_run(jobs)
  for i, s in ipairs(specs) do
    local out = H.cli_stream_tostring(jobs[i].out)
    s[field_out] = out ~= '' and out or '<Nothing>'
  end

  H.cli_job_clean(jobs)
end

H.update_checkout = function(jobs, specs)
  for i, s in ipairs(specs) do
    local needs_checkout = s.head ~= s.checkout_to
    jobs[i].command = needs_checkout and H.git_commands.checkout(specs[i].checkout_to) or {}
    jobs[i].exit_msg = needs_checkout and string.format('Checked out `%s` in plugin `%s`', s.checkout, s.name)
      or string.format('No changes for plugin `%s`', s.name)
  end
  H.cli_run(jobs)
  H.cli_job_clean(jobs)
end

H.update_compute_report = function(specs, confirm)
  -- TODO
  -- - Add interactive header on `confirm` with descriptions of what this is
  --   and what to do next.
  -- - In logs add note that `>`/`<` means commit will be added/reverted
end

H.update_show_report = function(specs, opts)
  -- TODO
end

H.infer_repo_data = function(spec_arr)
  local jobs = vim.tbl_map(function(spec) return H.cli_new_job({}, spec.path) end, spec_arr)

  -- Default branch
  for i, job in ipairs(jobs) do
    job.command = spec_arr[i].checkout == true and H.git_commands.get_default_origin_branch or {}
  end

  H.cli_run(jobs)

  for i, job in ipairs(jobs) do
    local def_branch = string.match(job.out[1] or '', '^origin/(%S+)')
    if spec_arr[i].checkout == true then spec_arr[i].checkout = def_branch or 'main' end
    H.cli_job_show_err(job, 'computing default branch for `' .. spec_arr[i].name .. '`')
    job.err, job.out = {}, {}
  end

  -- Pending changes
  for i, job in ipairs(jobs) do
    -- NOTE: This will error if `checkout` is not a branch
    job.command = H.git_commands.log('HEAD..origin/' .. spec_arr[i].checkout)
  end

  H.cli_run(jobs)

  for i, job in ipairs(jobs) do
    local out = H.cli_stream_tostring(job.out)
    spec_arr[i].log_pending = (#job.err == 0 and out ~= '') and out or '<Nothing>'
    job.err, job.out = {}, {}
  end

  -- Current HEAD
  for i, job in ipairs(jobs) do
    job.command = H.git_commands.get_head
  end

  H.cli_run(jobs)

  for i, job in ipairs(jobs) do
    spec_arr[i].head = H.cli_stream_tostring(job.out)
  end
end

-- Checkout/Snapshot ----------------------------------------------------------
H.convert_checkout_target_to_spec_arr = function(x)
  local session = MiniDeps.get_session()

  -- Use session specs by default
  if x == nil then
    x = {}
    for _, spec in ipairs(session) do
      x[spec.name] = spec.checkout
    end
  end

  -- Treat string input as path to snapshot file
  if type(x) == 'string' then
    local ok, out = pcall(dofile, H.full_path(x))
    if not (ok and type(out) == 'table') then H.error('Checkout target is not a path to proper snapshot.') end
    x = out
  end

  -- Input should be a map from plugin names to checkout target
  if type(x) ~= 'table' then H.error('Checkout target should be table.') end

  -- Add appropriate session specs with `checkout` updated to target
  local res = {}
  for _, spec in ipairs(session) do
    local new_checkout = x[spec.name]
    if H.is_proper_checkout(new_checkout) and spec.checkout ~= false then
      spec.checkout = new_checkout
      table.insert(res, spec)
    end
  end

  return res
end

H.is_proper_checkout = function(x) return type(x) == 'string' or type(x) == 'boolean' end

H.do_checkout = function(spec_arr)
  local jobs = {}

  -- Stash before checkout
  local stash_command = H.git_commands.stash(H.get_timestamp())
  for i, spec in ipairs(spec_arr) do
    jobs[i] = H.cli_new_job(stash_command, spec.path)
  end

  H.cli_run(jobs)

  -- Checkout
  for i, spec in ipairs(spec_arr) do
    jobs[i].command = H.git_commands.checkout(spec.checkout)
    jobs[i].exit_msg = string.format('Done checking out `%s` in `%s`', spec.checkout, spec.name)
    jobs[i].out = {}
  end

  H.cli_run(jobs)

  -- Register and show errors
  for i, spec in ipairs(spec_arr) do
    local job = jobs[i]
    local action_name = string.format('checkout `%s` in `%s`', spec.checkout, spec.name)
    H.cli_job_show_err(jobs[i], action_name)
  end

  -- Synchronize with local remotes (for previous `fetch` to have effect)
  for _, job in ipairs(jobs) do
    job.command, job.exit_msg = H.git_commands.sync_with_local_remote, nil
  end
  H.cli_run(jobs)

  -- Synchronize `FETCH_HEAD` to point to `HEAD`. It can be outdated if
  -- checking out to a different branch. If not done, next `fetch()` will
  -- show not proper log.
  for _, job in ipairs(jobs) do
    job.command = H.git_commands.sync_fetch_head
  end
  H.cli_run(jobs)
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

H.cli_job_to_lines = function(job, title, output_title)
  local lines = { '=== ' .. (title or '') .. ' ===' }
  local err = H.cli_stream_tostring(job.err)
  if err ~= '' then vim.list_extend(lines, vim.split('--- ERRORS ---\n\n' .. err .. '\n', '\n')) end

  local out = H.cli_stream_tostring(job.out)
  if out == '' then out = '<Nothing>' end
  output_title = output_title or 'OUTPUT'
  vim.list_extend(lines, vim.split('--- ' .. output_title .. ' ---\n\n' .. out, '\n'))

  return lines
end

H.cli_job_show_err = function(job, action_name)
  if #job.err == 0 then return end
  H.notify('Error during ' .. action_name .. '\n' .. H.cli_stream_tostring(job.err), 'ERROR')
end

H.cli_job_clean = function(jobs)
  for _, job in ipairs(jobs) do
    job.command, job.exit_msg, job.out = {}, nil, {}
  end
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

H.maybe_exec = function(f, ...)
  if not vim.is_callable(f) then return end
  local ok, err = pcall(f, ...)
  if not ok then H.notify('Error during hook execution:\n' .. err, 'WARN') end
end

H.get_timestamp = function() return vim.fn.strftime('%Y%m%d%H%M%S') end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('\\', '/'):gsub('/+', '/'):gsub('(.)/$', '%1')) end

H.short_path = function(path, cwd)
  cwd = cwd or vim.fn.getcwd()
  if not vim.startswith(path, cwd) then return vim.fn.fnamemodify(path, ':~') end
  local res = path:sub(cwd:len() + 1):gsub('^/+', ''):gsub('/+$', '')
  return res
end

H.readdir = function(path)
  if vim.fn.isdirectory(path) ~= 1 then return {} end
  path = H.full_path(path)
  return vim.tbl_map(function(x) return path .. '/' .. x end, vim.fn.readdir(path))
end

return MiniDeps
