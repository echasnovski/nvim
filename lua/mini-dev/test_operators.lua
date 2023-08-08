local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('operators', config) end
local unload_module = function() child.mini_unload('operators') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
--stylua: ignore end

-- Custom validators
local validate_edit = function(lines_before, cursor_before, keys, lines_after, cursor_after)
  child.ensure_normal_mode()
  set_lines(lines_before)
  set_cursor(cursor_before[1], cursor_before[2])

  type_keys(keys)

  eq(get_lines(), lines_after)
  eq(get_cursor(), cursor_after)

  child.ensure_normal_mode()
end

local validate_edit1d = function(line_before, col_before, keys, line_after, col_after)
  validate_edit({ line_before }, { 1, col_before }, keys, { line_after }, { 1, col_after })
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
  eq(child.lua_get('type(_G.MiniOperators)'), 'table')

  -- Highlight groups
  local validate_hl_group = function(name, ref) expect.match(child.cmd_capture('hi ' .. name), ref) end

  validate_hl_group('MiniOperatorsExchangeFrom', 'links to IncSearch')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniOperators.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniOperators.config.' .. field), value) end

  expect_config('mappings.replace', 'gr')

  expect_config('options.make_line_mappings', true)
  expect_config('options.make_visual_mappings', true)

  MiniTest.skip('TODO')
end

T['setup()']['respects `config` argument'] = function()
  reload_module({ options = { make_visual_mappings = false } })
  eq(child.lua_get('MiniOperators.config.options.make_visual_mappings'), false)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')

  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ options = 'a' }, 'options', 'table')

  MiniTest.skip('TODO')
end

-- Integration tests ==========================================================
T['Exchange'] = new_set()

T['Exchange']['works charwise in Normal mode'] = function()
  local keys = { 'gxiw', 'w', 'gxiw' }
  validate_edit1d('a bb', 0, keys, 'bb a', 3)
  validate_edit1d('a bb ccc', 0, keys, 'bb a ccc', 3)
  validate_edit1d('a bb ccc', 3, keys, 'a ccc bb', 6)
  validate_edit1d('a bb ccc dddd', 3, keys, 'a ccc bb dddd', 6)

  -- With dot-repeat allowing multiple exchanges
  validate_edit1d('a bb', 0, { 'gxiw', 'w', '.' }, 'bb a', 3)
  validate_edit1d('a bb ccc dddd', 0, { 'gxiw', 'w', '.', 'w.w.' }, 'bb a dddd ccc', 10)

  -- Different order
  local keys_back = { 'gxiw', 'b', 'gxiw' }
  validate_edit1d('a bb', 2, keys_back, 'bb a', 0)
  validate_edit1d('a bb ccc', 2, keys_back, 'bb a ccc', 0)
  validate_edit1d('a bb ccc', 5, keys_back, 'a ccc bb', 2)
  validate_edit1d('a bb ccc dddd', 5, keys_back, 'a ccc bb dddd', 2)

  -- Over several lines
  set_lines({ 'aa bb', 'cc dd', 'ee ff', 'gg hh' })

  -- - Set marks
  set_cursor(2, 2)
  type_keys('ma')
  set_cursor(4, 2)
  type_keys('mb')

  -- - Validate
  set_cursor(1, 0)
  type_keys('gx`a', '2j', 'gx`b')
  eq(get_lines(), { 'ee ff', 'gg dd', 'aa bb', 'cc hh' })
  eq(get_cursor(), { 3, 0 })

  -- Single cell
  validate_edit1d('aa bb', 0, { 'gxl', 'w', 'gxl' }, 'ba ab', 3)
end

