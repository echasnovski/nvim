-- TODO:
--
-- Code:
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
---     - Whether plugin is optional or should be sourced at start ("opt" vs
---       "start" package subdirectories).
---
--- - Automated show and save of fetch results to review before updating.
---
--- - Automated save of current snapshot prior to checkout for easier rollback in
---   case something does not work as expected.
---
--- - Helpers to implement two-stage startup: |MiniDeps.now()| and |MiniDeps.later()|.
---   See |MiniDeps-examples| for how to implement basic lazy loading with them.
---
--- Notes:
---
--- - All module's data is stored in `config.path.package` directory inside
---   "pack/deps" subdirectory. It itself has the following subdirectories:
---     - `opt` with optional plugins (sourced after |:packadd|).
---     - `start` with non-optional plugins (sourced at start unconditionally).
---     - `fetch` with history of the new data after |MiniDeps.fetch()|.
---     - `rollback` with history of the snapshots before |MiniDeps.checkout()|.
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
---   to create a separate package (like "pack/nogit" near "pack/deps").
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

--- Actions ~
---
--- This sections describes which actions are implemented in the module.
--- Any action is available as lua function and user command (described in tag).
---
---                                                                       *:DepsAdd*
--- <Add> - main action to add plugins:
--- - <Create> plugin.
--- - Make sure it can be used in current session.
---
---                                                                    *:DepsCreate*
--- <Create> - create plugin directory:
--- - If in `path.package` there is no directory with target basename , clone
---   plugin from its source URI.
--- - If plugin is present, but in the wrong subdirectory, move plugin.
--- - If plugin is present in correct subdirectory, do nothing.
---
---                                                                    *:DepsUpdate*
--- <Update> - main actinon to update plugins:
--- - <Fetch> new data from source URI.
--- - <Checkout> according to plugin specification.
---
---                                                                     *:DepsFetch*
--- <Fetch> - download plugin Git metadata without affecting plugin itself:
--- - Use `git fetch` to fetch data from source URI.
--- - Use `git log` to get newly fetched data and save output to the file in
---   fetch history.
--- - Create and show scratch buffer with the log.
---
---                                                                    *:DepsRemove*
--- <Remove> - main action to remove plugins:
--- - If plugin is present in `path.package` directory, delete its directory.
--- - If not present, do nothing.
---
---                                                                      *:DepsSync*
--- <Sync> - synchronous `path.package` directory to have only added plugins:
--- - <Remove> plugins which are not currently present in 'runtimpath'.
---
---                                                                  *:DepsSnapshot*
--- <Snapshot> - create a snapshot of current state of plugins:
--- - Get current commit of every plugin directory in `path.package`.
--- - Create a snapshot: table with plugin directory basenames as keys and
---   commits as values.
--- - Write the table to `path.snapshot` file in the form of a Lua code
---   appropriate for |dofile()|.
---
---                                                                  *:DepsCheckout*
--- <Checkout> - checkout plugins according to the input:
--- - If no input, checkout all <Add>ed plugins according to their specification.
--- - If table input, treat it as a snapshot object and checkout actually present
---   plugins according to it.
--- - If string input, treat it as file path with snapshot (as after <Snapshot>
---   action). Source the file expecting returned table and apply previous step.
---
---@tag MiniDeps-actions

--- Usage examples ~
---
--- # Inside config ~
---
--- ## Two-stage loading ~
---
--- # Inside session ~
---
---@tag MiniDeps-examples

--- Plugin specification ~
---
---@tag MiniDeps-plugin-specification

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
  -- Hooks to be called for every plugin
  hooks = {
    -- Before and after creating plugin directory
    pre_create = nil,
    post_create = nil,

    -- Before and after changing plugin content
    pre_change = nil,
    post_change = nil,

    -- Before and after deleteing plugin directory
    pre_delete = nil,
    post_delete = nil,
  },

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

MiniDeps.add = function()
  -- TODO
end

MiniDeps.create = function()
  -- TODO
end

MiniDeps.update = function()
  -- TODO
end

MiniDeps.fetch = function()
  -- TODO
  -- Outline:
  -- - Get value of `FETCH_HEAD`.
  -- - `git fetch`.
  -- - Get log as `git log <prev_FETCH_HEAD>..FETCH_HEAD`.
end

MiniDeps.remove = function()
  -- TODO
end

MiniDeps.sync = function()
  -- TODO
end

MiniDeps.snapshot = function()
  -- TODO
end

MiniDeps.checkout = function()
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
    hooks = { config.hooks, 'table' },
    path = { config.path, 'table' },
  })

  vim.validate({
    ['hooks.pre_create'] = { config.hooks.pre_create, 'function', true },
    ['hooks.post_create'] = { config.hooks.post_create, 'function', true },
    ['hooks.pre_change'] = { config.hooks.pre_change, 'function', true },
    ['hooks.post_change'] = { config.hooks.post_change, 'function', true },
    ['hooks.pre_delete'] = { config.hooks.pre_delete, 'function', true },
    ['hooks.post_delete'] = { config.hooks.post_delete, 'function', true },

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
