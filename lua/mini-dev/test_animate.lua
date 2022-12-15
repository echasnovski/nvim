local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set
local mark_flaky = helpers.mark_flaky

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('animate', config) end
local unload_module = function() child.mini_unload('animate') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

-- TODO: Remove after compatibility with Neovim<=0.6 is dropped
local skip_on_old_neovim = function()
  if child.fn.has('nvim-0.7') == 0 then MiniTest.skip() end
end

-- Data =======================================================================
local test_times = { total_timing = 250 }

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
  eq(child.lua_get('type(_G.MiniAnimate)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniAnimate'), 1)

  -- Highlight groups
  expect.match(child.cmd_capture('hi MiniAnimateCursor'), 'gui=reverse,nocombine')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniAnimate.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniAnimate.config.' .. field), value) end
  local expect_config_function =
    function(field) eq(child.lua_get('type(MiniAnimate.config.' .. field .. ')'), 'function') end

  expect_config('cursor.enable', true)
  expect_config_function('cursor.timing')
  expect_config_function('cursor.path')

  expect_config('scroll.enable', true)
  expect_config_function('scroll.timing')
  expect_config_function('scroll.subscroll')

  expect_config('resize.enable', true)
  expect_config_function('resize.timing')

  expect_config('open.enable', true)
  expect_config_function('open.timing')
  expect_config_function('open.position')
  expect_config_function('open.winblend')

  expect_config('close.enable', true)
  expect_config_function('close.timing')
  expect_config_function('close.position')
  expect_config_function('close.winblend')
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ cursor = { enable = false } })
  eq(child.lua_get('MiniAnimate.config.cursor.enable'), false)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')

  expect_config_error({ cursor = 'a' }, 'cursor', 'table')
  expect_config_error({ cursor = { enable = 'a' } }, 'cursor.enable', 'boolean')
  expect_config_error({ cursor = { timing = 'a' } }, 'cursor.timing', 'callable')
  expect_config_error({ cursor = { path = 'a' } }, 'cursor.path', 'callable')

  expect_config_error({ scroll = 'a' }, 'scroll', 'table')
  expect_config_error({ scroll = { enable = 'a' } }, 'scroll.enable', 'boolean')
  expect_config_error({ scroll = { timing = 'a' } }, 'scroll.timing', 'callable')
  expect_config_error({ scroll = { subscroll = 'a' } }, 'scroll.subscroll', 'callable')

  expect_config_error({ resize = 'a' }, 'resize', 'table')
  expect_config_error({ resize = { enable = 'a' } }, 'resize.enable', 'boolean')
  expect_config_error({ resize = { timing = 'a' } }, 'resize.timing', 'callable')

  expect_config_error({ open = 'a' }, 'open', 'table')
  expect_config_error({ open = { enable = 'a' } }, 'open.enable', 'boolean')
  expect_config_error({ open = { timing = 'a' } }, 'open.timing', 'callable')
  expect_config_error({ open = { position = 'a' } }, 'open.position', 'callable')
  expect_config_error({ open = { winblend = 'a' } }, 'open.winblend', 'callable')

  expect_config_error({ close = 'a' }, 'close', 'table')
  expect_config_error({ close = { enable = 'a' } }, 'close.enable', 'boolean')
  expect_config_error({ close = { timing = 'a' } }, 'close.timing', 'callable')
  expect_config_error({ close = { position = 'a' } }, 'close.position', 'callable')
  expect_config_error({ close = { winblend = 'a' } }, 'close.winblend', 'callable')
end

T['is_active()'] = new_set()

local is_active = function(action_type) return child.lua_get('MiniAnimate.is_active(...)', { action_type }) end

T['is_active()']['works for `cursor`'] = function()
  eq(is_active('cursor'), false)

  set_lines({ 'aa', 'aa', 'aa' })
  set_cursor(1, 0)
  type_keys('2j')
  eq(is_active('cursor'), true)
  sleep(test_times.total_timing - 20)
  eq(is_active('cursor'), true)
  sleep(20 + 10)
  eq(is_active('cursor'), false)
end