T['Exchange']['works linewise in Normal mode'] = function()
  local keys = { 'gx_', 'j', 'gx_' }
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, keys, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, keys, { 'bb', 'aa', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, keys, { 'aa', 'cc', 'bb' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 2, 0 }, keys, { 'aa', 'cc', 'bb', 'dd' }, { 3, 0 })

  -- With dot-repeat allowing multiple exchanges
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gx_', 'j', '.' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 1, 0 }, { 'gx_', 'j', '.', 'j.j.' }, { 'bb', 'aa', 'dd', 'cc' }, { 4, 0 })

  -- Different order
  local keys_back = { 'gx_', 'k', 'gx_' }
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, keys_back, { 'bb', 'aa' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, keys_back, { 'bb', 'aa', 'cc' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, keys_back, { 'aa', 'cc', 'bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 3, 0 }, keys_back, { 'aa', 'cc', 'bb', 'dd' }, { 2, 0 })

  -- Empty line
  validate_edit({ 'aa', '' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { '', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', '', 'bb' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { 'bb', '', 'aa' }, { 3, 0 })

  -- Blank line(s)
  validate_edit({ 'aa', '  ' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { '  ', 'aa' }, { 2, 0 })
  validate_edit({ ' ', '  ' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { '  ', ' ' }, { 2, 0 })

  -- Over several lines
  validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gxip', 'G', 'gxip' }, { 'cc', '', 'aa', 'bb' }, { 3, 0 })
end

T['Exchange']['works blockwise in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'io', function() vim.cmd('normal! \22') end)]])
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
  child.lua([[vim.keymap.set('o', 'iE', function() vim.cmd('normal! \22jj') end)]])
  child.lua([[vim.keymap.set('o', 'il', function() vim.cmd('normal! \22jl') end)]])

  local keys = { 'gxie', 'w', 'gxil' }
  validate_edit({ 'a bb', 'c dd' }, { 1, 0 }, keys, { 'bb a', 'dd c' }, { 1, 3 })
  validate_edit({ 'a bb x', 'c dd y' }, { 1, 0 }, keys, { 'bb a x', 'dd c y' }, { 1, 3 })
  validate_edit({ 'a b xx', 'c d yy' }, { 1, 2 }, keys, { 'a xx b', 'c yy d' }, { 1, 5 })
  validate_edit({ 'a b xx u', 'c d yy v' }, { 1, 2 }, keys, { 'a xx b u', 'c yy d v' }, { 1, 5 })

  -- With dot-repeat allowing multiple exchanges
  validate_edit({ 'a bb', 'c dd' }, { 1, 0 }, { 'gxie', 'w', '.' }, { 'b ab', 'd cd' }, { 1, 2 })
  validate_edit({ 'a b x y', 'c d u v' }, { 1, 0 }, { 'gxie', 'w', '.', 'w.w.' }, { 'b a y x', 'd c v u' }, { 1, 6 })

  -- Different order
  local keys_back = { 'gxil', 'b', 'gxie' }
  validate_edit({ 'a bb', 'c dd' }, { 1, 2 }, keys_back, { 'bb a', 'dd c' }, { 1, 0 })
  validate_edit({ 'a bb x', 'c dd y' }, { 1, 2 }, keys_back, { 'bb a x', 'dd c y' }, { 1, 0 })
  validate_edit({ 'a b xx', 'c d yy' }, { 1, 4 }, keys_back, { 'a xx b', 'c yy d' }, { 1, 2 })
  validate_edit({ 'a b xx u', 'c d yy v' }, { 1, 4 }, keys_back, { 'a xx b u', 'c yy d v' }, { 1, 2 })

  -- Spanning empty/blank line
  validate_edit({ 'a b', '', 'c d' }, { 1, 0 }, { 'gxiE', 'w', 'gxiE' }, { 'b a', '  ', 'd c' }, { 1, 2 })
  validate_edit({ 'a b', '   ' }, { 1, 0 }, { 'gxie', 'w', 'gxie' }, { 'b a', '   ' }, { 1, 2 })

  -- Single cell
  validate_edit1d('aa bb', 0, { 'gxio', 'w', 'gxio' }, 'ba ab', 3)
end

T['Exchange']['works with mixed submodes in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  -- Charwise from - Linewise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'gxiw', 'j', 'gx_' }, { 'bb', 'aa', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'gx/b$<CR>', 'G', 'gx_' }, { 'ccb', 'aa', 'b' }, { 2, 0 })

  -- Charwise from - Blockwise to
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'gxiw', 'j', 'gxie' }, { 'b', 'd', 'aac', 'e' }, { 3, 0 })
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'gx/c<CR>', 'jl', 'gxie' }, { 'c', 'eaa', 'db' }, { 2, 1 })

  -- Linewise from - Charwise to
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { 'gx_', 'j', 'gxiw' }, { 'bb', 'aa bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc cc' }, { 1, 0 }, { 'gxj', '2j', 'gxiw' }, { 'cc', 'aa', 'bb cc' }, { 2, 0 })

  -- Linewise from - Blockwise to
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'gx_', 'j', 'gxie' }, { 'b', 'd', 'aac', 'e' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cd', 'ef' }, { 1, 0 }, { 'gxj', '2j', 'gxie' }, { 'c', 'e', 'aad', 'bbf' }, { 3, 0 })

  -- Blockwise from - Charwise to
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { '<C-v>gx', 'j', 'gxiw' }, { 'bba', 'a bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { '<C-v>jgx', 'jw', 'gxiw' }, { 'bba', 'b a', 'b' }, { 2, 2 })

  -- Blockwise from - Linewise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>gx', 'j', 'gx_' }, { 'bba', 'a', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>jgx', 'G', 'gx_' }, { 'cca', 'b', 'a', 'b' }, { 3, 0 })
end

T['Exchange']['works in Normal mode for line'] = function() MiniTest.skip() end

T['Exchange']['works in Visual mode'] = function() MiniTest.skip() end

T['Exchange']['works when regions are made in different mode'] = function()
  -- Normal from - Visual to

  -- Normal to - Visual from
  MiniTest.skip()
end

T['Exchange']['respects `config.options.make_line_mappings`'] = function()
  -- child.api.nvim_del_keymap('n', 'grr')
  -- load_module({ options = { make_line_mappings = false } })
  -- eq(child.fn.maparg('grr', 'n'), '')
  MiniTest.skip()
end

T['Exchange']['respects `config.options.make_visual_mappings`'] = function()
  -- child.api.nvim_del_keymap('x', 'gr')
  -- load_module({ options = { make_visual_mappings = false } })
  -- eq(child.fn.maparg('gr', 'x'), '')
  MiniTest.skip()
end

T['Exchange']['highlights first step'] = function() MiniTest.skip() end

T['Exchange']['can be canceled'] = function() MiniTest.skip() end

T['Exchange']['works in edge cases'] = function()
  -- -- Start of line
  -- validate_edit1d('aa bb', 3, { 'yiw', '0', 'griw' }, 'bb bb', 0)
  --
  -- -- End of line
  -- validate_edit1d('aa bb', 0, { 'yiw', 'w', 'griw' }, 'aa aa', 3)
  --
  -- -- First line
  -- validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'yy', 'k', 'grr' }, { 'bb', 'bb' }, { 1, 0 })
  --
  -- -- Last line
  -- validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'yy', 'G', 'grr' }, { 'aa', 'bb', 'aa' }, { 3, 0 })
  MiniTest.skip()
