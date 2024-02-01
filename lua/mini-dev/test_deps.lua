local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('deps', config) end
local unload_module = function() child.mini_unload('deps') end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

local test_dir = 'tests/dir-deps'
local test_dir_absolute = vim.fn.fnamemodify(test_dir, ':p'):gsub('(.)/$', '%1')

-- Common test helpers
local log_level = function(level) return child.lua_get('vim.log.levels.' .. level) end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local add = forward_lua('MiniDeps.add')
local get_session = forward_lua('MiniDeps.get_session')

-- Common mocks
local mock_test_package = function(path)
  path = path or test_dir_absolute
  local lua_cmd = string.format(
    [[local config = vim.deepcopy(MiniDeps.config)
      config.path.package = %s
      MiniDeps.setup(config)]],
    vim.inspect(path)
  )
  child.lua(lua_cmd)
end

local mock_temp_plugin = function(path)
  MiniTest.finally(function() child.fn.delete(path, 'rf') end)
  local lua_dir = path .. '/lua'
  child.fn.mkdir(lua_dir, 'p')
  child.fn.writefile({ 'return {}' }, lua_dir .. '/module.lua')
end

-- Work with notifications
local mock_notify = function()
  child.lua([[
    _G.notify_log = {}
    vim.notify = function(...) table.insert(_G.notify_log, { ... }) end
  ]])
end

local get_notify_log = function() return child.lua_get('_G.notify_log') end

local validate_notifications = function(ref)
  local log = get_notify_log()
  eq(#log, #ref)
  for i = 1, #ref do
    expect.match(log[i][1], ref[i][1])
    eq(log[i][2], log_level(ref[i][2]))
  end
end

local clear_notify_log = function() return child.lua('_G.notify_log = {}') end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()

      -- Load module
      load_module()

      -- Make more comfortable screenshots
      child.set_size(7, 45)
      child.o.laststatus = 0
      child.o.ruler = false
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniDeps)'), 'table')

  -- User commands
  local has_user_command = function(cmd) eq(child.fn.exists(':' .. cmd), 2) end
  has_user_command('DepsAdd')
  has_user_command('DepsUpdate')
  has_user_command('DepsUpdateOffline')
  has_user_command('DepsShowLog')
  has_user_command('DepsClean')
  has_user_command('DepsSnapSave')
  has_user_command('DepsSnapLoad')

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniDepsChangeAdded', 'links to diffAdded')
  has_highlight('MiniDepsChangeRemoved', 'links to diffRemoved')
  has_highlight('MiniDepsHint', 'links to DiagnosticHint')
  has_highlight('MiniDepsInfo', 'links to DiagnosticInfo')
  has_highlight('MiniDepsPlaceholder', 'links to Comment')
  has_highlight('MiniDepsTitle', 'links to Title')
  has_highlight('MiniDepsTitleError', 'links to DiffDelete')
  has_highlight('MiniDepsTitleSame', 'links to DiffText')
  has_highlight('MiniDepsTitleUpdate', 'links to DiffAdd')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniDeps.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniDeps.config.' .. field), value) end

  expect_config('job.n_threads', vim.NIL)
  expect_config('job.timeout', 30000)

  expect_config('path.package', child.fn.stdpath('data') .. '/site')
  expect_config('path.snapshot', child.fn.stdpath('config') .. '/mini-deps-snap')
  expect_config('path.log', child.fn.stdpath(child.fn.has('nvim-0.8') == 1 and 'state' or 'data') .. '/mini-deps.log')

  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ silent = true })
  eq(child.lua_get('MiniDeps.config.silent'), true)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ job = 'a' }, 'job', 'table')
  expect_config_error({ job = { n_threads = 'a' } }, 'job.n_threads', 'number')
  expect_config_error({ job = { timeout = 'a' } }, 'job.timeout', 'number')

  expect_config_error({ path = 'a' }, 'path', 'table')
  expect_config_error({ path = { package = 1 } }, 'path.package', 'string')
  expect_config_error({ path = { snapshot = 1 } }, 'path.snapshot', 'string')
  expect_config_error({ path = { log = 1 } }, 'path.log', 'string')

  expect_config_error({ silent = 'a' }, 'silent', 'boolean')
