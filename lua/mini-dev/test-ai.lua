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
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

local get_latest_message = function() return child.cmd_capture('1messages') end

local validate_edit = function(before_lines, before_cursor, after_lines, after_cursor, keys)
  child.ensure_normal_mode()

  set_lines(before_lines)
  set_cursor(unpack(before_cursor))

  type_keys(keys)

  eq(get_lines(), after_lines)
  eq(get_cursor(), after_cursor)
end

local validate_edit1d = function(before_line, before_column, after_line, after_column, keys)
  validate_edit({ before_line }, { 1, before_column }, { after_line }, { 1, after_column }, keys)
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

local validate_find = function(lines, cursor, args, expected)
  set_lines(lines)
  set_cursor(cursor[1], cursor[2])

  local new_expected
  if expected == nil then
    new_expected = vim.NIL
  else
    new_expected = {
      left = { line = expected[1][1], col = expected[1][2] },
      right = { line = expected[2][1], col = expected[2][2] },
    }
  end

  eq(child.lua_get('MiniAi.find_textobject(...)', args), new_expected)
end

local validate_find1d = function(line, column, args, expected)
  local new_expected
  if expected ~= nil then new_expected = { { 1, expected[1] }, { 1, expected[2] } } end
  validate_find({ line }, { 1, column }, args, new_expected)
end

T['find_textobject()'] = new_set()

T['find_textobject()']['works'] = function() validate_find1d('aa(bb)cc', 3, { 'a', ')' }, { 3, 6 }) end

T['find_textobject()']['respects `id` argument'] =
  function() validate_find1d('(aa[bb]cc)', 4, { 'a', ']' }, { 4, 7 }) end

T['find_textobject()']['respects `ai_type` argument'] =
  function() validate_find1d('aa(bb)cc', 3, { 'i', ')' }, { 4, 5 }) end

T['find_textobject()']['respects `opts.n_lines`'] = function()
  local lines = { '(', '', 'a', '', ')' }
  validate_find(lines, { 3, 1 }, { 'a', ')', { n_lines = 1 } }, nil)
  validate_find(lines, { 3, 1 }, { 'a', ')', { n_lines = 2 } }, { { 1, 1 }, { 5, 1 } })

  -- Should handle 0
  validate_find(lines, { 3, 1 }, { 'a', ')', { n_lines = 0 } }, nil)
end

T['find_textobject()']['respects `opts.n_times`'] = function()
  local line, column = '(aa(bb)cc)', 4
  validate_find1d(line, column, { 'a', ')', { n_times = 1 } }, { 4, 7 })
  validate_find1d(line, column, { 'a', ')', { n_times = 2 } }, { 1, 10 })
  validate_find1d(line, column, { 'i', ')', { n_times = 2 } }, { 2, 9 })

  -- Should handle 0
  validate_find1d(line, 0, { 'a', ')', { n_times = 0 } }, nil)
end

T['find_textobject()']['respects `opts.reference_region`'] = function()
  local line = 'aa(bb(cc)dd)ee'
  local new_opts = function(left, right)
    return { reference_region = { left = { line = 1, col = left }, right = { line = 1, col = right } } }
  end

  validate_find1d(line, 0, { 'a', ')', new_opts(7, 7) }, { 6, 9 })
  validate_find1d(line, 0, { 'a', ')', new_opts(6, 9) }, { 3, 12 })
  validate_find1d(line, 0, { 'a', ')', new_opts(3, 12) }, nil)
end

