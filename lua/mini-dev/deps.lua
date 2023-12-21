-- TODO:
--
-- Code:
-- - Do not forget about stashing changes before `checkout()`.
--
-- Docs:
-- - Add examples of user commands in |MiniDeps-actions|.
--
-- Tests:

--- *mini.deps* Plugin manager
--- *MiniDeps*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Manage plugins utilizing Git and built-in |packages| with these actions:
---     - Add / create.
---     - Update / fetch.
---     - Snapshot / checkout.
---     - Remove / clean.
---     All these actions are available both as Lua functions and user commands
---     (see |MiniDeps.setup()).
---
--- - Minimal yet flexible plugin specification:
---     - Mandatory plugin source.
---     - Name of target plugin directory.
---     - Checkout target: branch, commit, tag, etc.
---     - Hooks to call before/after plugin is created/changed/deleted.
---
--- - Automated show and save of fetch results to review before updating.
---
--- - Automated save of current snapshot prior to checkout for easier rollback in
---   case something does not work as expected.
---
--- - Helpers to implement two-stage startup: |MiniDeps.now()| and |MiniDeps.later()|.
---   See |MiniDeps-examples| for how to implement basic lazy loading with them.
---
--- What it doesn't do:
---
--- - Allow manual dependencies in plugin specification. This is assumed to be
---   done by user manually with multiple |MiniDeps.add()| calles, each for
---   specific dependency plugin.
---   In case there is an official standard for plugins to supply dependency info
---   inside of them, 'mini.deps' will be updated to use it automatically.
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
---     - Has dependenies. This module does not by design.
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
---   |MiniDeps.create()| uses this directory.
---
--- - `start` with non-optional plugins (sourced at start unconditionally).
---   All its subdirectories are recognized as plugins and can be updated,
---   removed, etc. To actually use, move installed plugin from `opt` directory.
---
--- - `fetch` with history of the new data after |MiniDeps.fetch()|.
---   Each file contains a log of fetched changes for later review.
---
--- - `rollback` with history of automated snapshots. Each file is created
---   automatically before every run of |MiniDeps.checkout()|.
---   This can be used together with |MiniDeps.checkout()| to roll back after
---   unfortunate update.
---@tag MiniDeps-directory-structure

--- # Plugin specification ~
---
--- Each plugin dependency is managed based on its specification (a.k.a. "spec").
--- See |MiniDeps-examples| for how it is suggested to be used inside user config.
---
--- Specification is a string or table with the following fields:
---
--- - <source> `(string)` - field with URI of plugin source.
---   Can be anything allowed by `git clone`.
---   This is the only required field. Others are optional.
---   Note: as the most common case, URI of the format "user/repo" is transformed
---   into "https://github.com/user/repo". For relative path use "./user/repo".
---
--- - <name> `(string|nil)` - directory basename of where to put plugin source.
---   It is put in "pack/deps/opt" subdirectory of `config.path.package`.
---   Default: basename of a <source>.
---
--- - <checkout> `(string|boolean|nil)` - Git checkout target to be used
---   in |MiniDeps.checkout| when called without arguments.
---   Can be anything supported by `git checkout` - branch, commit, tag, etc.
---   Can also be boolean:
---     - `true` to checkout to latest default branch (`main` / `master` / etc.)
---     - `false` to not perform `git checkout` at all.
---   Default: `true`.
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
---
--- If `spec` is a string, it is transformed into `{ source = spec }`.
---@tag MiniDeps-plugin-specification

--- # User commands ~
---                                                                       *:DepsAdd*
---                                                                    *:DepsCreate*
---                                                                    *:DepsUpdate*
---                                                                     *:DepsFetch*
---                                                                  *:DepsSnapshot*
---                                                                  *:DepsCheckout*
---                                                                    *:DepsRemove*
---                                                                     *:DepsClean*
---@tag MiniDeps-commands

