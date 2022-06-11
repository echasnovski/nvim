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

T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
})

-- Data =======================================================================

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

T['new_set()']['works'] = function()
  skip()
end

T['skip()'] = new_set()

T['skip()']['works'] = function()
  skip()
end

T['note()'] = new_set()

T['note()']['works'] = function()
  skip()
end

T['finally()'] = new_set()

T['finally()']['works'] = function()
  skip()
end

T['run()'] = new_set()

T['run()']['works'] = function()
  skip()
end

T['run_file()'] = new_set()

T['run_file()']['works'] = function()
  skip()
end

T['run_at_location()'] = new_set()

T['run_at_location()']['works'] = function()
  skip()
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

T['execute()'] = new_set()

T['execute()']['works'] = function()
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
