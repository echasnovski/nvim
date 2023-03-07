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
local simplepos_to_pos = function(x) return { line = x[1], col = x[2] } end

local validate_positions = function(out, ref) eq(out, vim.tbl_map(simplepos_to_pos, ref)) end

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

local toggle = function(...) return child.lua_get('MiniSplitjoin.toggle(...)', { ... }) end

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

local split = function(...) return child.lua_get('MiniSplitjoin.split(...)', { ... }) end

T['split()']['works'] = function()
  validate_edit({ '(aaa, bb, c)' }, { 1, 0 }, { '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 }, split)
  validate_edit({ '[aaa, bb, c]' }, { 1, 0 }, { '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 }, split)
  validate_edit({ '{aaa, bb, c}' }, { 1, 0 }, { '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 }, split)
end

--stylua: ignore
T['split()']['works for arguments on multiple lines'] = function()
  validate_edit({ '(a', 'b',   'c)' },     { 1, 0 }, { '(', '\ta', '\tb', '\tc', ')' }, { 1, 0 }, split)
  validate_edit({ '(a', '\tb', '\t\tc)' }, { 1, 0 }, { '(', '\ta', '\t\tb', '\t\t\tc', '\t\t)' }, { 1, 0 }, split)

  validate_edit({ '(a', 'b, c', 'd)' }, { 1, 0 }, { '(', '\ta', '\tb,', '\tc', '\td', ')' }, { 1, 0 }, split)

  -- This can be better, but currently is outside of cost/benefit ratio
  validate_edit({ '(', '\ta,', '\tb', ')' }, { 1, 0 }, { "(", "", "\t\ta,", "\t", "\t\tb", "\t)" }, { 1, 0 }, split)
end

T['split()']['works on any part inside or on brackets'] = function()
  validate_edit({ 'b( a )b' }, { 1, 0 }, { 'b( a )b' }, { 1, 0 }, split)
  validate_edit({ 'b( a )b' }, { 1, 1 }, { 'b(', '\ta', ')b' }, { 1, 1 }, split)
  validate_edit({ 'b( a )b' }, { 1, 2 }, { 'b(', '\ta', ')b' }, { 2, 1 }, split)
  validate_edit({ 'b( a )b' }, { 1, 3 }, { 'b(', '\ta', ')b' }, { 2, 1 }, split)
  validate_edit({ 'b( a )b' }, { 1, 4 }, { 'b(', '\ta', ')b' }, { 2, 1 }, split)
  validate_edit({ 'b( a )b' }, { 1, 5 }, { 'b(', '\ta', ')b' }, { 3, 0 }, split)
  validate_edit({ 'b( a )b' }, { 1, 6 }, { 'b( a )b' }, { 1, 6 }, split)
end

T['split()']['works on indented line'] = function()
  validate_edit({ '\t (aaa, bb, c)' }, { 1, 2 }, { '\t (', '\t \taaa,', '\t \tbb,', '\t \tc', '\t )' }, { 1, 2 }, split)
end

T['split()']['works inside comments'] = function()
  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate_edit({ '# (aaa)' }, { 1, 2 }, { '# (', '# \taaa', '# )' }, { 1, 2 }, split)

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate_edit({ '-- (aaa)' }, { 1, 3 }, { '-- (', '-- \taaa', '-- )' }, { 1, 3 }, split)
  validate_edit({ '--- (aaa)' }, { 1, 4 }, { '--- (', '--- \taaa', '--- )' }, { 1, 4 }, split)
end

T['split()']['correctly increases indent of commented line in non-commented block'] = function()
  child.bo.commentstring = '# %s'
  validate_edit({ '(aa', '# b', 'c)' }, { 1, 0 }, { '(', '\taa', '\t# b', '\tc', ')' }, { 1, 0 }, split)
end

T['split()']['ignores separators inside nested arguments'] = function()
  validate_edit(
    { '(a, (b, c), [d, e], {f, e})' },
    { 1, 0 },
    { '(', '\ta,', '\t(b, c),', '\t[d, e],', '\t{f, e}', ')' },
    { 1, 0 },
    split
  )
end

T['split()']['ignores separators inside quotes'] = function()
  validate_edit({ [[(a, 'b, c', "d, e")]] }, { 1, 0 }, { '(', '\ta,', "\t'b, c',", '\t"d, e"', ')' }, { 1, 0 }, split)
end

T['split()']['works in empty brackets'] = function()
  validate_edit({ '()' }, { 1, 0 }, { '(', ')' }, { 1, 0 }, split)
  validate_edit({ '()' }, { 1, 1 }, { '(', ')' }, { 2, 0 }, split)
end

T['split()']["respects 'expandtab' and 'shiftwidth' for indenting"] = function()
  child.o.expandtab = true
  child.o.shiftwidth = 3
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(', '   aaa', ')' }, { 1, 0 }, split)
end

T['split()']['returns `nil` if no positions are found'] = function()
  set_lines({ 'aaa' })
  eq(split(), vim.NIL)
  eq(get_lines(), { 'aaa' })
end

T['split()']['respects `opts.position`'] = function()
  validate_edit({ ' (aaa)' }, { 1, 0 }, { ' (', ' \taaa', ' )' }, { 1, 0 }, split, { position = { line = 1, col = 2 } })
  validate_edit({ ' (aaa)' }, { 1, 1 }, { ' (aaa)' }, { 1, 1 }, split, { position = { line = 1, col = 1 } })
end

T['split()']['respects `opts.region`'] = function()
  local lines = { '(a, ")", b)' }
  local region = { from = { line = 1, col = 1 }, to = { line = 1, col = 11 } }
  validate_edit(lines, { 1, 0 }, { '(', '\ta,', '\t")",', '\tb', ')' }, { 1, 0 }, split, { region = region })
end

T['split()']['respects `opts.detect.brackets`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.brackets = { '%b{}' }")
  validate_edit({ '[aaa]' }, { 1, 0 }, { '[aaa]' }, { 1, 0 }, split)
  validate_edit({ '{aaa}' }, { 1, 0 }, { '{', '\taaa', '}' }, { 1, 0 }, split)

  -- Local
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, split, { detect = { brackets = {} } })
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, split, { detect = { brackets = { '%b[]' } } })
end

T['split()']['respects `opts.detect.separator`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.separator = '|'")
  validate_edit({ '(a|b)' }, { 1, 0 }, { '(', '\ta|', '\tb', ')' }, { 1, 0 }, split)

  -- Local
  local opts = { detect = { separator = '[,;]' } }
  validate_edit({ '(a, b; c)' }, { 1, 0 }, { '(', '\ta,', '\tb;', '\tc', ')' }, { 1, 0 }, split, opts)

  -- Empty separator should mean no internal separator
  opts = { detect = { separator = '' } }
  validate_edit({ '(a, b; c)' }, { 1, 0 }, { '(', '\ta, b; c', ')' }, { 1, 0 }, split, opts)
end

T['split()']['respects `opts.detect.exclude_regions`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.exclude_regions = { '%b[]' }")
  validate_edit(
    { '(a, (b, c), [d, e])' },
    { 1, 0 },
    { '(', '\ta,', '\t(b,', '\tc),', '\t[d, e]', ')' },
    { 1, 0 },
    split
  )

  -- Local
  local opts = { detect = { exclude_regions = { '%b()' } } }
  validate_edit(
    { '(a, (b, c), [d, e])' },
    { 1, 0 },
    { '(', '\ta,', '\t(b, c),', '\t[d,', '\te]', ')' },
    { 1, 0 },
    split,
    opts
  )
end

T['split()']['respects `opts.split.hooks_pre`'] = function()
  child.lua('_G.hook_pre_1 = function(...) _G.hook_pre_1_args = { ... }; return ... end')
  child.lua([[_G.hook_pre_2 = function(positions)
    _G.hook_pre_2_positions = positions
    return { positions[1] } end
  ]])

  local positions_ref = { { line = 1, col = 1 }, { line = 1, col = 4 } }

  -- Global
  child.lua('MiniSplitjoin.config.split.hooks_pre = { _G.hook_pre_2 }')
  set_lines({ '(aaa)' })
  split()
  eq(get_lines(), { '(', 'aaa)' })
  eq(child.lua_get('_G.hook_pre_1_args'), vim.NIL)
  eq(child.lua_get('_G.hook_pre_2_positions'), positions_ref)

  -- Local
  set_lines({ '(aaa)' })
  child.lua('MiniSplitjoin.split({ split = { hooks_pre = { _G.hook_pre_1, _G.hook_pre_2 } } })')
  eq(get_lines(), { '(', 'aaa)' })
  eq(child.lua_get('_G.hook_pre_1_args'), { positions_ref })
  eq(child.lua_get('_G.hook_pre_2_positions'), positions_ref)
end

T['split()']['respects `opts.split.hooks_post`'] = function()
  child.lua('_G.hook_post_1 = function(...) _G.hook_post_1_args = { ... }; return ... end')
  child.lua([[_G.hook_post_2 = function(positions)
    _G.hook_post_2_positions = positions
    return { positions[1] } end
  ]])

  local positions_ref = { { line = 1, col = 1 }, { line = 2, col = 4 }, { line = 3, col = 1 } }

  -- Global
  child.lua('MiniSplitjoin.config.split.hooks_post = { _G.hook_post_2 }')
  set_lines({ '(aaa)' })
  local out = split()
  eq(out, { { line = 1, col = 1 } })

  eq(get_lines(), { '(', '\taaa', ')' })
  eq(child.lua_get('_G.hook_post_1_args'), vim.NIL)
  eq(child.lua_get('_G.hook_post_2_positions'), positions_ref)

  -- Local
  set_lines({ '(aaa)' })
  out = child.lua_get('MiniSplitjoin.split({ split = { hooks_post = { _G.hook_post_1, _G.hook_post_2 } } })')
  eq(out, { { line = 1, col = 1 } })

  eq(get_lines(), { '(', '\taaa', ')' })
  eq(child.lua_get('_G.hook_post_1_args'), { positions_ref })
  eq(child.lua_get('_G.hook_post_2_positions'), positions_ref)
end

T['split()']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisplitjoin_disable = true
    validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, split)
  end,
})

T['split()']['respects `vim.b.minisplitjoin_config`'] = function()
  child.lua([[vim.b.minisplitjoin_config = { detect = { brackets = { '%b[]' } } }]])
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, split)
end

T['join()'] = new_set()

local join = function(...) return child.lua_get('MiniSplitjoin.join(...)', { ... }) end

T['join()']['works'] = function() MiniTest.skip() end

T['join()']['works for arguments on single line'] = function() MiniTest.skip() end

T['join()']['does nothing if arguments are on single line'] = function() MiniTest.skip() end

T['join()']['works inside comments'] = function() MiniTest.skip() end

T['join()']['works in empty brackets'] = function() MiniTest.skip() end

T['join()']['joins nested multiline argument into single line'] = function() MiniTest.skip() end

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

T['gen_hook'] = new_set()

T['gen_hook']['pad_brackets()'] = new_set()

T['gen_hook']['pad_brackets()']['works'] = function()
  -- Should return correctly updated input
  MiniTest.skip()
end

T['gen_hook']['pad_brackets()']['does not act in case of no arguments'] = function() MiniTest.skip() end

T['gen_hook']['pad_brackets()']['respects `opts.pad`'] = function() MiniTest.skip() end

T['gen_hook']['pad_brackets()']['respects `opts.brackets`'] = function() MiniTest.skip() end

T['gen_hook']['add_trailing_separator()'] = new_set()

T['gen_hook']['add_trailing_separator()']['works'] = function()
  -- Should return correctly updated input
  MiniTest.skip()
end

T['gen_hook']['add_trailing_separator()']['does nothing if there is already trailing separator'] =
  function() MiniTest.skip() end

T['gen_hook']['add_trailing_separator()']['does not act in case of no arguments'] = function() MiniTest.skip() end

T['gen_hook']['add_trailing_separator()']['respects `opts.sep`'] = function() MiniTest.skip() end

T['gen_hook']['add_trailing_separator()']['respects `opts.brackets`'] = function() MiniTest.skip() end

T['gen_hook']['del_trailing_separator()'] = new_set()

T['gen_hook']['del_trailing_separator()']['works'] = function()
  -- Should return correctly updated input
  MiniTest.skip()
end

T['gen_hook']['del_trailing_separator()']['does nothing if there is already no trailing separator'] =
  function() MiniTest.skip() end

T['gen_hook']['del_trailing_separator()']['respects `opts.sep`'] = function() MiniTest.skip() end

T['gen_hook']['del_trailing_separator()']['respects `opts.brackets`'] = function() MiniTest.skip() end

T['split_at()'] = new_set()

local split_at = function(positions)
  return child.lua_get('MiniSplitjoin.split_at(...)', { vim.tbl_map(simplepos_to_pos, positions) })
end

T['split_at()']['works'] = function()
  validate_edit({ '(aaa)' }, { 1, 2 }, { '(', '\taaa', ')' }, { 2, 2 }, split_at, { { 1, 1 }, { 1, 4 } })

  validate_edit({ '()' }, { 1, 1 }, { '(', '', ')' }, { 3, 0 }, split_at, { { 1, 1 }, { 1, 1 } })

  validate_edit(
    { '(aaa, bb, c)' },
    { 1, 7 },
    { '(', '\taaa,', '\tbb,', '\tc', ')' },
    { 3, 2 },
    split_at,
    { { 1, 1 }, { 1, 5 }, { 1, 9 }, { 1, 11 } }
  )
end

T['split_at()']['works not on single line'] = function()
  validate_edit(
    { 'aabb', 'ccdd' },
    { 1, 3 },
    { 'aa', '\tbb', '\tcc', 'dd' },
    { 2, 2 },
    split_at,
    { { 1, 2 }, { 2, 2 } }
  )
end

T['split_at()']['properly tracks cursor'] = function()
  validate_edit({ '()' }, { 1, 0 }, { '(', ')' }, { 1, 0 }, split_at, { { 1, 1 } })
  validate_edit({ '()' }, { 1, 1 }, { '(', ')' }, { 2, 0 }, split_at, { { 1, 1 } })

  local cursors = {
    { before = { 1, 0 }, after = { 1, 0 } },
    { before = { 1, 1 }, after = { 1, 1 } },
    { before = { 1, 2 }, after = { 2, 1 } },
    { before = { 1, 3 }, after = { 2, 1 } },
    { before = { 1, 4 }, after = { 2, 2 } },
    { before = { 1, 5 }, after = { 2, 3 } },
    { before = { 1, 6 }, after = { 2, 3 } },
    { before = { 1, 7 }, after = { 3, 0 } },
    { before = { 1, 8 }, after = { 3, 1 } },
  }
  for _, cursor in ipairs(cursors) do
    validate_edit(
      { 'b( aaa )b' },
      cursor.before,
      { 'b(', '\taaa', ')b' },
      cursor.after,
      split_at,
      { { 1, 2 }, { 1, 7 } }
    )
  end
end

T['split_at()']['copies indent of current line'] = function()
  validate_edit(
    { ' \t (aaa)' },
    { 1, 5 },
    { ' \t (', ' \t \taaa', ' \t )' },
    { 2, 5 },
    split_at,
    { { 1, 4 }, { 1, 7 } }
  )
end

T['split_at()']['does not increase indent of blank lines'] = function()
  validate_edit(
    { '(', 'a,b)' },
    { 2, 3 },
    { '(', '', '\ta,', '\tb', ')' },
    { 5, 0 },
    split_at,
    { { 1, 1 }, { 2, 2 }, { 2, 3 } }
  )

  validate_edit({ '  (', ')' }, { 2, 0 }, { '  (', '  ', ')' }, { 3, 0 }, split_at, { { 1, 3 } })
end

T['split_at()']['handles extra whitespace'] = function()
  validate_edit({ '(   aaa   )' }, { 1, 5 }, { '(', '\taaa', ')' }, { 2, 2 }, split_at, { { 1, 1 }, { 1, 7 } })
  validate_edit({ '(   aaa   )' }, { 1, 5 }, { '(', '\taaa', ')' }, { 2, 2 }, split_at, { { 1, 3 }, { 1, 9 } })
end

T['split_at()']['correctly tracks input positions'] = function()
  set_lines({ '(aaa, bb, c)' })
  local out = split_at({ { 1, 1 }, { 1, 5 }, { 1, 9 }, { 1, 11 } })
  validate_positions(out, { { 1, 1 }, { 2, 5 }, { 3, 4 }, { 4, 2 } })
  eq(get_lines(), { '(', '\taaa,', '\tbb,', '\tc', ')' })
end

--stylua: ignore
T['split_at()']['works inside comments'] = function()
  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate_edit({ '# (aaa)' }, { 1, 2 }, { '# (', '# \taaa', '# )' }, { 1, 2 }, split_at, { { 1, 3 }, { 1, 6 } })

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate_edit({ '-- (aaa)' },  { 1, 3 }, { '-- (',  '-- \taaa',  '-- )' },  { 1, 3 }, split_at, { { 1, 4 }, { 1, 7 } })
  validate_edit({ '--- (aaa)' }, { 1, 4 }, { '--- (', '--- \taaa', '--- )' }, { 1, 4 }, split_at, { { 1, 5 }, { 1, 8 } })
end

T['split_at()']['correctly increases indent of commented line in non-commented block'] = function()
  child.bo.commentstring = '# %s'

  validate_edit(
    { '(aa', '# b', 'c)' },
    { 1, 0 },
    { '(', '\taa', '\t# b', '\tc', ')' },
    { 1, 0 },
    split_at,
    { { 1, 1 }, { 3, 1 } }
  )
end

T['split_at()']['uses first and last positions to determine indent range'] = function()
  validate_edit(
    { '(a, b, c)' },
    { 1, 0 },
    { '(', 'a,', 'b,', '\tc', ')' },
    { 1, 0 },
    split_at,
    { { 1, 6 }, { 1, 3 }, { 1, 1 }, { 1, 8 } }
  )
end

T['split_at()']["respects 'expandtab' and 'shiftwidth' for indent increase"] = function()
  child.o.expandtab = true
  child.o.shiftwidth = 3
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(', '   aaa', ')' }, { 1, 0 }, split_at, { { 1, 1 }, { 1, 4 } })
end

T['join_at()'] = new_set()

local join_at = function(positions)
  return child.lua_get('MiniSplitjoin.join_at(...)', { vim.tbl_map(simplepos_to_pos, positions) })
end

T['join_at()']['works'] = function()
  validate_edit(
    { '(', '\taaa,', '   bb,', 'c', ')' },
    { 2, 2 },
    { '(aaa, bb, c)' },
    { 1, 2 },
    join_at,
    { { 1, 1 }, { 2, 4 }, { 3, 3 }, { 4, 1 } }
  )
end

T['join_at()']['works on single line'] = function()
  validate_edit({ '(', '\ta', '\tb', ')' }, { 1, 0 }, { '(a b)' }, { 1, 0 }, join_at, { { 1, 1 }, { 1, 1 }, { 1, 1 } })
end

T['join_at()']['joins line at any its column'] = function()
  for i = 1, 4 do
    validate_edit({ '   (', '\taaa', ')' }, { 2, 2 }, { '   (aaa)' }, { 1, 5 }, join_at, { { 1, i }, { 2, i } })
  end
end

T['join_at()']['properly tracks cursor'] = function()
  validate_edit({ '(', ')' }, { 1, 0 }, { '()' }, { 1, 0 }, join_at, { { 1, 1 } })
  validate_edit({ '(', ')' }, { 2, 0 }, { '()' }, { 1, 1 }, join_at, { { 1, 1 } })

  local cursors = {
    { before = { 1, 0 }, after = { 1, 0 } },
    { before = { 1, 1 }, after = { 1, 1 } },
    { before = { 2, 0 }, after = { 1, 2 } },
    { before = { 2, 1 }, after = { 1, 2 } },
    { before = { 2, 2 }, after = { 1, 3 } },
    { before = { 2, 3 }, after = { 1, 4 } },
    { before = { 2, 4 }, after = { 1, 5 } },
    { before = { 3, 0 }, after = { 1, 5 } },
    { before = { 3, 1 }, after = { 1, 6 } },
  }
  for _, cursor in ipairs(cursors) do
    validate_edit({ 'b(', '\taaa ', ')b' }, cursor.before, { 'b(aaa)b' }, cursor.after, join_at, { { 1, 2 }, { 2, 4 } })
  end
end

T['join_at()']['handles extra whitespace'] = function()
  validate_edit(
    { '( \t', '\t\ta  ', '  b\t\t', ' \t  )' },
    { 1, 0 },
    { '(a b)' },
    { 1, 0 },
    join_at,
    { { 1, 1 }, { 2, 1 }, { 3, 1 } }
  )
end

T['join_at()']['correctly works with positions on last line'] = function()
  validate_edit(
    { '(', 'a', ')b' },
    { 1, 0 },
    { '(a )b' },
    { 1, 0 },
    join_at,
    { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 3, 2 } }
  )
end

T['join_at()']['correctly tracks input positions'] = function()
  set_lines({ '(', '\taaa,', '\tbb,', '\tc', ')' })
  local out = join_at({ { 1, 1 }, { 2, 5 }, { 3, 4 }, { 4, 2 } })
  validate_positions(out, { { 1, 1 }, { 1, 5 }, { 1, 9 }, { 1, 11 } })
  eq(get_lines(), { '(aaa, bb, c)' })
end

--stylua: ignore
T['join_at()']['works inside comments'] = function()
  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate_edit({ '# (', '# \taaa', '# )' }, { 1, 2 }, { '# (aaa)' }, { 1, 2 }, join_at, { {1, 1}, {2, 1} })
  validate_edit({ '# (', 'aaa',     '# )' }, { 1, 2 }, { '# (aaa)' }, { 1, 2 }, join_at, { {1, 1}, {2, 2} })

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate_edit({ '-- (',  '-- \taaa',  '-- )' },  { 1, 3 }, { '-- (aaa)' },  { 1, 3 }, join_at, { { 1, 1 }, { 2, 2 } })
  validate_edit({ '--- (', '--- \taaa', '--- )' }, { 1, 4 }, { '--- (aaa)' }, { 1, 4 }, join_at, { { 1, 1 }, { 2, 2 } })
end

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