--- # Usage examples ~
---
--- Make sure that `git` CLI tool is installed.
---
--- ## In config ~
--- >
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
---     add({
---       -- Use full form of plugin specification
---       source = 'https://github.com/nvim-treesitter/nvim-treesitter',
---       checkout = is_010 and 'main' or 'master',
---       hooks = { post_change = function() vim.cmd('TSUpdate') end },
---     })
---
---     -- Run any code related to plugin's config
---     local parsers = { 'bach', 'python', 'r' }
---     if is_010 then
---       require('nvim-treesitter').setup({ ensure_install = parsers })
---     else
---       require('nvim-treesitter.configs').setup({ ensure_installed = parsers })
---     end
---   end)
--- <
--- ## Plugin management ~
---
--- `:DepsAdd user/repo` adds plugin from https://github.com/user/repo to the
--- current session (clones it, if it not present). See |:DepsAdd|.
--- To add plugin in every session, see previous section.
---
--- `:DepsUpdate` updates all plugins with new changes from their sources.
--- See |:DepsUpdate|.
--- Alternatively: `:DepsFetch` followed by `:DepsCheckout`.
---
--- `:DepsSnapshot` creates snapshot file in default location ('deps-snapshot'
--- file in config directory). See |:DepsSnapshot|.
---
--- `:DepsCheckout path/to/snapshot` makes present plugins have state from the
--- snapshot file. See |:DepsCheckout|.
---
--- `:DepsRemove repo` removes plugin with basename "repo". Do not forget to
--- update config to not add same plugin. See |:DepsRemove|.
--- Alternatively: `:DepsClean` removes all plugins which are not loaded in
--- current session. See |:DepsClean|.
--- Alternatively: manually delete plugin directory (if no hooks are set up).
---@tag MiniDeps-examples

---@alias __deps_spec table|string The |MiniDeps-plugin-specification| or an array of them.
---@alias __deps_return_spec table Array of normalized specs for actually processed plugins.
---@alias __deps_name table|string Plugin name present in current session specifications
---   or an array of them.

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
  },

  -- Whether to disable showing non-error feedback
  silent = false,
}
--minidoc_afterlines_end

--- Add plugin
---
--- - Call |MiniDeps.create()|.
--- - Make sure it can be used in current session.
---
---@param spec __deps_spec
---
---@return __deps_return_spec
MiniDeps.add = function(spec)
  -- Create plugins
  local spec_arr = MiniDeps.create(spec)

  -- Add target package path to 'packpath'
  local pack_path = H.full_path(H.get_config().path.package)
  if not string.find(vim.o.packpath, vim.pesc(pack_path)) then vim.o.packpath = vim.o.packpath .. ',' .. pack_path end

  -- Make sure plugins are in 'runtimepath'
  for _, sp in ipairs(spec_arr) do
    vim.cmd('packadd ' .. sp.name)
  end

  return spec_arr
end

--- Create plugin
---
--- - Register `spec` as specification in current session.
--- - If there is no directory present with `spec.name`:
---     - Execute `spec.hooks.pre_create`.
---     - Use `git clone` to clone plugin from its source URI into "pack/deps/opt".
---     - Execute `spec.hooks.post_create`.
---     - Run |MiniDeps.checkout()| with plugin's name.
---
---@param spec __deps_spec
---
---@return __deps_return_spec
MiniDeps.create = function(spec)
  local spec_arr = H.normalize_spec_arr(spec)

  -- Ensure target paths
  local deps_dir = H.full_path(H.get_config().path.package) .. '/pack/deps'
  vim.fn.mkdir(deps_dir, 'p')

  -- Preprocess specifications
  for _, sp in ipairs(spec_arr) do
    H.session_specs[sp.name] = sp
    sp.path, sp.to_create = H.get_plugin_path(sp.name, deps_dir)
  end

  -- Execute pre hooks
  for _, sp in ipairs(spec_arr) do
    if sp.to_create and vim.is_callable(sp.hooks.pre_create) then sp.hooks.pre_create() end
  end

  -- Create
  local jobs = {}
  for i, sp in ipairs(spec_arr) do
    local command = sp.to_create and H.git_commands.clone(sp.source, sp.path) or {}
    local exit_msg = 'Done creating ' .. vim.inspect(sp.name)
    table.insert(jobs, H.cli_new_job(command, exit_msg))
  end
  H.cli_run(jobs)

  -- TODO: ?Make sure that proper remote branch is created?

  -- TODO: Notify about errors when there is a converter from `job` to lines.

  -- Execute post hooks
  for _, sp in ipairs(spec_arr) do
    if sp.to_create and vim.is_callable(sp.hooks.post_create) then sp.hooks.post_create() end
  end

  -- Checkout only those plugins which did not error earlier
  local checkout_target = {}
  for i, sp in ipairs(spec_arr) do
    if #jobs[i].err == 0 then checkout_target[sp.name] = sp.checkout end
  end
  MiniDeps.checkout(checkout_target)

  --stylua: ignore
  return vim.tbl_map(function(x) x.path, x.to_create = nil, nil end, spec_arr)
