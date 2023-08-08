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
end

T['Replace']['works linewise in Normal mode'] = function()
  local lines = { 'aa', '', 'bb', 'cc', '', 'dd', 'ee' }
  validate_edit(lines, { 1, 0 }, { 'yy', '2j', 'grip' }, { 'aa', '', 'aa', '', 'dd', 'ee' }, { 3, 0 })

  -- - With dot-repeat
  validate_edit(lines, { 1, 0 }, { 'yy', '2j', 'grip', '2j', '.' }, { 'aa', '', 'aa', '', 'aa' }, { 5, 0 })
end

T['Replace']['works blockwise in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', 'grie' }, { 'a a c', 'a a c' }, { 1, 2 })

  -- With dot-repeat
  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', 'grie', 'w', '.' }, { 'a a a', 'a a a' }, { 1, 4 })
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

return T
