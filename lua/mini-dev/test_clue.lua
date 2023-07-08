local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('clue', config) end
local unload_module = function() child.mini_unload('clue') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

-- Mapping helpers
local replace_termcodes = function(x) return vim.api.nvim_replace_termcodes(x, true, false, true) end

local reset_test_map_count = function(mode, lhs)
  local lua_cmd = string.format([[_G['test_map_%s_%s'] = 0]], mode, replace_termcodes(lhs))
  child.lua(lua_cmd)
end

local get_test_map_count = function(mode, lhs)
  local lua_cmd = string.format([=[_G['test_map_%s_%s']]=], mode, replace_termcodes(lhs))
  return child.lua_get(lua_cmd)
end

local make_test_map = function(mode, lhs, opts)
  lhs = replace_termcodes(lhs)
  opts = opts or {}

  reset_test_map_count(mode, lhs)

  --stylua: ignore
  local lua_cmd = string.format(
    [[vim.keymap.set('%s', '%s', function() _G['test_map_%s_%s'] = _G['test_map_%s_%s'] + 1 end, %s)]],
    mode, lhs,
    mode, lhs,
    mode, lhs,
    vim.inspect(opts)
  )
  child.lua(lua_cmd)
end

-- Data =======================================================================

-- Output test set ============================================================
T = new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniClue)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniClue'), 1)

  -- Highlight groups
  local validate_hl_group = function(name, ref) expect.match(child.cmd_capture('hi ' .. name), ref) end

  validate_hl_group('MiniClueBorder', 'links to FloatBorder')
  validate_hl_group('MiniClueGroup', 'links to DiagnosticFloatingWarn')
  validate_hl_group('MiniClueNextKey', 'links to DiagnosticFloatingHint')
  validate_hl_group('MiniClueNoKeymap', 'links to DiagnosticFloatingError')
  validate_hl_group('MiniClueNormal', 'links to NormalFloat')
  validate_hl_group('MiniClueSingle', 'links to DiagnosticFloatingInfo')
  validate_hl_group('MiniClueTitle', 'links to FloatTitle')
end

T['setup()']['creates `config` field'] = function()
  load_module()

  eq(child.lua_get('type(_G.MiniClue.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniClue.config.' .. field), value) end

  -- expect_config('clues', {})
  -- expect_config('triggers', {})
  --
  -- expect_config('window.delay', 100)
  -- expect_config('window.config', {})
end

T['setup()']['respects `config` argument'] = function()
  load_module({ window = { delay = 10 } })
  eq(child.lua_get('MiniClue.config.window.delay'), 10)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')

  expect_config_error({ clues = 'a' }, 'clues', 'table')
  expect_config_error({ triggers = 'a' }, 'triggers', 'table')

  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { delay = 'a' } }, 'window.delay', 'number')
  expect_config_error({ window = { config = 'a' } }, 'window.config', 'table')
end

T['setup()']['respects "human-readable" key names'] = function()
  -- In `clues` (`keys` and 'postkeys')

  -- In `triggers`
  MiniTest.skip()
end

-- Integration tests ==========================================================
T['Emulating mappings'] = new_set()

T['Emulating mappings']['works'] = function()
  make_test_map('n', '<Space>f')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  type_keys(' f')
  eq(get_test_map_count('n', ' f'), 1)
end

T['Emulating mappings']['works with `<Cmd>` mappings'] = function() MiniTest.skip() end

T['Emulating mappings']['works buffer-local mappings'] = function() MiniTest.skip() end

return T
