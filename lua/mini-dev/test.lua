-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- Documentation ==============================================================
--- Extensible module for writing Neovim plugin tests.
---
--- Planned features:
--- - "Collect and execute" design.
--- - The `testset` (table with callable elements at matching fields) and
---   `test_step` (those fields after flattening along with hooks and spreading
---   arguments).
--- - Ability to filter (during collection): in directory, in file, **at cursor
---   position**, at tags.
--- - Sequential execution with structured reports ('note' and 'fail' strings)
---   and pretty output for all collected files ('o' - pass, 'O' - pass with
---   note, 'x' - fail, 'X' - fail with note). Try to design to allow async
---   execution.
---
--- # Setup~
---
--- This module needs a setup with `require('mini.test').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table
--- `MiniTest` which you can use for scripting or manually (with
--- `:lua MiniTest.*`). See |MiniTest.config| for available config settings.
---
--- # Disabling~
---
--- To disable, set `g:minitest_disable` (globally) or `b:minitest_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.test
---@tag MiniTest
---@toc_entry Test Neovim plugins

-- Module definition ==========================================================
-- TODO: make them local
MiniTest = {}
H = {}

--- Module setup
---
---@param config table Module config table. See |MiniTest.config|.
---
---@usage `require('mini.test').setup({})` (replace `{}` with your `config` table)
function MiniTest.setup(config)
  -- Export module
  _G.MiniTest = MiniTest

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--stylua: ignore start
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniTest.config = {
  -- Options controlling collection of test cases
  collect = {
    find_files = function() return vim.fn.globpath('tests', '**/test_*.lua', true, true) end,
    filter_cases = function(case) return true end,
  },

  -- Options controlling execution of test cases
  execute = {
    reporter = nil,
  },

  -- Path (relative to current directory) to script which handles project
  -- specific test configuration
  script_path = 'scripts/minitest.lua',
}
--minidoc_afterlines_end
--stylua: ignore end

-- Module data ================================================================
--- Table with information about current state of test execution
---
--- It is reset at the beginning and end of |MiniTest.execute()|.
---
--- At least these keys are supported:
--- - <all_cases> - all cases being currently executed.
--- - <case> - currently executed test case.
MiniTest.current = { testcase = nil, state_message = nil }

-- Module functionality =======================================================
function MiniTest.run(opts)
  if H.is_disabled() then
    return
  end

  -- Try sourcing project specific script first
  local success = H.execute_project_script(opts)
  if success then
    return
  end

  -- Collect and execute
  opts = vim.tbl_deep_extend('force', MiniTest.config, opts or {})
  local cases = MiniTest.collect(opts.collect)
  MiniTest.execute(cases, opts.execute)
end

