local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq, no_eq = helpers.expect, helpers.expect.equality, helpers.expect.no_equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('keymap', config) end
local unload_module = function() child.mini_unload('keymap') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local test_dir = 'tests/dir-keymap'

-- Time constants
local small_time = helpers.get_time_const(10)

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local mock_plugin = function(name) child.cmd('noautocmd set rtp+=tests/dir-keymap/mock-plugins/' .. name) end

local mock_test_steps = function(method_name)
  child.lua([[
    -- Action returns nothing
    _G.step_1 = {
      condition = function() table.insert(_G.log, 'cond 1'); return _G.step_1_cond end,
      action = function() table.insert(_G.log, 'action 1') end,
    }

    -- Action returns string keys to be emulated as if typed
    _G.step_2 = {
      condition = function() table.insert(_G.log, 'cond 2'); return _G.step_2_cond end,
      action = function() table.insert(_G.log, 'action 2'); return 'dd' end,
    }

    -- Action returns `<Cmd>...<CR>` string to be executed
    _G.step_3 = {
      condition = function() table.insert(_G.log, 'cond 3'); return _G.step_3_cond end,
      action = function()
        table.insert(_G.log, 'action 3')
        return '<Cmd>lua vim.api.nvim_buf_set_lines(0, 0, -1, false, { "From step 3" })<CR>'
      end,
    }

    -- Action returns `false` to indicate "keep processing next steps"
    _G.step_4 = {
      condition = function() table.insert(_G.log, 'cond 4'); return _G.step_4_cond end,
      action = function() table.insert(_G.log, 'action 4'); return false end,
    }

    -- Action returns callable to be executed later
    _G.step_5 = {
      condition = function() table.insert(_G.log, 'cond 5'); return _G.step_5_cond end,
      action = function()
        table.insert(_G.log, 'action 5')
        local upvalue = 'From step 5 with upvalue'
        return function() vim.api.nvim_buf_set_lines(0, 0, -1, false, { upvalue }) end
      end,
    }

    _G.steps = { _G.step_1, _G.step_2, _G.step_3, _G.step_4, _G.step_5 }
  ]])
end

local validate_log_and_clean = function(ref)
  eq(child.lua_get('_G.log'), ref)
  child.lua('_G.log = {}')
end

local validate_multi_works = function(key, method_name, ref_lines_state)
  mock_test_steps()
  child.lua('require("mini-dev.keymap").' .. method_name .. '(_G.steps)')

  -- Can pass through
  type_keys(key)
  validate_log_and_clean({ 'cond 1', 'cond 2', 'cond 3', 'cond 4', 'cond 5' })
  eq(get_lines(), ref_lines_state[1])

  -- Can handle an action returning nothing
  child.lua('_G.step_1_cond = true')
  type_keys(key)
  validate_log_and_clean({ 'cond 1', 'action 1' })
  eq(get_lines(), ref_lines_state[2])
  child.lua('_G.step_1_cond = false')

  -- Can emulate returned keys
  child.lua('_G.step_2_cond = true')
  type_keys(key)
  validate_log_and_clean({ 'cond 1', 'cond 2', 'action 2' })
  eq(get_lines(), ref_lines_state[3])
  child.lua('_G.step_2_cond = false')

  -- Can execute `<Cmd>...<CR>` string
  child.lua('_G.step_3_cond = true')
  type_keys(key)
  validate_log_and_clean({ 'cond 1', 'cond 2', 'cond 3', 'action 3' })
  eq(get_lines(), ref_lines_state[4])
  child.lua('_G.step_3_cond = false')

  -- Respects action returning `false` to indicate processing further steps
  child.lua('_G.step_4_cond = true')
  set_cursor(1, 11)
  type_keys(key)
  validate_log_and_clean({ 'cond 1', 'cond 2', 'cond 3', 'cond 4', 'action 4', 'cond 5' })
  eq(get_lines(), ref_lines_state[5])
  child.lua('_G.step_4_cond = false')

  -- Can execute callable returned from action
  child.lua('_G.step_5_cond = true')
  type_keys(key)
  validate_log_and_clean({ 'cond 1', 'cond 2', 'cond 3', 'cond 4', 'cond 5', 'action 5' })
  eq(get_lines(), ref_lines_state[6])
  child.lua('_G.step_5_cond = false')
  -- - Should not create side effects
  eq(child.lua_get('type(_G.MiniKeymap)'), 'nil')
