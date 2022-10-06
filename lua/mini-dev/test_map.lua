local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('map', config) end
local unload_module = function() child.mini_unload('map') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

local get_latest_message = function() return child.cmd_capture('1messages') end

local get_mode = function() return child.api.nvim_get_mode()['mode'] end

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
  eq(child.lua_get('type(_G.MiniMap)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniMap'), 1)

  -- Highlight groups
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniMapSymbolCount', 'links to Special')
  has_highlight('MiniMapSymbolLine', 'links to Title')
  has_highlight('MiniMapSymbolView', 'links to Delimiter')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniMap.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniMap.config.' .. field), value) end

  -- Check default values
  expect_config('integrations', {})

  expect_config('symbols.encode', vim.NIL)
  expect_config('symbols.scroll_line', '█')
  expect_config('symbols.scroll_view', '┃')

  expect_config('window.side', 'right')
  expect_config('window.show_integration_count', true)
  expect_config('window.width', 10)
  expect_config('window.winblend', 25)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ window = { width = 1 } })
  eq(child.lua_get('MiniMap.config.window.width'), 1)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  local expect_all_encode_symbols_check = function()
    local expect_bad_config = function(err_pattern)
      expect.error(function() child.lua([[MiniMap.setup(_G.bad_config)]]) end, err_pattern)
    end

    child.lua('_G.bad_config = { symbols = { encode = { resolution = { col = 2, row = 2 } } } }')
    for i = 1, 4 do
      expect_bad_config('symbols%.encode%[' .. i .. '%].*string')
      child.lua(string.format('_G.bad_config.symbols.encode[%d] = "%d"', i, i))
    end
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ integrations = 'a' }, 'integrations', 'array')
  expect_config_error({ integrations = { 'a' } }, 'integrations', 'callable')

  expect_config_error({ symbols = 'a' }, 'symbols', 'table')
  expect_config_error({ symbols = { encode = 'a' } }, 'symbols.encode', 'table')

  expect_config_error({ symbols = { encode = { resolution = 'a' } } }, 'symbols.encode.resolution', 'table')
  expect_config_error(
    { symbols = { encode = { resolution = { col = 'a' } } } },
    'symbols.encode.resolution.col',
    'number'
  )
  expect_config_error(
    { symbols = { encode = { resolution = { col = 2, row = 'a' } } } },
    'symbols.encode.resolution.row',
    'number'
  )
  expect_all_encode_symbols_check()

  expect_config_error({ symbols = { scroll_line = 1 } }, 'symbols.scroll_line', 'string')
  expect_config_error({ symbols = { scroll_view = 1 } }, 'symbols.scroll_view', 'string')

  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { side = 1 } }, 'window.side', 'one of')
  expect_config_error({ window = { side = 'a' } }, 'window.side', 'one of')
  expect_config_error({ window = { show_integration_count = 1 } }, 'window.show_integration_count', 'boolean')
  expect_config_error({ window = { width = 'a' } }, 'window.width', 'number')
  expect_config_error({ window = { winblend = 'a' } }, 'window.winblend', 'number')
end

-- Integration tests ==========================================================

return T