T['find_textobject()']['respects `opts.search_method`'] = function()
  local line = '(aa)bbb(cc)'
  local new_opts = function(search_method) return { search_method = search_method } end

  -- By default should be 'cover_or_next'
  validate_find1d(line, 4, { 'a', ')' }, { 8, 11 })

  validate_find1d(line, 1, { 'a', ')', new_opts('cover_or_next') }, { 1, 4 })
  validate_find1d(line, 4, { 'a', ')', new_opts('cover_or_next') }, { 8, 11 })
  validate_find1d(line, 8, { 'a', ')', new_opts('cover_or_next') }, { 8, 11 })

  validate_find1d(line, 1, { 'a', ')', new_opts('cover') }, { 1, 4 })
  validate_find1d(line, 4, { 'a', ')', new_opts('cover') }, nil)
  validate_find1d(line, 8, { 'a', ')', new_opts('cover') }, { 8, 11 })

  validate_find1d(line, 1, { 'a', ')', new_opts('cover_or_prev') }, { 1, 4 })
  validate_find1d(line, 4, { 'a', ')', new_opts('cover_or_prev') }, { 1, 4 })
  validate_find1d(line, 8, { 'a', ')', new_opts('cover_or_prev') }, { 8, 11 })

  validate_find1d(line, 1, { 'a', ')', new_opts('cover_or_nearest') }, { 1, 4 })
  validate_find1d(line, 4, { 'a', ')', new_opts('cover_or_nearest') }, { 1, 4 })
  validate_find1d(line, 5, { 'a', ')', new_opts('cover_or_nearest') }, { 1, 4 })
  validate_find1d(line, 6, { 'a', ')', new_opts('cover_or_nearest') }, { 8, 11 })
  validate_find1d(line, 8, { 'a', ')', new_opts('cover_or_nearest') }, { 8, 11 })
end

T['find_textobject()']['respects custom textobjects'] = function()
  local line, column = 'aabbcc', 0

  validate_find1d(line, column, { 'a', 'c' }, nil)
  child.lua([[MiniAi.config.custom_textobjects = { c = { '()c()' } }]])
  validate_find1d(line, column, { 'a', 'c' }, { 5, 5 })
end

T['find_textobject()']['works on multiple lines'] = function()
  local lines, cursor = { '(aa', '(bb', 'cc', 'dd)', 'ee)' }, { 3, 0 }
  validate_find(lines, cursor, { 'a', ')' }, { { 2, 1 }, { 4, 3 } })
  validate_find(lines, cursor, { 'i', ')' }, { { 2, 2 }, { 4, 2 } })
  validate_find(lines, cursor, { 'a', ')', { n_times = 2 } }, { { 1, 1 }, { 5, 3 } })
  validate_find(lines, cursor, { 'i', ')', { n_times = 2 } }, { { 1, 2 }, { 5, 2 } })

  -- Region over multiple lines is not empty (it has newline)
  validate_find({ 'aa(', ')' }, { 1, 1 }, { 'i', ')' }, { { 1, 4 }, { 1, 4 } })
end

T['find_textobject()']['may return position after line end'] = function()
  -- This powers multiline collapsing (calling `di)` leads to '()' single line)
  validate_find({ '(', 'aa', ')' }, { 2, 0 }, { 'i', ')' }, { { 1, 2 }, { 2, 3 } })
end

T['find_textobject()']['works with multibyte characters'] = function()
  -- Each multibyte character takes two column counts
  local line = '(ыы)ффф(ыы)'
  validate_find1d(line, 1, { 'a', ')' }, { 1, 6 })
  validate_find1d(line, 1, { 'a', ')', { n_times = 2 } }, { 13, 18 })
  validate_find1d(line, 6, { 'a', ')' }, { 13, 18 })
end

T['find_textobject()']['handles cursor on textobject edge'] = function()
  validate_find1d('aa(bb)cc', 2, { 'a', ')' }, { 3, 6 })
  validate_find1d('aa(bb)cc', 2, { 'i', ')' }, { 4, 5 })

  validate_find1d('aa(bb)cc', 5, { 'a', ')' }, { 3, 6 })
  validate_find1d('aa(bb)cc', 5, { 'i', ')' }, { 4, 5 })
end

T['find_textobject()']['first searches within current line'] = function()
  local lines, cursor = { '(', 'aa(bb)', ')' }, { 2, 0 }
  validate_find(lines, cursor, { 'a', ')' }, { { 2, 3 }, { 2, 6 } })
  validate_find(lines, cursor, { 'a', ')', { search_method = 'cover' } }, { { 1, 1 }, { 3, 1 } })
end

