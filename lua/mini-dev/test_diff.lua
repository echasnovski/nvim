local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('diff', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local set_ref_text = forward_lua([[require('mini-dev.diff').set_ref_text]])

local is_buf_enabled = function(buf_id)
  return child.lua_get('require("mini-dev.diff").get_buf_data(' .. buf_id .. ') ~= nil')
end

local get_buf_hunks = function(buf_id)
  buf_id = buf_id or 0
  return child.lua_get('require("mini-dev.diff").get_buf_data(' .. buf_id .. ').hunks')
end

-- Common mocks
local setup_with_dummy_source = function()
  child.lua([[
  _G.dummy_log = {}
  require('mini-dev.diff').setup({
    source = {
      name = 'dummy',
      attach = function() end,
      detach = function(...) table.insert(_G.dummy_log, { 'detach', { ... } }) end,
      apply_hunks = function(...) table.insert(_G.dummy_log, { 'apply_hunks', { ... } }) end,
    },
  })]])
end

local validate_dummy_log = function(ref_log) eq(child.lua_get('_G.dummy_log'), ref_log) end

local clean_dummy_log = function() child.lua('_G.dummy_log = {}') end

-- Module helpers
local get_viz_extmarks = function(buf_id)
  local ns_id = child.api.nvim_get_namespaces().MiniDiffViz
  local full_extmarks = child.api.nvim_buf_get_extmarks(buf_id, ns_id, 0, -1, { details = true })
  local res = {}
  for _, e in ipairs(full_extmarks) do
    table.insert(res, {
      line = e[2] + 1,
      sign_hl_group = e[4].sign_hl_group,
      sign_text = e[4].sign_text,
      number_hl_group = e[4].number_hl_group,
    })
  end
  return res
end

local validate_hl_group = function(name, pattern) expect.match(child.cmd_capture('hi ' .. name), pattern) end

-- Work with notifications
local mock_notify = function()
  child.lua([[
    _G.notify_log = {}
    vim.notify = function(...) table.insert(_G.notify_log, { ... }) end
  ]])
end

local get_notify_log = function() return child.lua_get('_G.notify_log') end

local validate_notifications = function(ref_log, msg_pattern)
  local notify_log = get_notify_log()
  local n = math.max(#notify_log, #ref_log)
  for i = 1, n do
    local real, ref = notify_log[i], ref_log[i]
    if real == nil then
      eq('Real notify log does not have entry for present reference log entry', ref)
    elseif ref == nil then
      eq(real, 'Reference does not have entry for present notify log entry')
    else
      local expect_msg = msg_pattern and expect.match or eq
      expect_msg(real[1], ref[1])
      eq(real[2], child.lua_get('vim.log.levels.' .. ref[2]))
    end
  end
end

local clear_notify_log = function() return child.lua('_G.notify_log = {}') end

-- Data =======================================================================
local small_time = 5

local test_ref_lines = { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff' }

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.set_size(10, 15)
      mock_notify()
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniDiff)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniDiff'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local is_010 = child.fn.has('nvim-0.10') == 1
  expect.match(child.cmd_capture('hi MiniDiffSignAdd'), 'links to ' .. (is_010 and 'Added' or 'diffAdded'))
  expect.match(child.cmd_capture('hi MiniDiffSignChange'), 'links to ' .. (is_010 and 'Changed' or 'diffChanged'))
  expect.match(child.cmd_capture('hi MiniDiffSignDelete'), 'links to ' .. (is_010 and 'Removed' or 'diffRemoved'))
  expect.match(child.cmd_capture('hi MiniDiffOverAdd'), 'links to DiffAdd')
  expect.match(child.cmd_capture('hi MiniDiffOverChange'), 'links to DiffText')
  expect.match(child.cmd_capture('hi MiniDiffOverContext'), 'links to DiffChange')
  expect.match(child.cmd_capture('hi MiniDiffOverDelete'), 'links to DiffDelete')
end

T['setup()']['creates `config` field'] = function()
  load_module()

  eq(child.lua_get('type(_G.MiniDiff.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniDiff.config.' .. field), value) end

  expect_config('view.style', 'sign')
  expect_config('view.signs', { add = '▒', change = '▒', delete = '▒' })
  expect_config('view.priority', child.highlight.priorities.user - 1)
  expect_config('source', vim.NIL)
  expect_config('delay.text_change', 200)
  expect_config('mappings.apply', 'gh')
  expect_config('mappings.reset', 'gH')
  expect_config('mappings.textobject', 'gh')
  expect_config('mappings.goto_first', '[H')
  expect_config('mappings.goto_prev', '[h')
  expect_config('mappings.goto_next', ']h')
  expect_config('mappings.goto_last', ']H')
  expect_config('options.algorithm', 'histogram')
  expect_config('options.indent_heuristic', true)
  expect_config('options.linematch', 60)
end

T['setup()']["respects 'number' option when setting default `view.style`"] = function()
  child.o.number = true
  load_module()
  eq(child.lua_get('MiniDiff.config.view.style'), 'number')
end

T['setup()']['respects `config` argument'] = function()
  load_module({ delay = { text_change = 20 } })
  eq(child.lua_get('MiniDiff.config.delay.text_change'), 20)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ view = 'a' }, 'view', 'table')
  expect_config_error({ view = { style = 1 } }, 'view.style', 'string')
  expect_config_error({ view = { signs = 'a' } }, 'view.signs', 'table')
  expect_config_error({ view = { signs = { add = 1 } } }, 'view.signs.add', 'string')
  expect_config_error({ view = { signs = { change = 1 } } }, 'view.signs.change', 'string')
  expect_config_error({ view = { signs = { delete = 1 } } }, 'view.signs.delete', 'string')
  expect_config_error({ view = { priority = 'a' } }, 'view.priority', 'number')

  expect_config_error({ source = 'a' }, 'source', 'table')

  expect_config_error({ delay = 'a' }, 'delay', 'table')
  expect_config_error({ delay = { text_change = 'a' } }, 'delay.text_change', 'number')

  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { apply = 1 } }, 'mappings.apply', 'string')
  expect_config_error({ mappings = { reset = 1 } }, 'mappings.reset', 'string')
  expect_config_error({ mappings = { textobject = 1 } }, 'mappings.textobject', 'string')
  expect_config_error({ mappings = { goto_first = 1 } }, 'mappings.goto_first', 'string')
  expect_config_error({ mappings = { goto_prev = 1 } }, 'mappings.goto_prev', 'string')
  expect_config_error({ mappings = { goto_next = 1 } }, 'mappings.goto_next', 'string')
  expect_config_error({ mappings = { goto_last = 1 } }, 'mappings.goto_last', 'string')

  expect_config_error({ options = 'a' }, 'options', 'table')
  expect_config_error({ options = { algorithm = 1 } }, 'options.algorithm', 'string')
  expect_config_error({ options = { indent_heuristic = 'a' } }, 'options.indent_heuristic', 'boolean')
  expect_config_error({ options = { linematch = 'a' } }, 'options.linematch', 'number')
