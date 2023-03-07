local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('splitjoin', config) end
local unload_module = function() child.mini_unload('splitjoin') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
--stylua: ignore end

-- Helper wrappers
local toggle = function(...) return child.lua_get('MiniSplitjoin.toggle(...)', { ... }) end

local split = function(...) return child.lua_get('MiniSplitjoin.split(...)', { ... }) end

local join = function(...) return child.lua_get('MiniSplitjoin.join(...)', { ... }) end

-- More general validators
local validate_edit = function(lines_before, cursor_before, lines_after, cursor_after, fun, ...)
  child.ensure_normal_mode()
  set_lines(lines_before)
  set_cursor(cursor_before[1], cursor_before[2])

  fun(...)

  eq(get_lines(), lines_after)
  eq(get_cursor(), cursor_after)
  child.ensure_normal_mode()
end

local validate_keys = function(lines_before, cursor_before, keys, lines_after, cursor_after)
  child.ensure_normal_mode()
  set_lines(lines_before)
  set_cursor(cursor_before[1], cursor_before[2])

  type_keys(keys)

  eq(get_lines(), lines_after)
  eq(get_cursor(), cursor_after)
  child.ensure_normal_mode()
end

-- Output test set ============================================================
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
  eq(child.lua_get('type(_G.MiniSplitjoin)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniSplitjoin.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniSplitjoin.config.' .. field), value) end

  expect_config('mappings.toggle', 'gS')
  expect_config('mappings.split', '')
  expect_config('mappings.join', '')

  expect_config('detect.brackets', vim.NIL)
  expect_config('detect.separator', ',')
  expect_config('detect.exclude_regions', vim.NIL)

  expect_config('split.hooks_pre', {})
  expect_config('split.hooks_post', {})

  expect_config('join.hooks_pre', {})
  expect_config('join.hooks_post', {})
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ detect = { separator = '[,;]' } })
  eq(child.lua_get('MiniSplitjoin.config.detect.separator'), '[,;]')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')

  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { toggle = 1 } }, 'mappings.toggle', 'string')
  expect_config_error({ mappings = { split = 1 } }, 'mappings.split', 'string')
  expect_config_error({ mappings = { join = 1 } }, 'mappings.join', 'string')

  expect_config_error({ detect = 'a' }, 'detect', 'table')
  expect_config_error({ detect = { brackets = 1 } }, 'detect.brackets', 'table')
  expect_config_error({ detect = { separator = 1 } }, 'detect.separator', 'string')
  expect_config_error({ detect = { exclude_regions = 1 } }, 'detect.exclude_regions', 'table')

  expect_config_error({ split = 'a' }, 'split', 'table')
  expect_config_error({ split = { hooks_pre = 1 } }, 'split.hooks_pre', 'table')
  expect_config_error({ split = { hooks_post = 1 } }, 'split.hooks_post', 'table')

  expect_config_error({ join = 'a' }, 'join', 'table')
  expect_config_error({ join = { hooks_pre = 1 } }, 'join.hooks_pre', 'table')
  expect_config_error({ join = { hooks_post = 1 } }, 'join.hooks_post', 'table')
end

T['setup()']['properly creates mappings'] = function()
  local has_map = function(lhs, mode) return child.cmd_capture(mode .. 'map ' .. lhs):find('MiniSplitjoin') ~= nil end
  eq(has_map('gS', 'n'), true)
  eq(has_map('gS', 'x'), true)
  eq(has_map('gj', 'n'), false)
  eq(has_map('gj', 'x'), false)

  unload_module()
  child.api.nvim_del_keymap('n', 'gS')
  child.api.nvim_del_keymap('x', 'gS')

  -- Supplying empty string should mean "don't create keymaps"
  load_module({ mappings = { toggle = '', split = 'gj' } })
  eq(has_map('gS', 'n'), false)
  eq(has_map('gS', 'x'), false)
  eq(has_map('gj', 'n'), true)
  eq(has_map('gj', 'x'), true)