end

T['Exchange']['works for intersecting regions'] = function()
  -- Charwise
  -- Linewise
  -- Blockwise
  MiniTest.skip()
end

T['Exchange']['works for regions in different buffers'] = function() MiniTest.skip() end

T['Exchange']['works for same region'] = function()
  -- Charwise
  validate_edit1d('aa bb cc', 4, { 'gxiw', 'gxiw' }, 'aa bb cc', 3)

  -- Linewise
  validate_edit1d('aa bb cc', 4, { 'gx_', 'gx_' }, 'aa bb cc', 0)

  -- Blockwise
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
  validate_edit({ 'ab', 'cd' }, { 1, 0 }, { 'gxie', 'gxie' }, { 'ab', 'cd' }, { 1, 0 })
end

T['Exchange']['does not have side effects'] = function()
  -- Marks `x`, `y` and registers `1`, `2`
  MiniTest.skip()
end

T['Exchange']['works with different base mapping'] = function()
  -- child.api.nvim_del_keymap('n', 'gr')
  -- child.api.nvim_del_keymap('n', 'grr')
  -- child.api.nvim_del_keymap('x', 'gr')
  --
  -- load_module({ mappings = { replace = 'cr' } })
  --
  -- validate_edit1d('aa bb', 0, { 'yiw', 'w', 'criw' }, 'aa aa', 3)
  -- validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'crr' }, { 'aa', 'aa' }, { 2, 0 })
  -- validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', 'cr' }, 'aa aa', 4)
  MiniTest.skip()