end

local validate_multi_input_validation = function(wrapper, method_name)
  child.lua('_G.method = ' .. vim.inspect(method_name))
  expect.error(function() wrapper('a') end, '`steps`.*array')
  expect.error(function() wrapper({ 'a' }) end, '`steps`.*valid steps.*not')
  expect.error(function() wrapper({ {} }) end, '`steps`.*valid steps.*not')
  expect.error(function() wrapper({ { condition = 'a' } }) end, '`steps`.*valid steps.*not')
  expect.error(
    function() child.lua('require("mini-dev.keymap")[_G.method]({ { condition = function() end, action = "a" } })') end,
    '`steps`.*valid steps.*not'
  )
end

local validate_multi_opts_usage = function(key, method_name)
  child.lua('_G.map_multi = require("mini-dev.keymap").' .. method_name)
  child.lua('_G.key = ' .. vim.inspect(key))

  local validate_mapping = function(is_buffer_local, ref_desc)
    local info = child.lua([[
      local map_info = vim.fn.maparg(_G.key, 'i', false, true)
      return { is_buffer_local = map_info.buffer == 1, desc = map_info.desc }
    ]])
    eq(info, { is_buffer_local = is_buffer_local, desc = ref_desc })
  end

  mock_test_steps()

  child.lua('_G.map_multi({ _G.step_3 })')
  validate_mapping(false, 'Multi ' .. key)

  -- Should create a separate buffer-local mapping with custom description
  child.lua('_G.map_multi({ _G.step_5 }, { buffer = 0, desc = "My multi", expr = false, replace_keycodes = false })')
  validate_mapping(true, 'My multi')

  -- Should be independent and actually use only buffer-local mapping
  child.lua('_G.step_3_cond, _G.step_5_cond = true, true')
  type_keys('i', key)
  eq(get_lines(), { 'From step 5 with upvalue' })
  eq(child.lua_get('_G.log'), { 'cond 5', 'action 5' })
  child.lua('_G.log = {}')

  child.cmd('iunmap <buffer> ' .. key)
  type_keys(key)
  eq(get_lines(), { 'From step 3' })
  eq(child.lua_get('_G.log'), { 'cond 3', 'action 3' })
end