T['is_active()']['works for `scroll`'] = function()
  eq(is_active('scroll'), false)

  set_lines({ 'aa', 'aa', 'aa' })
  set_cursor(1, 0)
  type_keys('<C-f>')
  eq(is_active('scroll'), true)
  sleep(test_times.total_timing - 20)
  eq(is_active('scroll'), true)
  sleep(20 + 10)
  eq(is_active('scroll'), false)
end

T['is_active()']['works for `resize`'] = function()
  eq(is_active('resize'), false)

  type_keys('<C-w>v', '<C-w>|')
  eq(is_active('resize'), true)
  sleep(test_times.total_timing - 20)
  eq(is_active('resize'), true)
  sleep(20 + 20)
  eq(is_active('resize'), false)
end

T['is_active()']['works for `open`/`close`'] = function()
  eq(is_active('open'), false)
  eq(is_active('close'), false)

  type_keys('<C-w>v')
  eq(is_active('open'), true)
  eq(is_active('close'), false)
  sleep(test_times.total_timing - 20)
  eq(is_active('open'), true)
  eq(is_active('close'), false)
  sleep(20 + 10)
  eq(is_active('open'), false)
  eq(is_active('close'), false)

  child.cmd('quit')
  eq(is_active('open'), false)
  eq(is_active('close'), true)
  sleep(test_times.total_timing - 20)
  eq(is_active('open'), false)
  eq(is_active('close'), true)
  sleep(20 + 10)
  eq(is_active('open'), false)
  eq(is_active('close'), false)
end

T['execute_after()'] = new_set()

T['execute_after()']['works immediately'] = function()
  child.lua([[MiniAnimate.execute_after('cursor', 'let g:been_here = v:true')]])
  eq(child.g.been_here, true)
end

T['execute_after()']['works after animation is done'] = function()
  skip_on_old_neovim()

  child.set_size(5, 80)
  child.api.nvim_set_keymap(
    'n',
    'n',
    [[<Cmd>lua vim.cmd('normal! n'); MiniAnimate.execute_after('scroll', 'let g:been_here = v:true')<CR>]],
    { noremap = true }
  )

  set_lines({ 'aa', 'bb', 'aa', 'aa', 'aa', 'aa', 'aa', 'aa', 'bb' })
  set_cursor(1, 0)
  type_keys('/', 'bb', '<CR>')

  type_keys('n')
  eq(child.g.been_here, vim.NIL)
  sleep(test_times.total_timing - 20)
  eq(child.g.been_here, vim.NIL)
  sleep(20 + 10)
  eq(child.g.been_here, true)
end

T['execute_after()']['validates input'] = function()
  expect.error(function() child.lua([[MiniAnimate.execute_after('a', function() end)]]) end, 'Wrong `animation_type`')
  expect.error(function() child.lua([[MiniAnimate.execute_after('cursor', 1)]]) end, '`action`.*string or callable')
end

T['execute_after()']['allows callable action'] = function()
  child.lua([[MiniAnimate.execute_after('cursor', function() _G.been_here = true end)]])
  eq(child.lua_get('_G.been_here'), true)
end

T['animate()'] = new_set()

T['animate()']['works'] = function()
  child.lua('_G.action_history = {}')
  child.lua('_G.step_action = function(step) table.insert(_G.action_history, step); return step < 3 end')
  child.lua('_G.step_timing = function(step) return 25 * step end')

  child.lua([[MiniAnimate.animate(_G.step_action, _G.step_timing)]])
  -- It should execute the following order:
  -- Action (step 0) - wait (step 1) - action (step 1) - ...
  -- So here it should be:
  -- 0 ms - `action(0)`
  -- 25(=`timing(1)`) ms - `action(1)`
  -- 75 ms - `action(2)`
  -- 150 ms - `action(3)` and stop
  eq(child.lua_get('_G.action_history'), { 0 })
  sleep(25 - 5)
  eq(child.lua_get('_G.action_history'), { 0 })
  sleep(5)
  eq(child.lua_get('_G.action_history'), { 0, 1 })

  sleep(50 - 5)
  eq(child.lua_get('_G.action_history'), { 0, 1 })
  sleep(5)
  eq(child.lua_get('_G.action_history'), { 0, 1, 2 })

  sleep(75 - 5)
  eq(child.lua_get('_G.action_history'), { 0, 1, 2 })
  sleep(5)
  eq(child.lua_get('_G.action_history'), { 0, 1, 2, 3 })