function MiniTest.collect(opts)
  opts = vim.tbl_deep_extend('force', MiniTest.config.collect, opts or {})

  -- Make single test set
  local set = MiniTest.new_testset()
  for _, file in ipairs(opts.find_files()) do
    local ok, t = pcall(dofile, file)
    if not ok then
      local msg = string.format([[Sourceing %s resulted into following error: %s]], vim.inspect(file), t)
      H.error(msg)
    end
    if not H.is_testset(t) then
      local msg = string.format(
        [[Output of %s is not a test set. Did you use `MiniTest.new_testset()`?]],
        vim.inspect(file)
      )
      H.error(msg)
    end

    set[file] = t
  end

  -- Convert to test cases. This also creates separate aligned array of hooks
  -- which should be executed once regarding test case. This is needed to
  -- correctly inject those hooks after filtering is done.
  local raw_cases, raw_hooks_once = H.set_to_testcases(set)

  -- Filter cases (at this stage don't have injected `hooks_once`)
  local cases, hooks_once = {}, {}
  for i, c in ipairs(raw_cases) do
    if opts.filter_cases(c) then
      table.insert(cases, c)
      table.insert(hooks_once, raw_hooks_once[i])
    end
  end

  -- Inject `hooks_once` into appropriate cases
  H.inject_hooks_once(cases, hooks_once)

  return cases
end

function MiniTest.execute(cases, opts)
  opts = vim.tbl_deep_extend('force', MiniTest.config.execute, opts or {})

  -- Call reporter on schedule
  local reporter = opts.reporter or function() end

  MiniTest.current.all_cases = cases
  for _, case in ipairs(cases) do
    MiniTest.current.case = case
    case.info = { state = nil, notes = {}, fails = {} }

    -- Execute
    local on_err = function(e)
      table.insert(case.info.fails, tostring(e))
    end

    for i, hook_pre in ipairs(case.hooks.pre) do
      case.info.state = string.format([[Executing 'pre' hook #%s]], i)
      reporter()
      xpcall(hook_pre, on_err)
    end

    case.info.state = 'Executing test'
    reporter()
    --stylua: ignore
    xpcall(function() case.test(unpack(case.args)) end, on_err)

    for i, hook_post in ipairs(case.hooks.post) do
      case.info.state = string.format([[Executing 'post' hook #%s]], i)
      reporter()
      xpcall(hook_post, on_err)
    end

    -- Finalize state
    local pass_fail = #case.info.fails == 0 and 'Pass' or 'Fail'
    local with_notes = #case.info.notes == 0 and '' or ' with notes'
    case.info.state = pass_fail .. with_notes
  end

  MiniTest.current = {}
end

--- Create test set
---
--- TODO: document how to use it (with/without order preservation,
--- `table.insert()` doesn't work).
---
---@param opts? table Allowed options:
---   - <hooks> - table with fields:
---       - <pre_once> - before first filtered node.
---       - <pre_case> - before each case (even nested).
---       - <post_case> - after each case (even nested).
---       - <post_once> - after last filtered node.
---   - <parametrize> - array where each element is a table of parameters to be
---     appended to "current parameters" of callable fields.
---   - <user> - user data to be forwarded to steps.
---@param tbl? table Initial cases (possibly nested). Will be executed without
---   any guarantees on order.
function MiniTest.new_testset(opts, tbl)
  opts = opts or {}
  tbl = tbl or {}

  -- Keep track of new elements order. This allows to iterate through elements
  -- in order they were added.
  local metatbl = { is_testset = true, key_order = vim.tbl_keys(tbl), opts = opts }
  metatbl.__newindex = function(tbl, key, value)
    table.insert(metatbl.key_order, key)
    rawset(tbl, key, value)
  end

  return setmetatable(tbl, metatbl)
end

-- Expectations ---------------------------------------------------------------
MiniTest.expect = {}

function MiniTest.expect.equal(left, right)
  --stylua: ignore
  if vim.deep_equal(left, right) then return true end

  H.error_expect('equal objects', 'Left: ' .. vim.inspect(left), 'Right: ' .. vim.inspect(right))
end

function MiniTest.expect.not_equal(left, right)
  --stylua: ignore
  if not vim.deep_equal(left, right) then return true end

  H.error_expect('*not* equal objects', 'Object: ' .. vim.inspect(left))
end

function MiniTest.expect.error(f, match, ...)
  vim.validate({ match = { match, 'string', true } })

  local ok, err = pcall(f, ...)
  err = err or ''
  local has_matched_error = not ok and string.find(err, match or '') ~= nil
  --stylua: ignore
  if has_matched_error then return true end

  local with_match = match == nil and '' or (' with match %s'):format(vim.inspect(match))
  local cause = 'error' .. with_match
  local suffix = ok and 'Observed no error' or ('Observed error: ' .. err)

  H.error_expect(cause, suffix)
end

function MiniTest.expect.no_error(f, ...)
  local ok, err = pcall(f, ...)
  --stylua: ignore
  if ok then return true end

  H.error_expect('no error', 'Observed error: ' .. err)
end

function MiniTest.expect.match(str, pattern)
  --stylua: ignore
  if str:find(pattern) ~= nil then return true end

  H.error_expect('string matching pattern ' .. vim.inspect(pattern), 'Observed string: ' .. str)
end

-- Helpers --------------------------------------------------------------------
--- Create child Neovim process
---
--- TODO: Write more documentation about:
--- - General approach: current and child processes "talk" with |RPC|, etc.
--- - Limitations: not being able to pass functions, "hanging" state while
---   waiting for user input (hit-enter-prompt, Operator-pending mode).
--- - Methods
---     - Job-related: `start`, `stop`, `restart`, etc.
---     - Wrappers for executing Lua inside child process: `api`, `fn`, `lsp`,
---       `loop`, etc.
---     - Wrappers: `type_keys()`, `is_blocking()` (also write about "blocking"
---       concept), etc.
---
---@usage
--- -- Initiate
--- local child = MiniTest.new_child_neovim()
--- child.start()
---
--- -- Use API functions
--- child.api.nvim_buf_set_lines(0, 0, -1, true, { 'This is inside child Neovim' })
---
--- -- Execute Lua code, commands, etc.
--- child.lua('_G.n = 0')
--- child.cmd('au CursorMoved * lua _G.n = _G.n + 1')
--- child.type_keys('l')
--- print(child.lua_get('_G.n')) -- Should be 1
---
--- -- Use other `vim.xxx` Lua wrappers (get executed inside child process)
--- vim.b.aaa = 'current process'
--- child.b.aaa = 'child process'
--- print(child.lua_get('vim.b.aaa')) -- Should be 'child process'
---
--- -- Stop
--- child.stop()
function MiniTest.new_child_neovim()
  local child = { address = vim.fn.tempname() }

  -- TODO:
  -- - Add some automated safety mechanism to prevent hanging child process.
  --   Something like timer checking if process is blocked.

  -- Start fully functional Neovim instance (not '--embed' or '--headless',
  -- because they don't provide full functionality)
  function child.start(args, opts)
    args = args or {}
    opts = vim.tbl_deep_extend('force', { nvim_executable = 'nvim', connection_timeout = 5000 }, opts or {})

    local t = { '--clean', '--listen', child.address }
    vim.list_extend(t, args)
    args = t

    -- Using 'libuv' for creating a job is crucial for getting this to work in
    -- Github Actions. Other approaches:
    -- - Use built-in `vim.fn.jobstart(args)`. Works locally but doesn't work
    --   in Github Action.
    -- - Use `plenary.job`. Works fine both locally and in Github Action, but
    --   needs a 'plenary.nvim' dependency (not exactly bad, but undesirable).
    local job = {}
    job.stdin, job.stdout, job.stderr = vim.loop.new_pipe(false), vim.loop.new_pipe(false), vim.loop.new_pipe(false)
    job.handle, job.pid = vim.loop.spawn(opts.nvim_executable, {
      stdio = { job.stdin, job.stdout, job.stderr },
      args = args,
    }, function() end)

    child.job = job
    child.start_args, child.start_opts = args, opts

    local step = 10
    local connected, i, max_tries = nil, 0, math.floor(opts.connection_timeout / step)
    repeat
      i = i + 1
      vim.loop.sleep(step)
      connected, child.channel = pcall(vim.fn.sockconnect, 'pipe', child.address, { rpc = true })
    until connected or i >= max_tries

    if not connected then
      vim.notify('Failed to make connection to child Neovim.')
      child.stop()
    end

    -- Enable method chaining
    return child
  end

  function child.stop()
    pcall(vim.fn.chanclose, child.channel)

    if child.job ~= nil then
      -- TODO: consider figuring out a way to do it better (should actually
      -- close/kill all child processes when running interactively)
      child.job.handle:kill(9)
      child.job = nil
    end

    -- Enable method chaining
    return child
  end

  function child.restart(args, opts)
    args = args or {}
    opts = vim.tbl_deep_extend('force', child.start_opts or {}, opts or {})

    if child.job ~= nil then
      child.stop()
    end

    child.address = vim.fn.tempname()
    child.start(args, opts)
  end

  -- Wrappers for common `vim.xxx` objects (will get executed inside child)
  child.api = setmetatable({}, {
    __index = function(_, key)
      return function(...)
        return vim.rpcrequest(child.channel, key, ...)
      end
    end,
  })

  -- Variant of `api` functions called with `vim.rpcnotify`. Useful for
  -- making blocking requests (like `getchar()`).
  child.api_notify = setmetatable({}, {
    __index = function(_, key)
      return function(...)
        return vim.rpcnotify(child.channel, key, ...)
      end
    end,
  })

  ---@return table Emulates `vim.xxx` table (like `vim.fn`)
  ---@private
  local forward_to_child = function(tbl_name)
    -- TODO: try to figure out the best way to operate on tables with function
    -- values (needs "deep encode/decode" of function objects)
    return setmetatable({}, {
      __index = function(_, key)
        local obj_name = ('vim[%s][%s]'):format(vim.inspect(tbl_name), vim.inspect(key))
        local value_type = child.api.nvim_exec_lua(('return type(%s)'):format(obj_name), {})

        if value_type == 'function' then
          -- This allows syntax like `child.fn.mode(1)`
          return function(...)
            return child.api.nvim_exec_lua(([[return %s(...)]]):format(obj_name), { ... })
          end
        end

        -- This allows syntax like `child.bo.buftype`
        return child.api.nvim_exec_lua(([[return %s]]):format(obj_name), {})
      end,
      __newindex = function(_, key, value)
        local obj_name = ('vim[%s][%s]'):format(vim.inspect(tbl_name), vim.inspect(key))
        -- This allows syntax like `child.b.aaa = function(x) return x + 1 end`
        -- (inherits limitations of `string.dump`: no upvalues, etc.)
        if type(value) == 'function' then
          local dumped = vim.inspect(string.dump(value))
          value = ('loadstring(%s)'):format(dumped)
        else
          value = vim.inspect(value)
        end

        child.api.nvim_exec_lua(('%s = %s'):format(obj_name, value), {})
      end,
    })
  end

  --stylua: ignore start
  local supported_vim_tables = {
    -- Collections
    'diagnostic', 'fn', 'highlight', 'json', 'loop', 'lsp', 'mpack', 'treesitter', 'ui',
    -- Variables
    'g', 'b', 'w', 't', 'v', 'env',
    -- Options (no 'opt' becuase not really usefult due to use of metatables)
    'o', 'go', 'bo', 'wo',
  }
  --stylua: ignore end
  for _, v in ipairs(supported_vim_tables) do
    child[v] = forward_to_child(v)
  end

  -- Convenience wrappers
  --- Type keys
  ---
  ---@param wait? number Number of milliseconds to wait after each entry.
  ---@param ... string|table<number, string> Separate entries for |nvim_input|, after
  ---   which `wait` will be applied. Can be either string or array of strings.
  ---
  ---@private
  function child.type_keys(wait, ...)
    local has_wait = type(wait) == 'number'
    local keys = has_wait and { ... } or { wait, ... }
    keys = vim.tbl_flatten(keys)

    for _, k in ipairs(keys) do
      if type(k) ~= 'string' then
        error('In `type_keys()` each argument should be either string or array of strings.')
      end

      -- From `nvim_input` docs: "On execution error: does not fail, but
      -- updates v:errmsg.". So capture it manually.
      local cur_errmsg
      -- But do that only if Neovim is not "blocking". Otherwise, usage of
      -- `child.v` will block execution.
      if not child.is_blocking() then
        cur_errmsg = child.v.errmsg
        child.v.errmsg = ''
      end

      -- Need to escape bare `<` (see `:h nvim_input`)
      child.api.nvim_input(k == '<' and '<LT>' or k)

      -- Possibly throw error manually
      if not child.is_blocking() then
        if child.v.errmsg ~= '' then
          error(child.v.errmsg, 2)
        else
          child.v.errmsg = cur_errmsg
        end
      end

      -- Possibly wait
      if has_wait and wait > 0 then
        child.loop.sleep(wait)
      end
    end
  end

  function child.cmd(str)
    return child.api.nvim_exec(str, false)
  end

  function child.cmd_capture(str)
    return child.api.nvim_exec(str, true)
  end

  function child.lua(str, args)
    return child.api.nvim_exec_lua(str, args or {})
  end

  function child.lua_notify(str, args)
    return child.api_notify.nvim_exec_lua(str, args or {})
  end

  function child.lua_get(str, args)
    return child.api.nvim_exec_lua('return ' .. str, args or {})
  end

  function child.is_blocking()
    return child.api.nvim_get_mode()['blocking']
  end

  -- Various wrappers
  function child.ensure_normal_mode()
    local cur_mode = child.fn.mode()

    -- Exit from Visual mode
    local ctrl_v = vim.api.nvim_replace_termcodes('<C-v>', true, true, true)
    if cur_mode == 'v' or cur_mode == 'V' or cur_mode == ctrl_v then
      child.type_keys(cur_mode)
      return
    end

    -- Exit from Terminal mode
    if cur_mode == 't' then
      child.type_keys([[<C-\>]], '<C-n>')
      return
    end

    -- Exit from other modes
    child.type_keys('<Esc>')
  end

  return child
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniTest.config

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    collect = { config.collect, 'table' },
    execute = { config.execute, 'table' },
    script_path = { config.script_path, 'string' },
  })

  vim.validate({
    ['collect.find_files'] = { config.collect.find_files, 'function' },
    ['collect.filter_cases'] = { config.collect.filter_cases, 'function' },

    ['execute.reporter'] = { config.execute.reporter, 'function' },
  })

  return config
end

function H.apply_config(config)
  MiniTest.config = config
end

function H.is_disabled()
  return vim.g.minitest_disable == true or vim.b.minitest_disable == true
end

-- Work with project specific script ==========================================
function H.execute_project_script(...)
  -- Don't process script if there are more than one active `run` calls
  if H.is_inside_script then
    return
  end

  -- Don't process script if at least one argument is not default (`nil`)
  if #{ ... } > 0 then
    return
  end

  -- Store information
  local config_cache = MiniTest.config

  -- Pass information to a possible `run()` call inside script
  H.is_inside_script = true

  -- Execute script
  local success = pcall(vim.cmd, 'luafile ' .. MiniTest.config.script_path)

  -- Restore information
  MiniTest.config = config_cache
  H.is_inside_script = nil

  return success
end

-- Works with test cases ------------------------------------------------------
---@class testcase
---
---@field args table Array of arguments with which `test` will be called.
---@field desc table Description: array of fields from nested testsets.
---@field hooks table Hooks to be executed as part of test case. Has fields
---   <pre> and <post> with arrays to be consecutively executed before and
---   after execution of `test`.
---@field info table? Information about test case execution. Value of `nil`
---   means that this particular case was not executed. Has following fields:
---     - <fails> - array of strings with failing information.
---     - <notes> - array of strings with non-failing information.
---     - <state> - state of test execution. One of:
---         - 'Executing <name of what is being executed>' (during execution).
---         - 'Pass' (no fails, no notes).
---         - 'Pass with notes' (no fails, some notes).
---         - 'Fail' (some fails, no notes).
---         - 'Fail with notes' (some fails, some notes).
---@field test function|table Main callable object representing test action.
---@field user table User data: array of `opts.user` from nested testsets.
---@private

--- Convert test set to array of test cases
---
---@return ... Tuple of aligned arrays: with test cases and hooks that should
---   be executed only once before corresponding item.
---@private
function H.set_to_testcases(set, template, hooks_once)
  template = template or { args = {}, desc = {}, hooks = { pre = {}, post = {} }, user = {} }
  hooks_once = hooks_once or { pre = {}, post = {} }

  local metatbl = getmetatable(set)
  local opts, key_order = metatbl.opts, metatbl.key_order
  local hooks, parametrize, user = opts.hooks or {}, opts.parametrize or { {} }, opts.user or {}

  -- Convert to steps only callable or test set nodes
  local node_keys = vim.tbl_filter(function(key)
    local node = set[key]
    return vim.is_callable(node) or H.is_testset(node)
  end, key_order)

  if #node_keys == 0 then
    return {}
  end

  -- Ensure that newly added hooks are represented by new functions.
  -- This is needed to count them later only within current set. Example: use
  -- the same function in several `_once` hooks. In `H.inject_hooks_once` it
  -- will be injected only once overall whereas it should be injected only once
  -- within corresponding test set.
  hooks_once = H.extend_hooks(
    hooks_once,
    { pre = H.wrap_callable(hooks.pre_once), post = H.wrap_callable(hooks.post_once) }
  )

  local testcase_arr, hooks_once_arr = {}, {}
  -- Process nodes in order they were added as `T[...] = x`
  for _, key in ipairs(node_keys) do
    local node = set[key]
    for _, args in ipairs(parametrize) do
      local cur_template = H.extend_template(template, {
        args = args,
        desc = key,
        hooks = { pre = hooks.pre_case, post = hooks.post_case },
        user = user,
      })

      if vim.is_callable(node) then
        table.insert(testcase_arr, H.new_testcase(cur_template, node))
        table.insert(hooks_once_arr, hooks_once)
      elseif H.is_testset(node) then
        local nest_testcase_arr, nest_hooks_once_arr = H.set_to_testcases(node, cur_template, hooks_once)
        vim.list_extend(testcase_arr, nest_testcase_arr)
        vim.list_extend(hooks_once_arr, nest_hooks_once_arr)
      end
    end
  end

  return testcase_arr, hooks_once_arr
end

function H.inject_hooks_once(cases, hooks_once)
  -- NOTE: this heavily relies on the equivalence of "have same object id" and
  -- "are same hooks"
  local already_injected = {}
  local n = #cases

  -- Inject 'pre' hooks moving forwards
  for i = 1, n do
    local case, hooks = cases[i], hooks_once[i].pre
    local target_tbl_id = 1
    for j = 1, #hooks do
      local h = hooks[j]
      if not already_injected[h] then
        table.insert(case.hooks.pre, target_tbl_id, h)
        target_tbl_id, already_injected[h] = target_tbl_id + 1, true
      end
    end
  end

  -- Inject 'post' hooks moving backwards
  for i = n, 1, -1 do
    local case, hooks = cases[i], hooks_once[i].post
    local target_table_id = #case.hooks.post + 1
    for j = #hooks, 1, -1 do
      local h = hooks[j]
      if not already_injected[h] then
        table.insert(case.hooks.post, target_table_id, h)
        already_injected[h] = true
      end
    end
  end

  return cases
end

function H.new_testcase(template, test)
  template.test = test
  return template
end

function H.extend_template(template, layer)
  local res = vim.deepcopy(template)

  vim.list_extend(res.args, layer.args)
  table.insert(res.desc, layer.desc)
  res.hooks = H.extend_hooks(res.hooks, layer.hooks, false)
  res.user = vim.tbl_deep_extend('force', res.user, layer.user)

  return res
end

function H.extend_hooks(hooks, layer, do_deepcopy)
  local res = hooks
  if do_deepcopy == nil or do_deepcopy then
    res = vim.deepcopy(hooks)
  end

  -- Closer (in terms of nesting) hooks should be closer to test callable
  if vim.is_callable(layer.pre) then
    table.insert(res.pre, layer.pre)
  end
  if vim.is_callable(layer.post) then
    table.insert(res.post, 1, layer.post)
  end

  return res
end

-- Reporters ------------------------------------------------------------------
-- function H.cases_to_lines(cases, opts)
--   opts = vim.tbl_deep_extend('force', { depth = 1 }, opts)
-- end

-- Predicates -----------------------------------------------------------------
function H.is_testset(x)
  local metatbl = getmetatable(x)
  return type(metatbl) == 'table' and metatbl.is_testset == true
end

-- Expectation utilities ------------------------------------------------------
function H.error_expect(cause, ...)
  local msg = string.format('Failed expectation for %s.\n%s', cause, table.concat({ ... }, '\n'))
  error(debug.traceback(msg, 3), 3)
end

-- Utilities ------------------------------------------------------------------
function H.message(msg)
  vim.cmd('echomsg ' .. vim.inspect('(mini.test) ' .. msg))
end

function H.error(msg)
  error(string.format('(mini.test) %s', msg))
end

function H.wrap_callable(f)
  if vim.is_callable(f) then
    --stylua: ignore
     return function(...) return f(...) end
  end
end

return MiniTest