end

-- Most of action specific tests are done in their functions
T['toggle()'] = new_set()

T['toggle()']['works'] = function() MiniTest.skip() end

T['toggle()']['correctly calls `split()`'] = function() MiniTest.skip() end

T['toggle()']['correctly calls `join()`'] = function() MiniTest.skip() end

T['toggle()']['respects `opts.region`'] = function() MiniTest.skip() end

T['toggle()']['respects `opts.position`'] = function() MiniTest.skip() end

T['toggle()']['respects `opts.detect.brackets`'] = function() MiniTest.skip() end

T['toggle()']['returns `nil` if no positions are found'] = function() MiniTest.skip() end

T['toggle()']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisplitjoin_disable = true
    MiniTest.skip()
  end,
})

T['toggle()']['respects `vim.b.minisplitjoin_config`'] = function()
  child.lua('_G.hook_pre = function() end')
  child.lua([[vim.b.minisplitjoin_config = {
    split = { hooks_pre = { _G.hook_pre } },
    join = { hooks_pre = { _G.hook_pre } },
  }]])

  MiniTest.skip()
end

T['split()'] = new_set()

T['split()']['works for arguments on single line'] = function() MiniTest.skip() end

T['split()']['works for arguments on multiple lines'] = function() MiniTest.skip() end

T['split()']['works inside comments'] = function() MiniTest.skip() end

T['split()']["respects 'expandtab' for indenting"] = function() MiniTest.skip() end

T['split()']['returns `nil` if no positions are found'] = function() MiniTest.skip() end

T['split()']['respects `opts.region`'] = function() MiniTest.skip() end

T['split()']['respects `opts.position`'] = function() MiniTest.skip() end

T['split()']['respects `opts.detect.brackets`'] = function() MiniTest.skip() end

T['split()']['respects `opts.detect.separator`'] = function() MiniTest.skip() end

T['split()']['respects `opts.detect.exclude_regions`'] = function() MiniTest.skip() end

T['split()']['respects `opts.split.hooks_pre`'] = function() MiniTest.skip() end

T['split()']['respects `opts.split.hooks_post`'] = function() MiniTest.skip() end

T['split()']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisplitjoin_disable = true
    MiniTest.skip()
  end,
})

T['split()']['respects `vim.b.minisplitjoin_config`'] = function()
  child.lua('_G.hook_pre = function() end')
  child.lua([[vim.b.minisplitjoin_config = { split = { hooks_pre = { _G.hook_pre } } }]])

  MiniTest.skip()
end

T['join()'] = new_set()

T['join()']['works for arguments on multiple lines'] = function() MiniTest.skip() end

T['join()']['does nothing if arguments are on single line'] = function() MiniTest.skip() end

T['join()']['works inside comments'] = function() MiniTest.skip() end

T['join()']['returns `nil` if no positions are found'] = function() MiniTest.skip() end

T['join()']['respects `opts.region`'] = function() MiniTest.skip() end

T['join()']['respects `opts.position`'] = function() MiniTest.skip() end

T['join()']['respects `opts.detect.brackets`'] = function() MiniTest.skip() end

T['join()']['respects `opts.detect.separator`'] = function() MiniTest.skip() end

T['join()']['respects `opts.detect.exclude_regions`'] = function() MiniTest.skip() end

T['join()']['respects `opts.join.hooks_pre`'] = function() MiniTest.skip() end

T['join()']['respects `opts.join.hooks_post`'] = function() MiniTest.skip() end

T['join()']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisplitjoin_disable = true
    MiniTest.skip()
  end,
})

T['join()']['respects `vim.b.minisplitjoin_config`'] = function()
  child.lua('_G.hook_pre = function() end')
  child.lua([[vim.b.minisplitjoin_config = { join = { hooks_pre = { _G.hook_pre } } }]])

  MiniTest.skip()
end

T['get_hook'] = new_set()