end

T['Exchange']['allows custom mappings'] = function()
  -- child.api.nvim_del_keymap('n', 'gr')
  -- child.api.nvim_del_keymap('n', 'grr')
  -- child.api.nvim_del_keymap('x', 'gr')
  --
  -- load_module({ mappings = { replace = '' } })
  --
  -- child.lua([[
  --   vim.keymap.set('n', 'cr', 'v:lua.MiniOperators.replace()', { expr = true, replace_keycodes = false, desc = 'Replace' })
  --   vim.keymap.set('n', 'crr', 'cr_', { remap = true, desc = 'Replace line' })
  --   vim.keymap.set('x', 'cr', '<Cmd>lua MiniOperators.replace("visual")<CR>', { desc = 'Replace selection' })
  -- ]])
  --
  -- validate_edit1d('aa bb', 0, { 'yiw', 'w', 'criw' }, 'aa aa', 3)
  -- validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'crr' }, { 'aa', 'aa' }, { 2, 0 })
  -- validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', 'cr' }, 'aa aa', 4)
  MiniTest.skip()
end

T['Exchange']['respects `vim.{g,b}.minioperators_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    -- child[var_type].minioperators_disable = true
    --
    -- validate_edit1d('aa bb', 0, {'yiw', 'w', 'griw'}, 'aa wbb', 4)
    MiniTest.skip()
  end,
})

T['Replace'] = new_set()

T['Replace']['works charwise in Normal mode'] = function()
  validate_edit1d('aa bb cc', 0, { 'yiw', 'w', 'graW' }, 'aa aacc', 3)

  -- With dot-repeat
  validate_edit1d('aa bb cc', 0, { 'yiw', 'w', 'graW', '.' }, 'aaaa', 2)

  -- Over several lines
  set_lines({ 'aa bb', 'cc dd' })

  -- - Set mark
  set_cursor(2, 2)
  type_keys('ma')

  -- - Validate
  set_cursor(1, 0)
  type_keys('yiw', 'w', 'gr`a')
  eq(get_lines(), { 'aa aa dd' })
  eq(get_cursor(), { 1, 3 })

  -- Single cell
  validate_edit1d('aa bb', 0, { 'yl', 'w', 'grl' }, 'aa ab', 3)
end

T['Replace']['works linewise in Normal mode'] = function()
  local lines = { 'aa', '', 'bb', 'cc', '', 'dd', 'ee' }
  validate_edit(lines, { 1, 0 }, { 'yy', '2j', 'grip' }, { 'aa', '', 'aa', '', 'dd', 'ee' }, { 3, 0 })

  -- - With dot-repeat
  validate_edit(lines, { 1, 0 }, { 'yy', '2j', 'grip', '2j', '.' }, { 'aa', '', 'aa', '', 'aa' }, { 5, 0 })
end

