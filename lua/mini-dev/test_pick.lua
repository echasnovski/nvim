local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('pick', config) end
local unload_module = function() child.mini_unload('pick') end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

-- Tweak `expect_screenshot()` to test only on Neovim=0.9 (as it introduced
-- titles and 0.10 introduced footer).
-- Use `child.expect_screenshot_orig()` for original testing.
child.expect_screenshot_orig = child.expect_screenshot
child.expect_screenshot = function(opts, allow_past_09)
  -- TODO: Regenerate all screenshots with 0.10 after its stable release
  if child.fn.has('nvim-0.9') == 0 or child.fn.has('nvim-0.10') == 1 then return end
  child.expect_screenshot_orig(opts)
end

child.has_float_footer = function()
  -- https://github.com/neovim/neovim/pull/24739
  return child.fn.has('nvim-0.10') == 1
end

-- Test paths helpers
local test_dir = 'tests/dir-pick'

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local stop = forward_lua('MiniPick.stop')
local get_picker_items = forward_lua('MiniPick.get_picker_items')
local get_picker_stritems = forward_lua('MiniPick.get_picker_stritems')
local get_picker_matches = forward_lua('MiniPick.get_picker_matches')
local get_picker_state = forward_lua('MiniPick.get_picker_state')
local get_picker_query = forward_lua('MiniPick.get_picker_query')
local is_picker_active = forward_lua('MiniPick.is_picker_active')

-- Use `child.api_notify` to allow user input while child process awaits for
-- `start()` to return a value
local start = function(...) child.lua_notify('MiniPick.start(...)', { ... }) end

local start_with_items = function(items, name) start({ source = { items = items, name = name } }) end

-- Common test helpers
local validate_buf_option =
  function(buf_id, option_name, option_value) eq(child.api.nvim_buf_get_option(buf_id, option_name), option_value) end

local validate_win_option =
  function(win_id, option_name, option_value) eq(child.api.nvim_win_get_option(win_id, option_name), option_value) end

-- Common mocks

