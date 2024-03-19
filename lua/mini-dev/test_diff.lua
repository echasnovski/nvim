local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('diff', config) end
local unload_module = function(config) child.mini_unload('diff', config) end
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

local get_buf_hunks = function(buf_id)
  buf_id = buf_id or 0
  return child.lua_get('require("mini-dev.diff").get_buf_data(' .. buf_id .. ').hunks')
end

local get_buf_data = function(buf_id)
  return child.lua(
    [[
      local res = require('mini-dev.diff').get_buf_data(...)
      if res == nil then return nil end
      -- Can not return callables from child process
      res.config.source = nil
      return res
    ]],
    { buf_id }
  )
end

local is_buf_enabled = function(buf_id) return get_buf_data(buf_id) ~= vim.NIL end

-- Common mocks
local small_time = 5

local setup_with_dummy_source = function(text_change_delay)
  text_change_delay = text_change_delay or small_time
  child.lua([[
    _G.dummy_log = {}
    _G.dummy_source = {
      name = 'dummy',
      attach = function(...) table.insert(_G.dummy_log, { 'attach', { ... } }) end,
      detach = function(...) table.insert(_G.dummy_log, { 'detach', { ... } }) end,
      apply_hunks = function(...) table.insert(_G.dummy_log, { 'apply_hunks', { ... } }) end,
    }
  ]])
  local lua_cmd = string.format(
    [[require('mini-dev.diff').setup({
    delay = { text_change = %d },
    source = _G.dummy_source,
  })]],
    text_change_delay
  )
  child.lua(lua_cmd)
end

local validate_dummy_log = function(ref_log) eq(child.lua_get('_G.dummy_log'), ref_log) end

local clean_dummy_log = function() child.lua('_G.dummy_log = {}') end

-- Module helpers
local setup_enabled_buffer = function()
  -- Usually used to make tests on not initial (kind of special) buffer
  local init_buf_id = child.api.nvim_get_current_buf()
  child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))
  child.lua('MiniDiff.enable(0)')
  child.api.nvim_buf_delete(init_buf_id, { force = true })
  clean_dummy_log()
end

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

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.set_size(10, 15)
      mock_notify()
      setup_with_dummy_source()
      clean_dummy_log()
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
  unload_module()
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
  eq(is_buf_enabled(buf_id_normal), true)
  eq(is_buf_enabled(buf_id_bad_1), false)
  eq(is_buf_enabled(buf_id_bad_2), false)
end

T['enable()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

local enable = forward_lua('MiniDiff.enable')

T['enable()']['works in not normal buffer'] = function()
  local buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(buf_id)
  clean_dummy_log()
  enable(buf_id)
  validate_dummy_log({ { 'attach', { buf_id } } })
end

T['enable()']['works in not current buffer'] = function()
  local buf_id = child.api.nvim_create_buf(true, false)
  enable(buf_id)
  validate_dummy_log({ { 'attach', { buf_id } } })
  eq(is_buf_enabled(buf_id), true)
end

T['enable()']['normalizes input buffer'] = function()
  local buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(buf_id)
  clean_dummy_log()
  enable(0)
  eq(is_buf_enabled(buf_id), true)
end

T['enable()']['does not re-enable already enabled buffer'] = function()
  enable()
  validate_dummy_log({})
end

T['enable()']['makes buffer update cache on `BufWinEnter`'] = function()
  eq(get_buf_data().config.delay.text_change, small_time)
  child.b.minidiff_config = { delay = { text_change = 200 } }
  child.api.nvim_exec_autocmds('BufWinEnter', { buffer = child.api.nvim_get_current_buf() })
  eq(get_buf_data().config.delay.text_change, 200)
end

T['enable()']['makes buffer disabled when deleted'] = function()
  local alt_buf_id = child.api.nvim_create_buf(true, false)
  enable(alt_buf_id)
  clean_dummy_log()

  local buf_id = child.api.nvim_get_current_buf()
  child.api.nvim_buf_delete(buf_id, { force = true })
  validate_dummy_log({ { 'detach', { buf_id } } })
end

T['enable()']['makes buffer reset on rename'] = function()
  local buf_id = child.api.nvim_get_current_buf()
  child.api.nvim_buf_set_name(0, 'hello')
  validate_dummy_log({ { 'detach', { buf_id } }, { 'attach', { buf_id } } })
end

T['enable()']['validates arguments'] = function()
  expect.error(function() enable({}) end, '`buf_id`.*valid buffer id')
end

T['enable()']['respects `vim.{g,b}.minidiff_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    local buf_id = child.api.nvim_create_buf(true, false)
    if var_type == 'b' then child.api.nvim_buf_set_var(buf_id, 'minidiff_disable', true) end
    if var_type == 'g' then child.api.nvim_set_var('minidiff_disable', true) end
    enable(buf_id)
    validate_dummy_log({})
    eq(is_buf_enabled(buf_id), false)
  end,
})

