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
  expect_config('n_lines', 20)
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

-- Integration tests ==========================================================

return T
