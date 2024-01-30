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
local mock_package = function() child.lua('MiniDeps.config.path.package = ' .. vim.inspect(test_dir_absolute)) end

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
  has_highlight('MiniDepsTitleError', 'links to Error')
  has_highlight('MiniDepsTitleSame', 'links to Title')
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
  load_module({ path = { package = test_dir_absolute } })
  eq(vim.startswith(child.o.packpath, test_dir_absolute), true)
end

T['setup()']['clears session'] = function()
  load_module({ path = { package = test_dir_absolute } })
  add('plugin_1')
  eq(#get_session(), 1)

  load_module({ path = { package = test_dir_absolute } })
  eq(#get_session(), 0)
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
  eq(child.lua_get('_G.log'), {})

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

T['Commands'][':DepsAdd'] = function() MiniTest.skip() end

return T