end

T['setup()']["prepends 'packpath' with package path"] = function()
  mock_test_package(test_dir_absolute)
  eq(vim.startswith(child.o.packpath, test_dir_absolute), true)
end

T['setup()']['clears session'] = function()
  load_module({ path = { package = test_dir_absolute } })
  add('plugin_1')
  eq(#get_session(), 1)

  load_module({ path = { package = test_dir_absolute } })
  eq(#get_session(), 0)
end

T['add()'] = new_set({ hooks = { pre_case = mock_test_package } })

T['add()']['works for present plugins'] = new_set({ parametrize = { { 'plugin_1' }, { { name = 'plugin_1' } } } }, {
  test = function(spec)
    local ref_path = test_dir_absolute .. '/pack/deps/opt/plugin_1'
    expect.no_match(child.o.runtimepath, vim.pesc(ref_path))
    eq(get_session(), {})

    add(spec)

    expect.match(child.o.runtimepath, vim.pesc(ref_path))
    eq(get_session(), { { name = 'plugin_1', path = ref_path, hooks = {}, depends = {} } })
  end,
})

T['add()']['infers name from source'] = new_set({
  parametrize = {
    { 'user/plugin_1' },
    { 'https://github.com/user/plugin_1' },
    { { source = 'user/plugin_1' } },
    { { source = 'https://github.com/user/plugin_1' } },
  },
}, {
  test = function(spec)
    local ref_path = test_dir_absolute .. '/pack/deps/opt/plugin_1'
    add(spec)
    expect.match(child.o.runtimepath, vim.pesc(ref_path))
    eq(
      get_session(),
      { { source = 'https://github.com/user/plugin_1', name = 'plugin_1', path = ref_path, hooks = {}, depends = {} } }
    )
  end,
})

T['add()']['can update session data'] = function()
  local opt_dir = test_dir_absolute .. '/pack/deps/opt'
  add('plugin_1')
  add('plugin_2')
  eq(get_session(), {
    { path = opt_dir .. '/plugin_1', name = 'plugin_1', depends = {}, hooks = {} },
    { path = opt_dir .. '/plugin_2', name = 'plugin_2', depends = {}, hooks = {} },
  })

  add({ source = 'my_source', name = 'plugin_1' })
  add({ name = 'plugin_2', depends = { 'plugin_3' } })
  eq(get_session(), {
    { path = opt_dir .. '/plugin_1', name = 'plugin_1', source = 'my_source', depends = {}, hooks = {} },
    { path = opt_dir .. '/plugin_2', name = 'plugin_2', depends = { 'plugin_3' }, hooks = {} },
    { path = opt_dir .. '/plugin_3', name = 'plugin_3', depends = {}, hooks = {} },
  })

  child.lua([[
    MiniDeps.add({ name = 'plugin_3', hooks = { post_update = function() return 'Hello' end } })
    _G.hello = MiniDeps.get_session()[3].hooks.post_update()
  ]])
  eq(child.lua_get('_G.hello'), 'Hello')
end

T['add()']['respects plugins from "start" directory'] = function()
  local start_dir = test_dir_absolute .. '/pack/deps/start'
  mock_temp_plugin(start_dir .. '/plug')
  MiniTest.finally(function() child.fn.delete(start_dir, 'rf') end)
  mock_test_package(test_dir_absolute)

  add('user/plug')
  eq(get_session(), {
    { path = start_dir .. '/plug', name = 'plug', source = 'https://github.com/user/plug', hooks = {}, depends = {} },
  })

  MiniTest.skip('Should test that installation was not done. I.e. mock Git and test that it was not called.')
end

T['add()']['normalizes specification'] = function() MiniTest.skip() end

T['add()']['validates_specification'] = function() MiniTest.skip() end

T['add()']['allows nested dependencies'] = function() MiniTest.skip() end

T['add()']['validates `opts`'] = function()
  expect.error(function() add('plugin_1', 'a') end, '`opts`.*table')
  expect.error(function() add('plugin_1', { checkout = 'branch' }) end, '`add%(%)`.*single spec')
end

T['add()']['Install'] = new_set()

T['add()']['Install']['works'] = function() MiniTest.skip() end

T['add()']['Install']['properly executes hooks'] = function()
  -- Including when installing dependencies
  MiniTest.skip()
end

T['add()']['Install']['works with absent package directory'] = function() MiniTest.skip() end

T['add()']['Install']['does not affect newly added session data'] = function()
  -- Basically, does not add `job` field
  MiniTest.skip()
end

T['update()'] = new_set()

local update = forward_lua('MiniDeps.update')

T['update()']['works'] = function() MiniTest.skip() end

T['clean()'] = new_set()

local clean = forward_lua('MiniDeps.clean')

T['clean()']['works'] = function() MiniTest.skip() end

T['snap_get()'] = new_set()

local snap_get = forward_lua('MiniDeps.snap_get')

T['snap_get()']['works'] = function() MiniTest.skip() end

T['snap_set()'] = new_set()

local snap_set = forward_lua('MiniDeps.snap_set')

T['snap_set()']['works'] = function() MiniTest.skip() end

T['snap_load()'] = new_set()

local snap_load = forward_lua('MiniDeps.snap_load')

T['snap_load()']['works'] = function() MiniTest.skip() end

T['snap_save()'] = new_set()

local snap_save = forward_lua('MiniDeps.snap_save')

T['snap_save()']['works'] = function() MiniTest.skip() end

T['get_session()'] = new_set({ hooks = { pre_case = mock_test_package } })

T['get_session()']['works'] = function()
  local opt_dir = test_dir_absolute .. '/pack/deps/opt'

  add('plugin_1')
  add({ source = 'https://my_site.com/plugin_2', depends = { 'user/plugin_3' } })
  eq(get_session(), {
    { path = opt_dir .. '/plugin_1', name = 'plugin_1', depends = {}, hooks = {} },
    {
      path = opt_dir .. '/plugin_3',
      name = 'plugin_3',
      source = 'https://github.com/user/plugin_3',
      depends = {},
      hooks = {},
    },
    {
      path = opt_dir .. '/plugin_2',
      name = 'plugin_2',
      source = 'https://my_site.com/plugin_2',
      depends = { 'user/plugin_3' },
      hooks = {},
    },
  })
end

T['get_session()']['works even after several similar `add()`'] = function()
  add({ source = 'user/plugin_1', checkout = 'hello', depends = { 'plugin_2' } })
  -- Every extra adding should override previous but only new data fields
  add({ name = 'plugin_1', checkout = 'hello' })
  add({ name = 'plugin_2', checkout = 'world' })
  add({ source = 'https://my_site.com/plugin_1', depends = { 'plugin_3' } })

  local opt_dir = test_dir_absolute .. '/pack/deps/opt'
  eq(get_session(), {
    { path = opt_dir .. '/plugin_2', name = 'plugin_2', depends = {}, hooks = {}, checkout = 'world' },
    {
      path = opt_dir .. '/plugin_1',
      name = 'plugin_1',
      source = 'https://my_site.com/plugin_1',
      -- Although both 'plugin_2' and 'plugin_3' are in dependencies,
      -- 'plugin_1' was added only indicating 'plugin_2' as dependency, so it
      -- only has it in session before itself.
      depends = { 'plugin_2', 'plugin_3' },
      hooks = {},
      checkout = 'hello',
    },
    { path = opt_dir .. '/plugin_3', name = 'plugin_3', depends = {}, hooks = {} },
  })
end

T['get_session()']["respects plugins from 'start' directory which are in 'runtimepath'"] = function()
  local start_dir = test_dir_absolute .. '/pack/deps/start'
  mock_temp_plugin(start_dir .. '/start')
  mock_temp_plugin(start_dir .. '/start_manual')
  mock_temp_plugin(start_dir .. '/start_manual_dependency')
  mock_temp_plugin(start_dir .. '/start_not_in_rtp')
  MiniTest.finally(function() child.fn.delete(start_dir, 'rf') end)
  mock_test_package(test_dir_absolute)

  -- Make sure that only somem of 'start' plugins are in 'runtimepath'
  local lua_cmd = string.format(
    'vim.api.nvim_list_runtime_paths = function() return { %s, %s, %s } end',
    vim.inspect(start_dir .. '/start_manual'),
    vim.inspect(start_dir .. '/start_manual_dependency'),
    vim.inspect(start_dir .. '/start')
  )
  child.lua(lua_cmd)

  -- Add some plugins manually both from 'opt' and 'start' directories
  add('plugin_1')
  add({ source = 'user/start_manual', depends = { 'start_manual_dependency' } })

  eq(get_session(), {
    -- Should add plugins from "start" *after* manually added ones
    { path = test_dir_absolute .. '/pack/deps/opt/plugin_1', name = 'plugin_1', depends = {}, hooks = {} },

    -- Should not affect or duplicate already manually added ones
    { path = start_dir .. '/start_manual_dependency', name = 'start_manual_dependency', depends = {}, hooks = {} },

    {
      path = start_dir .. '/start_manual',
      name = 'start_manual',
      source = 'https://github.com/user/start_manual',
      depends = { 'start_manual_dependency' },
      hooks = {},
    },

    { path = start_dir .. '/start', name = 'start', depends = {}, hooks = {} },
  })
end

T['now()'] = new_set()

T['now()']['works'] = function()
  -- Should execute input right now
  child.lua([[
    _G.log = {}
    MiniDeps.now(function() log[#log + 1] = 'now' end)
    log[#log + 1] = 'after now'
  ]])
  eq(child.lua_get('_G.log'), { 'now', 'after now' })
end

T['now()']['can be called inside other `now()`/`later()` call'] = function()
  child.lua([[
    _G.log = {}
    MiniDeps.now(function()
      log[#log + 1] = 'now'
      MiniDeps.now(function() log[#log + 1] = 'now_now' end)
    end)
    MiniDeps.later(function()
      log[#log + 1] = 'later'
      MiniDeps.now(function() log[#log + 1] = 'later_now' end)
    end)
  ]])
  eq(child.lua_get('_G.log'), { 'now', 'now_now' })

  sleep(10)
  eq(child.lua_get('_G.log'), { 'now', 'now_now', 'later', 'later_now' })
end

T['now()']['clears queue betwenn different event loops'] = function()
  child.lua([[
    _G.log = {}
    _G.f = function() log[#log + 1] = 'now' end
    MiniDeps.now(_G.f)
  ]])
  eq(child.lua_get('_G.log'), { 'now' })

  sleep(2)
  child.lua('MiniDeps.now(_G.f)')
  -- If it did not clear the queue, it would have been 3 elements
  eq(child.lua_get('_G.log'), { 'now', 'now' })
end

T['now()']['notifies about errors after everything is executed'] = function()
  mock_notify()
  child.lua([[
    _G.log = {}
    MiniDeps.now(function() error('Inside now()') end)
    _G.f = function() log[#log + 1] = 'later' end
    MiniDeps.later(_G.f)
    MiniDeps.later(_G.f)
    MiniDeps.later(_G.f)
    MiniDeps.later(_G.f)
    MiniDeps.later(_G.f)
  ]])

  sleep(1)
  validate_notifications({})

  sleep(10)
  eq(child.lua_get('_G.log'), { 'later', 'later', 'later', 'later', 'later' })
  validate_notifications({ { 'errors.*Inside now()', 'ERROR' } })
end

T['now()']['shows all errors at once'] = function()
  mock_notify()
  child.lua([[
    MiniDeps.now(function() error('Inside now() #1') end)
    MiniDeps.now(function() error('Inside now() #2') end)
  ]])
  sleep(2)
  validate_notifications({ { 'errors.*Inside now%(%) #1.*Inside now%(%) #2', 'ERROR' } })
end

T['now()']['does not respect `config.silent`'] = function()
  -- Should still show errors even if `config.silent = true`
  child.lua('MiniDeps.config.silent = true')
  mock_notify()
  child.lua('MiniDeps.now(function() error("Inside now()") end)')
  sleep(2)
  validate_notifications({ { 'Inside now%(%)', 'ERROR' } })
end

T['later()'] = new_set()

T['later()']['works'] = function()
  -- Should execute input later without blocking
  child.lua([[
    _G.log = {}
    MiniDeps.later(function() log[#log + 1] = 'later' end)
    log[#log + 1] = 'after later'
    _G.log_in_this_loop = vim.deepcopy(_G.log)
  ]])
  eq(child.lua_get('_G.log_in_this_loop'), { 'after later' })

  sleep(2)
  eq(child.lua_get('_G.log'), { 'after later', 'later' })
end

T['later()']['can be called inside other `now()`/`later()` call'] = function()
  child.lua([[
    _G.log = {}
    MiniDeps.later(function()
      log[#log + 1] = 'later'
      MiniDeps.later(function() log[#log + 1] = 'later_later' end)
    end)
    MiniDeps.now(function()
      log[#log + 1] = 'now'
      MiniDeps.later(function() log[#log + 1] = 'now_later' end)
    end)
  ]])
  eq(child.lua_get('_G.log'), { 'now' })

  sleep(10)
  eq(child.lua_get('_G.log'), { 'now', 'later', 'now_later', 'later_later' })
end

T['later()']['clears queue betwenn different event loops'] = function()
  child.lua([[
    _G.log = {}
    _G.f = function() log[#log + 1] = 'later' end
    MiniDeps.later(_G.f)
  ]])
  eq(child.lua_get('_G.log'), {})
  sleep(2)
  eq(child.lua_get('_G.log'), { 'later' })

  child.lua('MiniDeps.later(_G.f)')
  -- If it did not clear the queue, it would have been 3 elements
  sleep(4)
  eq(child.lua_get('_G.log'), { 'later', 'later' })
end

T['later()']['notifies about errors after everything is executed'] = function()
  mock_notify()
  child.lua([[
    _G.log = {}
    MiniDeps.later(function() error('Inside later()') end)
    _G.f = function() log[#log + 1] = 'later' end
    MiniDeps.later(_G.f)
    MiniDeps.later(_G.f)
    MiniDeps.later(_G.f)
    MiniDeps.later(_G.f)
    MiniDeps.later(_G.f)
  ]])
  eq(child.lua_get('_G.log'), {})

  sleep(1)
  validate_notifications({})

  sleep(10)
  eq(child.lua_get('_G.log'), { 'later', 'later', 'later', 'later', 'later' })
  validate_notifications({ { 'errors.*Inside later()', 'ERROR' } })
end

T['later()']['shows all errors at once'] = function()
  mock_notify()
  child.lua([[
    MiniDeps.later(function() error('Inside later() #1') end)
    MiniDeps.later(function() error('Inside later() #2') end)
  ]])
  sleep(5)
  validate_notifications({ { 'errors.*Inside later%(%) #1.*Inside later%(%) #2', 'ERROR' } })
end

T['later()']['does not respect `config.silent`'] = function()
  -- Should still show errors even if `config.silent = true`
  child.lua('MiniDeps.config.silent = true')
  mock_notify()
  child.lua('MiniDeps.later(function() error("Inside later()") end)')
  sleep(2)
  validate_notifications({ { 'Inside later%(%)', 'ERROR' } })
end

-- Integration tests ----------------------------------------------------------
T['Commands'] = new_set()

T['Commands'][':DepsAdd'] = new_set()

T['Commands'][':DepsAdd']['works'] = function() MiniTest.skip() end

T['Commands'][':DepsUpdate'] = new_set()

T['Commands'][':DepsUpdate']['works'] = function() MiniTest.skip() end

T['Commands'][':DepsUpdateOffline'] = new_set()

T['Commands'][':DepsUpdateOffline']['works'] = function() MiniTest.skip() end

T['Commands'][':DepsShowLog'] = new_set()

T['Commands'][':DepsShowLog']['works'] = function() MiniTest.skip() end

T['Commands'][':DepsClean'] = new_set()

T['Commands'][':DepsClean']['works'] = function() MiniTest.skip() end

T['Commands'][':DepsSnapSave'] = new_set()

T['Commands'][':DepsSnapSave']['works'] = function() MiniTest.skip() end

T['Commands'][':DepsSnapLoad'] = new_set()

T['Commands'][':DepsSnapLoad']['works'] = function() MiniTest.skip() end

return T