end

T['animate()']['respects `opts.max_steps`'] = function()
  child.lua('_G.step_action = function(step) _G.latest_step = step; return step < 1000 end')
  child.lua('MiniAnimate.animate(_G.step_action, function() return 10 end, { max_steps = 2 })')
  sleep(50)
  eq(child.lua_get('_G.latest_step'), 2)
end

T['animate()']['handles step times less than 1 ms'] = function()
  child.lua('_G.step_action = function(step) _G.latest_step = step; return step < 5 end')
  child.lua('MiniAnimate.animate(_G.step_action, function() return 0.1 end)')

  -- All steps should be executed immediately
  eq(child.lua_get('_G.latest_step'), 5)
end

T['animate()']['handles non-integer step times'] = function()
  -- It should accumulate fractional parts, not discard them
  child.lua('_G.step_action = function(step) _G.latest_step = step; return step < 10 end')
  child.lua('MiniAnimate.animate(_G.step_action, function() return 1.9 end)')

  sleep(19 - 5)
  eq(child.lua_get('_G.latest_step') < 10, true)

  sleep(5 + 1)
  eq(child.lua_get('_G.latest_step'), 10)
end

T['gen_timing'] = new_set()

local validate_timing = function(family, target, opts, tolerance)
  opts = opts or {}
  tolerance = tolerance or 0.1
  local lua_cmd = string.format('_G.f = MiniAnimate.gen_timing.%s(...)', family)
  child.lua(lua_cmd, { opts })

  local f = function(...) return child.lua_get('_G.f(...)', { ... }) end
  for i, _ in ipairs(target) do
    -- Expect approximate equality
    eq(math.abs(f(i, #target) - target[i]) <= tolerance, true)
  end

  child.lua('_G.f = nil')
end

--stylua: ignore
T['gen_timing']['respects `opts.easing` argument'] = function()
  validate_timing('none',        { 0,    0,    0,    0,    0 })
  validate_timing('linear',      { 20,   20,   20,   20,   20 })
  validate_timing('quadratic',   { 33.3, 26.7, 20,   13.3, 6.7 },  { easing = 'in' })
  validate_timing('quadratic',   { 6.7,  13.3, 20,   26.7, 33.3 }, { easing = 'out' })
  validate_timing('quadratic',   { 27.3, 18.2, 9,    18.2, 27.3 }, { easing = 'in-out' })
  validate_timing('cubic',       { 45.5, 29.1, 16.4, 7.2,  1.8 },  { easing = 'in' })
  validate_timing('cubic',       { 1.8,  7.2,  16.4, 29.1, 45.5 }, { easing = 'out' })
  validate_timing('cubic',       { 33.3, 14.8, 3.8,  14.8, 33.3 }, { easing = 'in-out' })
  validate_timing('quartic',     { 55.5, 28.5, 12,   3.5,  0.5 },  { easing = 'in' })
  validate_timing('quartic',     { 0.5,  3.5,  12,   28.5, 55.5 }, { easing = 'out' })
  validate_timing('quartic',     { 38,   11.3, 1.4,  11.3, 38 },   { easing = 'in-out' })
  validate_timing('exponential', { 60.9, 24.2, 9.6,  3.8,  1.5 },  { easing = 'in' })
  validate_timing('exponential', { 1.5,  3.8,  9.6,  24.2, 60.9 }, { easing = 'out' })
  validate_timing('exponential', { 38.4, 10.2, 2.8,  10.2, 38.4 }, { easing = 'in-out' })

  -- 'in-out' variants should be always symmetrical
  validate_timing('quadratic',   { 30,   20,   10,  10,  20,   30 },   { easing = 'in-out' })
  validate_timing('cubic',       { 38.6, 17.1, 4.3, 4.3, 17.1, 38.6 }, { easing = 'in-out' })
  validate_timing('quartic',     { 45,   13.3, 1.7, 1.7, 13.3, 45 },   { easing = 'in-out' })
  validate_timing('exponential', { 45.5, 11.6, 2.9, 2.9, 11.6, 45.5 }, { easing = 'in-out' })
end

T['gen_timing']['respects `opts` other arguments'] = function()
  validate_timing('linear', { 10, 10 }, { unit = 'total' })
  validate_timing('linear', { 100, 100 }, { duration = 100 })
  validate_timing('linear', { 50, 50 }, { unit = 'total', duration = 100 })
end

T['gen_timing']['validates `opts` values'] = function()
  local validate = function(opts, err_pattern)
    expect.error(function() child.lua('MiniAnimate.gen_timing.linear(...)', { opts }) end, err_pattern)
  end

  validate({ easing = 'a' }, 'one of')
  validate({ duration = 'a' }, 'number')
  validate({ duration = -1 }, 'positive')
  validate({ unit = 'a' }, 'one of')
end

--stylua: ignore
T['gen_timing']['handles `n_steps=1` for all progression families and `opts.easing`'] = function()
  validate_timing('none',        { 0 })
  validate_timing('linear',      { 20 })
  validate_timing('quadratic',   { 20 }, { easing = 'in' })
  validate_timing('quadratic',   { 20 }, { easing = 'out' })
  validate_timing('quadratic',   { 20 }, { easing = 'in-out' })
  validate_timing('cubic',       { 20 }, { easing = 'in' })
  validate_timing('cubic',       { 20 }, { easing = 'out' })
  validate_timing('cubic',       { 20 }, { easing = 'in-out' })
  validate_timing('quartic',     { 20 }, { easing = 'in' })
  validate_timing('quartic',     { 20 }, { easing = 'out' })
  validate_timing('quartic',     { 20 }, { easing = 'in-out' })
  validate_timing('exponential', { 20 }, { easing = 'in' })
  validate_timing('exponential', { 20 }, { easing = 'out' })
  validate_timing('exponential', { 20 }, { easing = 'in-out' })
end

T['gen_path'] = new_set()

T['gen_path']['line()'] = new_set()

local validate_path = function(destination, output) eq(child.lua_get('_G.test_path(...)', { destination }), output) end

local validate_default_path_predicate = function()
  -- Default predicate should ignore nearby lines
  validate_path({ 0, 0 }, {})

  validate_path({ 1, 0 }, {})
  validate_path({ 1, 100 }, {})
  validate_path({ 1, -100 }, {})

  validate_path({ -1, 0 }, {})
  validate_path({ -1, 100 }, {})
  validate_path({ -1, -100 }, {})
end

--stylua: ignore
T['gen_path']['line()']['works'] = function()
  child.lua('_G.test_path = MiniAnimate.gen_path.line()')

  -- Basic checks
  validate_path({  3,  3 }, { { 0, 0 }, {  1,  1 }, {  2,  2 } })
  validate_path({ -3,  3 }, { { 0, 0 }, { -1,  1 }, { -2,  2 } })
  validate_path({  3, -3 }, { { 0, 0 }, {  1, -1 }, {  2, -2 } })
  validate_path({ -3, -3 }, { { 0, 0 }, { -1, -1 }, { -2, -2 } })

  -- Default predicate
  validate_default_path_predicate()

  -- Walks along dimension with further distance
  validate_path({ 3, 5 }, { { 0, 0 }, { 1, 1 }, { 1, 2 }, { 2, 3 }, { 2, 4 } })
  validate_path({ 5, 3 }, { { 0, 0 }, { 1, 1 }, { 2, 1 }, { 3, 2 }, { 4, 2 } })

  validate_path({ 3, -5 }, { { 0, 0 }, {  1, -1 }, {  1, -2 }, {  2, -3 }, {  2, -4 } })
  validate_path({ -5, 3 }, { { 0, 0 }, { -1,  1 }, { -2,  1 }, { -3,  2 }, { -4,  2 } })

  validate_path({ -3, -5 }, { { 0, 0 }, { -1, -1 }, { -1, -2 }, { -2, -3 }, { -2, -4 } })
  validate_path({ -5, -3 }, { { 0, 0 }, { -1, -1 }, { -2, -1 }, { -3, -2 }, { -4, -2 } })
end

--stylua: ignore
T['gen_path']['line()']['respects `opts.predicate`'] = function()
  child.lua('_G.test_path = MiniAnimate.gen_path.line({ predicate = function() return true end })')

  -- Should allow all non-trivial `destination`
  validate_path({ 0, 0 }, {})
  validate_path({  1, 3 }, { { 0, 0 }, { 0, 1 }, {  1, 2 } })
  validate_path({ -1, 3 }, { { 0, 0 }, { 0, 1 }, { -1, 2 } })

  validate_path({ 3, 3 }, { { 0, 0 }, { 1, 1 }, { 2, 2 } })
end

T['gen_path']['angle()'] = new_set()

--stylua: ignore
T['gen_path']['angle()']['works'] = function()
  child.lua('_G.test_path = MiniAnimate.gen_path.angle()')

  -- Basic checks
  validate_path({  3,  3 }, { { 0, 0 }, { 0,  1 }, { 0,  2 }, { 0,  3 }, {  1,  3 }, {  2,  3 }})
  validate_path({ -3,  3 }, { { 0, 0 }, { 0,  1 }, { 0,  2 }, { 0,  3 }, { -1,  3 }, { -2,  3 }})
  validate_path({  3, -3 }, { { 0, 0 }, { 0, -1 }, { 0, -2 }, { 0, -3 }, {  1, -3 }, {  2, -3 }})
  validate_path({ -3, -3 }, { { 0, 0 }, { 0, -1 }, { 0, -2 }, { 0, -3 }, { -1, -3 }, { -2, -3 }})

  -- Default predicate (should ignore nearby lines)
  validate_default_path_predicate()

  -- Walks along line (horizontal) first
  validate_path({ 2, 3 }, { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 0, 3 }, { 1, 3 } })
  validate_path({ 3, 2 }, { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } })
end

--stylua: ignore
T['gen_path']['angle()']['respects `opts.predicate`'] = function()
  child.lua('_G.test_path = MiniAnimate.gen_path.angle({ predicate = function() return true end })')

  -- Should allow all non-trivial `destination`
  validate_path({ 0, 0 }, {})
  validate_path({  1, 3 }, { { 0, 0 }, { 0, 1 }, {  0, 2 }, { 0, 3 } })
  validate_path({ -1, 3 }, { { 0, 0 }, { 0, 1 }, {  0, 2 }, { 0, 3 } })

  validate_path({  3,  3 }, { { 0, 0 }, { 0,  1 }, { 0,  2 }, { 0,  3 }, {  1,  3 }, {  2,  3 }})
end

--stylua: ignore
T['gen_path']['angle()']['respects `opts.first_direction`'] = function()
  child.lua([[_G.test_path = MiniAnimate.gen_path.angle({ first_direction = 'vertical' })]])

  -- Should walk along column (vertical) first
  validate_path({ 2, 3 }, { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 2, 1 }, { 2, 2 } })
  validate_path({ 3, 2 }, { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 }, { 3, 1 } })