T['find_textobject()']['handles `n_times > 1` with matches on current line'] = function()
  local lines, cursor = { '((', 'aa(bb)cc(dd)', '))' }, { 2, 0 }
  validate_find(lines, cursor, { 'a', ')', { n_times = 1 } }, { { 2, 3 }, { 2, 6 } })
  validate_find(lines, cursor, { 'a', ')', { n_times = 2 } }, { { 2, 9 }, { 2, 12 } })
  validate_find(lines, cursor, { 'a', ')', { n_times = 3 } }, { { 1, 2 }, { 3, 1 } })
  validate_find(lines, cursor, { 'a', ')', { n_times = 4 } }, { { 1, 1 }, { 3, 2 } })
end

T['find_textobject()']['handles empty region'] = function()
  -- Empty region has left edge strictly on right of right edge
  local line, column = 'aa()bb(cc)', 0
  validate_find1d(line, column, { 'i', ')' }, { 4, 3 })
  validate_find1d(line, column, { 'i', ')', { n_times = 2 } }, { 8, 9 })
end

T['find_textobject()']['handles function as textobject spec'] = function()
  child.lua([[MiniAi.config.custom_textobjects = { c = function() return { '()c()' } end }]])
  validate_find1d('aabbcc', 0, { 'a', 'c' }, { 5, 5 })
end

T['find_textobject()']['shows message if no region is found'] = function()
  -- Avoid hit-enter-prompt
  child.o.columns = 150

  local validate = function(msg, args)
    child.cmd('messages clear')
    validate_find1d('aa', 0, args, nil)
    eq(get_latest_message(), msg)
  end

  validate(
    [[(mini.ai) No textobject "a)" found covering region within 50 lines and `search_method = 'cover_or_next'`.]],
    { 'a', ')' }
  )
  validate(
    [[(mini.ai) No textobject "i]" found covering region 2 times within 1 line and `search_method = 'cover'`.]],
    { 'i', ']', { n_times = 2, n_lines = 1, search_method = 'cover' } }
  )
  validate(
    [[(mini.ai) No textobject "i]" found covering region 0 times within 0 lines and `search_method = 'cover_or_next'`.]],
    { 'i', ']', { n_times = 0, n_lines = 0 } }
  )
end

T['find_textobject()']['respects `vim.b.miniai_config`'] = function()
  child.b.miniai_config = { search_method = 'cover' }
  validate_find1d('aa(bb)', 0, { 'a', ')' }, nil)
end

local validate_move = function(lines, cursor, args, expected)
  set_lines(lines)
  set_cursor(cursor[1], cursor[2])
  child.lua([[MiniAi.move_cursor(...)]], args)
  eq(get_cursor(), { expected[1], expected[2] })
end

local validate_move1d =
  function(line, column, args, expected) validate_move({ line }, { 1, column }, args, { 1, expected }) end

T['move_cursor()'] = new_set()

T['move_cursor()']['works'] = function() validate_move1d('aa(bbb)', 4, { 'left', 'a', ')' }, 2) end

T['move_cursor()']['respects `side` argument'] = function()
  local line = '(aa)bb(cc)'
  validate_move1d(line, 1, { 'left', 'a', ')' }, 0)
  validate_move1d(line, 1, { 'right', 'a', ')' }, 3)
  validate_move1d(line, 4, { 'left', 'a', ')' }, 6)
  validate_move1d(line, 4, { 'right', 'a', ')' }, 9)
  validate_move1d(line, 7, { 'left', 'a', ')' }, 6)
  validate_move1d(line, 7, { 'right', 'a', ')' }, 9)

  -- It should validate `side` argument
  expect.error(
    function() child.lua([[MiniAi.move_cursor('leftright', 'a', ')')]]) end,
    vim.pesc([[(mini.ai) `side` should be one of 'left' or 'right'.]])
  )
end

T['move_cursor()']['respects `ai_type` argument'] = function()
  validate_move1d('aa(bbb)', 4, { 'left', 'i', ')' }, 3)
  validate_move1d('aa(bbb)', 4, { 'right', 'i', ')' }, 5)
end

T['move_cursor()']['respects `id` argument'] = function() validate_move1d('aa[bbb]', 4, { 'left', 'a', ']' }, 2) end

T['move_cursor()']['respects `opts` argument'] =
  function() validate_move1d('aa(bbb)cc(ddd)', 4, { 'left', 'a', ')', { n_times = 2 } }, 9) end