-- Data =======================================================================
local test_items = { 'a_b_c', 'abc', 'a_b_b', 'c_a_a', 'b_c_c' }

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()

      -- Make more comfortable screenshots
      child.set_size(15, 40)
      child.o.laststatus = 0
      child.o.ruler = false

      load_module()

      -- Make border differentiable in screenshots
      child.cmd('hi MiniPickBorder ctermfg=2')
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniPick)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniPick'), 1)

  -- Highlight groups
  local validate_hl_group = function(name, ref) expect.match(child.cmd_capture('hi ' .. name), ref) end

  -- - Make sure to clear highlight groups defined for better screenshots
  child.cmd('hi clear MiniPickBorder')
  load_module()

  validate_hl_group('MiniPickBorder', 'links to FloatBorder')
  validate_hl_group('MiniPickBorderBusy', 'links to DiagnosticFloatingWarn')
  validate_hl_group('MiniPickBorderText', 'links to FloatTitle')
  validate_hl_group('MiniPickIconDirectory', 'links to Directory')
  validate_hl_group('MiniPickIconFile', 'links to MiniPickNormal')
  validate_hl_group('MiniPickHeader', 'links to DiagnosticFloatingHint')
  validate_hl_group('MiniPickMatchCurrent', 'links to CursorLine')
  validate_hl_group('MiniPickMatchMarked', 'links to Visual')
  validate_hl_group('MiniPickMatchRanges', 'links to DiagnosticFloatingHint')
  validate_hl_group('MiniPickNormal', 'links to NormalFloat')
  validate_hl_group('MiniPickPreviewLine', 'links to CursorLine')
  validate_hl_group('MiniPickPreviewRegion', 'links to IncSearch')
  validate_hl_group('MiniPickPrompt', 'links to DiagnosticFloatingInfo')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniPick.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniPick.config.' .. field), value) end

  expect_config('delay.async', 10)
  expect_config('delay.busy', 50)

  expect_config('mappings.caret_left', '<Left>')
  expect_config('mappings.caret_right', '<Right>')
  expect_config('mappings.choose', '<CR>')
  expect_config('mappings.choose_in_split', '<C-s>')
  expect_config('mappings.choose_in_tabpage', '<C-t>')
  expect_config('mappings.choose_in_vsplit', '<C-v>')
  expect_config('mappings.choose_marked', '<M-CR>')
  expect_config('mappings.delete_char', '<BS>')
  expect_config('mappings.delete_char_right', '<Del>')
  expect_config('mappings.delete_left', '<C-u>')
  expect_config('mappings.delete_word', '<C-w>')
  expect_config('mappings.mark', '<C-x>')
  expect_config('mappings.mark_all', '<C-a>')
  expect_config('mappings.move_down', '<C-n>')
  expect_config('mappings.move_start', '<C-g>')
  expect_config('mappings.move_up', '<C-p>')
  expect_config('mappings.paste', '<C-r>')
  expect_config('mappings.refine', '<C-Space>')
  expect_config('mappings.scroll_down', '<C-f>')
  expect_config('mappings.scroll_left', '<C-h>')
  expect_config('mappings.scroll_right', '<C-l>')
  expect_config('mappings.scroll_up', '<C-b>')
  expect_config('mappings.stop', '<Esc>')
  expect_config('mappings.toggle_info', '<S-Tab>')
  expect_config('mappings.toggle_preview', '<Tab>')

  expect_config('options.content_direction', 'from_top')
  expect_config('options.use_cache', false)

  expect_config('source.items', vim.NIL)
  expect_config('source.name', vim.NIL)
  expect_config('source.cwd', vim.NIL)
  expect_config('source.match', vim.NIL)
  expect_config('source.show', vim.NIL)
  expect_config('source.preview', vim.NIL)
  expect_config('source.choose', vim.NIL)
  expect_config('source.choose_marked', vim.NIL)

  expect_config('window.config', vim.NIL)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ options = { use_cache = true } })
  eq(child.lua_get('MiniPick.config.options.use_cache'), true)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ delay = 'a' }, 'delay', 'table')
  expect_config_error({ delay = { async = 'a' } }, 'delay.async', 'number')
  expect_config_error({ delay = { busy = 'a' } }, 'delay.busy', 'number')

  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { caret_left = 1 } }, 'mappings.caret_left', 'string')
  expect_config_error({ mappings = { caret_right = 1 } }, 'mappings.caret_right', 'string')
  expect_config_error({ mappings = { choose = 1 } }, 'mappings.choose', 'string')
  expect_config_error({ mappings = { choose_in_split = 1 } }, 'mappings.choose_in_split', 'string')
  expect_config_error({ mappings = { choose_in_tabpage = 1 } }, 'mappings.choose_in_tabpage', 'string')
  expect_config_error({ mappings = { choose_in_vsplit = 1 } }, 'mappings.choose_in_vsplit', 'string')
  expect_config_error({ mappings = { choose_marked = 1 } }, 'mappings.choose_marked', 'string')
  expect_config_error({ mappings = { delete_char = 1 } }, 'mappings.delete_char', 'string')
  expect_config_error({ mappings = { delete_char_right = 1 } }, 'mappings.delete_char_right', 'string')
  expect_config_error({ mappings = { delete_left = 1 } }, 'mappings.delete_left', 'string')
  expect_config_error({ mappings = { delete_word = 1 } }, 'mappings.delete_word', 'string')
  expect_config_error({ mappings = { mark = 1 } }, 'mappings.mark', 'string')
  expect_config_error({ mappings = { mark_all = 1 } }, 'mappings.mark_all', 'string')
  expect_config_error({ mappings = { move_down = 1 } }, 'mappings.move_down', 'string')
  expect_config_error({ mappings = { move_start = 1 } }, 'mappings.move_start', 'string')
  expect_config_error({ mappings = { move_up = 1 } }, 'mappings.move_up', 'string')
  expect_config_error({ mappings = { paste = 1 } }, 'mappings.paste', 'string')
  expect_config_error({ mappings = { refine = 1 } }, 'mappings.refine', 'string')
  expect_config_error({ mappings = { scroll_down = 1 } }, 'mappings.scroll_down', 'string')
  expect_config_error({ mappings = { scroll_left = 1 } }, 'mappings.scroll_left', 'string')
  expect_config_error({ mappings = { scroll_right = 1 } }, 'mappings.scroll_right', 'string')
  expect_config_error({ mappings = { scroll_up = 1 } }, 'mappings.scroll_up', 'string')
  expect_config_error({ mappings = { stop = 1 } }, 'mappings.stop', 'string')
  expect_config_error({ mappings = { toggle_info = 1 } }, 'mappings.toggle_info', 'string')
  expect_config_error({ mappings = { toggle_preview = 1 } }, 'mappings.toggle_preview', 'string')

  expect_config_error({ options = 'a' }, 'options', 'table')
  expect_config_error({ options = { content_direction = 1 } }, 'options.content_direction', 'string')
  expect_config_error({ options = { use_cache = 1 } }, 'options.use_cache', 'boolean')

  expect_config_error({ source = 'a' }, 'source', 'table')
  expect_config_error({ source = { items = 1 } }, 'source.items', 'table')
  expect_config_error({ source = { name = 1 } }, 'source.name', 'string')
  expect_config_error({ source = { cwd = 1 } }, 'source.cwd', 'string')
  expect_config_error({ source = { match = 1 } }, 'source.match', 'function')
  expect_config_error({ source = { show = 1 } }, 'source.show', 'function')
  expect_config_error({ source = { preview = 1 } }, 'source.preview', 'function')
  expect_config_error({ source = { choose = 1 } }, 'source.choose', 'function')
  expect_config_error({ source = { choose_marked = 1 } }, 'source.choose_marked', 'function')

  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { config = 1 } }, 'window.config', 'table or callable')