T['get_hook']['pad_brackets()'] = new_set()

T['get_hook']['pad_brackets()']['works'] = function()
  -- Should return correctly updated input
  MiniTest.skip()
end

T['get_hook']['pad_brackets()']['does not act in case of no arguments'] = function() MiniTest.skip() end

T['get_hook']['pad_brackets()']['respects `opts.pad`'] = function() MiniTest.skip() end

T['get_hook']['pad_brackets()']['respects `opts.brackets`'] = function() MiniTest.skip() end

T['get_hook']['add_trailing_separator()'] = new_set()

T['get_hook']['add_trailing_separator()']['works'] = function()
  -- Should return correctly updated input
  MiniTest.skip()
end

T['get_hook']['add_trailing_separator()']['does nothing if there is already trailing separator'] =
  function() MiniTest.skip() end

T['get_hook']['add_trailing_separator()']['does not act in case of no arguments'] = function() MiniTest.skip() end

T['get_hook']['add_trailing_separator()']['respects `opts.sep`'] = function() MiniTest.skip() end

T['get_hook']['add_trailing_separator()']['respects `opts.brackets`'] = function() MiniTest.skip() end

T['get_hook']['del_trailing_separator()'] = new_set()

T['get_hook']['del_trailing_separator()']['works'] = function()
  -- Should return correctly updated input
  MiniTest.skip()
end

T['get_hook']['del_trailing_separator()']['does nothing if there is already no trailing separator'] =
  function() MiniTest.skip() end

T['get_hook']['del_trailing_separator()']['respects `opts.sep`'] = function() MiniTest.skip() end

T['get_hook']['del_trailing_separator()']['respects `opts.brackets`'] = function() MiniTest.skip() end

T['split_at()'] = new_set()

T['split_at()']['works'] = function() MiniTest.skip() end

T['split_at()']['correctly tracks input positions'] = function() MiniTest.skip() end

T['split_at()']['works inside comments'] = function()
  -- Should respect both 'commentstring' and 'comments'
  MiniTest.skip()
end

T['split_at()']['properly tracks cursor'] = function() MiniTest.skip() end

T['split_at()']['uses first and last positions to determine indent range'] = function() MiniTest.skip() end

T['split_at()']["respects 'expandtab' for indenting"] = function() MiniTest.skip() end

T['join_at()'] = new_set()

T['join_at()']['works'] = function() MiniTest.skip() end

T['join_at()']['correctly tracks input positions'] = function() MiniTest.skip() end

T['join_at()']['works inside comments'] = function()
  -- Should respect both 'commentstring' and 'comments'
  MiniTest.skip()
end

T['join_at()']['properly tracks cursor'] = function() MiniTest.skip() end

T['get_visual_region()'] = new_set()

T['get_visual_region()']['works'] = function() MiniTest.skip() end

T['get_indent()'] = new_set()

T['get_indent()']['works'] = function() MiniTest.skip() end

T['get_indent()']['respects `respect_comments` argument'] = function()
  -- Should respect both 'commentstring' and 'comments'
  MiniTest.skip()
end

-- Integration tests ==========================================================
T['Mappings'] = new_set()

T['Mappings']['Toggle'] = new_set()

T['Mappings']['Toggle']['works in Normal mode'] = function()
  -- Should also test dot-repeat
  MiniTest.skip()
end

T['Mappings']['Toggle']['works in Visual mode'] = function() MiniTest.skip() end

T['Mappings']['Split'] = new_set()

T['Mappings']['Split']['works in Normal mode'] = function()
  -- Should also test dot-repeat
  MiniTest.skip()
end

T['Mappings']['Split']['works in Visual mode'] = function() MiniTest.skip() end

T['Mappings']['Join'] = new_set()

T['Mappings']['Join']['works in Normal mode'] = function()
  -- Should also test dot-repeat
  MiniTest.skip()
end

T['Mappings']['Join']['works in Visual mode'] = function() MiniTest.skip() end

return T