T['Replace']['works blockwise in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'io', function() vim.cmd('normal! \22') end)]])
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', 'grie' }, { 'a a c', 'a a c' }, { 1, 2 })

  -- With dot-repeat
  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', 'grie', 'w', '.' }, { 'a a a', 'a a a' }, { 1, 4 })

  -- Single cell
  validate_edit1d('aa bb', 0, { '<C-v>y', 'w', 'grio' }, 'aa ab', 3)
end

T['Replace']['works with mixed submodes in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  -- Charwise paste - Linewise region
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'yiw', 'j', 'gr_' }, { 'aa', 'aa', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'y/b$<CR>', 'j', 'gr_' }, { 'aa', 'aa', 'b', 'cc' }, { 2, 0 })

  -- Charwise paste - Blockwise region
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'yiw', 'j', 'grie' }, { 'aa', 'aac', 'e' }, { 2, 0 })
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'y/c<CR>', 'j', 'grie' }, { 'aa', 'aac', 'b e' }, { 2, 0 })

  -- Linewise paste - Charwise region
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { 'yy', 'j', 'griw' }, { 'aa', 'aa bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc cc' }, { 1, 0 }, { 'yj', '2j', 'griw' }, { 'aa', 'bb', 'aa', 'bb cc' }, { 3, 0 })

  -- Linewise paste - Blockwise region
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'yy', 'j', 'grie' }, { 'aa', 'aac', 'e' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cd', 'ef' }, { 1, 0 }, { 'yj', '2j', 'grie' }, { 'aa', 'bb', 'aad', 'bbf' }, { 3, 0 })

  -- Blockwise paste - Charwise region
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { '<C-v>y', 'j', 'griw' }, { 'aa', 'a bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { 'y<C-v>j', 'j', 'griw' }, { 'aa', 'a', 'b bb' }, { 2, 0 })

  -- Blockwise paste - Linewise region
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>y', 'j', 'gr_' }, { 'aa', 'a', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'y<C-v>j', 'j', 'gr_' }, { 'aa', 'a', 'b', 'cc' }, { 2, 0 })
end

T['Replace']['works with two types of `[count]` in Normal mode'] = function()
  -- First `[count]` for paste with dot-repeat
  validate_edit1d('aa bb cc dd', 0, { 'yiw', 'w', '2graW' }, 'aa aaaacc dd', 3)
  validate_edit1d('aa bb cc dd', 0, { 'yiw', 'w', '2graW', 'w', '.' }, 'aa aaaaccaaaa', 9)

  -- Second `[count]` for textobject with dot-repeat
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', 'gr2aW' }, 'aa aadd ee', 3)
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', 'gr2aW', '.' }, 'aaaa', 2)

  -- Both `[count]`s with dot-repeat
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', '2gr2aW' }, 'aa aaaadd ee', 3)
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', '2gr2aW', '.' }, 'aaaaaa', 2)
end

T['Replace']['works in Normal mode for line'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 1 }, { 'yy', 'j', 'grr' }, { 'aa', 'aa' }, { 2, 0 })

  -- With dot-repeat
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 1 }, { 'yy', 'j', 'grr', 'j', '.' }, { 'aa', 'aa', 'aa' }, { 3, 0 })
end

T['Replace']['works with `[count]` in Normal mode for line'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 1 }, { 'yy', 'j', '2grr' }, { 'aa', 'aa', 'aa' }, { 2, 0 })

  -- With dot-repeat
  validate_edit(
    { 'aa', 'bb', 'cc' },
    { 1, 1 },
    { 'yy', 'j', '2grr', '2j', '.' },
    { 'aa', 'aa', 'aa', 'aa', 'aa' },
    { 4, 0 }
  )
end

local validate_replace_visual = function(lines_before, cursor_before, keys_without_replace)
  -- Get reference lines and cursor position assuming replacing in Visual mode
  -- should be the same as using `P`
  set_lines(lines_before)
  set_cursor(unpack(cursor_before))
  type_keys(keys_without_replace, 'P')

  local lines_after, cursor_after = get_lines(), get_cursor()

  -- Validate
  validate_edit(lines_before, cursor_before, { keys_without_replace, 'gr' }, lines_after, cursor_after)
end

T['Replace']['works in Visual mode'] = function()
  -- Charwise selection
  validate_replace_visual({ 'aa bb' }, { 1, 0 }, { 'yiw', 'w', 'viw' })
  validate_replace_visual({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'viw' })
  validate_replace_visual({ 'aa', 'bb' }, { 1, 0 }, { 'y<C-v>j', 'viw' })

  -- Linewise selection
  validate_replace_visual({ 'aa', 'bb' }, { 1, 0 }, { 'yiw', 'j', 'V' })
  validate_replace_visual({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'V' })
  validate_replace_visual({ 'aa', 'bb' }, { 1, 0 }, { 'y<C-v>j', 'j', 'V' })

  -- Blockwise selection
  validate_replace_visual({ 'a b', 'a b' }, { 1, 0 }, { 'yiw', 'w', '<C-v>j' })
  validate_replace_visual({ 'a b', 'a b' }, { 1, 0 }, { 'yy', 'w', '<C-v>j' })
  validate_replace_visual({ 'a b', 'a b' }, { 1, 0 }, { 'y<C-v>j', 'w', '<C-v>j' })