end

T['gen_path']['walls()'] = new_set()

--stylua: ignore
T['gen_path']['walls()']['works'] = function()
  child.lua('_G.test_path = MiniAnimate.gen_path.walls()')

  -- Basic checks
  validate_path(
  { 3, 3 },
  {
    { 3, 3 + 10 }, { 3, 3 - 10 },
    { 3, 3 +  9 }, { 3, 3 -  9 },
    { 3, 3 +  8 }, { 3, 3 -  8 },
    { 3, 3 +  7 }, { 3, 3 -  7 },
    { 3, 3 +  6 }, { 3, 3 -  6 },
    { 3, 3 +  5 }, { 3, 3 -  5 },
    { 3, 3 +  4 }, { 3, 3 -  4 },
    { 3, 3 +  3 }, { 3, 3 -  3 },
    { 3, 3 +  2 }, { 3, 3 -  2 },
    { 3, 3 +  1 }, { 3, 3 -  1 }
  })

  validate_path(
  { -3, -3 },
  {
    { -3, -3 + 10 }, { -3, -3 - 10 },
    { -3, -3 +  9 }, { -3, -3 -  9 },
    { -3, -3 +  8 }, { -3, -3 -  8 },
    { -3, -3 +  7 }, { -3, -3 -  7 },
    { -3, -3 +  6 }, { -3, -3 -  6 },
    { -3, -3 +  5 }, { -3, -3 -  5 },
    { -3, -3 +  4 }, { -3, -3 -  4 },
    { -3, -3 +  3 }, { -3, -3 -  3 },
    { -3, -3 +  2 }, { -3, -3 -  2 },
    { -3, -3 +  1 }, { -3, -3 -  1 }
  })

  -- Default predicate (should ignore nearby lines)
  validate_default_path_predicate()