end

-- This set mostly contains general function testing which doesn't fit into
-- more specialized integration tests later
T['start()'] = new_set()

T['start()']['works'] = function()
  child.lua_notify('_G.picked_item = MiniPick.start(...)', { { source = { items = test_items } } })
  child.expect_screenshot()

  -- Should focus on floating window
  eq(child.api.nvim_get_current_win(), get_picker_state().windows.main)

  -- Should close window after an item and print it (as per `default_choose()`)
  type_keys('<CR>')
  child.expect_screenshot()

  -- Should return picked value
  eq(child.lua_get('_G.picked_item'), test_items[1])
end

T['start()']['works with window footer'] = function()
  -- TODO: Use this as primary test after support for Neovim<=0.9 is dropped
  if not child.has_float_footer() then return end

  child.lua_notify('_G.picked_item = MiniPick.start(...)', { { source = { items = test_items } } })
  child.expect_screenshot_orig()

  eq(child.api.nvim_get_current_win(), get_picker_state().windows.main)
  type_keys('<CR>')
  child.expect_screenshot_orig()
  eq(child.lua_get('_G.picked_item'), test_items[1])
end

T['start()']['can be started without explicit items'] = function()
  child.lua_notify('_G.picked_item = MiniPick.start()')
  child.expect_screenshot()
  type_keys('<CR>')
  eq(child.lua_get('_G.picked_item'), vim.NIL)
end

T['start()']['creates proper window'] = function()
  start_with_items(test_items)
  local win_id = get_picker_state().windows.main
  eq(child.api.nvim_win_is_valid(win_id), true)

  local win_config = child.api.nvim_win_get_config(win_id)
  eq(win_config.relative, 'editor')
  eq(win_config.focusable, true)

  validate_win_option(win_id, 'list', true)
  validate_win_option(win_id, 'listchars', 'extends:…')
  validate_win_option(win_id, 'wrap', false)
end

T['start()']['creates proper main buffer'] = function()
  start_with_items(test_items)
  local buf_id = get_picker_state().buffers.main
  eq(child.api.nvim_buf_is_valid(buf_id), true)
  validate_buf_option(buf_id, 'filetype', 'minipick')
  validate_buf_option(buf_id, 'buflisted', false)
  validate_buf_option(buf_id, 'buftype', 'nofile')
end

T['start()']['tracks lost focus'] = function()
  child.lua_notify([[MiniPick.start({
    source = { items = { 'a', 'b' } },
    mappings = { error = { char = 'e', func = function() error() end } },
  })]])
  child.expect_screenshot()
  type_keys('e')
  -- By default it checks inside a timer with 1 second period
  sleep(1000 + 50)
  child.expect_screenshot()
end

T['start()']['validates `opts`'] = function()
  local validate = function(opts, error_pattern)
    expect.error(function() child.lua('MiniPick.start(...)', { opts }) end, error_pattern)
  end

  validate(1, 'Picker options.*table')

  validate({ delay = { async = 'a' } }, '`delay.async`.*number')
  validate({ delay = { async = 0 } }, '`delay.async`.*positive')
  validate({ delay = { busy = 'a' } }, '`delay.busy`.*number')
  validate({ delay = { busy = 0 } }, '`delay.busy`.*positive')

  validate({ options = { content_direction = 1 } }, '`options%.content_direction`.*one of')
  validate({ options = { use_cache = 1 } }, '`options%.use_cache`.*boolean')

  validate({ mappings = { [1] = '<C-f>' } }, '`mappings`.*only string fields')
  validate({ mappings = { choose = 1 } }, 'Mapping for default action "choose".*string')
  expect.error(
    function() child.lua('MiniPick.start({ mappings = { choose = { char = "a", func = function() end } } })') end,
    'default action.*string'
  )
  validate(
    { mappings = { ['Manual action'] = 1 } },
    'Mapping for manual action "Manual action".*table with `char` and `func`'
  )

  validate({ source = { items = 1 } }, '`source%.items`.*array or callable')
  validate({ source = { cwd = 1 } }, '`source%.cwd`.*valid directory path')
  validate({ source = { cwd = 'not-existing-path' } }, '`source%.cwd`.*valid directory path')
  validate({ source = { match = 1 } }, '`source%.match`.*callable')
  validate({ source = { show = 1 } }, '`source%.show`.*callable')
  validate({ source = { preview = 1 } }, '`source%.preview`.*callable')
  validate({ source = { choose = 1 } }, '`source%.choose`.*callable')
  validate({ source = { choose_marked = 1 } }, '`source%.choose_marked`.*callable')

  validate({ window = { config = 1 } }, '`window%.config`.*table or callable')