T['move_cursor()']['always jumps exactly `opts.n_times` times'] = function()
  -- It can be not that way if cursor is on edge of one of target textobjects
  local line = 'aa(bb)cc(dd)ee(ff)'
  validate_move1d(line, 0, { 'left', 'a', ')', { n_times = 2 } }, 8) -- 0->2->8
  validate_move1d(line, 2, { 'left', 'a', ')', { n_times = 2 } }, 14) -- 2->8->14
  validate_move1d(line, 3, { 'left', 'a', ')', { n_times = 2 } }, 8) -- 3->2->8
  validate_move1d(line, 5, { 'left', 'a', ')', { n_times = 2 } }, 8) -- 5->2->8

  validate_move1d(line, 0, { 'right', 'a', ')', { n_times = 2 } }, 11) -- 0->5->11
  validate_move1d(line, 2, { 'right', 'a', ')', { n_times = 2 } }, 11) -- 2->5->11
  validate_move1d(line, 3, { 'right', 'a', ')', { n_times = 2 } }, 11) -- 3->5->11
  validate_move1d(line, 5, { 'right', 'a', ')', { n_times = 2 } }, 17) -- 5->11->17
end

T['move_cursor()']['opens just enough folds'] = function()
  set_lines({ '(aa', 'b)', 'c', 'd' })

  -- Manually create two nested closed folds
  set_cursor(3, 0)
  type_keys('zf', 'G')
  type_keys('zf', 'gg')
  eq(child.fn.foldlevel(1), 1)
  eq(child.fn.foldlevel(3), 2)
  eq(child.fn.foldclosed(2), 1)
  eq(child.fn.foldclosed(3), 1)

  -- Moving cursor should open just enough folds
  set_cursor(1, 1)
  child.lua([[MiniAi.move_cursor('right', 'a', ')')]])
  eq(get_cursor(), { 2, 1 })
  eq(child.fn.foldclosed(2), -1)
  eq(child.fn.foldclosed(3), 3)
end

T['move_cursor()']['handles function as textobject spec'] = function()
  -- Should call it only once
  child.lua('_G.n = 0')
  child.lua([[MiniAi.config.custom_textobjects = { c = function() _G.n = _G.n + 1; return { '()c()' } end }]])
  validate_move1d('aabbcc', 0, { 'left', 'a', 'c' }, 4)
  eq(child.lua_get('_G.n'), 1)
end

T['select_textobject()'] = new_set()

T['select_textobject()']['works'] = function() MiniTest.skip() end

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