end

--stylua: ignore
T['gen_path']['walls()']['respects `opts.predicate`'] = function()
  child.lua('_G.test_path = MiniAnimate.gen_path.walls({ predicate = function() return true end })')

  -- Should allow all non-trivial `destination`
  validate_path({ 0, 0 }, {})

  validate_path(
  { 1, 3 },
  {
    { 1, 3 + 10 }, { 1, 3 - 10 },
    { 1, 3 +  9 }, { 1, 3 -  9 },
    { 1, 3 +  8 }, { 1, 3 -  8 },
    { 1, 3 +  7 }, { 1, 3 -  7 },
    { 1, 3 +  6 }, { 1, 3 -  6 },
    { 1, 3 +  5 }, { 1, 3 -  5 },
    { 1, 3 +  4 }, { 1, 3 -  4 },
    { 1, 3 +  3 }, { 1, 3 -  3 },
    { 1, 3 +  2 }, { 1, 3 -  2 },
    { 1, 3 +  1 }, { 1, 3 -  1 }
  })
  validate_path(
  { -1, 3 },
  {
    { -1, 3 + 10 }, { -1, 3 - 10 },
    { -1, 3 +  9 }, { -1, 3 -  9 },
    { -1, 3 +  8 }, { -1, 3 -  8 },
    { -1, 3 +  7 }, { -1, 3 -  7 },
    { -1, 3 +  6 }, { -1, 3 -  6 },
    { -1, 3 +  5 }, { -1, 3 -  5 },
    { -1, 3 +  4 }, { -1, 3 -  4 },
    { -1, 3 +  3 }, { -1, 3 -  3 },
    { -1, 3 +  2 }, { -1, 3 -  2 },
    { -1, 3 +  1 }, { -1, 3 -  1 }
  })
