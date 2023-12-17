-- TODO:
--
-- Code:
-- - Do not forget about submodules in `create()` and `fetch()`.
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
---     - Remove / sync.
---     - Snapshot / checkout.
---     All these actions are available both as Lua functions and user commands
---     (see |MiniDeps.setup()).
---
--- - Minimal yet flexible plugin specification:
---     - URI of plugin source.
---     - Basename of target plugin directory.
---     - Checkout target: branch, commit, tag, any manual shell subcommand.
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
--- Specification is a table with the following fields:
---
--- - <source> `(string)` - field with URI of plugin source.
---   Can be anything allowed by `git clone`.
---   This is the only required field. Others are optional.
---
--- - <name> `(string|nil)` - directory basename of where to put plugin source.
---   It is put in "pack/deps/opt" subdirectory of `config.path.package`.
---   Default: basename of a <source>.
---
--- - <checkout> `(string|boolean|nil)` - Git checkout target to be used
---   in |MiniDeps.checkout| when called without arguments.
---   Can be anything supported by `git checkout` - branch, commit, tag, etc.
---   Can also be `false` to not perform `git checkout` at all.
---
--- - <hooks> `(table|nil)` - table with callable hooks to call on certain events.
---   Each hook is executed without arguments. Possible hook names:
---     - <pre_create>  - before creating plugin directory.
---     - <post_create> - after  creating plugin directory.
---     - <pre_change>  - before making change in plugin directory.
---     - <post_change> - after  making change in plugin directory.
---     - <pre_delete>  - before deleting plugin directory.
---     - <post_delete> - after  deleting plugin directory.
---
--- Note: for simplicity, specification is also allowed to be a string. It is
--- assumed to be in a GitHub "user/repo" format and is transformed into
--- `source` like "https://github.com/user/repo", other fields being default.
---@tag MiniDeps-plugin-specification

--- # User commands ~
---                                                                       *:DepsAdd*
---                                                                    *:DepsCreate*
---                                                                    *:DepsUpdate*
---                                                                     *:DepsFetch*
---                                                                    *:DepsRemove*
---                                                                     *:DepsClean*
---                                                                  *:DepsSnapshot*
---                                                                  *:DepsCheckout*
---@tag MiniDeps-commands

--- # Usage examples ~
---
--- Make sure that `git` CLI tool is installed.
---
--- ## Inside config ~
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
---   now(function() require('mini.starter').setup() end)
---   now(function() require('mini.statusline').setup() end)
---   now(function() require('mini.tabline').setup() end)
---
---   -- Delay code execution safely with `later()`
---   later(function() require('mini.ai').setup() end)
---   later(function()
---     require('mini.pick').setup()
---     vim.ui.select = MiniPick.ui_select
---   end)
---
---   -- Use plugins
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
--- - To update plugins, run |:DepsUpdate| and wait for visual feedback
---   that data is fetched and plugins are checked out.
---   Alternatively, run |:DepsFetch|, examine the changes, and run |:DepsCheckout|
---   if you want that changes to take effect.
---
--- - To save current plugin state, run |:DepsSnapshot|. This will save exact
---   state of plugins into some file ('deps-snapshot' in config directory by
---   default). This is usually tracked with version control to have the most
---   recent information about working setup.
---
--- - To revert to some previous state, run |:DepsCheckout| with a snapshot file.
---   Either with manually created (after |:DepsSnapshot|) or automatically
---   created (before every |:DepsCheckout|; stored in "rollback" package
---   directory, see |MiniDeps-directory-structure|).
---   Note: |:DepsCheckout| has Tab-completion for these files.
---
--- - To remove a plugin, run `:DepsRemove <plugin basename>`. Following example
---   config earlier, `:DepsRemove nvim-treesitter` will remove
---   'nvim-treesitter/nvim-treesitter' plugin.
---   Alternatively, remove `add()` call from config, restart Neovim, and
---   run |:DepsClean|.
---   Alternatively (if there are no relevant hooks for deleting plugin) manually
---   delete plugin directory.
---@tag MiniDeps-examples

---@alias __deps_spec table|string Object with |MiniDeps-plugin-specification|.
---@alias __deps_name table|string Plugin name present in current session specifications
---   or an array of them.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
local MiniDeps = {}
local H = {}

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
  -- Paths describing where to store data
  path = {
    -- Directory for built-in package.
    -- All data is actually stored in the 'pack/deps' subdirectory.
    package = vim.fn.stdpath('data') .. '/site',

    -- Default file path for a snapshot
    snapshot = vim.fn.stdpath('config') .. '/deps-snapshot',
  },
}
--minidoc_afterlines_end

--- Add plugin
---
--- - Call |MiniDeps.create()|.
--- - Make sure it can be used in current session.
---
---@param spec __deps_spec
MiniDeps.add = function(spec)
  -- TODO
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
MiniDeps.create = function(spec)
  -- TODO
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

--- Create snapshot file
---
--- - Get current commit of every plugin directory in `path.package`.
--- - Create a snapshot object: table with plugin directory basenames as keys
---   and commits as values.
--- - Write the table to `path` file in the form of a Lua code ready for |dofile()|.
---
---@param path string|nil A valid path on disk where to write snapshot file.
---   Default: `config.path.snapshot`.
MiniDeps.snapshot = function(path)
  -- TODO
end

--- Checkout plugins
---
--- - If no input, checkout all plugins registered in current session
---   (with |MiniDeps.add()| or |MiniDeps.create()|) according to their specification.
---   See |MiniDeps.get_session_data()|.
--- - If table input, treat it as a snapshot object (as described
---   in |MiniDeps.snapshot()|) and checkout acutally present on dick plugins
---   according to it. That is, entries in snapshot table which are not present
---   on disk are ignored.
--- - If string input, treat it as file path with snapshot (as
---   after |MiniDeps.snapshot()|). Source the file expecting returned table and
---   apply previous step.
---
---@param target table|string|nil A checkout target. Default: `nil`.
MiniDeps.checkout = function(target)
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
    path = { config.path, 'table' },
  })

  vim.validate({
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

-- Plugin specification -------------------------------------------------------
H.validate_spec = function(x)
  if type(x) == 'string' then x = { source = 'https://github.com/' .. x } end

  if type(x) ~= 'table' then H.error('Plugin spec should be table.') end
  if type(x.source) ~= 'string' then H.error('`source` in plugin spec should be string.') end
  if not (x.target == nil or type(x.target) == 'string') then H.error('`target` in plugin spec should be string.') end
  if not (x.checkout == nil or type(x.checkout) == 'string' or x.checkout == false) then
    H.error('`checkout` in plugin spec should be string or `false`.')
  end

  if not (x.hooks == nil or type(x.hooks) == 'table') then H.error('`hooks` in plugin spec should be table.') end
  local hook_names = { 'pre_create', 'post_create', 'pre_change', 'post_change', 'pre_delete', 'post_delete' }
  for _, hook_name in ipairs(hook_names) do
    if not (x[hook_name] == nil or vim.is_callable(x[hook_name])) then
      H.error('`hooks.' .. hook_name .. '` should be callable.')
    end
  end

  return x
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

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('\\', '/'):gsub('/+', '/'):gsub('(.)/$', '%1')) end

H.short_path = function(path, cwd)
  cwd = cwd or vim.fn.getcwd()
  if not vim.startswith(path, cwd) then return vim.fn.fnamemodify(path, ':~') end
  local res = path:sub(cwd:len() + 1):gsub('^/+', ''):gsub('/+$', '')
  return res
end

return MiniDeps