end

T['setup()']['auto enables in all existing buffers'] = function()
  local buf_id_normal = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(buf_id_normal)

  local buf_id_bad_1 = child.api.nvim_create_buf(false, true)
  local buf_id_bad_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_bad_2, 0, -1, false, { '\0' })

  -- Only normal valid text buffers should be auto enabled
  setup_with_dummy_source()
  eq(is_buf_enabled(buf_id_normal), true)
  eq(is_buf_enabled(buf_id_bad_1), false)
  eq(is_buf_enabled(buf_id_bad_2), false)
end

T['enable()'] = new_set()

local enable = forward_lua([[require('mini-dev.diff').enable]])

T['enable()']['works'] = function() MiniTest.skip() end

T['enable()']['works with defaults'] = function()
  -- child.b.minihipatterns_config = test_config
  -- set_lines(test_lines)
  -- enable()
  -- child.expect_screenshot()
  MiniTest.skip()
end

T['enable()']['works in not normal buffer'] = function() MiniTest.skip() end

T['enable()']['works in not current buffer'] = function() MiniTest.skip() end

T['enable()']['reacts to text change'] = function()
  -- -- Should enable debounced auto highlight on text change
  -- enable(0, test_config)
  --
  -- -- Interactive text change
  -- type_keys('i', 'abc')
  -- sleep(test_config.delay.text_change - small_time)
  -- type_keys('d')
  --
  -- -- - No highlights should be shown as delay was smaller than in config
  -- child.expect_screenshot()
  --
  -- -- - Still no highlights should be shown
  -- sleep(test_config.delay.text_change - small_time)
  -- child.expect_screenshot()
  --
  -- -- - Now there should be highlights
  -- sleep(2 * small_time)
  -- child.expect_screenshot()
  --
  -- -- Not interactive text change
  -- set_lines({ 'ABCD', 'abcd' })
  --
  -- child.expect_screenshot()
  -- sleep(test_config.delay.text_change + small_time)
  -- child.expect_screenshot()
  MiniTest.skip()