end

--stylua: ignore
T['gen_path']['walls()']['respects `opts.width`'] = function()
  child.lua('_G.test_path = MiniAnimate.gen_path.walls({ width = 2 })')
  validate_path(
  { 3, 3 },
  {
    { 3, 3 + 2 }, { 3, 3 - 2 },
    { 3, 3 + 1 }, { 3, 3 - 1 }
  })

  child.lua('_G.test_path = MiniAnimate.gen_path.walls({ width = 1 })')
  validate_path({ 3, 3 }, { { 3, 3 + 1 }, { 3, 3 - 1 } })

  child.lua('_G.test_path = MiniAnimate.gen_path.walls({ width = 0 })')
  validate_path({ 3, 3 }, {})
end

T['gen_path']['spiral()'] = new_set()

--stylua: ignore
T['gen_path']['spiral()']['works'] = function()
  child.lua('_G.test_path = MiniAnimate.gen_path.spiral()')

  -- Basic checks
  validate_path(
  { 3, 3 },
  -- Should go in narrowing spiral
  {
    -- Top (width 2)
    { 3 - 2, 3 - 2 }, { 3 - 2, 3 - 1 }, { 3 - 2, 3 + 0 }, { 3 - 2, 3 + 1 },
    -- Right (width 2)
    { 3 - 2, 3 + 2 }, { 3 - 1, 3 + 2 }, { 3 + 0, 3 + 2 }, { 3 + 1, 3 + 2 },
    -- Bottom (width 2)
    { 3 + 2, 3 + 2 }, { 3 + 2, 3 + 1 }, { 3 + 2, 3 + 0 }, { 3 + 2, 3 - 1 },
    -- Left (width 2)
    { 3 + 2, 3 - 2 }, { 3 + 1, 3 - 2 }, { 3 + 0, 3 - 2 }, { 3 - 1, 3 - 2 },
    -- Top (width 1)
    { 3 - 1, 3 - 1 }, { 3 - 1, 3 + 0 },
    -- Right (width 1)
    { 3 - 1, 3 + 1 }, { 3 + 0, 3 + 1 },
    -- Bottom (width 1)
    { 3 + 1, 3 + 1 }, { 3 + 1, 3 + 0 },
    -- Left (width 1)
    { 3 + 1, 3 - 1 }, { 3 + 0, 3 - 1 },
  })

  -- Default predicate (should ignore nearby lines)
  validate_default_path_predicate()
 end

