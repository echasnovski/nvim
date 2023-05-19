-- TODO
local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set
local mark_flaky = helpers.mark_flaky

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('hipatterns', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

-- Data =======================================================================
local test_config = {
  highlighters = { abcd = { pattern = 'abcd', group = 'Error' } },
  delay = { text_change = 20, scroll = 20 },
}
local small_time = 5

-- Output test set ============================================================
T = new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniHipatterns)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniHipatterns'), 1)

  -- Highlight groups
  expect.match(child.cmd_capture('hi MiniHipatternsFixme'), 'links to DiagnosticError')
  expect.match(child.cmd_capture('hi MiniHipatternsHack'), 'links to DiagnosticWarn')
  expect.match(child.cmd_capture('hi MiniHipatternsTodo'), 'links to DiagnosticInfo')
  expect.match(child.cmd_capture('hi MiniHipatternsNote'), 'links to DiagnosticHint')
end

T['setup()']['creates `config` field'] = function()
  load_module()

  eq(child.lua_get('type(_G.MiniHipatterns.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniHipatterns.config.' .. field), value) end

  expect_config('highlighters', {})
  expect_config('delay.text_change', 200)
  expect_config('delay.scroll', 50)
end

T['setup()']['respects `config` argument'] = function()
  load_module({ delay = { text_change = 20 } })
  eq(child.lua_get('MiniHipatterns.config.delay.text_change'), 20)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ highlighters = 'a' }, 'highlighters', 'table')
  expect_config_error({ delay = 'a' }, 'delay', 'table')
  expect_config_error({ delay = { text_change = 'a' } }, 'delay.text_change', 'number')
  expect_config_error({ delay = { scroll = 'a' } }, 'delay.scroll', 'number')
end

T['enable()'] = new_set()

T['enable()']['works'] = function()
  child.set_size(10, 15)
  local test_file = 'tests/hipatterns_enable'
  MiniTest.finally(function() vim.fn.delete(test_file) end)

  set_lines({ 'abcd abcd', 'Abcd ABCD', 'abcdabcd' })
  child.lua([[require('mini-dev.hipatterns').enable(...)]], { 0, test_config })

  -- Should register buffer as enabled
  local init_buf_id = child.api.nvim_get_current_buf()
  eq(child.lua_get([[require('mini-dev.hipatterns').get_enabled_buffers()]]), { init_buf_id })

  -- Should add highlights immediately
  child.expect_screenshot()

  -- Should enable debounced auto highlight on text change
  set_cursor(3, 0)
  type_keys(0.5 * test_config.delay.text_change, 'o', 'abcd')
  -- - No highlights should be shown
  child.expect_screenshot()
  sleep(test_config.delay.text_change + small_time)
  -- - Now there should be highlights
  child.expect_screenshot()

  -- Should disable on buffer detach
  child.ensure_normal_mode()
  child.cmd('bdelete!')
  eq(child.lua_get([[require('mini-dev.hipatterns').get_enabled_buffers()]]), {})
end

T['enable()']['validates arguments'] = function() MiniTest.skip() end

T['disable()'] = new_set()

T['disable()']['works'] = function() MiniTest.skip() end

T['disable()']['validates arguments'] = function() MiniTest.skip() end

T['toggle()'] = new_set()

T['toggle()']['works'] = function() MiniTest.skip() end

T['toggle()']['validates arguments'] = function() MiniTest.skip() end

T['update()'] = new_set()

T['update()']['works'] = function() MiniTest.skip() end

T['update()']['validates arguments'] = function() MiniTest.skip() end

T['get_enabled_buffers()'] = new_set()

T['get_enabled_buffers()']['works'] = function() MiniTest.skip() end

T['gen_highlighter'] = new_set()

T['gen_highlighter']['pattern()'] = new_set()

T['gen_highlighter']['pattern()']['works'] = function() MiniTest.skip() end

T['gen_highlighter']['pattern()']['respects `opts.priority`'] = function() MiniTest.skip() end

T['gen_highlighter']['pattern()']['respects `opts.filter`'] = function() MiniTest.skip() end

T['gen_highlighter']['hex_color()'] = new_set()

T['gen_highlighter']['hex_color()']['works'] = function() MiniTest.skip() end

T['gen_highlighter']['hex_color()']['respects `opts.priority`'] = function() MiniTest.skip() end

T['gen_highlighter']['hex_color()']['respects `opts.filter`'] = function() MiniTest.skip() end

T['gen_highlighter']['hex_color()']['respects `opts.style`'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
T['Auto highlight'] = new_set()

T['Auto highlight']['works'] = function() MiniTest.skip() end

T['Auto highlight']['respects `vim.{g,b}.minihipatterns_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type) MiniTest.skip() end,
})

T['Highlighters'] = new_set()

T['Highlighters']['works'] = function() MiniTest.skip() end

T['Highlighters']['silently skips wrong entries'] = function() MiniTest.skip() end

T['Highlighters']['respects `pattern`'] = function() MiniTest.skip() end

T['Highlighters']['allows callable `pattern`'] = function() MiniTest.skip() end

T['Highlighters']['respects `group`'] = function() MiniTest.skip() end

T['Highlighters']['allows callable `group`'] = function() MiniTest.skip() end

T['Highlighters']['respects `priority`'] = function() MiniTest.skip() end

T['Highlighters']['respects `vim.b.minihipatterns_config`'] = function() MiniTest.skip() end

T['Delay'] = new_set()

T['Delay']['works'] = function() MiniTest.skip() end

T['Delay']['respects `text_change`'] = function() MiniTest.skip() end

T['Delay']['respects `scroll`'] = function() MiniTest.skip() end

T['Delay']['respects `vim.b.minihipatterns_config`'] = function() MiniTest.skip() end

T['Autocommands'] = new_set()

T['Autocommands']['works on buffer enter'] = function() MiniTest.skip() end

T['Autocommands']['works on window scroll'] = function()
  -- Paste several times changing same lines leading to not proper highlights.
  -- Scrolling should make them up to date.
  MiniTest.skip()
end

T['Autocommands']['works on filetype change'] = function() MiniTest.skip() end

T['Autocommands']['works on color scheme change'] = function() MiniTest.skip() end

return T