end

T['enable()']['does not flicker during text insert'] = function()
  -- enable(0, test_config)
  --
  -- -- Interactive text change
  -- type_keys('i', 'abcd')
  -- sleep(test_config.delay.text_change + small_time)
  -- child.expect_screenshot()
  --
  -- type_keys(' abcd')
  -- child.expect_screenshot()
  -- sleep(test_config.delay.text_change + small_time)
  -- child.expect_screenshot()
  MiniTest.skip()
end

T['enable()']['reacts to buffer enter'] = function()
  -- local init_buf_id = child.api.nvim_get_current_buf()
  -- enable(init_buf_id, { highlighters = test_config.highlighters })
  --
  -- local other_buf_id = child.api.nvim_create_buf(true, false)
  -- child.api.nvim_set_current_buf(other_buf_id)
  --
  -- -- On buffer enter it should update config and highlighting (after delay)
  -- local lua_cmd = string.format('vim.b[%d].minihipatterns_config = { delay = { text_change = 10 } }', init_buf_id)
  -- child.lua(lua_cmd)
  -- child.api.nvim_buf_set_lines(init_buf_id, 0, -1, false, { 'abcd' })
  --
  -- child.api.nvim_set_current_buf(init_buf_id)
  --
  -- child.expect_screenshot()
  -- sleep(10 + small_time)
  -- child.expect_screenshot()
  MiniTest.skip()
end

T['enable()']['reacts to filetype change'] = function()
  -- child.lua([[_G.hipatterns_config = {
  --   highlighters = {
  --     abcd_ft = {
  --       pattern = function(buf_id)
  --         if vim.bo[buf_id].filetype == 'aaa' then return nil end
  --         return 'abcd'
  --       end,
  --       group = 'Error'
  --     },
  --   },
  --   delay = { text_change = 20 },
  -- }]])
  --
  -- set_lines({ 'xxabcdxx' })
  -- child.lua([[require('mini.hipatterns').enable(0, _G.hipatterns_config)]])
  -- child.expect_screenshot()
  --
  -- -- Should update highlighting after delay
  -- child.cmd('set filetype=aaa')
  -- child.expect_screenshot()
  -- sleep(20 + 2)
  -- child.expect_screenshot()
  MiniTest.skip()
end

T['enable()']['reacts to delete of line with match'] = function()
  -- set_lines({ 'abcd', 'xxx', 'xxx', 'abcd', 'xxx', 'xxx', 'abcd' })
  --
  -- local hi_abcd = {
  --   pattern = 'abcd',
  --   group = '',
  --   extmark_opts = { virt_text = { { 'Hello', 'Error' } }, virt_text_pos = 'right_align' },
  -- }
  -- local config = { highlighters = { abcd = hi_abcd }, delay = { text_change = 30, scroll = 10 } }
  -- enable(0, config)
  --
  -- sleep(30 + small_time)
  -- child.expect_screenshot()
  --
  -- local validate = function(line_to_delete)
  --   child.api.nvim_win_set_cursor(0, { line_to_delete, 0 })
  --   type_keys('dd')
  --   sleep(30 + small_time)
  --   child.expect_screenshot()
  -- end
  --
  -- validate(1)
  -- validate(3)
  -- validate(5)
  MiniTest.skip()
end

T['enable()']['validates arguments'] = function()
  -- expect.error(function() enable('a', {}) end, '`buf_id`.*valid buffer id')
  -- expect.error(function() enable(child.api.nvim_get_current_buf(), 'a') end, '`config`.*table')
  MiniTest.skip()
end

T['enable()']['respects `vim.{g,b}.minihipatterns_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    -- child[var_type].minihipatterns_disable = true
    --
    -- set_lines(test_lines)
    -- enable(0, test_config)
    -- sleep(test_config.delay.text_change + small_time)
    -- child.expect_screenshot()
    MiniTest.skip()
  end,
})

T['enable()']['respects `vim.b.minihipatterns_config`'] = function()
  -- set_lines(test_lines)
  -- child.b.minihipatterns_config = test_config
  -- enable(0)
  --
  -- child.expect_screenshot()
  --
  -- -- Delay should also be respected
  -- set_lines({ 'abcd' })
  -- sleep(test_config.delay.text_change - small_time)
  -- child.expect_screenshot()
  -- sleep(2 * small_time)
  -- child.expect_screenshot()
  MiniTest.skip()
end

T['disable()'] = new_set()

local disable = forward_lua([[require('mini-dev.diff').disable]])