end

--- Update plugin
---
--- - Use |MiniDeps.fetch()| to get new data from source URI.
--- - Use |MiniDeps.checkout()| to checkout according to plugin specification.
---
---@param name __deps_name
MiniDeps.update = function(name)
  -- TODO
end

--- Fetch new plugin data
---
--- - Use `git fetch` to fetch data from source URI.
--- - Use `git log` to get newly fetched data and save output to the file in
---   fetch history.
--- - Create and show scratch buffer with the log.
---
--- Notes:
--- - This function is asynchronously.
--- - This does not affect actual plugin code. Run |MiniDeps.checkout()| for that.
---
---@param name __deps_name
MiniDeps.fetch = function(name)
  -- TODO
  -- Outline:
  -- - Get value of `FETCH_HEAD`.
  -- - `git fetch --all --write-fetch-head`.
  -- - Get log as `git log <prev_FETCH_HEAD>..FETCH_HEAD`.
end

--- Create snapshot file
---
--- - Get current commit of every plugin directory in `path.package`.
--- - Create a snapshot: table with plugin names as keys and commits as values.
--- - Write the table to `path` file in the form of a Lua code ready for |dofile()|.
---
---@param path string|nil A valid path on disk where to write snapshot file.
---   Default: `config.path.snapshot`.
MiniDeps.snapshot = function(path)
  -- TODO
end

--- Checkout plugins
---
--- - If table input, treat it as a map of checkout targets for plugin names.
---   Fields are plugin names and values are checkout targets as
---   in |MiniDeps-plugin-specification|.
---   Notes:
---   - Only present on disk plugins are checked out. That is, plugin names
---     which are not present on disk are ignored.
---
---   Example of cehckout target: >
---     { plugin_1 = true, plugin_2 = false, plugin_3 = 'main' }
--- <
--- - If string input, treat it as snapshot file (as after |MiniDeps.snapshot()|).
---   Source the file expecting returned table and apply previous step.
---
--- - If no input, checkout all plugins registered in current session
---   (with |MiniDeps.add()| or |MiniDeps.create()|) according to their specs.
---   See |MiniDeps.get_session_data()|.
---
---@param target table|string|nil A checkout target. Default: `nil`.
MiniDeps.checkout = function(target)
  add_to_log('checkout target', target)
  -- TODO
end

--- Remove plugin
---
--- - If there is directory present with `spec.name`:
---     - Execute `spec.hooks.pre_delete`.
---     - Delete plugin directory.
---     - Execute `spec.hooks.post_delete`.
---
---@param name __deps_name
MiniDeps.remove = function(name)
  -- TODO
end

--- Clean plugins
---
--- - Delete plugin directories which are currently not present in 'runtimpath'.
MiniDeps.clean = function()
  -- TODO
end

--- Get session data
MiniDeps.get_session_data = function()
  -- TODO
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

-- Specs for current session. Fields - directory name / `name` from spec.
H.session_specs = {}

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
  })

  return config
end

H.apply_config = function(config) MiniDeps.config = config end

H.create_user_commands = function(config)
  -- TODO
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniDeps.config, vim.b.minideps_config or {}, config or {})
end

