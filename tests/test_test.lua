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

local filter_by_desc = function(cases, id, value)
  return vim.tbl_filter(function(c)
    return c.desc[id] == value
  end, cases)
end

local expect_all_state = function(cases, state)
  local res = true
  for _, c in ipairs(cases) do
    if type(c.exec) ~= 'table' or c.exec.state ~= state then
      res = false
    end
  end

  eq(res, true)
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

T['run()']['handles `parametrize`'] = function()
  local res = testrun_ref_file('run-parametrize')
  eq(#res, 10)

  local short_res = vim.tbl_map(function(c)
    local desc = vim.list_slice(c.desc, 2)
    return { args = c.args, desc = desc, passed_args = c.exec.fails[1]:match('Passed arguments: (.*)$') }
  end, res)

  eq(short_res[1], { args = { 'a' }, desc = { 'parametrize', 'first level' }, passed_args = '"a"' })
  eq(short_res[2], { args = { 'b' }, desc = { 'parametrize', 'first level' }, passed_args = '"b"' })

  eq(short_res[3], { args = { 'a', 1 }, desc = { 'parametrize', 'nested', 'test' }, passed_args = '"a", 1' })
  eq(short_res[4], { args = { 'a', 2 }, desc = { 'parametrize', 'nested', 'test' }, passed_args = '"a", 2' })
  eq(short_res[5], { args = { 'b', 1 }, desc = { 'parametrize', 'nested', 'test' }, passed_args = '"b", 1' })
  eq(short_res[6], { args = { 'b', 2 }, desc = { 'parametrize', 'nested', 'test' }, passed_args = '"b", 2' })

  --stylua: ignore start
  eq(short_res[7],  { args = { 'a', 'a', 1, 1 }, desc = { 'multiple args', 'nested', 'test' }, passed_args = '"a", "a", 1, 1' })
  eq(short_res[8],  { args = { 'a', 'a', 2, 2 }, desc = { 'multiple args', 'nested', 'test' }, passed_args = '"a", "a", 2, 2' })
  eq(short_res[9],  { args = { 'b', 'b', 1, 1 }, desc = { 'multiple args', 'nested', 'test' }, passed_args = '"b", "b", 1, 1' })
  eq(short_res[10], { args = { 'b', 'b', 2, 2 }, desc = { 'multiple args', 'nested', 'test' }, passed_args = '"b", "b", 2, 2' })
  --stylua: ignore end
end

T['run()']['handles `data`'] = function()
  local res = testrun_ref_file('run-data')
  local short_res = vim.tbl_map(function(c)
    return { data = c.data, desc = vim.list_slice(c.desc, 2) }
  end, res)

  eq(#short_res, 2)
  eq(short_res[1], {
    data = { a = 1, b = 2 },
    desc = { 'data', 'first level' },
  })
  eq(short_res[2], {
    data = { a = 10, b = 2, c = 30 },
    desc = { 'data', 'nested', 'should override' },
  })
end

T['run()']['handles `hooks`'] = function()
  local res = testrun_ref_file('run-hooks')
  local order_cases = vim.tbl_map(function(c)
    return {
      desc = vim.list_slice(c.desc, 2),
      fails = c.exec.fails,
      n_hooks = { pre = #c.hooks.pre, post = #c.hooks.post },
    }
  end, filter_by_desc(res, 2, 'order'))

  eq(order_cases[1], {
    desc = { 'order', 'first level' },
    fails = { 'pre_once_1', 'pre_case_1', 'First level test', 'post_case_1' },
    n_hooks = { pre = 2, post = 1 },
  })
  eq(order_cases[2], {
    desc = { 'order', 'nested', 'first' },
    fails = { 'pre_once_2', 'pre_case_1', 'pre_case_2', 'Nested #1', 'post_case_2', 'post_case_1' },
    n_hooks = { pre = 3, post = 2 },
  })
  eq(order_cases[3], {
    desc = { 'order', 'nested', 'second' },
    fails = { 'pre_case_1', 'pre_case_2', 'Nested #2', 'post_case_2', 'post_case_1', 'post_once_2', 'post_once_1' },
    n_hooks = { pre = 2, post = 4 },
  })
end

T['run()']['handles same function in `*_once` hooks'] = function()
  local res = testrun_ref_file('run-hooks')
  local case = filter_by_desc(res, 2, 'same `*_once` hooks')[1]

  -- The fact that it was called 4 times indicates that using same function in
  -- `*_once` hooks leads to its correct multiple execution
  eq(case.exec.fails, { 'Same function', 'Same function', 'Same hook test', 'Same function', 'Same function' })
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

local collect_general = function()
  local path = get_ref_path('general')
  local command = string.format([[_G.cases = MiniTest.collect({ find_files = function() return { '%s' } end })]], path)
  child.lua(command)
end

T['collect()'] = new_set()

T['collect()']['works'] = function()
  child.lua('_G.cases = MiniTest.collect()')

  -- Should return array of cases
  eq(child.lua_get('vim.tbl_islist(_G.cases)'), true)

  local keys = child.lua_get('vim.tbl_keys(_G.cases[1])')
  table.sort(keys)
  eq(keys, { 'args', 'data', 'desc', 'hooks', 'test' })
end

T['collect()']['respects `emulate_busted` option'] = function()
  local res = testrun_ref_file('collect-busted')

  -- All descriptions should be prepended with file name
  eq(#filter_by_desc(res, 1, get_ref_path('collect-busted')), #res)

  -- `describe()/it()`
  eq(#filter_by_desc(res, 2, 'describe()/it()'), 3)

  -- `setup()/teardown()`
  expect_all_state(filter_by_desc(res, 2, 'setup()/teardown()'), 'Pass')

  -- `before_each()/after_each()`
  expect_all_state(filter_by_desc(res, 2, 'before_each()/after_each()'), 'Pass')

  -- `MiniTest.skip()`
  expect_all_state(filter_by_desc(res, 2, 'MiniTest.skip()'), 'Pass with notes')

  -- `MiniTest.finally()`
  local cases_finally = filter_by_desc(res, 2, 'MiniTest.finally()')
  -- all_have_state(filter_by_desc(cases_finally, 3, 'works with no error'))
  expect_all_state(filter_by_desc(cases_finally, 3, 'works with no error'), 'Pass')
  expect_all_state(filter_by_desc(cases_finally, 3, 'works with error'), 'Pass')
end

T['collect()']['respects `find_files` option'] = function()
  local command = string.format(
    [[_G.cases = MiniTest.collect({ find_files = function() return { '%s' } end })]],
    get_ref_path('general')
  )
  child.lua(command)
  eq(child.lua_get('#_G.cases'), 2)
  eq(child.lua_get('_G.cases[1].desc[1]'), 'tests/dir-test/testref_general.lua')
end

T['collect()']['respects `filter_cases` option'] = function()
  local command = string.format(
    [[_G.cases = MiniTest.collect({
      find_files = function() return { '%s' } end,
      filter_cases = function(case) return case.desc[2] == 'case 2' end,
    })]],
    get_ref_path('general')
  )
  child.lua(command)

  eq(child.lua_get('#_G.cases'), 1)
  eq(child.lua_get('_G.cases[1].desc[2]'), 'case 2')
end

T['execute()'] = new_set()

T['execute()']['respects `reporter` option'] = new_set()

T['execute()']['respects `reporter` option']['empty'] = function()
  collect_general()
  child.lua('MiniTest.execute(_G.cases, { reporter = {} })')
end

T['execute()']['respects `reporter` option']['partial'] = function()
  collect_general()
  child.lua([[MiniTest.execute(
    _G.cases,
    { reporter = {
      start = function() _G.was_in_start = true end,
      finish = function() _G.was_in_finish = true end,
    } }
  )]])

  eq(child.lua_get('_G.was_in_start'), true)
  eq(child.lua_get('_G.was_in_finish'), true)
end

T['execute()']['respects `stop_on_error` option'] = function()
  collect_general()

  child.lua('MiniTest.execute(_G.cases, { stop_on_error = true })')

  eq(child.lua_get('type(_G.cases[1].exec)'), 'table')
  eq(child.lua_get('_G.cases[1].exec.state'), 'Fail')

  eq(child.lua_get('type(_G.cases[2].exec)'), 'nil')
end

T['execute()']['properly calls `reporter` methods'] = function()
  collect_general()

  child.lua([[
  _G.update_history = {}
  _G.reporter = {
    start = function(all_cases) _G.all_cases = all_cases end,
    update = function(case_num)
      table.insert(_G.update_history, { case_num = case_num, state = _G.all_cases[case_num].exec.state })
    end,
    finish = function() _G.was_in_finish = true end,
  }]])

  child.lua([[MiniTest.execute(_G.cases, { reporter = _G.reporter })]])
  eq(child.lua_get('#_G.all_cases'), 2)
  eq(child.lua_get('_G.update_history'), {
    { case_num = 1, state = "Executing 'pre' hook #1" },
    { case_num = 1, state = "Executing 'pre' hook #2" },
    { case_num = 1, state = 'Executing test' },
    { case_num = 1, state = "Executing 'post' hook #1" },
    { case_num = 1, state = 'Fail' },
    { case_num = 2, state = "Executing 'pre' hook #1" },
    { case_num = 2, state = 'Executing test' },
    { case_num = 2, state = "Executing 'post' hook #1" },
    { case_num = 2, state = "Executing 'post' hook #2" },
    { case_num = 2, state = 'Pass' },
  })
  eq(child.lua_get('_G.was_in_finish'), true)
end

T['execute()']['handles no cases'] = function()
  child.lua('MiniTest.execute({})')
  eq(child.lua_get('MiniTest.current.all_cases'), {})

  -- Should throw message
  eq(child.cmd_capture('1messages'), '(mini.test) No cases to execute.')
end

T['stop()'] = new_set()

T['stop()']['works'] = function()
  collect_general()

  child.lua('_G.grandchild = MiniTest.new_child_neovim(); _G.grandchild.start()')
  child.lua('MiniTest.execute(_G.cases, { reporter = { start = function() MiniTest.stop() end } })')

  eq(child.lua_get('type(_G.cases[1].exec)'), 'nil')
  eq(child.lua_get('type(_G.cases[2].exec)'), 'nil')

  -- Should close all opened child processed by default
  eq(child.lua_get('_G.grandchild.is_running()'), false)
end

T['stop()']['respects `close_all_child_neovim` option'] = function()
  collect_general()

  child.lua('_G.grandchild = MiniTest.new_child_neovim(); _G.grandchild.start()')
  -- Register cleanup
  MiniTest.finally(function()
    child.lua('_G.grandchild.stop()')
  end)
  child.lua([[MiniTest.execute(
    _G.cases,
    { reporter = { start = function() MiniTest.stop({ close_all_child_neovim = false }) end } }
  )]])

  -- Shouldn't close as per option
  eq(child.lua_get('_G.grandchild.is_running()'), true)
end

T['is_executing()'] = new_set()

T['is_executing()']['works'] = function()
  collect_general()

  -- Tests are executing all the time while reporter is active, but not before
  -- or after
  eq(child.lua_get('MiniTest.is_executing()'), false)

  child.lua([[
  _G.executing_states = {}
  local track_is_executing = function() table.insert(_G.executing_states, MiniTest.is_executing()) end
  MiniTest.execute(
    _G.cases,
    { reporter = { start = track_is_executing, update = track_is_executing, finish = track_is_executing } }
  )]])

  local all_true = true
  for _, s in ipairs(child.lua_get('_G.executing_states')) do
    if s ~= true then
      all_true = false
    end
  end
  eq(all_true, true)

  eq(child.lua_get('MiniTest.is_executing()'), false)
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