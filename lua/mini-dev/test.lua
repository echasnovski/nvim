-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- Documentation ==============================================================
--- Extensible module for writing Neovim plugin tests.
---
--- Planned features:
--- - "Collect and execute" design.
--- - The `test_set` (table with executable elements at matching fields) and
---   `test_step` (those fields after flattening along with hooks and spreading
---   params).
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
    filter_steps = function(step) return true end,
  },

  -- Options controlling execution of test cases
  execute = {},
}
--minidoc_afterlines_end
--stylua: ignore end

-- Module functionality =======================================================
function MiniTest.collect(opts)
  opts = vim.tbl_deep_extend('force', MiniTest.config.collect, opts or {})
  local set = MiniTest.new_test_set()
  for _, file in ipairs(opts.find_files()) do
    local ok, t = pcall(dofile, file)
    if not ok then
      H.error([[Can't source file ]] .. vim.inspect(file))
    end
    if not H.is_test_set(t) then
      local msg = string.format(
        [[Output of %s is not a test set. Did you use `MiniTest.new_test_set()`?]],
        vim.inspect(file)
      )
      H.error(msg)
    end

    set[file] = t
  end

  local steps = H.set_to_steps(set)

  steps = vim.tbl_filter(MiniTest.config.collect.filter_steps, steps)

  -- TODO: Remove redundant hooks (for example, if all cases from nested test
  -- set are filtered out)

  return steps
end
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
      child.job.stdin:close()
      child.job.stdout:close()
      child.job.stderr:close()

      -- Use `pcall` to not error with `channel closed by client`
      pcall(child.cmd, '0cquit!')
      child.job.handle:kill()
      child.job.handle:close()

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

--- Create test set
---
---@param opts? table Allowed options:
---   - <hooks> - table with fields:
---       - <pre_first> - before first filtered node.
---       - <pre_node> - before each node.
---       - <pre_case> - before each case (even nested).
---       - <post_case> - after each case (even nested).
---       - <post_node> - after each node.
---       - <post_last> - after last filtered node.
---   - <parametrize> - array where each element is a table of parameters to be
---     appended to "current parameters" of executable fields.
---   - <user> - user data to be forwarded to steps.
function MiniTest.new_test_set(opts)
  -- Keep track of new elements order. This allows to iterate through elements
  -- in order they were added.
  local metatbl = { is_test_set = true, key_order = {}, opts = opts or {} }
  metatbl.__newindex = function(tbl, key, value)
    table.insert(metatbl.key_order, key)
    rawset(tbl, key, value)
  end

  return setmetatable({}, metatbl)
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
  })

  vim.validate({
    ['collect.find_files'] = { config.collect.find_files, 'function' },
    ['collect.filter_steps'] = { config.collect.filter_steps, 'function' },
  })

  return config
end

function H.apply_config(config)
  MiniTest.config = config
end

function H.is_disabled()
  return vim.g.minitest_disable == true or vim.b.minitest_disable == true
end

-- Works with steps -----------------------------------------------------------
function H.set_to_steps(set, data, case_hooks)
  data = data or { desc = {}, params = {}, user = {} }
  case_hooks = case_hooks or { pre = {}, post = {} }

  local metatbl = getmetatable(set)
  local opts, key_order = metatbl.opts, metatbl.key_order
  local hooks, parametrize, user = opts.hooks or {}, opts.parametrize or { {} }, opts.user or {}

  -- Convert to steps only executable or test set nodes
  local node_keys = vim.tbl_filter(function(key)
    local node = set[key]
    return H.is_executable(node) or H.is_test_set(node)
  end, key_order)

  if #node_keys == 0 then
    return {}
  end

  -- Start adding steps
  case_hooks = H.nest_case_hooks(case_hooks, { pre = hooks.pre_case, post = hooks.post_case }, data)
  local steps = {}
  local add_step = function(f, d, exec_type)
    local step = H.new_step(f, d, exec_type)
    --stylua: ignore
    if step == nil then return end
    table.insert(steps, H.new_step(f, d, exec_type))
  end

  add_step(hooks.pre_first, data, 'hook_pre_first')

  -- Process nodes in order they were added as `T[...] = x`
  for _, key in ipairs(node_keys) do
    local node = set[key]
    for _, params in ipairs(parametrize) do
      local node_data = H.nest_step_data(data, { desc = key, params = params, user = user })

      add_step(hooks.pre_node, node_data, 'hook_pre_node')

      if H.is_executable(node) then
        vim.list_extend(steps, case_hooks.pre)
        add_step(node, node_data, 'case')
        vim.list_extend(steps, case_hooks.post)
      elseif H.is_test_set(node) then
        vim.list_extend(steps, H.set_to_steps(node, node_data, case_hooks))
      end

      add_step(hooks.post_node, node_data, 'hook_post_node')
    end
  end

  add_step(hooks.post_last, data, 'hook_post_last')

  return steps
end

function H.new_step(executable, data, exec_type)
  --stylua: ignore
  if not H.is_executable(executable) then return end

  local res = vim.deepcopy(data)
  res.executable = executable
  res.type = exec_type
  return res
end

function H.nest_step_data(data, new_data)
  local res = vim.deepcopy(data)

  table.insert(res.desc, new_data.desc)
  vim.list_extend(res.params, new_data.params)
  table.insert(res.user, new_data.user)

  return res
end

function H.nest_case_hooks(case_hooks, new_case_hooks, data)
  local res = vim.deepcopy(case_hooks)

  if H.is_executable(new_case_hooks.pre) then
    local step = H.new_step(new_case_hooks.pre, data, 'hook_pre_case')
    table.insert(res.pre, step)
  end

  if H.is_executable(new_case_hooks.post) then
    local step = H.new_step(new_case_hooks.post, data, 'hook_post_case')
    -- Closer (in terms of nesting) hooks should be closer to test case
    table.insert(res.post, 1, step)
  end

  return res
end

-- Predicates -----------------------------------------------------------------
function H.is_test_set(x)
  local metatbl = getmetatable(x)
  return type(metatbl) == 'table' and metatbl.is_test_set == true
end

function H.is_executable(x)
  return type(x) == 'function' or (getmetatable(x) or {}).__call ~= nil
end

-- Utilities ------------------------------------------------------------------
function H.message(msg)
  vim.cmd('echomsg ' .. vim.inspect('(mini.test) ' .. msg))
end

function H.error(msg)
  error(string.format('(mini.test) %s', msg))
end