end

T['start()']['respects `source.items`'] = function()
  -- Array
  start_with_items({ 'a', 'b' })
  child.expect_screenshot()
  stop()

  -- Callable returning array of items
  child.lua([[_G.items_callable_return = function() return { 'c', 'd' } end]])
  child.lua_notify('MiniPick.start({ source = { items = _G.items_callable_return } })')
  child.expect_screenshot()
  stop()

  -- Callable setting items manually
  child.lua([[_G.items_callable_later = function() MiniPick.set_picker_items({ 'e', 'f' }) end]])
  child.lua_notify('MiniPick.start({ source = { items = _G.items_callable_later } })')
  poke_eventloop()
  child.expect_screenshot()
  stop()

  -- Callable setting items manually *later*
  child.lua([[_G.items_callable_later = function()
    vim.schedule(function() MiniPick.set_picker_items({ 'g', 'h' }) end)
  end]])
  child.lua_notify('MiniPick.start({ source = { items = _G.items_callable_later } })')
  poke_eventloop()
  child.expect_screenshot()
  stop()
end

T['start()']['correctly computes stritems'] = function()
  child.set_size(15, 80)
  child.lua_notify([[MiniPick.start({ source = { items = {
    'string_item',
    { text = 'table_item' },
    { a = 'fallback item', b = 1 },
    function() return 'string_item_from_callable' end,
    function() return { text = 'table_item_from_callable' } end,
    function() return { c = 'fallback item from callable', d = 1 } end,
  } } })]])
  child.expect_screenshot()
end

T['start()']['resolves items after making picker active'] = function()
  child.lua_notify([[MiniPick.start({ source = {
    items = function()
      _G.picker_is_active = MiniPick.is_picker_active()
      _G.picker_name = MiniPick.get_picker_opts().source.name
      return { 'a', 'b' }
    end,
    name = 'This picker'
  } })]])
  eq(get_picker_stritems(), { 'a', 'b' })
  eq(child.lua_get('_G.picker_is_active'), true)
  eq(child.lua_get('_G.picker_name'), 'This picker')
end

T['start()']['respects `source.name`'] = function()
  start({ source = { items = test_items, name = 'Hello' } })
  eq(child.lua_get('MiniPick.get_picker_opts().source.name'), 'Hello')
  if child.has_float_footer() then child.expect_screenshot_orig() end
end

T['start()']['respects `source.cwd`'] = function()
  local lua_cmd = string.format(
    [[MiniPick.start({ source = {
      items = function() return { MiniPick.get_picker_opts().source.cwd } end,
      cwd = %s,
    } })]],
    vim.inspect(test_dir)
  )
  child.lua_notify(lua_cmd)
  eq(get_picker_stritems(), { vim.fn.fnamemodify(test_dir, ':p') })
end

T['start()']['respects `source.match`'] = function()
  child.lua_notify([[MiniPick.start({ source = {
    items = { 'a', 'b', 'c' },
    match = function(...)
      _G.match_args = { ... }
      return { 2 }
    end,
  } })]])

  child.expect_screenshot()
  eq(get_picker_matches().all, { 'b' })
  eq(child.lua_get('_G.match_args'), { { 1, 2, 3 }, { 'a', 'b', 'c' }, {} })

  type_keys('x')
  eq(get_picker_matches().all, { 'b' })
  eq(child.lua_get('_G.match_args'), { { 2 }, { 'a', 'b', 'c' }, { 'x' } })
end

T['start()']['respects `source.show`'] = function()
  child.lua_notify([[MiniPick.start({ source = {
    items = { 'a', { text = 'b' }, 'bb' },
    show = function(items_to_show, buf_id, ...)
      _G.show_args = { items_to_show, buf_id, ... }
      local lines = vim.tbl_map(
        function(x) return '__' .. (type(x) == 'table' and x.text or x) end,
        items_to_show
      )
      vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    end,
  } })]])
  local buf_id = get_picker_state().buffers.main

  child.expect_screenshot()
  eq(child.lua_get('_G.show_args'), { { 'a', { text = 'b' }, 'bb' }, buf_id })

  type_keys('b')
  child.expect_screenshot()
  eq(child.lua_get('_G.show_args'), { { { text = 'b' }, 'bb' }, buf_id })
end