T['disable()']['works'] = function()
  -- local cur_buf_id = child.api.nvim_get_current_buf()
  -- set_lines(test_lines)
  -- enable(0, test_config)
  -- child.expect_screenshot()
  --
  -- -- By default should disable current buffer
  -- disable()
  -- child.expect_screenshot()
  -- eq(get_enabled_buffers(), {})
  --
  -- -- Allows 0 as alias for current buffer
  -- enable(0, test_config)
  -- eq(get_enabled_buffers(), { cur_buf_id })
  -- disable(0)
  -- eq(get_enabled_buffers(), {})
  MiniTest.skip()
end

T['disable()']['works in not current buffer'] = function()
  -- local init_buf_id = child.api.nvim_get_current_buf()
  -- set_lines(test_lines)
  -- enable(0, test_config)
  -- child.expect_screenshot()
  --
  -- child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))
  -- disable(init_buf_id)
  -- child.api.nvim_set_current_buf(init_buf_id)
  -- sleep(test_config.delay.text_change + small_time)
  -- child.expect_screenshot()
  MiniTest.skip()
end

T['disable()']['works on not enabled buffer'] = function()
  expect.no_error(function() disable(0) end)
end

T['disable()']['validates arguments'] = function()
  expect.error(function() disable('a') end, '`buf_id`.*valid buffer id')
end

T['toggle()'] = new_set()

local toggle = forward_lua([[require('mini-dev.diff').toggle]])

T['toggle()']['works'] = function()
  -- local cur_buf_id = child.api.nvim_get_current_buf()
  -- set_lines(test_lines)
  --
  -- -- By default should disable current buffer
  -- child.lua('_G.test_config = ' .. vim.inspect(test_config))
  -- child.lua([[require('mini.hipatterns').toggle(nil, test_config)]])
  -- child.expect_screenshot()
  -- eq(get_enabled_buffers(), { cur_buf_id })
  --
  -- toggle()
  -- child.expect_screenshot()
  -- eq(get_enabled_buffers(), {})
  --
  -- -- Allows 0 as alias for current buffer
  -- toggle(0, test_config)
  -- eq(get_enabled_buffers(), { cur_buf_id })
  --
  -- toggle(0)
  -- eq(get_enabled_buffers(), {})
  MiniTest.skip()
end

T['toggle()']['validates arguments'] = function()
  expect.error(function() toggle('a') end, '`buf_id`.*valid buffer id')
end

T['toggle_overlay()'] = new_set()

T['toggle_overlay()']['works'] = function() MiniTest.skip() end

T['get_buf_data()'] = new_set()

T['get_buf_data()']['works'] = function()
  -- local create_buf = function() return child.api.nvim_create_buf(true, false) end
  -- local buf_id_1 = create_buf()
  -- create_buf()
  -- local buf_id_3 = create_buf()
  -- local buf_id_4 = create_buf()
  --
  -- enable(buf_id_3)
  -- enable(buf_id_1)
  -- enable(buf_id_4)
  -- eq(get_enabled_buffers(), { buf_id_1, buf_id_3, buf_id_4 })
  --
  -- disable(buf_id_3)
  -- eq(get_enabled_buffers(), { buf_id_1, buf_id_4 })
  --
  -- -- Does not return invalid buffers
  -- child.api.nvim_buf_delete(buf_id_4, {})
  -- eq(get_enabled_buffers(), { buf_id_1 })
  MiniTest.skip()
end

T['get_buf_data()']['returns copy of underlying data'] = function() MiniTest.skip() end

T['set_ref_text()'] = new_set()

T['set_ref_text()']['works'] = function() MiniTest.skip() end

T['set_ref_text()']['enables not enabled buffer'] = function() MiniTest.skip() end

T['gen_source'] = new_set()

T['gen_source']['git()'] = new_set()

T['gen_source']['git()']['works'] = function() MiniTest.skip() end

T['gen_source']['save()'] = new_set()

T['gen_source']['save()']['works'] = function() MiniTest.skip() end

T['do_hunks()'] = new_set({ hooks = { pre_case = setup_with_dummy_source } })

local do_hunks = forward_lua('MiniDiff.do_hunks')

T['do_hunks()']['works'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'axa', 'bbb', 'ccc' })

  -- Apply
  do_hunks(0, 'apply')
  -- - By default should do action on all lines
  local ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 1 },
    { buf_start = 2, buf_count = 0, ref_start = 3, ref_count = 1 },
  }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'axa', 'bbb', 'ccc' })
end

