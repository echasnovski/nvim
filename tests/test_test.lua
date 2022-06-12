-- This is intended to mostly cover general API. In a sense, all tests in this
-- plugin also test 'mini.test'.
local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set, skip = MiniTest.new_set, MiniTest.skip

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('test', config) end
local unload_module = function() child.mini_unload('test') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

local get_ref_path = function(name)
  return string.format('tests/dir-test/testref_%s.lua', name)
end

local get_current_all_cases = function()
  -- Encode functions inside child. Works only for "simple" functions.
  local command = [[vim.tbl_map(function(case)
    case.hooks = { pre = vim.tbl_map(string.dump, case.hooks.pre), post = vim.tbl_map(string.dump, case.hooks.post) }
    case.test = string.dump(case.test)
    return case
  end, MiniTest.current.all_cases)]]
  local res = child.lua_get(command)

  -- Decode functions in current process
  res = vim.tbl_map(function(case)
    case.hooks = { pre = vim.tbl_map(loadstring, case.hooks.pre), post = vim.tbl_map(loadstring, case.hooks.post) }
    case.test = loadstring(case.test)
    return case
  end, res)

  -- Update array to enable getting element by last entry of `desc` field
  return setmetatable(res, {
    __index = function(t, key)
      return vim.tbl_filter(function(case_output)
        local last_desc = case_output.desc[#case_output.desc]
        return last_desc == key
      end, t)[1]
    end,
  })
end

local testrun_ref_file = function(name)
  local find_files_command = string.format([[_G.find_files = function() return { '%s' } end]], get_ref_path(name))
  child.lua(find_files_command)
  child.lua('MiniTest.run({ collect = { find_files = _G.find_files }, execute = { reporter = {} } })')
  return get_current_all_cases()
end

-- Output test set
T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniTest)'), 'table')

  -- Highlight groups
  expect.match(child.cmd_capture('hi MiniTestFail'), 'gui=bold')
  expect.match(child.cmd_capture('hi MiniTestPass'), 'gui=bold')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniTest.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value)
    eq(child.lua_get('MiniTest.config.' .. field), value)
  end

  expect_config('collect.emulate_busted', true)
  eq(child.lua_get('type(_G.MiniTest.config.collect.find_files)'), 'function')
  eq(child.lua_get('type(_G.MiniTest.config.collect.filter_cases)'), 'function')
  expect_config('execute.reporter', vim.NIL)
  expect_config('execute.stop_on_error', false)
  expect_config('script_path', 'scripts/minitest.lua')
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ script_path = 'a' })
  eq(child.lua_get('MiniTest.config.script_path'), 'a')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    local pattern = vim.pesc(name) .. '.*' .. vim.pesc(target_type)
    expect.error(load_module, pattern, config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ collect = 'a' }, 'collect', 'table')
  expect_config_error({ collect = { emulate_busted = 'a' } }, 'collect.emulate_busted', 'boolean')
  expect_config_error({ collect = { find_files = 'a' } }, 'collect.find_files', 'function')
  expect_config_error({ collect = { filter_cases = 'a' } }, 'collect.filter_cases', 'function')
  expect_config_error({ execute = 'a' }, 'execute', 'table')
  expect_config_error({ execute = { reporter = 'a' } }, 'execute.reporter', 'function')
  expect_config_error({ execute = { stop_on_error = 'a' } }, 'execute.stop_on_error', 'boolean')
  expect_config_error({ script_path = 1 }, 'script_path', 'string')
end

T['current'] = new_set()

T['current']['works'] = function()
  skip()
end

T['new_set()'] = new_set()

