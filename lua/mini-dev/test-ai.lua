local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set, finally = MiniTest.new_set, MiniTest.finally
local mark_flaky = helpers.mark_flaky

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('ai', config) end
local unload_module = function() child.mini_unload('ai') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
--stylua: ignore end

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
  eq(child.lua_get('type(_G.MiniAi)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniAi.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniAi.config.' .. field), value) end

  -- Check default values
  expect_config('custom_textobjects', vim.NIL)
  expect_config('mappings.around', 'a')
  expect_config('mappings.inside', 'i')
  expect_config('mappings.goto_left', 'g[')
  expect_config('mappings.goto_right', 'g]')
  expect_config('n_lines', 50)
  expect_config('search_method', 'cover_or_next')
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ n_lines = 10 })
  eq(child.lua_get('MiniAi.config.n_lines'), 10)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ custom_textobjects = 'a' }, 'custom_textobjects', 'table')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { around = 1 } }, 'mappings.around', 'string')
  expect_config_error({ mappings = { inside = 1 } }, 'mappings.inside', 'string')
  expect_config_error({ mappings = { goto_left = 1 } }, 'mappings.goto_left', 'string')
  expect_config_error({ mappings = { goto_right = 1 } }, 'mappings.goto_right', 'string')
  expect_config_error({ n_lines = 'a' }, 'n_lines', 'number')
  expect_config_error({ search_method = 1 }, 'search_method', 'one of')
end

T['setup()']['properly handles `config.mappings`'] = function()
  local has_map = function(lhs) return child.cmd_capture('xmap ' .. lhs):find('MiniAi') ~= nil end
  eq(has_map('a'), true)

  unload_module()
  child.api.nvim_del_keymap('x', 'a')

  -- Supplying empty string should mean "don't create keymap"
  load_module({ mappings = { around = '' } })
  eq(has_map('a'), false)
end

T['find_textobject()'] = new_set()

T['find_textobject()']['works'] = function() MiniTest.skip() end

T['find_textobject()']['respects `n_lines`'] = function() MiniTest.skip() end

T['find_textobject()']['works'] = function() MiniTest.skip() end

T['find_textobject()']['works'] = function() MiniTest.skip() end

T['find_textobject()']['works'] = function() MiniTest.skip() end

T['find_textobject()']['works'] = function() MiniTest.skip() end

T['move_cursor()'] = new_set()

T['select_textobject()'] = new_set()

-- Actual testing is done in 'Integration tests'
T['expr_textobject()'] = new_set()

T['expr_textobject()']['is present'] = function() eq(child.lua_get('type(MiniAi.expr_textobject)'), 'function') end

-- Actual testing is done in 'Integration tests'
T['expr_motion()'] = new_set()

T['expr_motion()']['is present'] = function() eq(child.lua_get('type(MiniAi.expr_motion)'), 'function') end

T['Search method'] = new_set()

T['Search method']['works with "cover"'] = function() MiniTest.skip() end

T['Search method']['works with "cover_or_prev"'] = function() MiniTest.skip() end

T['Search method']['works with "cover_or_nearest"'] = function() MiniTest.skip() end

T['Search method']['throws error on incorrect `config.search_method`'] = function() MiniTest.skip() end

T['Search method']['respects `vim.b.minisurround_config`'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
T['Textobjects'] = new_set()

T['Textobjects']['work with dot-repeat'] = function() MiniTest.skip() end

T['Builtin textobjects'] = new_set()

T['Builtin textobjects']['Brackets'] = new_set()

T['Builtin textobjects']['Quotes'] = new_set()

T['Builtin textobjects']['User prompt'] = new_set()

T['Builtin textobjects']['Argument'] = new_set()

T['Builtin textobjects']['Argument']['correctly selects first argument when outside'] = function()
  -- Line: '  (aa, bb, cc)'. Cursor: 0 column. Typing `vaa` should select first
  -- argument.
end

T['Builtin textobjects']['Function call'] = new_set()

T['Builtin textobjects']['Tags'] = new_set()

T['Builtin textobjects']['Default'] = new_set()

T['Builtin textobjects']['Default']['work'] = function() MiniTest.skip() end

T['Builtin textobjects']['Default']['work in edge cases'] = function()
  -- `va_`, `ca_` for `__` line
  -- `va_`, `ca_` for `____` line
  MiniTest.skip()
end

T['Custom textobjects'] = new_set()

T['Custom textobjects']['work with special patterns'] = new_set()

T['Custom textobjects']['work with special patterns']['%bxx'] = function()
  -- `%bxx` should represent balanced character
end

T['Custom textobjects']['work with special patterns']['x.-y'] = function()
  -- `x.-y` should work with `a%.-a` and `a%-a`

  -- `x.-y` should work with patterns like `x+.-x+`
end

T['Custom textobjects']['selects smallest span'] = function()
  -- Edges can't be inside current span
  MiniTest.skip()
end

T['Consecutive calls'] = new_set()

T['Motion'] = new_set()

return T