-- Git commands ---------------------------------------------------------------
--stylua: ignore
H.git_commands = {
  clone = function(source, path)
    return {
      'git', 'clone',
      '--quiet', '--filter=blob:none',
      '--recurse-submodules', '--also-filter-submodules',
      '--origin', 'origin',
      source, path,
    }
  end,
  stash = function(path) end,
  checkout = function(target, path) return { 'git', '-C', path, 'checkout', '--quiet', target } end,
  get_default_checkout = function(path) return { 'git', '-C', path, 'rev-parse', '--abbrev-ref', 'origin/HEAD'} end,
  fetch = function(path)
    return { 'git', '-C', path, 'fetch', '--quiet', '--all', '--recurse-submodules=yes', 'origin' }
  end,
  -- { 'git', '-C', 'clones/' .. name, 'log', '--format=%h - %ai - %an%n  %s%n', 'main~~..main' }, -- log after fetch
  -- { 'git', '-C', 'clones/' .. name, 'rev-parse', '--abbrev-ref', 'origin/HEAD'}, -- checkout default
  -- { 'git', '-C', 'clones/' .. name, 'rev-parse', 'HEAD'}, -- snapshot
}

-- File system ----------------------------------------------------------------
H.get_plugin_path = function(name, deps_dir)
  local start_path = string.format('%s/start/%s', deps_dir, name)
  local opt_path = string.format('%s/opt/%s', deps_dir, name)
  local is_start_present, is_opt_present = vim.loop.fs_stat(start_path) ~= nil, vim.loop.fs_stat(opt_path) ~= nil
  -- Use 'opt' directory by default
  local path = is_start_present and start_path or opt_path
  local is_present = not (is_start_present or is_opt_present)
  return path, is_present
end

-- Plugin specification -------------------------------------------------------
H.normalize_spec_arr = function(x)
  if not vim.tbl_islist(x) then x = { x } end

  local res = {}
  for _, val in ipairs(x) do
    if type(val) == 'string' then val = { source = val } end
    local is_spec = type(val) == 'table' and type(val.source) == 'string'
    if is_spec then table.insert(res, H.normalize_spec(val)) end
    if not is_spec then H.error(vim.inspect(val, { newline = ' ', indent = '' }) .. ' is not a plugin spec.') end
  end

  return res
end

H.normalize_spec = function(x)
  -- Allow 'user/repo' as source
  if x.source:find('^[^/]+/[^/]+$') ~= nil then x.source = 'https://github.com/' .. x.source end

  x.name = x.name or vim.fn.fnamemodify(x.source, ':t')
  if type(x.name) ~= 'string' then H.error('`name` in plugin spec should be string.') end

  if x.checkout == nil then x.checkout = true end
  if not (type(x.checkout) == 'string' or type(x.checkout) == 'boolean') then
    H.error('`checkout` in plugin spec should be string or boolean.')
  end

  x.hooks = x.hooks or {}
  if type(x.hooks) ~= 'table' then H.error('`hooks` in plugin spec should be table.') end
  local hook_names = { 'pre_create', 'post_create', 'pre_change', 'post_change', 'pre_delete', 'post_delete' }
  for _, hook_name in ipairs(hook_names) do
    if not (x[hook_name] == nil or vim.is_callable(x[hook_name])) then
      H.error('`hooks.' .. hook_name .. '` should be callable.')
    end
  end

  return x
end