end

T['Replace']['works with `[count]` in Visual mode'] =
  function() validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', '2gr' }, 'aa aaaa', 6) end

T['Replace']['works with `[register]`'] = function()
  -- Normal mode
  validate_edit1d('aa bb cc', 0, { '"xyiw', 'w', 'yiw', 'w', '"xgriw' }, 'aa bb aa', 6)

  -- Visual mode
  validate_edit1d('aa bb cc', 0, { '"xyiw', 'w', 'yiw', 'w', 'viw', '"xgr' }, 'aa bb aa', 7)
end

T['Replace']['validatees `[register]` content'] = function()
  child.o.cmdheight = 10
  set_lines({ 'aa bb' })
  type_keys('yiw', 'w')

  expect.error(function() type_keys('"agriw') end, 'Register "a".*empty')
  expect.error(function() type_keys('"Agriw') end, 'Register "A".*unknown')
end

T['Replace']['respects `config.options.make_line_mappings`'] = function()
  child.api.nvim_del_keymap('n', 'grr')
  load_module({ options = { make_line_mappings = false } })
  eq(child.fn.maparg('grr', 'n'), '')
end

T['Replace']['respects `config.options.make_visual_mappings`'] = function()
  child.api.nvim_del_keymap('x', 'gr')
  load_module({ options = { make_visual_mappings = false } })
  eq(child.fn.maparg('gr', 'x'), '')
end

T['Replace']['works in edge cases'] = function()
  -- Start of line
  validate_edit1d('aa bb', 3, { 'yiw', '0', 'griw' }, 'bb bb', 0)

  -- End of line
  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'griw' }, 'aa aa', 3)

  -- First line
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'yy', 'k', 'grr' }, { 'bb', 'bb' }, { 1, 0 })

  -- Last line
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'yy', 'G', 'grr' }, { 'aa', 'bb', 'aa' }, { 3, 0 })
end

T['Replace']['does not have side effects'] = function()
  -- Register type should not change
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'griw' }, { 'aa', 'aa' }, { 2, 0 })
  eq(child.fn.getregtype('"'), 'V')
end

T['Replace']['works with different base mapping'] = function()
  child.api.nvim_del_keymap('n', 'gr')
  child.api.nvim_del_keymap('n', 'grr')
  child.api.nvim_del_keymap('x', 'gr')

  load_module({ mappings = { replace = 'cr' } })

  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'criw' }, 'aa aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'crr' }, { 'aa', 'aa' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', 'cr' }, 'aa aa', 4)
end

T['Replace']['allows custom mappings'] = function()
  child.api.nvim_del_keymap('n', 'gr')
  child.api.nvim_del_keymap('n', 'grr')
  child.api.nvim_del_keymap('x', 'gr')

  load_module({ mappings = { replace = '' } })

  child.lua([[
    vim.keymap.set('n', 'cr', 'v:lua.MiniOperators.replace()', { expr = true, replace_keycodes = false, desc = 'Replace' })
    vim.keymap.set('n', 'crr', 'cr_', { remap = true, desc = 'Replace line' })
    vim.keymap.set('x', 'cr', '<Cmd>lua MiniOperators.replace("visual")<CR>', { desc = 'Replace selection' })
  ]])

  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'criw' }, 'aa aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'crr' }, { 'aa', 'aa' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', 'cr' }, 'aa aa', 4)
end

T['Replace']['respects `vim.{g,b}.minioperators_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minioperators_disable = true

    validate_edit1d('aa bb', 0, { 'yiw', 'w', 'griw' }, 'aa wbb', 4)
  end,
})

return T