T['gen_path']['spiral()']['respects `opts.predicate`'] = function()
  child.lua('_G.test_path = MiniAnimate.gen_path.spiral({ predicate = function() return true end })')

  -- Should allow all non-trivial `destination`
  validate_path({ 0, 0 }, {})

  eq(#child.lua_get('_G.test_path({ 1, 3 })') > 0, true)
  eq(#child.lua_get('_G.test_path({ 3, 1 })') > 0, true)
end

--stylua: ignore
T['gen_path']['spiral()']['respects `opts.width`'] = function()
  child.lua('_G.test_path = MiniAnimate.gen_path.spiral({ width = 1 })')
  validate_path(
  { 3, 3 },
  {
    { 3 - 1, 3 - 1 }, { 3 - 1, 3 + 0 },
    { 3 - 1, 3 + 1 }, { 3 + 0, 3 + 1 },
    { 3 + 1, 3 + 1 }, { 3 + 1, 3 + 0 },
    { 3 + 1, 3 - 1 }, { 3 + 0, 3 - 1 },
  })

  child.lua('_G.test_path = MiniAnimate.gen_path.spiral({ width = 0 })')
  validate_path({ 3, 3 }, {})
end

T['gen_subscroll'] = new_set()

local validate_subscroll =
  function(total_scroll, output) eq(child.lua_get('_G.test_subscroll(...)', { total_scroll }), output) end

T['gen_subscroll']['equal()'] = new_set()

--stylua: ignore
T['gen_subscroll']['equal()']['works'] = function()
  child.lua('_G.test_subscroll = MiniAnimate.gen_subscroll.equal()')

  -- Basic checks
  validate_subscroll(2, { 1, 1 })
  validate_subscroll(5, { 1, 1, 1, 1, 1 })

  -- Default predicate (should subscroll only for more than 1)
  validate_subscroll(1, {})
  validate_subscroll(0, {})

  -- Divides equally between steps if total scroll is more than default maximum
  -- allowed number of steps
  validate_subscroll(
    60,
    {
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    }
  )
  validate_subscroll(
    63,
    {
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
    }
  )
  validate_subscroll(
    66,
    {
      1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2,
    }
  )
  validate_subscroll(
    72,
    {
      1, 1, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2,
      1, 1, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2,
      1, 1, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2,
    }
  )
  validate_subscroll(
    120 - 3,
    {
      1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
      1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
      1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    }
  )
end

T['gen_subscroll']['equal()']['respects `opts.predicate`'] = function()
  child.lua('_G.test_subscroll = MiniAnimate.gen_subscroll.equal({ predicate = function() return true end })')

  -- Should allow all non-trivial `destination`
  validate_subscroll(0, {})
  validate_subscroll(1, { 1 })
end

T['gen_subscroll']['equal()']['respects `opts.max_output_steps`'] = function()
  child.lua('_G.test_subscroll = MiniAnimate.gen_subscroll.equal({ max_output_steps = 10 })')

  validate_subscroll(11, { 1, 1, 1, 1, 1, 1, 1, 1, 1, 2 })
end

T['gen_position'] = new_set()

T['gen_position']['static()'] = new_set()

T['gen_position']['static()']['works'] = function() MiniTest.skip() end

T['gen_position']['center()'] = new_set()

T['gen_position']['center()']['works'] = function() MiniTest.skip() end

T['gen_position']['wipe()'] = new_set()

T['gen_position']['wipe()']['works'] = function() MiniTest.skip() end

T['gen_winblend'] = new_set()

T['gen_winblend']['linear()'] = new_set()

T['gen_winblend']['linear()']['works'] = function() MiniTest.skip() end

-- Integration tests ==========================================================

return T