T['Search method']['respects `vim.b.miniai_config`'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
local validate_textobject = function(lines, cursor, name, expected)
  child.ensure_normal_mode()
  set_lines(lines)
  set_cursor(unpack(cursor))
  type_keys('v', name)
  eq(child.fn.mode(), 'v')
  child.expect_visual_marks({ expected[1][1], expected[1][2] - 1 }, { expected[2][1], expected[2][2] - 1 })
end

local validate_textobject1d = function(line, column, name, expected)
  validate_textobject({ line }, { 1, column }, name, { { 1, expected[1] }, { 1, expected[2] } })
end

T['Textobject'] = new_set()

T['Textobject']['works'] = function() MiniTest.skip() end

T['Textobject']['works in Visual mode'] = function() MiniTest.skip() end

T['Textobject']['works in Operator-pending mode'] = function() MiniTest.skip() end

T['Textobject']['works with dot-repeat'] = function() MiniTest.skip() end

T['Textobject']['works multibyte characters'] = function() MiniTest.skip() end

T['Textobject']['respects `v:count`'] = function() MiniTest.skip() end

T['Builtin'] = new_set()

T['Builtin']['Open brackets'] = new_set({ parametrize = { { '(' }, { '[' }, { '{' } } })

T['Builtin']['Open brackets']['works'] = function(open)
  local close = ({ ['('] = ')', ['['] = ']', ['{'] = '}' })[open]
  MiniTest.skip()
end

T['Builtin']['Open brackets']['works with empty region'] = function() MiniTest.skip() end

T['Builtin']['Open brackets']['works on multiple lines'] = function() MiniTest.skip() end

T['Builtin']['Open brackets']['works consecutively'] = function() MiniTest.skip() end

T['Builtin']['Close brackets'] = new_set({ parametrize = { { ')' }, { ']' }, { '}' } } })

T['Builtin']['Close brackets']['works'] = function(close)
  local open = ({ [')'] = '(', [']'] = '[', ['}'] = '{' })[close]
  MiniTest.skip()
end

T['Builtin']['Close brackets']['works with empty region'] = function() MiniTest.skip() end

T['Builtin']['Close brackets']['works on multiple lines'] = function() MiniTest.skip() end

T['Builtin']['Close brackets']['works consecutively'] = function() MiniTest.skip() end

T['Builtin']['Quotes'] = new_set()

T['Builtin']['Quotes']['works with empty region'] = function() MiniTest.skip() end

T['Builtin']['Quotes']['works consecutively'] = function() MiniTest.skip() end

T['Builtin']['User prompt'] = new_set()

T['Builtin']['User prompt']['works with empty region'] = function() MiniTest.skip() end

T['Builtin']['User prompt']['works with multibyte characters'] = function()
  -- Line: ы ы ф ф ы ф
  MiniTest.skip()
end

T['Builtin']['User prompt']['works consecutively'] = function() MiniTest.skip() end

T['Builtin']['Argument'] = new_set()

T['Builtin']['Argument']['works'] = function()
  -- Don't check on first comma, as it is ambiguous
  for i = 2, 3 do
    validate_textobject1d('f(xx, yy, tt)', i, 'aa', { 3, 5 })
    validate_textobject1d('f(xx, yy, tt)', i, 'ia', { 3, 4 })
  end
  for i = 5, 7 do
    validate_textobject1d('f(xx, yy, tt)', i, 'aa', { 5, 8 })
    validate_textobject1d('f(xx, yy, tt)', i, 'ia', { 7, 8 })
  end
  for i = 8, 11 do
    validate_textobject1d('f(xx, yy, tt)', i, 'aa', { 9, 12 })
    validate_textobject1d('f(xx, yy, tt)', i, 'ia', { 11, 12 })
  end
end

T['Builtin']['Argument']['is ambiguous on first comma'] = function()
  -- It chooses argument with smaller width. This is not good, but is a result
  -- of compromise over comma asymmetry.
  validate_textobject1d('f(x, yyyyyy)', 3, 'aa', { 3, 4 })
  validate_textobject1d('f(xxxxxx, y)', 8, 'aa', { 9, 11 })
end

T['Builtin']['Argument']['works inside all balanced brackets'] = function()
  validate_textobject1d('(xx, yy)', 2, 'aa', { 2, 4 })
  validate_textobject1d('[xx, yy]', 2, 'aa', { 2, 4 })
  validate_textobject1d('{xx, yy}', 2, 'aa', { 2, 4 })
end

T['Builtin']['Argument']['ignores commas inside balanced brackets'] = function()
  validate_textobject1d('f(xx, (yy, tt))', 5, 'aa', { 5, 14 })
  validate_textobject1d('f(xx, [yy, tt])', 5, 'aa', { 5, 14 })
  validate_textobject1d('f(xx, {yy, tt})', 5, 'aa', { 5, 14 })

  validate_textobject1d('f((xx, yy) , tt)', 10, 'aa', { 3, 12 })
  validate_textobject1d('f([xx, yy] , tt)', 10, 'aa', { 3, 12 })
  validate_textobject1d('f({xx, yy} , tt)', 10, 'aa', { 3, 12 })
end

T['Builtin']['Argument']['ignores commas inside balanced quotes'] = function()
  validate_textobject1d([[f(xx, 'yy, tt')]], 5, 'aa', { 5, 14 })
  validate_textobject1d([[f(xx, "yy, tt")]], 5, 'aa', { 5, 14 })

  validate_textobject1d([[f('xx, yy' , tt)]], 10, 'aa', { 3, 12 })
  validate_textobject1d([[f("xx, yy" , tt)]], 10, 'aa', { 3, 12 })
end

T['Builtin']['Argument']['ignores empty arguments'] = function()
  -- No argument should be detected
  validate_textobject1d('f()', 0, 'aa', { 1, 1 })

  validate_textobject1d('f(,)', 0, 'aa', { 3, 3 })
  validate_textobject1d('f(,)', 0, 'ia', { 3, 3 })

  validate_textobject1d('f(, xx)', 0, 'aa', { 3, 6 })
  validate_textobject1d('f(, xx)', 0, 'ia', { 5, 6 })

  validate_textobject1d('f(,, xx)', 0, 'aa', { 3, 3 })
  validate_textobject1d('f(,, xx)', 0, 'ia', { 3, 3 })
  validate_textobject1d('f(,, xx)', 0, '2aa', { 4, 7 })
  validate_textobject1d('f(,, xx)', 0, '2ia', { 6, 7 })

  validate_textobject1d('f(xx,, yy)', 0, 'aa', { 3, 5 })
  validate_textobject1d('f(xx,, yy)', 0, 'ia', { 3, 4 })
  validate_textobject1d('f(xx,, yy)', 0, '2aa', { 6, 9 })
  validate_textobject1d('f(xx,, yy)', 0, '2ia', { 8, 9 })

  validate_textobject1d('f(xx, yy,, tt)', 0, '1aa', { 3, 5 })
  validate_textobject1d('f(xx, yy,, tt)', 0, '2aa', { 5, 8 })
  validate_textobject1d('f(xx, yy,, tt)', 0, '3aa', { 9, 9 })
  validate_textobject1d('f(xx, yy,, tt)', 0, '4aa', { 10, 13 })

  validate_textobject1d('f(xx,,)', 0, 'aa', { 3, 5 })
  validate_textobject1d('f(xx,,)', 0, 'ia', { 3, 4 })
  validate_textobject1d('f(xx,,)', 0, '2aa', { 6, 6 })
  validate_textobject1d('f(xx,,)', 0, '2ia', { 6, 6 })

  validate_textobject1d('f(xx,)', 0, 'aa', { 3, 5 })
  validate_textobject1d('f(xx,)', 0, 'ia', { 3, 4 })
end

T['Builtin']['Argument']['works with whitespace argument'] = function()
  validate_textobject1d('f( )', 2, 'aa', { 3, 3 })

  validate_textobject1d('f( , )', 0, 'aa', { 3, 4 })
  validate_textobject1d('f( , )', 0, 'ia', { 3, 3 })
  validate_textobject1d('f( , )', 0, '2aa', { 4, 5 })
  validate_textobject1d('f( , )', 0, '2ia', { 5, 5 })

  validate_textobject1d('f(x, ,y)', 0, '2aa', { 4, 5 })
  validate_textobject1d('f(x, ,y)', 0, '2ia', { 5, 5 })
end

T['Builtin']['Argument']['works with single argument'] = function()
  validate_textobject1d('f(x)', 2, 'aa', { 3, 3 })
  validate_textobject1d('f(xx)', 0, 'aa', { 3, 4 })
  validate_textobject1d('f(xxx)', 0, 'aa', { 3, 5 })
end

T['Builtin']['Argument']['works in Operator-pending mode'] = function()
  local validate = function(before_line, before_column, after_line, after_column, keys)
    validate_edit1d(before_line, before_column, after_line, after_column, 'd' .. keys)
    validate_edit1d(before_line, before_column, after_line, after_column, 'c' .. keys)
    eq(child.fn.mode(), 'i')
  end

  -- Normal cases
  validate('f(x)', 2, 'f()', 2, 'aa')
  validate('f(x)', 2, 'f()', 2, 'ia')

  validate('f(  x)', 2, 'f()', 2, 'aa')
  validate('f(  x)', 2, 'f(  )', 4, 'ia')

  validate('f(x  )', 2, 'f()', 2, 'aa')
  validate('f(x  )', 2, 'f(  )', 2, 'ia')

  validate('f(  x  )', 2, 'f()', 2, 'aa')
  validate('f(  x  )', 2, 'f(    )', 4, 'ia')

  validate('f(x, y, t)', 2, 'f( y, t)', 2, 'aa')
  validate('f(x, y, t)', 2, 'f(, y, t)', 2, 'ia')
  validate('f(x, y, t)', 5, 'f(x, t)', 3, 'aa')
  validate('f(x, y, t)', 5, 'f(x, , t)', 5, 'ia')
  validate('f(x, y, t)', 8, 'f(x, y)', 6, 'aa')
  validate('f(x, y, t)', 8, 'f(x, y, )', 8, 'ia')

  -- Edge cases
  validate('f( )', 2, 'f()', 2, 'aa')
  validate('f( )', 2, 'f()', 2, 'ia')

  validate('f(, )', 2, 'f()', 2, 'aa')
  validate('f(, )', 2, 'f(, )', 4, 'ia')

  validate('f( ,)', 2, 'f()', 2, 'aa')
  validate('f( ,)', 2, 'f( ,)', 3, 'ia')

  validate('f(x,,)', 4, 'f(x,)', 4, 'aa')
  validate('f(x,,)', 4, 'f(x,,)', 5, 'ia')
end

T['Builtin']['Argument']['works consecutively'] = function()
  local validate_next = function(keys, next_region)
    type_keys(keys)
    eq({ child.fn.col('.'), child.fn.col('v') }, next_region)
  end

  -- `a` textobject
  set_lines({ 'f(xx, yy, tt)' })
  set_cursor(1, 0)
  type_keys('v')
  validate_next('aa', { 3, 5 })
  validate_next('aa', { 5, 8 })
  validate_next('aa', { 9, 12 })

  -- `i` textobject
  child.ensure_normal_mode()
  set_lines({ 'f(xx, yy, tt)' })
  set_cursor(1, 0)
  type_keys('v')
  validate_next('ia', { 3, 4 })
  validate_next('2ia', { 7, 8 })
  validate_next('2ia', { 11, 12 })
end

T['Builtin']['User prompt']['works consecutively'] = function() MiniTest.skip() end

T['Builtin']['Function call'] = new_set()

T['Builtin']['Function call']['works with empty region'] = function() MiniTest.skip() end

T['Builtin']['Function call']['works consecutively'] = function() MiniTest.skip() end

T['Builtin']['Tag'] = new_set()

T['Builtin']['Tag']['works with empty region'] = function() MiniTest.skip() end

T['Builtin']['Tag']['works consecutively'] = function() MiniTest.skip() end

T['Builtin']['Default'] = new_set()

T['Builtin']['Default']['work'] = function() MiniTest.skip() end

T['Builtin']['Default']['work in edge cases'] = function()
  -- `va_`, `ca_` for `__` line
  -- `va_`, `ca_` for `____` line
  MiniTest.skip()
end

T['Builtin']['Default']['work with empty region'] = function() MiniTest.skip() end

T['Builtin']['Default']['works consecutively'] = function() MiniTest.skip() end

T['Custom textobject'] = new_set()

T['Custom textobject']['works'] = function() MiniTest.skip() end

T['Custom textobject']['works consecutively'] = function() MiniTest.skip() end

T['Custom textobject']['expands specification'] = function() MiniTest.skip() end

T['Custom textobject']['handles different extractions in last item'] = function() MiniTest.skip() end

T['Custom textobject']['works with special patterns'] = new_set()

T['Custom textobject']['works with special patterns']['%bxx'] = function()
  -- `%bxx` should represent balanced character
end

T['Custom textobject']['works with special patterns']['x.-y'] = function()
  -- `x.-y` should work with `a%.-a` and `a%-a`

  -- `x.-y` should work with patterns like `x+.-x+`
end

T['Custom textobject']['selects smallest span'] = function()
  -- Edge strings can't be inside current span
  MiniTest.skip()
end

T['Custom textobject']['works with empty region'] = function() MiniTest.skip() end

T['Custom textobject']['works with single character region'] = function()
  -- In Visual and Operator-pending mode
  -- `cia` in `f(x)` when cursor is on `x`
  MiniTest.skip()
end

T['Custom textobject']['works with extreme specification'] = function()
  -- Specs:
  -- { 'x' } { '()x()' }, { '()()()x()' }, { '()x()()()' }
  MiniTest.skip()
end

T['Motion'] = new_set()

T['Motion']['works'] = function() MiniTest.skip() end

T['Motion']['works with dot-repeat'] = function() MiniTest.skip() end

T['Motion']['works multibyte characters'] = function() MiniTest.skip() end

return T