T['do_hunks()']['works with no hunks'] = function()
  set_lines({ 'aaa' })
  set_ref_text(0, { 'aaa' })

  -- Apply
  do_hunks(0, 'apply')
  validate_dummy_log({})
  validate_notifications({ { '(mini.diff) No hunks to apply', 'INFO' } })
  clear_notify_log()

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'aaa' })
  validate_notifications({ { '(mini.diff) No hunks to reset', 'INFO' } })
  clear_notify_log()
end

T['do_hunks()']['works with "add" hunks'] = function()
  local ref_hunks

  set_lines({ 'uuu', 'aaa', 'vvv', 'ccc', 'www', 'xxx' })
  set_ref_text(0, { 'aaa', 'ccc' })

  -- Apply
  do_hunks(0, 'apply')
  ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 0, ref_count = 0 },
    { buf_start = 3, buf_count = 1, ref_start = 1, ref_count = 0 },
    { buf_start = 5, buf_count = 2, ref_start = 2, ref_count = 0 },
  }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'aaa', 'ccc' })
end

T['do_hunks()']['works with "change" hunks'] = function()
  set_lines({ 'aaa', 'BBB', 'ccc', 'DDD', 'eee', 'fff' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  -- Apply
  do_hunks(0, 'apply')
  local ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 1 },
    { buf_start = 3, buf_count = 1, ref_start = 3, ref_count = 1 },
    { buf_start = 5, buf_count = 2, ref_start = 5, ref_count = 2 },
  }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })
end