T['enable()']['respects `vim.b.minidiff_config`'] = function()
  local buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_var(buf_id, 'minidiff_config', { delay = { text_change = 200 } })
  enable(buf_id)
  eq(get_buf_data(buf_id).config.delay.text_change, 200)
end

T['disable()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

local disable = forward_lua('MiniDiff.disable')

T['disable()']['works'] = function()
  local buf_id = child.api.nvim_get_current_buf()
  eq(is_buf_enabled(buf_id), true)
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  disable(buf_id)
  eq(is_buf_enabled(buf_id), false)

  -- Should delete buffer autocommands
  eq(child.api.nvim_get_autocmds({ buffer = buf_id }), {})

  -- Should detach source
  validate_dummy_log({ { 'detach', { buf_id } } })

  -- Should clear visualization
  child.expect_screenshot()
end

T['disable()']['works in not current buffer'] = function()
  local buf_id = child.api.nvim_create_buf(true, false)
  enable(buf_id)
  clean_dummy_log()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  disable(buf_id)
  eq(is_buf_enabled(buf_id), false)
  validate_dummy_log({ { 'detach', { buf_id } } })
end

T['disable()']['works in not enabled buffer'] = function()
  local buf_id = child.api.nvim_create_buf(true, false)
  eq(is_buf_enabled(buf_id), false)
  expect.no_error(function() disable(buf_id) end)
end

T['disable()']['normalizes input buffer'] = function()
  local buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(buf_id)

  enable(buf_id)
  eq(is_buf_enabled(buf_id), true)
  disable(0)
  eq(is_buf_enabled(buf_id), false)
end

T['disable()']['validates arguments'] = function()
  expect.error(function() disable('a') end, '`buf_id`.*valid buffer id')
end

T['toggle()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

local toggle = forward_lua('MiniDiff.toggle')

T['toggle()']['works'] = function()
  child.lua([[
    _G.log = {}
    local cur_enable = MiniDiff.enable
    MiniDiff.enable = function(...)
      table.insert(_G.log, { 'enabled', { ... } })
      cur_enable(...)
    end
    local cur_disable = MiniDiff.disable
    MiniDiff.disable = function(...)
      cur_disable(...)
      table.insert(_G.log, { 'disabled', { ... } })
    end
  ]])

  local buf_id = child.api.nvim_get_current_buf()
  eq(is_buf_enabled(buf_id), true)
  toggle(buf_id)
  eq(is_buf_enabled(buf_id), false)
  toggle(buf_id)
  eq(is_buf_enabled(buf_id), true)

  eq(child.lua_get('_G.log'), { { 'disabled', { buf_id } }, { 'enabled', { buf_id } } })
end

T['toggle_overlay()'] = new_set()

T['toggle_overlay()']['works'] = function() MiniTest.skip() end

T['get_buf_data()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

T['get_buf_data()']['works'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  child.lua('_G.buf_data = MiniDiff.get_buf_data()')

  -- Should have proper structure
  local fields = child.lua_get('vim.tbl_keys(_G.buf_data)')
  table.sort(fields)
  eq(fields, { 'config', 'hunk_summary', 'hunks', 'ref_text' })

  eq(child.lua_get('vim.deep_equal(MiniDiff.config, _G.buf_data.config)'), true)
  eq(child.lua_get('_G.buf_data.hunk_summary'), { add = 1, change = 0, delete = 0, n_ranges = 1 })
  eq(
    child.lua_get('_G.buf_data.hunks'),
    { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' } }
  )
  eq(child.lua_get('_G.buf_data.ref_text'), 'aaa\n')
end

T['get_buf_data()']['works with not set reference text'] = function()
  local buf_data = get_buf_data()
  eq(buf_data.hunks, {})
  eq(buf_data.hunk_summary, {})
  eq(buf_data.ref_text, nil)
end

T['get_buf_data()']['works on not enabled buffer'] = function()
  local out = child.lua([[
    local buf_id = vim.api.nvim_create_buf(true, false)
    return MiniDiff.get_buf_data(buf_id) == nil
  ]])
  eq(out, true)
end

T['get_buf_data()']['validates arguments'] = function()
  expect.error(function() get_buf_data('a') end, '`buf_id`.*valid buffer id')
end

T['get_buf_data()']['returns copy of underlying data'] = function()
  local out = child.lua([[
    local buf_data = MiniDiff.get_buf_data()
    buf_data.hunks = 'aaa'
    return MiniDiff.get_buf_data().hunks ~= 'aaa'
  ]])
  eq(out, true)
end

T['get_buf_data()']['correctly computes summary numbers'] = function()
  child.lua('MiniDiff.config.options.linematch = 0')
  local buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(buf_id)
  enable(buf_id)
  eq(get_buf_data(buf_id).config.options.linematch, 0)

  local validate = function(ref_summary) eq(get_buf_data(buf_id).hunk_summary, ref_summary) end

  -- Delete lines
  set_lines({ 'BBB', 'DDD' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD' })
  -- NOTE: Number of ranges is 1 because in buffer two delete hunks start on
  -- consecutive lines
  validate({ add = 0, change = 0, delete = 2, n_ranges = 1 })

  -- Add lines
  set_lines({ 'AAA', 'uuu', 'BBB', 'vvv' })
  set_ref_text(0, { 'AAA', 'BBB' })
  validate({ add = 2, change = 0, delete = 0, n_ranges = 2 })

  -- Changed lines are computed per hunk as minimum number of added and deleted
  -- lines. Excess is counted as corresponding lines (added/deleted)
  set_lines({ 'aaa', 'CCC', 'ddd', 'eee', 'uuu' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  local ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 2, type = 'change' },
    { buf_start = 3, buf_count = 3, ref_start = 4, ref_count = 2, type = 'change' },
  }
  eq(get_buf_hunks(buf_id), ref_hunks)
  validate({ add = 1, change = 3, delete = 1, n_ranges = 2 })
end

T['get_buf_data()']['uses number of contiguous ranges in summary'] = function()
  if child.fn.has('nvim-0.9') == 0 then MiniTest.skip('Contiguous regions are relevant with `linematch` option.') end

  set_lines({ 'AAA', 'uuu', 'BbB', 'DDD', 'www', 'EEE' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  local buf_data = get_buf_data()
  eq(buf_data.hunks, {
    { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' },
    { buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 1, type = 'change' },
    { buf_start = 3, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' },
    { buf_start = 5, buf_count = 1, ref_start = 4, ref_count = 0, type = 'add' },
  })

  eq(buf_data.hunk_summary.n_ranges, 2)
end

T['set_ref_text()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

T['set_ref_text()']['works'] = function()
  set_lines({ 'aaa' })

  local validate = function(input_ref_text, ref_ref_text, ref_hunks)
    set_ref_text(0, input_ref_text)
    eq(get_buf_data().ref_text, ref_ref_text)
    eq(get_buf_data().hunks, ref_hunks)
  end
  local ref_hunks = { { buf_start = 1, buf_count = 0, ref_start = 2, ref_count = 1, type = 'delete' } }

  -- Should work with table input (as an array of lines)
  validate({ 'aaa', 'bbb' }, 'aaa\nbbb\n', ref_hunks)

  -- Should work with empty table to remove reference text
  validate({}, nil, {})

  -- Should work with string input
  validate('aaa\n\n', 'aaa\n\n', ref_hunks)

  -- Should append newline if not present
  validate('aaa\nccc', 'aaa\nccc\n', ref_hunks)
  validate('aaa\nccc\n', 'aaa\nccc\n', ref_hunks)
end

T['set_ref_text()']['removing reference text removes visualization'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })
  child.expect_screenshot()
  set_ref_text(0, {})
  child.expect_screenshot()
end

T['set_ref_text()']['enables not enabled buffer'] = function()
  local buf_id = child.api.nvim_create_buf(true, false)
  set_ref_text(buf_id, { 'aaa' })
  eq(is_buf_enabled(buf_id), true)
end

T['set_ref_text()']['immediately updates diff data and visualization'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })
  local ref_hunks = { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' } }
  eq(get_buf_hunks(0), ref_hunks)
  child.expect_screenshot()
end

T['set_ref_text()']['validates arguments'] = function()
  expect.error(function() set_ref_text('a') end, '`buf_id`.*valid buffer id')
end

T['gen_source'] = new_set()

T['gen_source']['git()'] = new_set()

T['gen_source']['git()']['works'] = function() MiniTest.skip() end

T['gen_source']['save()'] = new_set()

T['gen_source']['save()']['works'] = function() MiniTest.skip() end

T['do_hunks()'] = new_set()

local do_hunks = forward_lua('MiniDiff.do_hunks')

T['do_hunks()']['works'] = function()
  set_lines({ 'aaa', 'BBB' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

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
  eq(get_lines(), { 'AAA', 'BBB', 'CCC' })
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
  set_lines({ 'aaa', 'BBB' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  -- Apply
  do_hunks(0, 'apply', { line_start = 2 })
  local ref_hunks = { { buf_start = 2, buf_count = 0, ref_start = 3, ref_count = 1 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset', { line_start = 2 })
  eq(get_lines(), { 'aaa', 'BBB', 'CCC' })
end

T['do_hunks()']['respects `opts.line_end`'] = function()
  set_lines({ 'aaa', 'BBB' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  -- Apply
  do_hunks(0, 'apply', { line_end = 1 })
  local ref_hunks = { { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 1 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset', { line_end = 1 })
  eq(get_lines(), { 'AAA', 'BBB' })
end

T['do_hunks()']['allows negative target lines'] = function()
  set_lines({ 'aaa', 'BBB' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  -- Apply
  do_hunks(0, 'apply', { line_start = -2, line_end = -1 })
  local ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 1 },
    { buf_start = 2, buf_count = 0, ref_start = 3, ref_count = 1 },
  }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset', { line_start = -2, line_end = -1 })
  eq(get_lines(), { 'AAA', 'BBB', 'CCC' })
end

T['do_hunks()']['allows target range to contain lines between hunks'] = function()
  set_lines({ 'aaa', 'bbb', 'uuu', 'vvv', 'ccc', 'www', 'ddd', 'eee' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })

  -- Apply
  do_hunks(0, 'apply', { line_start = 2, line_end = 7 })
  -- - By default should do action on all lines
  local ref_hunks = {
    { buf_start = 3, buf_count = 2, ref_start = 2, ref_count = 0 },
    { buf_start = 6, buf_count = 1, ref_start = 3, ref_count = 0 },
  }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })

  -- Reset
  do_hunks(0, 'reset', { line_start = 2, line_end = 7 })
  eq(get_lines(), { 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
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
  set_ref_text(0, { 'aaa', 'bbb' })

  expect.error(function() do_hunks(-1) end, 'valid buffer')

  expect.error(function() do_hunks(0, 'aaa') end, '`action`.*one of')

  expect.error(function() do_hunks(0, 'apply', { line_start = 'a' }) end, '`line_start`.*number')
  expect.error(function() do_hunks(0, 'apply', { line_end = 'a' }) end, '`line_end`.*number')
  expect.error(function() do_hunks(0, 'apply', { line_start = 2, line_end = 1 }) end, '`line_start`.*less.*`line_end`')

  disable()
  expect.error(function() do_hunks(0) end, 'Buffer.*not enabled')
end

T['goto_hunk()'] = new_set()

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
T['operator()'] = new_set()

T['operator()']['is present'] = function() eq(child.lua_get('type(MiniDiff.operator)'), 'function') end

-- More thorough tests are done in "Integration tests"
T['textobject()'] = new_set()

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

T['Visualization'] = new_set()

T['Visualization']['works'] = function()
  -- Should update in debounce fashion
  MiniTest.skip()
end

T['Visualization']['works when "change" overlaps with "delete"'] = function()
  -- Should prefer "change"
  MiniTest.skip()
end

T['Visualization']['does not flicker during text insert'] = function() MiniTest.skip() end

T['Visualization']['reacts to text change'] = function()
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

T['Visualization']['reacts to buffer enter'] = function()
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

T['Visualization']['reacts to filetype change'] = function()
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

T['Visualization']['reacts to delete of line with match'] = function()
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

T['Visualization']['respects `view.style`'] = function() MiniTest.skip() end

T['Visualization']['respects `view.signs`'] = function() MiniTest.skip() end

T['Visualization']['respects `view.priority`'] = function() MiniTest.skip() end

T['Visualization']['respects `vim.b.minidiff_config`'] = function(var_type)
  child.b.minidiff_config = {}
  MiniTest.skip()
end

T['Visualization']['respects `vim.{g,b}.minidiff_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minidiff_disable = true
    MiniTest.skip()
  end,
})

T['Overlay'] = new_set()

T['Overlay']['works'] = function() MiniTest.skip() end

T['Overlay']['works when "change" overlaps with "delete"'] = function() MiniTest.skip() end

T['Overlay']['respects `view.priority`'] = function() MiniTest.skip() end

T['Diff'] = new_set()

T['Diff']['works'] = function() MiniTest.skip() end

T['Diff']['set proper summary buffer-local variables'] = function()
  -- vim.b.minidiff_summary
  -- vim.b.minidiff_summary_string
  MiniTest.skip()
end

T['Diff']['respects `options.algorithm`'] = function() MiniTest.skip() end

T['Diff']['respects `options.indent_heuristic`'] = function() MiniTest.skip() end

T['Diff']['respects `options.linematch`'] = function() MiniTest.skip() end

-- More thorough tests are done in "do_hunks"
T['Operator'] = new_set({ hooks = { pre_case = clean_dummy_log } })

T['Operator']['apply'] = new_set()

T['Operator']['apply']['works in Normal mode'] = function()
  local ref_hunks
  set_lines({ 'aaa', 'bbb', 'CCC', 'uuu', 'vvv' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  set_cursor(1, 0)
  type_keys('gh', 'j')
  ref_hunks = { { buf_start = 1, buf_count = 2, ref_start = 1, ref_count = 2 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })
  clean_dummy_log()

  -- With dot-repeat
  set_cursor(4, 0)
  type_keys('.')
  ref_hunks = { { buf_start = 4, buf_count = 2, ref_start = 3, ref_count = 0 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })
end

T['Operator']['apply']['allows dot-repeat across buffers'] = function()
  local ref_hunks
  set_lines({ 'aaa', 'uuu', 'vvv' })
  set_ref_text(0, { 'aaa' })
  set_cursor(2, 0)
  type_keys('gh', '_')
  ref_hunks = { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })
  clean_dummy_log()

  local new_buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(new_buf_id)
  set_lines({ 'ccc', 'ddd', 'www', 'xxx', 'eee' })
  set_ref_text(0, { 'ccc', 'ddd', 'eee' })
  set_cursor(3, 0)
  type_keys('.')
  ref_hunks = { { buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 0 } }
  validate_dummy_log({ { 'attach', { new_buf_id } }, { 'apply_hunks', { new_buf_id, ref_hunks } } })
  clean_dummy_log()
end

T['Operator']['apply']['works in Visual mode'] = function()
  set_lines({ 'aaa', 'bbb', 'CCC', 'uuu', 'vvv' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  set_cursor(1, 0)
  type_keys('vj', 'gh')
  local ref_hunks = { { buf_start = 1, buf_count = 2, ref_start = 1, ref_count = 2 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })
  eq(child.fn.mode(), 'n')
end

T['Operator']['apply']['restores window view'] = function()
  child.set_size(7, 15)
  local ref_hunks

  -- Should restore on first application
  set_lines({ 'ooo', 'ppp', 'qqq', 'rrr', 'aaa', 'sss', 'ttt', 'uuu', 'bbb' })

  set_ref_text(0, { 'aaa', 'bbb' })
  set_cursor(4, 2)
  type_keys('zz')
  eq(child.fn.line('w0'), 2)

  type_keys('gh', 'gg')
  ref_hunks = { { buf_start = 1, buf_count = 4, ref_start = 0, ref_count = 0 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })
  clean_dummy_log()

  eq(get_cursor(), { 4, 2 })
  eq(child.fn.line('w0'), 2)

  -- Should not interfere with dot-repeat
  set_ref_text(0, { 'ooo', 'ppp', 'qqq', 'rrr', 'aaa', 'bbb' })
  set_cursor(8, 2)
  type_keys('zz')
  eq(child.fn.line('w0'), 6)
  type_keys('.')
  ref_hunks = { { buf_start = 6, buf_count = 3, ref_start = 5, ref_count = 0 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })
  -- - Places cursor at the start of textobject as all operators do
  eq(get_cursor(), { 1, 2 })
  eq(child.fn.line('w0'), 1)
end

T['Operator']['apply']['works with different mapping'] = function()
  child.lua([[MiniDiff.setup({ source = _G.dummy_source, mappings = { apply = 'Gh' } })]])

  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  set_cursor(2, 0)
  type_keys('Gh', '_')
  local ref_hunks = { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0 } }
  validate_dummy_log({ { 'apply_hunks', { child.api.nvim_get_current_buf(), ref_hunks } } })
end

T['Operator']['reset'] = new_set()

T['Operator']['reset']['works in Normal mode'] = function()
  set_lines({ 'aaa', 'bbb', 'CCC', 'uuu', 'vvv' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  set_cursor(1, 2)
  type_keys('gH', 'j')
  eq(get_lines(), { 'AAA', 'BBB', 'CCC', 'uuu', 'vvv' })
  eq(get_cursor(), { 1, 2 })

  -- With dot-repeat
  set_cursor(4, 1)
  type_keys('.')
  eq(get_lines(), { 'AAA', 'BBB', 'CCC' })
  eq(get_cursor(), { 3, 1 })
end

T['Operator']['reset']['allows dot-repeat across buffers'] = function()
  set_lines({ 'aaa', 'uuu', 'vvv' })
  set_ref_text(0, { 'aaa' })
  set_cursor(2, 0)
  type_keys('gH', '_')
  eq(get_lines(), { 'aaa', 'vvv' })

  local new_buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(new_buf_id)
  set_lines({ 'ccc', 'ddd', 'www', 'xxx', 'eee' })
  set_ref_text(0, { 'ccc', 'ddd', 'eee' })
  set_cursor(3, 0)
  type_keys('.')
  eq(get_lines(), { 'ccc', 'ddd', 'xxx', 'eee' })
end

T['Operator']['reset']['works in Visual mode'] = function()
  set_lines({ 'aaa', 'bbb', 'CCC', 'uuu', 'vvv' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  set_cursor(1, 2)
  type_keys('vj', 'gH')
  eq(get_lines(), { 'AAA', 'BBB', 'CCC', 'uuu', 'vvv' })
  eq(get_cursor(), { 1, 2 })
end

T['Operator']['reset']['works with different mapping'] = function()
  child.lua([[MiniDiff.setup({ source = _G.dummy_source, mappings = { reset = 'GH' } })]])

  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  set_cursor(2, 0)
  type_keys('GH', '_')
  eq(get_lines(), { 'aaa' })
end

T['Textobject'] = new_set()

T['Textobject']['works'] = function()
  set_lines({ 'aaa', 'uuu', 'vvv', 'bbb', 'ccc', 'www' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  set_cursor(2, 0)
  type_keys('d', 'gh')
  eq(get_lines(), { 'aaa', 'bbb', 'ccc', 'www' })
  eq(get_cursor(), { 2, 0 })

  -- With dot-repeat
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  set_cursor(4, 0)
  type_keys('.')
  eq(get_lines(), { 'aaa', 'bbb', 'ccc' })
  eq(get_cursor(), { 3, 0 })
end

T['Textobject']['does not depend on relative position inside hunk'] = function()
  set_lines({ 'aaa', 'uuu', 'vvv', 'www', 'bbb' })
  set_ref_text(0, { 'aaa', 'bbb' })

  set_cursor(3, 0)
  type_keys('d', 'gh')
  eq(get_lines(), { 'aaa', 'bbb' })
end

T['Textobject']['works when not inside hunk range'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  set_cursor(1, 0)
  type_keys('d', 'gh')
  eq(get_lines(), { 'aaa', 'bbb' })
  validate_notifications({ { '(mini.diff) No hunk range under cursor', 'INFO' } })
end

T['Textobject']['allows dot-repeat across buffers'] = function()
  set_lines({ 'aaa', 'uuu' })
  set_ref_text(0, { 'aaa' })
  set_cursor(2, 0)
  type_keys('d', 'gh')
  eq(get_lines(), { 'aaa' })

  local new_buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(new_buf_id)
  set_lines({ 'bbb', 'ccc', 'vvv', 'www', 'ddd' })
  set_ref_text(0, { 'bbb', 'ccc', 'ddd' })
  set_cursor(3, 0)
  type_keys('.')
  eq(get_lines(), { 'bbb', 'ccc', 'ddd' })
end

T['Textobject']['correctly computes contiguous ranges'] = function()
  if child.fn.has('nvim-0.9') == 0 then MiniTest.skip('Contiguous regions are relevant with `linematch` option.') end

  -- "Change" hunk adjacent to "add" and "delete" hunks
  set_lines({ 'AAA', 'uuu', 'BbB', 'DDD', 'www', 'EEE' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  eq(get_buf_hunks(), {
    { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' },
    { buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 1, type = 'change' },
    { buf_start = 3, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' },
    { buf_start = 5, buf_count = 1, ref_start = 4, ref_count = 0, type = 'add' },
  })

  set_cursor(3, 0)
  type_keys('d', 'gh')
  eq(get_lines(), { 'AAA', 'DDD', 'www', 'EEE' })
end

T['Textobject']['works with "delete" hunks on edges as target'] = function()
  -- First line
  set_lines({ 'bbb', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  set_cursor(1, 1)
  type_keys('d', 'gh')
  eq(get_lines(), { 'ccc' })
  eq(get_cursor(), { 1, 1 })

  -- Last line
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  set_cursor(2, 1)
  type_keys('d', 'gh')
  eq(get_lines(), { 'aaa' })
  eq(get_cursor(), { 1, 1 })
end

T['Textobject']['works with different mapping'] = function()
  child.lua([[
    MiniDiff.setup({ source = _G.dummy_source, mappings = { textobject = 'Gh' } })
  ]])

  set_lines({ 'aaa', 'uuu', 'bbb' })
  set_ref_text(0, { 'aaa', 'bbb' })

  set_cursor(2, 0)
  type_keys('d', 'Gh')
  eq(get_lines(), { 'aaa', 'bbb' })
end

T['Textobject']['throws error in not enabled buffer'] = function()
  child.set_size(30, 80)
  child.o.cmdheight = 10
  disable()
  expect.error(function() type_keys('d', 'gh') end, 'not enabled')
end

T['Textobject']['respects `vim.{g,b}.minidiff_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child.set_size(30, 80)
    child.o.cmdheight = 10
    set_lines({ 'aaa', 'uuu' })
    set_ref_text(0, { 'aaa' })

    child[var_type].minidiff_disable = true
    set_cursor(2, 0)
    expect.error(function() type_keys('d', 'gh') end, 'not enabled')
  end,
})

-- More thorough tests are done in "goto_hunk"
T['Goto'] = new_set()

T['Goto']['works in Normal mode'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(keys, ref_cursor)
    set_cursor(4, 0)
    type_keys(keys)
    eq(get_cursor(), ref_cursor)
  end

  validate('[H', { 1, 0 })
  validate('[h', { 3, 0 })
  validate(']h', { 5, 0 })
  validate(']H', { 7, 0 })
end

T['Goto']['works in Visual mode'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(keys, ref_cursor)
    child.ensure_normal_mode()
    set_cursor(4, 0)
    type_keys('v', keys)
    eq(get_cursor(), ref_cursor)
    eq(child.fn.mode(), 'v')
  end

  validate('[H', { 1, 0 })
  validate('[h', { 3, 0 })
  validate(']h', { 5, 0 })
  validate(']H', { 7, 0 })
end

T['Goto']['works in Operator-pending mode'] = function()
  local validate = function(keys, lines_1, cursor_1, lines_2, cursor_2)
    set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
    set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

    set_cursor(4, 1)

    -- Should operate linewise
    type_keys('d', keys)
    eq(get_lines(), lines_1)
    eq(get_cursor(), cursor_1)

    -- With dot-repeat
    type_keys('.')
    eq(get_lines(), lines_2)
    eq(get_cursor(), cursor_2)
  end

  validate('[H', { 'www', 'ccc', 'xxx' }, { 1, 1 }, { 'ccc', 'xxx' }, { 1, 1 })
  validate('[h', { 'uuu', 'aaa', 'www', 'ccc', 'xxx' }, { 3, 1 }, { 'ccc', 'xxx' }, { 1, 1 })
  validate(']h', { 'uuu', 'aaa', 'vvv', 'ccc', 'xxx' }, { 4, 1 }, { 'uuu', 'aaa', 'vvv' }, { 3, 1 })
  validate(']H', { 'uuu', 'aaa', 'vvv' }, { 3, 1 }, { 'uuu', 'aaa' }, { 2, 1 })
end

T['Goto']['allows dot-repeat across buffers'] = function()
  set_lines({ 'aaa', 'uuu', 'bbb' })
  set_ref_text(0, { 'aaa' })
  set_cursor(1, 0)
  type_keys('d', ']h')
  eq(get_lines(), { 'bbb' })

  local new_buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(new_buf_id)
  set_lines({ 'ccc', 'ddd', 'vvv', 'www', 'eee' })
  set_ref_text(0, { 'ccc', 'ddd', 'eee' })
  set_cursor(2, 0)
  type_keys('.')
  eq(get_lines(), { 'ccc', 'www', 'eee' })
end

T['Goto']['respects [count]'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(keys, ref_cursor)
    set_cursor(4, 0)
    type_keys('2', keys)
    eq(get_cursor(), ref_cursor)
  end

  validate('[H', { 3, 0 })
  validate('[h', { 1, 0 })
  validate(']h', { 7, 0 })
  validate(']H', { 5, 0 })
end

T['Goto']['works with different mappings'] = function()
  child.lua([[
    MiniDiff.setup({
      source = _G.dummy_source,
      mappings = {
        goto_first = '[G',
        goto_prev = '[g',
        goto_next = ']g',
        goto_last = ']G',
      }
    })
  ]])

  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(keys, ref_cursor)
    set_cursor(4, 0)
    type_keys(keys)
    eq(get_cursor(), ref_cursor)
  end

  validate('[G', { 1, 0 })
  validate('[g', { 3, 0 })
  validate(']g', { 5, 0 })
  validate(']G', { 7, 0 })
end

return T