T['start()']['respects `source.preview`'] = function()
  child.lua_notify([[MiniPick.start({ source = {
    items = { 'a', { text = 'b' }, 'bb' },
    preview = function(item, buf_id, ...)
      _G.preview_args = { item, buf_id, ... }
      local stritem = type(item) == 'table' and item.text or item
      vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { 'Preview: ' .. stritem })
    end,
  } })]])
  local validate_preview_args = function(item_ref)
    local preview_args = child.lua_get('_G.preview_args')
    eq(preview_args[1], item_ref)
    eq(child.api.nvim_buf_is_valid(preview_args[2]), true)
  end

  type_keys('<Tab>')

  child.expect_screenshot()
  validate_preview_args('a')
  local preview_buf_id_1 = child.lua_get('_G.preview_args')[2]

  type_keys('<C-n>')
  child.expect_screenshot()
  validate_preview_args({ text = 'b' })
  eq(preview_buf_id_1 ~= child.lua_get('_G.preview_args')[2], true)
end

T['start()']['respects `source.choose`'] = function()
  child.lua_notify([[MiniPick.start({ source = {
    items = { 'a', { text = 'b' }, 'bb' },
    choose = function(...) _G.choose_args = { ... } end,
  } })]])

  type_keys('<C-n>', '<CR>')
  eq(child.lua_get('_G.choose_args'), { { text = 'b' } })
  eq(is_picker_active(), false)
end

T['start()']['respects `source.choose_marked`'] = function()
  child.lua_notify([[MiniPick.start({ source = {
    items = { 'a', { text = 'b' }, 'bb' },
    choose_marked = function(...) _G.choose_marked_args = { ... } end,
  } })]])

  type_keys('<C-x>', '<C-n>', '<C-x>', '<M-CR>')
  eq(child.lua_get('_G.choose_marked_args'), { { 'a', { text = 'b' } } })
  eq(is_picker_active(), false)
end

T['start()']['respects `mappings`'] = function()
  start({ source = { items = { 'a', 'b' } }, mappings = { stop = 'c' } })
  eq(is_picker_active(), true)
  type_keys('a')
  eq(is_picker_active(), true)
  type_keys('c')
  eq(is_picker_active(), false)
end

T['start()']['respects `options.content_direction`'] = function()
  start({ source = { items = { 'a', 'b' } }, options = { content_direction = 'from_bottom' } })
  child.expect_screenshot()
end

T['start()']['respects `options.use_cache`'] = function()
  child.lua('_G.match_n_calls = 0')
  local validate_calls = function(n_calls_ref, match_items_ref)
    eq(child.lua_get('_G.match_n_calls'), n_calls_ref)
    eq(get_picker_matches().all, match_items_ref)
  end

  child.lua_notify([[MiniPick.start({
    source = {
      items = { 'a', 'b', 'bb' },
      match = function(...)
        _G.match_n_calls = _G.match_n_calls + 1
        return MiniPick.default_match(...)
      end,
    },
    options = { use_cache = true },
  })]])
  validate_calls(0, { 'a', 'b', 'bb' })

  type_keys('b')
  validate_calls(1, { 'b', 'bb' })

  type_keys('b')
  validate_calls(2, { 'bb' })

  type_keys('<BS>')
  validate_calls(2, { 'b', 'bb' })

  type_keys('<BS>')
  validate_calls(2, { 'a', 'b', 'bb' })

  type_keys('b')
  validate_calls(2, { 'b', 'bb' })

  type_keys('x')
  validate_calls(3, {})
end

T['start()']['allows manual mappings'] = function()
  child.lua_notify([[MiniPick.start({
      source = { items = { 'a', 'b' } },
      mappings = { manual = { char = 'm', func = function() _G.been_here = true end } },
    })]])
  type_keys('m')
  eq(child.lua_get('_G.been_here'), true)
end

T['start()']['respects `window.config`'] = function()
  -- As table
  start({ source = { items = { 'a', 'b', 'c' } }, window = { config = { border = 'double' } } })
  child.expect_screenshot()
  stop()

  -- As callable
  child.lua_notify([[MiniPick.start({
    source = { items = { 'a', 'b', 'c' } },
    window = { config = function() return { anchor = 'NW', row = 2, width = vim.o.columns } end },
  })]])
  child.expect_screenshot()
  stop()
end

T['start()']['stops currently active picker'] = function()
  start_with_items({ 'a', 'b', 'c' })
  eq(is_picker_active(), true)
  start_with_items({ 'd', 'e', 'f' })
  sleep(2)
  child.expect_screenshot()
end