T['do_hunks()']['works with "delete" hunks'] = function()
  set_lines({ 'bbb', 'ddd' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff' })

  -- Apply
  do_hunks(0, 'apply')
  local ref_hunks = {
    { buf_start = 0, buf_count = 0, ref_start = 1, ref_count = 1 },
    { buf_start = 1, buf_count = 0, ref_start = 3, ref_count = 1 },
    { buf_start = 2, buf_count = 0, ref_start = 5, ref_count = 2 },
  }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff' })
end

T['do_hunks()']['works with "delete" hunks on edges as target'] = function()
  local ref_hunks

  -- First line
  set_lines({ 'bbb' })
  set_ref_text(0, { 'aaa', 'bbb' })

  do_hunks(0, 'apply', { line_start = 1, line_end = 1 })
  ref_hunks = { { buf_start = 0, buf_count = 0, ref_start = 1, ref_count = 1 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })
  clean_dummy_log()

  do_hunks(0, 'reset', { line_start = 1, line_end = 1 })
  eq(get_lines(), { 'aaa', 'bbb' })

  -- Last line
  set_lines({ 'aaa' })
  set_ref_text(0, { 'aaa', 'bbb' })

  do_hunks(0, 'apply', { line_start = 2, line_end = 2 })
  ref_hunks = { { buf_start = 1, buf_count = 0, ref_start = 2, ref_count = 1 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })
  clean_dummy_log()

  do_hunks(0, 'reset', { line_start = 2, line_end = 2 })
  eq(get_lines(), { 'aaa', 'bbb' })
end

T['do_hunks()']['respects `opts.line_start`'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'axa', 'bbb', 'ccc' })

  -- Apply
  do_hunks(0, 'apply', { line_start = 2 })
  local ref_hunks = { { buf_start = 2, buf_count = 0, ref_start = 3, ref_count = 1 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset', { line_start = 2 })
  eq(get_lines(), { 'aaa', 'bbb', 'ccc' })
end

T['do_hunks()']['respects `opts.line_end`'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'axa', 'bbb', 'ccc' })

  -- Apply
  do_hunks(0, 'apply', { line_end = 1 })
  local ref_hunks = { { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 1 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset', { line_end = 1 })
  eq(get_lines(), { 'axa', 'bbb' })
end

T['do_hunks()']['allows negative target lines'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'axa', 'bbb', 'ccc' })

  -- Apply
  do_hunks(0, 'apply', { line_start = -2, line_end = -1 })
  local ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 1 },
    { buf_start = 2, buf_count = 0, ref_start = 3, ref_count = 1 },
  }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset', { line_start = -2, line_end = -1 })
  eq(get_lines(), { 'axa', 'bbb', 'ccc' })
end

T['do_hunks()']['can act on hunk part'] = function()
  set_lines({ 'uuu', 'vvv', 'aaa', 'bbb', 'ccc' })
  set_ref_text(0, { 'aaa', 'BBB', 'CCC' })

  -- Apply
  do_hunks(0, 'apply', { line_start = 2, line_end = 4 })
  local ref_hunks = {
    { buf_start = 2, buf_count = 1, ref_start = 0, ref_count = 0 },
    -- If hunk intersects target range, its reference part is used in full
    { buf_start = 4, buf_count = 1, ref_start = 2, ref_count = 2 },
  }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset', { line_start = 2, line_end = 4 })
  eq(get_lines(), { 'uuu', 'aaa', 'BBB', 'CCC', 'ccc' })
end

T['do_hunks()']['validates arguments'] = function()
  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_ref_text(0, test_ref_lines)

  expect.error(function() do_hunks(-1) end, 'valid buffer')

  expect.error(function() do_hunks(0, 'aaa') end, '`action`.*one of')

  expect.error(function() do_hunks(0, 'apply', { line_start = 'a' }) end, '`line_start`.*number')
  expect.error(function() do_hunks(0, 'apply', { line_end = 'a' }) end, '`line_end`.*number')
  expect.error(function() do_hunks(0, 'apply', { line_start = 2, line_end = 1 }) end, '`line_start`.*less.*`line_end`')

  disable()
  expect.error(function() do_hunks(0) end, 'Buffer.*not enabled')
end

T['goto_hunk()'] = new_set({ hooks = { pre_case = setup_with_dummy_source } })

local goto_hunk = forward_lua('MiniDiff.goto_hunk')

T['goto_hunk()']['works'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, ref_cursor)
    set_cursor(4, 0)
    goto_hunk(direction)
    eq(get_cursor(), ref_cursor)
  end

  validate('first', { 1, 0 })
  validate('prev', { 3, 0 })
  validate('next', { 5, 0 })
  validate('last', { 7, 0 })
end

T['goto_hunk()']['works when inside hunk range'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'www', 'xxx', 'ccc', 'yyy' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, ref_cursor)
    set_cursor(4, 0)
    goto_hunk(direction)
    eq(get_cursor(), ref_cursor)
  end

  -- Should not count current hunk when computing target
  validate('first', { 1, 0 })
  validate('prev', { 1, 0 })
  validate('next', { 7, 0 })
  validate('last', { 7, 0 })
end

T['goto_hunk()']['respects `opts.n_times`'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, ref_cursor)
    set_cursor(4, 0)
    goto_hunk(direction, { n_times = 2 })
    eq(get_cursor(), ref_cursor)
  end

  validate('first', { 3, 0 })
  validate('prev', { 1, 0 })
  validate('next', { 7, 0 })
  validate('last', { 5, 0 })
end

T['goto_hunk()']['allows too big `opts.n_times`'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, ref_cursor)
    set_cursor(4, 0)
    goto_hunk(direction, { n_times = 1000 })
    eq(get_cursor(), ref_cursor)
  end

  -- Should partially go until reaches the end
  validate('first', { 7, 0 })
  validate('prev', { 1, 0 })
  validate('next', { 7, 0 })
  validate('last', { 1, 0 })
end

T['goto_hunk()']['respects `opts.line_start`'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, ref_cursor)
    set_cursor(1, 0)
    goto_hunk(direction, { line_start = 4 })
    eq(get_cursor(), ref_cursor)
  end

  validate('first', { 1, 0 })
  validate('prev', { 3, 0 })
  validate('next', { 5, 0 })
  validate('last', { 7, 0 })
end

T['goto_hunk()']['does not wrap around edges'] = function()
  set_lines({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
  set_ref_text(0, { 'aaa', 'BBB', 'ccc', 'DDD', 'eee' })

  local validate = function(direction, init_cursor)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction)
    eq(get_cursor(), init_cursor)
    validate_notifications({ { '(mini.diff) No hunk ranges in direction "' .. direction .. '"', 'INFO' } })
    clear_notify_log()
  end

  validate('prev', { 2, 1 })
  validate('next', { 4, 1 })
end

T['goto_hunk()']['works with no hunks'] = function()
  set_lines({ 'aaa' })
  set_ref_text(0, { 'aaa' })

  local cursor = get_cursor()
  goto_hunk('next')
  eq(get_cursor(), cursor)
  validate_notifications({ { '(mini.diff) No hunks to go to', 'INFO' } })
end

T['goto_hunk()']['correctly computes contiguous ranges'] = function()
  if child.fn.has('nvim-0.9') == 0 then MiniTest.skip('Contiguous regions are relevant with `linematch` option.') end

  local validate = function(init_cursor, direction, opts, ref_cursor)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction, opts)
    eq(get_cursor(), ref_cursor)
  end

  -- "Change" hunk adjacent to "add" and "delete" hunks
  set_lines({ 'AAA', 'uuu', 'BbB', 'DDD', 'www', 'EEE' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  eq(get_buf_hunks(), {
    { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' },
    { buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 1, type = 'change' },
    { buf_start = 3, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' },
    { buf_start = 5, buf_count = 1, ref_start = 4, ref_count = 0, type = 'add' },
  })

  validate({ 1, 0 }, 'first', {}, { 2, 0 })
  validate({ 1, 0 }, 'first', { n_times = 2 }, { 5, 0 })

  validate({ 6, 0 }, 'prev', {}, { 5, 0 })
  validate({ 5, 0 }, 'prev', {}, { 2, 0 })

  validate({ 1, 0 }, 'next', {}, { 2, 0 })
  validate({ 2, 0 }, 'next', {}, { 5, 0 })

  validate({ 6, 0 }, 'last', {}, { 5, 0 })
  validate({ 6, 0 }, 'last', { n_times = 2 }, { 2, 0 })
end

T['goto_hunk()']['adds current position to jump list'] = function()
  set_lines({ 'aaa', 'uuu', 'bbb', 'vvv', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(init_cursor, direction, ref_cursor)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction)
    eq(get_cursor(), ref_cursor)
    type_keys('<C-o>')
    eq(get_cursor(), init_cursor)
  end

  validate({ 3, 1 }, 'first', { 2, 0 })
  validate({ 3, 1 }, 'prev', { 2, 0 })
  validate({ 3, 1 }, 'next', { 4, 0 })
  validate({ 3, 1 }, 'last', { 4, 0 })
end

T['goto_hunk()']['puts cursor on first line of range'] = function()
  set_lines({ 'aaa', 'uuu', 'vvv', 'bbb', 'www', 'xxx', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(init_cursor, direction, ref_cursor)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction)
    eq(get_cursor(), ref_cursor)
  end

  validate({ 1, 0 }, 'first', { 2, 0 })
  validate({ 7, 0 }, 'first', { 2, 0 })

  validate({ 6, 0 }, 'prev', { 2, 0 })
  validate({ 4, 0 }, 'prev', { 2, 0 })

  validate({ 1, 0 }, 'next', { 2, 0 })
  validate({ 4, 0 }, 'next', { 5, 0 })

  validate({ 7, 0 }, 'last', { 5, 0 })
  validate({ 4, 0 }, 'last', { 5, 0 })
end

T['goto_hunk()']['puts cursor on first non-blank column'] = function()
  set_lines({ 'AAA', '  uuu', 'BBB', '\tvvv', 'CCC', '\t www', 'DDD' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD' })

  local validate = function(init_cursor, direction, opts, ref_cursor)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction, opts)
    eq(get_cursor(), ref_cursor)
  end

  validate({ 1, 0 }, 'first', {}, { 2, 2 })
  validate({ 1, 0 }, 'first', { n_times = 2 }, { 4, 1 })
  validate({ 1, 0 }, 'first', { n_times = 3 }, { 6, 2 })

  validate({ 7, 0 }, 'prev', {}, { 6, 2 })
  validate({ 5, 0 }, 'prev', {}, { 4, 1 })
  validate({ 3, 0 }, 'prev', {}, { 2, 2 })

  validate({ 1, 0 }, 'next', {}, { 2, 2 })
  validate({ 3, 0 }, 'next', {}, { 4, 1 })
  validate({ 5, 0 }, 'next', {}, { 6, 2 })

  validate({ 7, 0 }, 'last', {}, { 6, 2 })
  validate({ 7, 0 }, 'last', { n_times = 2 }, { 4, 1 })
  validate({ 7, 0 }, 'last', { n_times = 3 }, { 2, 2 })
end

T['goto_hunk()']['opens just enough folds'] = function()
  set_lines({ 'aaa', 'uuu', 'bbb', 'ccc', 'ddd', 'eee' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })

  local validate = function(init_cursor, direction)
    child.cmd('2,3fold')
    child.cmd('5,6fold')
    for i, s in ipairs({ -1, 2, 2, -1, 5, 5 }) do
      eq(child.fn.foldclosed(i), s)
    end

    set_cursor(unpack(init_cursor))
    goto_hunk(direction)
    eq(get_cursor(), { 2, 0 })
    for i, s in ipairs({ -1, -1, -1, -1, 5, 5 }) do
      eq(child.fn.foldclosed(i), s)
    end
  end

  validate({ 1, 0 }, 'first')
  validate({ 3, 0 }, 'prev')
  validate({ 1, 0 }, 'next')
  validate({ 6, 0 }, 'last')
end

T['goto_hunk()']['validates arguments'] = function()
  expect.error(function() goto_hunk('aaa') end, '`direction`.*one of')
  expect.error(function() goto_hunk('next', { n_times = 'a' }) end, '`opts.n_times`.*number')
  expect.error(function() goto_hunk('next', { n_times = 0 }) end, '`opts.n_times`.*positive')
  expect.error(function() goto_hunk('next', { line_start = 'a' }) end, '`opts.line_start`.*number')
  expect.error(function() goto_hunk('next', { line_start = 0 }) end, '`opts.line_start`.*positive')

  disable()
  expect.error(function() goto_hunk() end, 'Buffer.*not enabled')
end

-- More thorough tests are done in "Integration tests"
T['operator()'] = new_set({ hooks = { pre_case = setup_with_dummy_source } })

T['operator()']['is present'] = function() eq(child.lua_get('type(MiniDiff.operator)'), 'function') end

-- More thorough tests are done in "Integration tests"
T['textobject()'] = new_set({ hooks = { pre_case = setup_with_dummy_source } })

T['textobject()']['is present'] = function() eq(child.lua_get('type(MiniDiff.textobject)'), 'function') end

-- Integration tests ==========================================================
T['Auto enable'] = new_set()

T['Auto enable']['enables for normal buffers'] = function()
  -- child.set_size(10, 30)
  -- child.o.winwidth = 1
  --
  -- local buf_id_1 = child.api.nvim_get_current_buf()
  -- set_lines(test_lines)
  -- child.cmd('wincmd v')
  --
  -- local buf_id_2 = child.api.nvim_create_buf(true, false)
  -- child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { '22abcd22' })
  --
  -- local buf_id_3 = child.api.nvim_create_buf(true, false)
  -- child.api.nvim_set_current_buf(buf_id_3)
  -- set_lines({ '33abcd33' })
  --
  -- load_module(test_config)
  -- -- Should enable in all proper buffers currently shown in some window
  -- child.expect_screenshot()
  -- eq(child.lua_get('MiniHipatterns.get_enabled_buffers()'), { buf_id_1, buf_id_3 })
  --
  -- child.api.nvim_set_current_buf(buf_id_2)
  -- child.expect_screenshot()
  -- eq(child.lua_get('MiniHipatterns.get_enabled_buffers()'), { buf_id_1, buf_id_2, buf_id_3 })
  MiniTest.skip()
end

T['Auto enable']['works after `:edit`'] = function()
  -- load_module(test_config)
  --
  -- local test_file = 'tests/hipatterns_file'
  -- MiniTest.finally(function() vim.fn.delete(test_file) end)
  --
  -- child.cmd('edit ' .. test_file)
  -- set_lines(test_lines)
  -- child.cmd('write')
  --
  -- sleep(test_config.delay.text_change + small_time)
  -- child.expect_screenshot()
  --
  -- child.cmd('edit')
  -- child.expect_screenshot()
  MiniTest.skip()
end

T['Auto enable']['does not enable for not normal buffers'] = function()
  -- load_module(test_config)
  -- local scratch_buf_id = child.api.nvim_create_buf(false, true)
  -- child.api.nvim_set_current_buf(scratch_buf_id)
  --
  -- set_lines(test_lines)
  -- sleep(test_config.delay.text_change + small_time)
  -- -- Should be no highlighting
  -- child.expect_screenshot()
  MiniTest.skip()
end

T['Operator'] = new_set()

T['Operator']['apply'] = new_set()

T['Operator']['apply']['works'] = function() MiniTest.skip() end

T['Operator']['apply']['allows dot-repeat'] = function() MiniTest.skip() end

T['Operator']['apply']['restores window view'] = function()
  -- Should restore on first application

  -- Should not interfere with dot-repeat
  MiniTest.skip()
end

T['Operator']['reset'] = new_set()

T['Operator']['reset']['works'] = function() MiniTest.skip() end

T['Operator']['reset']['allows dot-repeat'] = function() MiniTest.skip() end

T['Operator']['reset']['works with dot-repeat'] = function() MiniTest.skip() end

T['Textobject'] = new_set()

T['Textobject']['works'] = function() MiniTest.skip() end

T['Textobject']['works with dot-repeat'] = function() MiniTest.skip() end

T['Textobject']['correctly computes contiguous ranges'] = function() MiniTest.skip() end

T['Goto'] = new_set()

T['Goto']['works'] = function() MiniTest.skip() end

return T