T['new_set()']['tracks field order'] = function()
  local res = testrun_ref_file('new-set')

  -- Check order
  --stylua: ignore
  local order_cases = vim.tbl_map(
    function(c) return c.desc[#c.desc] end,
    vim.tbl_filter(function(c) return c.desc[2] == 'order' end, res)
  )
  eq(order_cases, { 'From initial call', 'zzz First added', 'aaa Second added', 1 })
end

T['new_set()']['stores `opts`'] = function()
  local opts = { parametrize = { { 'a' } } }
  child.lua([[_G.set = MiniTest.new_set(...)]], { opts })
  eq(child.lua_get([[getmetatable(_G.set).opts]]), opts)
end

T['case helpers'] = new_set()

T['case helpers']['work'] = function()
  local res = testrun_ref_file('case-helpers')

  -- `finally()`
  eq(res['finally() with error; check'].exec.state, 'Pass')
  eq(res['finally() no error; check'].exec.state, 'Pass')

  -- `skip()`
  eq(res['skip(); no message'].exec.state, 'Pass with notes')
  eq(res['skip(); no message'].exec.notes, { 'Skip test' })

  eq(res['skip(); with message'].exec.state, 'Pass with notes')
  eq(res['skip(); with message'].exec.notes, { 'This is a custom skip message' })

  -- `add_note()`
  eq(res['add_note()'].exec.state, 'Pass with notes')
  eq(res['add_note()'].exec.notes, { 'This note should be appended' })
end

T['run()'] = new_set()

T['run()']['respects `opts` argument'] = function()
  child.lua([[MiniTest.run({ collect = { find_files = function() return {} end } })]])
  eq(#get_current_all_cases(), 0)
end

T['run()']['tries to execute script if no arguments are supplied'] = function()
  local script_path = get_ref_path('custom-script')
  child.lua('MiniTest.config.script_path = ' .. vim.inspect(script_path))

  eq(child.lua_get('_G.custom_script_result'), vim.NIL)
  child.lua('MiniTest.run()')
  eq(child.lua_get('_G.custom_script_result'), 'This actually ran')
end

T['run_file()'] = new_set()

T['run_file()']['works'] = function()
  child.lua([[MiniTest.run_file(...)]], { get_ref_path('run') })
  local last_desc = child.lua_get(
    [[vim.tbl_map(function(case) return case.desc[#case.desc] end, MiniTest.current.all_cases)]]
  )
  eq(last_desc, { 'run_at_location()', 'extra case' })
end

T['run_at_location()'] = new_set()

T['run_at_location()']['works with non-default input'] = new_set({ parametrize = { { 3 }, { 4 }, { 5 } } }, {
  function(line)
    local path = get_ref_path('run')
    local command = string.format([[MiniTest.run_at_location({ file = '%s', line = %s })]], path, line)
    child.lua(command)

    local all_cases = get_current_all_cases()
    eq(#all_cases, 1)
    eq(all_cases[1].desc, { path, 'run_at_location()' })
  end,
})

T['run_at_location()']['uses cursor position by default'] = function()
  local path = get_ref_path('run')
  child.cmd('edit ' .. path)
  set_cursor(4, 0)
  child.lua('MiniTest.run_at_location()')

  local all_cases = get_current_all_cases()
  eq(#all_cases, 1)
  eq(all_cases[1].desc, { path, 'run_at_location()' })
end

T['collect()'] = new_set()

T['collect()']['respects `emulate_busted` option'] = function()
  skip()
end

T['collect()']['respects `find_files` option'] = function()
  skip()
end

T['collect()']['respects `filter_cases` option'] = function()
  skip()
end

T['collect()']['handles `parametrize`'] = function()
  skip()
end

T['collect()']['handles `data`'] = function()
  skip()
end

T['collect()']['handles `hooks`'] = function()
  skip()
end

T['collect()']['handles same function in `*_case` hooks'] = function()
  skip()
end

T['execute()'] = new_set()

T['execute()']['works'] = function()
  skip()
end

T['execute()']['handles no cases'] = function()
  skip()
end

T['stop()'] = new_set()

T['stop()']['works'] = function()
  skip()
end

T['is_executing()'] = new_set()

T['is_executing()']['works'] = function()
  skip()
end

T['expect'] = new_set()

T['expect']['equality()'] = new_set()

T['expect']['equality()']['works'] = function()
  skip()
end

T['expect']['no_equality()'] = new_set()

T['expect']['no_equality()']['works'] = function()
  skip()
end

T['expect']['error()'] = new_set()

T['expect']['error()']['works'] = function()
  skip()
end

T['expect']['no_error()'] = new_set()

T['expect']['no_error()']['works'] = function()
  skip()
end

T['expect']['reference_screenshot()'] = new_set()

T['expect']['reference_screenshot()']['works'] = function()
  skip()
end

T['new_expectation()'] = new_set()

T['new_expectation()']['works'] = function()
  skip()
end

T['new_child_neovim()'] = new_set()

T['new_child_neovim()']['works'] = function()
  skip()
end

-- Integration tests ==========================================================
T['gen_reporter'] = new_set()

T['gen_reporter']['buffer'] = new_set()

T['gen_reporter']['buffer']['works'] = function()
  skip()
end

T['gen_reporter']['stdout'] = new_set()

T['gen_reporter']['stdout']['works'] = function()
  skip()
end

return T
