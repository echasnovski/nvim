local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('diff', config) end
local set_lines = function(...) return child.set_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

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

-- Data =======================================================================
local small_time = 5

local test_lines = { 'abcd abcd', 'Abcd ABCD', 'abcdaabcd' }

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.set_size(10, 15)
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

T['enable()'] = new_set()

local enable = forward_lua([[require('mini-dev.diff').enable]])
local get_buf_data = forward_lua([[require('mini-dev.diff').get_buf_data]])

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

T['gen_source'] = new_set()

T['gen_source']['hex_color()'] = new_set()

local enable_hex_color = function(...)
  child.lua(
    [[_G.hipatterns = require('mini.hipatterns')
      _G.hipatterns.setup({
        highlighters = { hex_color = _G.hipatterns.gen_highlighter.hex_color(...) },
      })]],
    { ... }
  )
end

T['gen_source']['hex_color()']['works'] = function()
  -- set_lines({
  --   -- Should be highlighted
  --   '#000000 #ffffff',
  --   '#FffFFf',
  --
  --   -- Should not be highlighted
  --   '#00000 #0000000',
  --   '#00000g',
  -- })
  --
  -- enable_hex_color()
  --
  -- child.expect_screenshot()
  --
  -- -- Should use correct highlight groups
  -- --stylua: ignore
  -- eq(get_hipatterns_extmarks(0), {
  --   { line = 1, from_col = 1, to_col = 7,  hl_group = 'MiniHipatterns000000' },
  --   { line = 1, from_col = 9, to_col = 15, hl_group = 'MiniHipatternsffffff' },
  --   { line = 2, from_col = 1, to_col = 7,  hl_group = 'MiniHipatternsffffff' },
  -- })
  -- expect.match(child.cmd_capture('hi MiniHipatterns000000'), 'guifg=#ffffff guibg=#000000')
  -- expect.match(child.cmd_capture('hi MiniHipatternsffffff'), 'guifg=#000000 guibg=#ffffff')
  MiniTest.skip()
end

return T