-- CLI ------------------------------------------------------------------------
H.cli_run = function(jobs)
  local config_job = H.get_config().job
  local n_threads = config_job.n_threads or math.floor(0.8 * #vim.loop.cpu_info())
  local timeout = config_job.timeout or 60000

  local n_total, id_started, n_finished = #jobs, 0, 0
  if n_total == 0 then return {} end

  local run_next
  run_next = function()
    if n_total <= id_started then return end
    id_started = id_started + 1

    local job = jobs[id_started]
    local command, exit_msg = job.command or {}, job.exit_msg

    -- Allow reusing job structure. Do nothing if previously there were errors.
    if not (#job.err == 0 and #command > 0) then
      n_finished = n_finished + 1
      return run_next()
    end

    local executable, args = command[1], vim.list_slice(command, 2, #command)
    local process, stdout, stderr = nil, vim.loop.new_pipe(), vim.loop.new_pipe()
    local spawn_opts = { args = args, stdio = { nil, stdout, stderr } }

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

H.cli_new_job = function(command, exit_msg) return { command = command, exit_msg = exit_msg, out = {}, err = {} } end

-- vim.fn.delete('clones', 'rf')
-- vim.fn.mkdir('clones', 'p')

_G.repos = {
  'mini.nvim',
  'mini.ai',
  'mini.align',
  -- 'mini.animate',
  -- 'mini.base16',
  -- 'mini.basics',
  -- 'mini.bracketed',
  -- 'mini.bufremove',
  -- 'mini.clue',
  -- 'mini.colors',
  -- 'mini.comment',
  -- 'mini.completion',
  -- 'mini.cursorword',
  -- 'mini.doc',
  -- 'mini.extra',
  -- 'mini.files',
  -- 'mini.fuzzy',
  -- 'mini.hipatterns',
  -- 'mini.hues',
  -- 'mini.indentscope',
  -- 'mini.jump',
  -- 'mini.jump2d',
  -- 'mini.map',
  -- 'mini.misc',
  -- 'mini.move',
  -- 'mini.operators',
  -- 'mini.pairs',
  -- 'mini.pick',
  -- 'mini.sessions',
  -- 'mini.splitjoin',
  -- 'mini.starter',
  -- 'mini.statusline',
  -- 'mini.surround',
  -- 'mini.tabline',
  -- 'mini.test',
  -- 'mini.trailspace',
  -- 'mini.visits',
}

_G.test_jobs = {}
--stylua: ignore
for _, repo in ipairs(repos) do
  local name = repo:sub(6)
  local job = H.cli_new_job(
    { 'git', '-C', 'clones', 'clone', '--quiet', '--filter=blob:none', 'https://github.com/echasnovski/' .. repo, name }, -- create
    -- { 'git', '-C', 'clones/' .. name, 'fetch', '--quiet', 'origin', 'main' }, -- fetch
    -- { 'git', '-C', 'clones/' .. name, 'log', '--format=%h - %ai - %an%n  %s%n', 'main~~..main' }, -- log after fetch
    -- { 'git', '-C', 'clones/' .. name, 'checkout', '--quiet', 'HEAD~' }, -- checkout
    -- { 'git', '-C', 'clones/' .. name, 'checkout', '--quiet', 'main' }, -- checkout
    -- { 'git', '-C', 'clones/' .. name, 'checkout', '--quiet', 'v0.10.0' }, -- checkout
    -- { 'git', '-C', 'clones/' .. name, 'rev-parse', '--abbrev-ref', 'origin/HEAD'}, -- checkout default
    -- { 'git', '-C', 'clones/' .. name, 'rev-parse', 'HEAD'}, -- snapshot

    'Done with ' .. vim.inspect(name)
  )
  table.insert(_G.test_jobs, job)
end

-- vim.fn.writefile({}, 'worklog')
-- _G.test_commands = {}
-- for i = 1, 18 do
--   table.insert(_G.test_commands, { './date-and-sleep.sh', tostring(i) })
-- end

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
  if H.get_config().silent and level ~= 'ERROR' then return end
  if type(msg) == 'table' then msg = table.concat(msg, '\n') end
  vim.notify(string.format('(mini.deps) %s', msg), vim.log.levels[level])
  vim.cmd('redraw')
end)

H.to_lines = function(arr)
  local s = table.concat(arr):gsub('\n+$', '')
  return vim.split(s, '\n')
end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('\\', '/'):gsub('/+', '/'):gsub('(.)/$', '%1')) end

H.short_path = function(path, cwd)
  cwd = cwd or vim.fn.getcwd()
  if not vim.startswith(path, cwd) then return vim.fn.fnamemodify(path, ':~') end
  local res = path:sub(cwd:len() + 1):gsub('^/+', ''):gsub('/+$', '')
  return res
end

return MiniDeps