local is_pumvisible = function() return child.fn.pumvisible() == 1 end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.lua('_G.log = {}')
    end,
    post_once = child.stop,
    n_retry = helpers.get_n_retry(2),
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()
  -- Global variable
  eq(child.lua_get('type(_G.MiniKeymap)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  load_module()
  eq(child.lua_get('type(_G.MiniKeymap.config)'), 'table')
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
end

T['map_multi_tab()'] = new_set()

local map_multi_tab = forward_lua('require("mini-dev.keymap").map_multi_tab')

T['map_multi_tab()']['works'] = function()
  type_keys('i')
  local ref_lines_state = {
    { '\t' }, -- Act as if unmapped
    { '\t' }, -- Do nothing
    { '\tdd' }, -- Emulate returned keys
    { 'From step 3' }, -- Execute `<Cmd>...<CR>` string
    { 'From step 3\t' }, -- Respect `false` action return as "pass through"
    { 'From step 5 with upvalue' }, -- Execute callable returned from action
  }
  validate_multi_works('<Tab>', 'map_multi_tab', ref_lines_state)
end

T['map_multi_tab()']['works with empty steps'] = function()
  map_multi_tab({})
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
end

T['map_multi_tab()']['respects `opts`'] = function() validate_multi_opts_usage('<Tab>', 'map_multi_tab') end

T['map_multi_tab()']['built-in steps'] = new_set()

T['map_multi_tab()']['built-in steps']['pmenu_next'] = function()
  child.o.completeopt = 'menuone,noselect'
  map_multi_tab({ 'pmenu_next' })

  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  type_keys('aa ab ', '<C-n>')
  eq(is_pumvisible(), true)

  -- Should act as pressing `<C-n>`
  type_keys('<Tab>')
  eq(is_pumvisible(), true)
  eq(get_lines(), { '\taa ab aa' })

  type_keys('<C-e>')
  eq(is_pumvisible(), false)
  eq(get_lines(), { '\taa ab ' })
  type_keys('<Tab>')
  eq(get_lines(), { '\taa ab \t' })
end

T['map_multi_tab()']['built-in steps']['cmp_next'] = function()
  map_multi_tab({ 'cmp_next' })

  -- Should work if 'cmp' module is not present
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('nvim-cmp')

  -- Should pass through if there is no visible nvim-cmp menu
  type_keys('<Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'cmp.visible' })

  child.lua('_G.cmp_visible_res = true')
  type_keys('<Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'cmp.visible', 'cmp.select_next_item' })
end

T['map_multi_tab()']['built-in steps']['blink_next'] = function()
  map_multi_tab({ 'blink_next' })

  -- Should work if 'blink.cmp' module is not present
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('blink.cmp')

  -- Should pass through if there is no visible blink menu
  type_keys('<Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'blink.is_menu_visible' })

  child.lua('_G.blink_is_menu_visible_res = true')
  type_keys('<Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'blink.is_menu_visible', 'blink.select_next' })
end

T['map_multi_tab()']['built-in steps']['minisnippets_next'] = function() MiniTest.skip() end

T['map_multi_tab()']['built-in steps']['minisnippets_expand'] = function() MiniTest.skip() end

T['map_multi_tab()']['built-in steps']['vimsnippet_next'] = function() MiniTest.skip() end

T['map_multi_tab()']['built-in steps']['luasnip_next'] = function() MiniTest.skip() end

T['map_multi_tab()']['built-in steps']['luasnip_expand'] = function() MiniTest.skip() end

T['map_multi_tab()']['built-in steps']['jump_after_tsnode'] = function() MiniTest.skip() end

T['map_multi_tab()']['built-in steps']['jump_after_pair'] = function() MiniTest.skip() end

T['map_multi_tab()']['built-in steps']['increase_indent'] = function() MiniTest.skip() end

T['map_multi_tab()']['validates input'] = function() validate_multi_input_validation(map_multi_tab, 'map_multi_tab') end

T['map_multi_shifttab()'] = new_set()

local map_multi_shifttab = forward_lua('require("mini-dev.keymap").map_multi_shifttab')

T['map_multi_shifttab()']['works'] = function()
  type_keys('i')
  -- Pressing unmapped `<S-Tab>` in Insert mode behaves like pressing `<Tab>`
  local ref_lines_state = {
    { '\t' }, -- Act as if unmapped
    { '\t' }, -- Do nothing
    { '\tdd' }, -- Emulate returned keys
    { 'From step 3' }, -- Execute `<Cmd>...<CR>` string
    { 'From step 3\t' }, -- Respect `false` action return as "pass through"
    { 'From step 5 with upvalue' }, -- Execute callable returned from action
  }
  validate_multi_works('<S-Tab>', 'map_multi_shifttab', ref_lines_state)
end

T['map_multi_shifttab()']['works with empty steps'] = function()
  map_multi_shifttab({})
  type_keys('i', '<S-Tab>')
  eq(get_lines(), { '\t' })
end

T['map_multi_shifttab()']['respects `opts`'] = function() validate_multi_opts_usage('<S-Tab>', 'map_multi_shifttab') end

T['map_multi_shifttab()']['built-in steps'] = new_set()

T['map_multi_shifttab()']['built-in steps']['pmenu_prev'] = function()
  child.o.completeopt = 'menuone,noselect'
  map_multi_shifttab({ 'pmenu_prev' })

  type_keys('i', '<S-Tab>')
  eq(get_lines(), { '\t' })
  type_keys('aa ab ', '<C-n>')
  eq(is_pumvisible(), true)

  -- Should act as pressing `<C-p>`
  type_keys('<S-Tab>')
  eq(is_pumvisible(), true)
  eq(get_lines(), { '\taa ab ab' })

  type_keys('<C-e>')
  eq(is_pumvisible(), false)
  eq(get_lines(), { '\taa ab ' })
  type_keys('<S-Tab>')
  eq(get_lines(), { '\taa ab \t' })
end

T['map_multi_shifttab()']['built-in steps']['cmp_prev'] = function()
  map_multi_shifttab({ 'cmp_prev' })

  -- Should work if 'cmp' module is not present
  type_keys('i', '<S-Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('nvim-cmp')

  -- Should pass through if there is no visible nvim-cmp menu
  type_keys('<S-Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'cmp.visible' })

  child.lua('_G.cmp_visible_res = true')
  type_keys('<S-Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'cmp.visible', 'cmp.select_prev_item' })
end

T['map_multi_shifttab()']['built-in steps']['blink_prev'] = function()
  map_multi_shifttab({ 'blink_prev' })

  -- Should work if 'blink.cmp' module is not present
  type_keys('i', '<S-Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('blink.cmp')

  -- Should pass through if there is no visible blink.cmp menu
  type_keys('<S-Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'blink.is_menu_visible' })

  child.lua('_G.blink_is_menu_visible_res = true')
  type_keys('<S-Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'blink.is_menu_visible', 'blink.select_prev' })
end

T['map_multi_shifttab()']['built-in steps']['minisnippets_prev'] = function() MiniTest.skip() end

T['map_multi_shifttab()']['built-in steps']['vimsnippet_prev'] = function() MiniTest.skip() end

T['map_multi_shifttab()']['built-in steps']['luasnip_prev'] = function() MiniTest.skip() end

T['map_multi_shifttab()']['built-in steps']['jump_before_tsnode'] = function() MiniTest.skip() end

T['map_multi_shifttab()']['built-in steps']['jump_before_pair'] = function() MiniTest.skip() end

T['map_multi_shifttab()']['built-in steps']['decrease_indent'] = function() MiniTest.skip() end

T['map_multi_shifttab()']['validates input'] = function()
  validate_multi_input_validation(map_multi_shifttab, 'map_multi_shifttab')
end

T['map_multi_cr()'] = new_set()

local map_multi_cr = forward_lua('require("mini-dev.keymap").map_multi_cr')

T['map_multi_cr()']['works'] = function()
  type_keys('i')
  local ref_lines_state = {
    { '', '' }, -- Act as if unmapped
    { '', '' }, -- Do nothing
    { '', 'dd' }, -- Emulate returned keys
    { 'From step 3' }, -- Execute `<Cmd>...<CR>` string
    { 'From step 3', '' }, -- Respect `false` action return as "pass through"
    { 'From step 5 with upvalue' }, -- Execute callable returned from action
  }
  validate_multi_works('<CR>', 'map_multi_cr', ref_lines_state)
end

T['map_multi_cr()']['works with empty steps'] = function()
  map_multi_cr({})
  type_keys('i', '<CR>')
  eq(get_lines(), { '', '' })
end

T['map_multi_cr()']['respects `opts`'] = function() validate_multi_opts_usage('<CR>', 'map_multi_cr') end

T['map_multi_cr()']['built-in steps'] = new_set()

T['map_multi_cr()']['built-in steps']['pmenu_accept'] = function()
  child.o.completeopt = 'menuone,noselect'
  map_multi_cr({ 'pmenu_accept' })

  type_keys('i', '<CR>')
  eq(get_lines(), { '', '' })

  -- Should accept selected (and only selected) item, i.e. act like `<C-y>`
  type_keys('aa ab ', '<C-n>', '<C-n>')
  eq(is_pumvisible(), true)
  eq(get_lines(), { '', 'aa ab aa' })

  type_keys('<CR>')
  eq(is_pumvisible(), false)
  eq(get_lines(), { '', 'aa ab aa' })
end

T['map_multi_cr()']['built-in steps']['cmp_accept'] = function()
  map_multi_cr({ 'cmp_accept' })

  -- Should work if 'cmp' module is not present
  type_keys('i', '<CR>')
  eq(get_lines(), { '', '' })
  validate_log_and_clean({})

  mock_plugin('nvim-cmp')

  -- Should pass through if there is no selected nvim-cmp item
  type_keys('<CR>')
  eq(get_lines(), { '', '', '' })
  validate_log_and_clean({ 'cmp.get_selected_entry' })

  child.lua('_G.cmp_get_selected_entry_res = {}')
  type_keys('<CR>')
  -- - Should not modify text
  eq(get_lines(), { '', '', '' })
  validate_log_and_clean({ 'cmp.get_selected_entry', 'cmp.confirm' })
end

T['map_multi_cr()']['built-in steps']['blink_accept'] = function()
  map_multi_cr({ 'blink_accept' })

  -- Should work if 'blink.mp' module is not present
  type_keys('i', '<CR>')
  eq(get_lines(), { '', '' })
  validate_log_and_clean({})

  mock_plugin('blink.cmp')

  -- Should pass through if there is no selected blink.cmp item
  type_keys('<CR>')
  eq(get_lines(), { '', '', '' })
  validate_log_and_clean({ 'blink.get_selected_item' })

  child.lua('_G.blink_get_selected_item_res = {}')
  type_keys('<CR>')
  -- - Should not modify text
  eq(get_lines(), { '', '', '' })
  validate_log_and_clean({ 'blink.get_selected_item', 'blink.accept' })
end

T['map_multi_cr()']['built-in steps']['minipairs_cr'] = function() MiniTest.skip() end

T['map_multi_cr()']['built-in steps']['nvimautopairs_cr'] = function() MiniTest.skip() end

T['map_multi_cr()']['validates input'] = function() validate_multi_input_validation(map_multi_cr, 'map_multi_cr') end

T['map_multi_bs()'] = new_set()

local map_multi_bs = forward_lua('require("mini-dev.keymap").map_multi_bs')

T['map_multi_bs()']['works'] = function()
  type_keys('i', 'ab')

  local ref_lines_state = {
    { 'a' }, -- Act as if unmapped
    { 'a' }, -- Do nothing
    { 'add' }, -- Emulate returned keys
    { 'From step 3' }, -- Execute `<Cmd>...<CR>` string
    { 'From step ' }, -- Respect `false` action return as "pass through"
    { 'From step 5 with upvalue' }, -- Execute callable returned from action
  }

  validate_multi_works('<BS>', 'map_multi_bs', ref_lines_state)
end

T['map_multi_bs()']['works with empty steps'] = function()
  map_multi_bs({})
  type_keys('i', 'a', 'b', '<BS>')
  eq(get_lines(), { 'a' })
end

T['map_multi_bs()']['respects `opts`'] = function() validate_multi_opts_usage('<BS>', 'map_multi_bs') end

T['map_multi_bs()']['built-in steps'] = new_set()

T['map_multi_bs()']['built-in steps']['hungry_bs'] = function()
  -- { 'hungry_bs', 'minipairs_bs' } should work for cases like `(  )`
  MiniTest.skip()
end

T['map_multi_bs()']['built-in steps']['minipairs_bs'] = function() MiniTest.skip() end

T['map_multi_bs()']['built-in steps']['nvimautopairs_bs'] = function() MiniTest.skip() end

T['map_multi_bs()']['validates input'] = function() validate_multi_input_validation(map_multi_bs, 'map_multi_bs') end

T['gen_step.search_pattern()'] = new_set()

T['gen_step.search_pattern()']['works'] = function() MiniTest.skip() end

T['gen_step.search_pattern()']['respects `opts.side`'] = function() MiniTest.skip() end

T['map_as_combo()'] = new_set()

T['map_as_combo()']['works'] = function() MiniTest.skip() end

T['map_as_combo()']['detecting combo does not depend on preceding keys'] = function()
  -- Should work when fast typing 'j'-'j'-'k'
  MiniTest.skip()
end

T['map_as_combo()']['works when typing already mapped keys'] = function()
  -- On Neovim>=0.11 for a `jk` LHS. On Neovim<0.11 for a `gjgk` LHS.
  child.cmd('xnoremap j gj')

  MiniTest.skip()
end

T['map_as_combo()']['works with tricky LHS'] = function()
  -- - Should recognise `'<<Tab>>'` as three keys (`<`, `\t`, `>`)
  MiniTest.skip()
end

T['map_as_combo()']['separate combos act independently'] = function()
  -- With `jjk` and `jk` combos, both should act after typing `jjk`
  MiniTest.skip()
end

T['map_as_combo()']['works inside macros'] = function() MiniTest.skip() end

T['map_as_combo()']['respects `opts.delay`'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
return T
