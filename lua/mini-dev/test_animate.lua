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

T['gen_timing']['none()'] = new_set()

T['gen_timing']['none()']['works'] = function() MiniTest.skip() end

T['gen_timing']['linear()'] = new_set()

T['gen_timing']['linear()']['works'] = function() MiniTest.skip() end

T['gen_timing']['quadratic()'] = new_set()

T['gen_timing']['quadratic()']['works'] = function() MiniTest.skip() end

T['gen_timing']['cubic()'] = new_set()

T['gen_timing']['cubic()']['works'] = function() MiniTest.skip() end

T['gen_timing']['quartic()'] = new_set()

T['gen_timing']['quartic()']['works'] = function() MiniTest.skip() end

T['gen_timing']['exponential()'] = new_set()

T['gen_timing']['exponential()']['works'] = function() MiniTest.skip() end

T['gen_path'] = new_set()

T['gen_path']['line()'] = new_set()

T['gen_path']['line()']['works'] = function() MiniTest.skip() end

T['gen_path']['line()']['respects `opts.predicate`'] = function() MiniTest.skip() end

T['gen_path']['angle()'] = new_set()

T['gen_path']['angle()']['works'] = function() MiniTest.skip() end

T['gen_path']['line()']['respects `opts.predicate`'] = function() MiniTest.skip() end

T['gen_path']['walls()'] = new_set()

T['gen_path']['walls()']['works'] = function() MiniTest.skip() end

T['gen_path']['line()']['respects `opts.predicate`'] = function() MiniTest.skip() end

T['gen_path']['spiral()'] = new_set()

T['gen_path']['spiral()']['works'] = function() MiniTest.skip() end

T['gen_path']['line()']['respects `opts.predicate`'] = function() MiniTest.skip() end

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