T['start()']['stops impoperly aborted previous picker'] = function()
  child.lua_notify([[MiniPick.start({
    source = { items = { 'a', 'b', 'c' } },
    mappings = { error = { char = 'e', func = function() error() end } },
  })]])
  child.expect_screenshot()
  type_keys('e')

  start({ source = { items = { 'd', 'e', 'f' } }, window = { config = { width = 10 } } })
  child.expect_screenshot()
end

T['start()']['triggers `MiniPickStart` User event'] = function()
  child.cmd('au User MiniPickStart lua _G.n_user_start = (_G.n_user_start or 0) + 1')
  start_with_items(test_items)
  eq(child.lua_get('_G.n_user_start'), 1)
end

T['start()']['respects global config'] = function()
  child.lua([[MiniPick.config.window.config = { anchor = 'NW', row = 1 }]])
  start_with_items({ 'a', 'b', 'c' })
  child.expect_screenshot()
end

T['start()']['respects `vim.b.minipick_config`'] = function()
  child.lua([[MiniPick.config.window.config = { anchor = 'NW', row = 1 }]])
  child.b.minipick_config = { window = { config = { row = 3, width = 10 } } }
  start_with_items({ 'a', 'b', 'c' })
  child.expect_screenshot()
end

T['stop()'] = new_set()

T['stop()']['works'] = function()
  start_with_items(test_items)
  child.expect_screenshot()
  stop()
  child.expect_screenshot()
  eq(is_picker_active(), false)
end

T['stop()']['can be called without active picker'] = function() expect.no_error(stop) end

T['stop()']['triggers `MiniPickStop` User event'] = function()
  child.cmd('au User MiniPickStop lua _G.n_user_stop = (_G.n_user_stop or 0) + 1')
  start_with_items(test_items)
  stop()
  eq(child.lua_get('_G.n_user_stop'), 1)
end

T['refresh()'] = new_set()

T['refresh()']['works'] = function() MiniTest.skip() end

T['refresh()']['is called on `VimResized`'] = function() MiniTest.skip() end

T['refresh()']['can be called without active picker'] = function() MiniTest.skip() end

T['refresh()']['recomputes window config'] = function() MiniTest.skip() end

T['default_match()'] = new_set()

T['default_match()']['works with active picker'] = function() MiniTest.skip() end

T['default_match()']['does not block query update'] = function()
  -- Basically, it should pokes correctly and stops current match
  -- And respect `delay.async`
  MiniTest.skip()
end

T['default_match()']['works without active picker'] = function() MiniTest.skip() end

T['default_match()']['works with empty query'] = function() MiniTest.skip() end

T['default_match()']['filters items that match query with gaps'] = function() MiniTest.skip() end

T['default_match()']['sorts by match width -> match start -> item index'] = function() MiniTest.skip() end

T['default_match()']['respects special queries'] = function()
  local items = {
    '^abc',
    'xx^axbc',
    "'abc",
    "xx'axbc",
    'abc$',
    'abxc$xx',
    '*abc',
    'xx*axbc',
    'a b c',
  }

  -- All should also test for just inserting special char
  -- Forced fuzzy
  -- Forced exact
  -- Exact start or/and exact end
  -- Grouped fuzzy
  MiniTest.skip()
end

T['default_match()']['works with multibyte characters'] = function()
  -- Both for match and highlight
  MiniTest.skip()
end

T['default_match()']['works with special characters'] = function()
  -- Like `.`, `\`.
  -- Both in exact and fuzzy matches
  MiniTest.skip()
end

T['default_show()'] = new_set()

T['default_show()']['works'] = function() MiniTest.skip() end

T['default_show()']['respects `opts.show_icons`'] = function()
  -- Both with and without 'nvim-web-devicons'
  MiniTest.skip()
end

T['default_show()']['shows icons for only present file system entries'] = function() MiniTest.skip() end

T['default_show()']['handles stritems with present `\n`'] = function() MiniTest.skip() end

T['default_show()']["respects 'ignorecase'/'smartcase'"] = function() MiniTest.skip() end

T['default_show()']['handles query similar to `default_match`'] = function()
  -- Like forced exact and others should be properly highlighted
  MiniTest.skip()
end

T['default_show()']['works with multibyte characters'] = function() MiniTest.skip() end

T['default_show()']['works with non-single-char-entries queries'] = function() MiniTest.skip() end

T['default_preview()'] = new_set()

T['default_preview()']['works'] = function() MiniTest.skip() end

T['default_choose()'] = new_set()

T['default_choose()']['works'] = function() MiniTest.skip() end

T['default_choose_marked()'] = new_set()

T['default_choose_marked()']['works'] = function() MiniTest.skip() end

T['default_choose_marked()']['falls back to choosing first item'] = function()
  -- Can also be called without active picker

  -- Test
  MiniTest.skip()
end

T['ui_select()'] = new_set()

T['ui_select()']['works'] = function() MiniTest.skip() end

T['builtin.files()'] = new_set()

T['builtin.files()']['works'] = function() MiniTest.skip() end

T['builtin.files()']['respects `source.cwd`'] = function() MiniTest.skip() end

T['builtin.grep()'] = new_set()

T['builtin.grep()']['works'] = function() MiniTest.skip() end

T['builtin.grep()']['respects `source.cwd`'] = function() MiniTest.skip() end

T['builtin.grep_live()'] = new_set()

T['builtin.grep_live()']['works'] = function() MiniTest.skip() end

T['builtin.grep_live()']['respects `source.cwd`'] = function() MiniTest.skip() end

T['builtin.help()'] = new_set()

T['builtin.help()']['works'] = function() MiniTest.skip() end

T['builtin.help()']['can be properly aborted'] = function() MiniTest.skip() end

T['builtin.help()']['handles consecutive applications'] = function()
  -- - Works when "Open tag" -> "Open tag in same file".
  MiniTest.skip()
end

T['builtin.buffers()'] = new_set()

T['builtin.buffers()']['works'] = function() MiniTest.skip() end

T['builtin.buffers()']['preview does not trigger buffer events'] = function()
  -- - Preview doesn't trigger `BufEnter` which might interfer with many
  --   plugins (like `setup_auto_root()` from 'mini.misc').
  MiniTest.skip()
end

T['builtin.cli()'] = new_set()

T['builtin.cli()']['works'] = function() MiniTest.skip() end

T['builtin.cli()']['respects `source.cwd`'] = function() MiniTest.skip() end

T['builtin.resume()'] = new_set()

T['builtin.resume()']['works'] = function() MiniTest.skip() end

T['builtin.resume()']['can be called consecutively'] = function() MiniTest.skip() end

T['get_picker_items()'] = new_set()

T['get_picker_items()']['works'] = function() MiniTest.skip() end

T['get_picker_items()']['can be called without active picker'] = function() MiniTest.skip() end

T['get_picker_stritems()'] = new_set()

T['get_picker_stritems()']['works'] = function() MiniTest.skip() end

T['get_picker_stritems()']['can be called without active picker'] = function() MiniTest.skip() end

T['get_picker_matches()'] = new_set()

T['get_picker_matches()']['works'] = function() MiniTest.skip() end

T['get_picker_matches()']['can be called without active picker'] = function() MiniTest.skip() end

T['get_picker_opts()'] = new_set()

T['get_picker_opts()']['works'] = function() MiniTest.skip() end

T['get_picker_opts()']['can be called without active picker'] = function() MiniTest.skip() end

T['get_picker_state()'] = new_set()

T['get_picker_state()']['works'] = function() MiniTest.skip() end

T['get_picker_state()']['can be called without active picker'] = function() MiniTest.skip() end

T['get_picker_query()'] = new_set()

T['get_picker_query()']['works'] = function() MiniTest.skip() end

T['get_picker_query()']['can be called without active picker'] = function() MiniTest.skip() end

T['set_picker_items()'] = new_set()

T['set_picker_items()']['works'] = function() MiniTest.skip() end

T['set_picker_items()']['can be called without active picker'] = function() MiniTest.skip() end

T['set_picker_items_from_cli()'] = new_set()

T['set_picker_items_from_cli()']['works'] = function() MiniTest.skip() end

T['set_picker_items_from_cli()']['can be called without active picker'] = function() MiniTest.skip() end

T['set_picker_match_inds()'] = new_set()

T['set_picker_match_inds()']['works'] = function() MiniTest.skip() end

T['set_picker_match_inds()']['can be called without active picker'] = function() MiniTest.skip() end

T['set_picker_opts()'] = new_set()

T['set_picker_opts()']['works'] = function() MiniTest.skip() end

T['set_picker_opts()']['can be called without active picker'] = function() MiniTest.skip() end

T['set_picker_target_window()'] = new_set()

T['set_picker_target_window()']['works'] = function() MiniTest.skip() end

T['set_picker_target_window()']['can be called without active picker'] = function() MiniTest.skip() end

T['set_picker_query()'] = new_set()

T['set_picker_query()']['works'] = function() MiniTest.skip() end

T['set_picker_query()']['can be called without active picker'] = function() MiniTest.skip() end

T['get_querytick()'] = new_set()

T['get_querytick()']['works'] = function() MiniTest.skip() end

T['is_picker_active()'] = new_set()

T['is_picker_active()']['works'] = function() MiniTest.skip() end

T['poke_is_picker_active()'] = new_set()

T['poke_is_picker_active()']['works'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
T['Overall view'] = new_set()

T['Overall view']['shows prompt'] = function()
  -- Initial
  -- After typical typing
  -- After moving caret, both usual case and with spaces (as it might modify query)
  MiniTest.skip()
end

T['Overall view']['uses footer for extra info'] = function()
  if not child.has_float_footer() then return end

  -- Basic test

  -- Should update after marking

  MiniTest.skip()
end

T['Overall view']['correctly infers footer empty space'] = function()
  if not child.has_float_footer() then return end

  -- Check both `border = 'double'` and `border = <custom_array>`
  MiniTest.skip()
end

T['Overall view']['does not show footer if not items is set'] = function()
  if not child.has_float_footer() then return end

  start()
  child.expect_screenshot_orig()
end

T['Overall view']['respects `options.content_direction` with footer'] = function()
  if not child.has_float_footer() then return end

  start({ source = { items = { 'a', 'b' } }, options = { content_direction = 'from_bottom' } })
  child.expect_screenshot_orig()
end

T['Overall view']['truncates border text'] = function()
  if not child.has_float_footer() then return end

  MiniTest.skip()
end

T['Overall view']['allows "none" as border'] = function() MiniTest.skip() end

T['Overall view']['respects tabline and statusline'] = function() MiniTest.skip() end

T['Overall view']['allows very large dimensions'] = function() MiniTest.skip() end

T['Overall view']['uses dedicated highlight groups'] = function()
  -- MiniPickBorder
  -- MiniPickBorderBusy
  -- MiniPickBorderText
  -- MiniPickNormal
  -- MiniPickPrompt
  MiniTest.skip()
end

T['Main view'] = new_set()

T['Main view']['works'] = function() MiniTest.skip() end

T['Main view']['uses dedicated highlight groups'] = function()
  -- MiniPickIconDirectory
  -- MiniPickIconFile
  -- MiniPickMatchCurrent
  -- MiniPickMatchMarked
  -- MiniPickMatchRanges
  MiniTest.skip()
end

T['Main view']['works with `options.content_direction="from_bottom"`'] = function()
  -- Both with `default_show` and custom `source.show`
  MiniTest.skip()
end

T['Info view'] = new_set()

T['Info view']['works'] = function() MiniTest.skip() end

T['Info view']['uses dedicated highlight groups'] = function()
  -- MiniPickHeader
  MiniTest.skip()
end

T['Info view']['respects manual mappings'] = function() MiniTest.skip() end

T['Info view']['is updated after moving/marking current item'] = function() MiniTest.skip() end

T['Info view']['switches to main after query update'] = function() MiniTest.skip() end

T['Preview'] = new_set()

T['Preview']['works'] = function() MiniTest.skip() end

T['Preview']['uses dedicated highlight groups'] = function()
  -- MiniPickPreviewLine
  -- MiniPickPreviewRegion
  MiniTest.skip()
end

T['Preview']['is updated after moving current item'] = function() MiniTest.skip() end

T['Preview']['switches to main after query update'] = function() MiniTest.skip() end

T['Marking'] = new_set()

T['Marking']['works'] = function() MiniTest.skip() end

T['Matching'] = new_set()

T['Matching']['works'] = function() MiniTest.skip() end

T['Matching']['narrows matched indexes with query progression'] = function() MiniTest.skip() end

T['Matching']['allows returning wider set of match indexes'] = function()
  -- Like if input is `{ 1 }` for 3 items, returning `{ 1, 2 }` should work
  MiniTest.skip()
end

T['Matching']["respects 'ignorecase'"] = function() MiniTest.skip() end

T['Matching']["respects 'smartcase'"] = function() MiniTest.skip() end

T['Key query process'] = new_set()

T['Key query process']['works'] = function() MiniTest.skip() end

T['Key query process']['does not block'] = function()
  -- Allows actions to be executed: from RPC, inside a timer
  MiniTest.skip()
end

T['Key query process']['resets matched indexes after deleting query character'] = function() MiniTest.skip() end

T['Key query process']['respects `delay.async`'] = function() MiniTest.skip() end

T['Key query process']['respects `delay.busy`'] = function() MiniTest.skip() end

T['Key query process']['respects `options.use_cache`'] = function() MiniTest.skip() end

T['Key query process']['works when no items is (yet) set'] = function()
  -- Like in time between `start()` and source calling `set_picker_items()`

  -- Check most of the built-in actions
  MiniTest.skip()
end

T['Key query process']['respects mouse click'] = function()
  -- Inside main window - ignore; outside - stop
  MiniTest.skip()
end

T['Key query process']['handles not configured key presses'] = function()
  -- Like `<M-a>`, `<Shift> + <arrow>`, etc.
  MiniTest.skip()
end

T['Mappings'] = new_set()

T['Mappings']['works with `choose_*`'] = function() MiniTest.skip() end

return T
