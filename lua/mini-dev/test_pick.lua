local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('pick', config) end
local unload_module = function() child.mini_unload('pick') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
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
local real_files_dir = 'tests/dir-pick/real-files'

local join_path = function(...) return table.concat({ ... }, '/') end

local real_file = function(basename) return join_path(real_files_dir, basename) end

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
local set_picker_items = forward_lua('MiniPick.set_picker_items')
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

local validate_buf_name = function(buf_id, name)
  buf_id = buf_id or child.api.nvim_get_current_buf()
  name = name ~= '' and child.fn.fnamemodify(name, ':p') or ''
  name = name:gsub('/+$', '')
  eq(child.api.nvim_buf_get_name(buf_id), name)
end

local validate_no_buf_name = function(buf_id, name)
  buf_id = buf_id or child.api.nvim_get_current_buf()
  name = name ~= '' and child.fn.fnamemodify(name, ':p') or ''
  eq(child.api.nvim_buf_get_name(buf_id) == name, false)
end

local seq_along = function(x)
  local res = {}
  for i = 1, #x do
    res[i] = i
  end
  return res
end

-- Common mocks

-- Data =======================================================================
local test_items = { 'a_b_c', 'abc', 'a_b_b', 'c_a_a', 'b_c_c' }

local many_items = {}
for i = 1, 1000000 do
  many_items[3 * i - 2] = 'ab'
  many_items[3 * i - 1] = 'ac'
  many_items[3 * i] = 'bb'
end

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
    show = function(buf_id, items_to_show, query, ...)
      _G.show_args = { buf_id, items_to_show, query, ... }
      local lines = vim.tbl_map(
        function(x) return '__' .. (type(x) == 'table' and x.text or x) end,
        items_to_show
      )
      vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    end,
  } })]])
  local buf_id = get_picker_state().buffers.main

  child.expect_screenshot()
  eq(child.lua_get('_G.show_args'), { buf_id, { 'a', { text = 'b' }, 'bb' }, {} })

  type_keys('b')
  child.expect_screenshot()
  eq(child.lua_get('_G.show_args'), { buf_id, { { text = 'b' }, 'bb' }, { 'b' } })
end

T['start()']['respects `source.preview`'] = function()
  child.lua_notify([[MiniPick.start({ source = {
    items = { 'a', { text = 'b' }, 'bb' },
    preview = function(buf_id, item, ...)
      _G.preview_args = { buf_id, item, ... }
      local stritem = type(item) == 'table' and item.text or item
      vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { 'Preview: ' .. stritem })
    end,
  } })]])
  local validate_preview_args = function(item_ref)
    local preview_args = child.lua_get('_G.preview_args')
    eq(child.api.nvim_buf_is_valid(preview_args[1]), true)
    eq(preview_args[2], item_ref)
  end

  type_keys('<Tab>')

  child.expect_screenshot()
  validate_preview_args('a')
  local preview_buf_id_1 = child.lua_get('_G.preview_args')[1]

  type_keys('<C-n>')
  child.expect_screenshot()
  validate_preview_args({ text = 'b' })
  eq(preview_buf_id_1 ~= child.lua_get('_G.preview_args')[1], true)
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

local refresh = forward_lua('MiniPick.refresh')

T['refresh()']['works'] = function()
  start_with_items(test_items)
  child.expect_screenshot()

  child.lua('MiniPick.set_picker_opts({ window = { config = { width = 10 } } })')
  refresh()
  child.expect_screenshot()
end

T['refresh()']['is called on `VimResized`'] = function()
  child.set_size(15, 40)
  start_with_items(test_items)
  child.expect_screenshot()

  child.set_size(15, 20)
  child.expect_screenshot()
end

T['refresh()']['can be called without active picker'] = function() expect.no_error(refresh) end

T['refresh()']['recomputes window config'] = function()
  child.lua([[
    _G.width = 0
    _G.win_config = function()
      _G.width = _G.width + 10
      return { width = _G.width }
    end
  ]])

  child.lua_notify([[MiniPick.start({ source = { items = { 'a', 'b', 'c' } }, window = { config = _G.win_config } })]])
  child.expect_screenshot()
  refresh()
  child.expect_screenshot()
end

T['default_match()'] = new_set()

local default_match = forward_lua('MiniPick.default_match')

local validate_match =
  function(stritems, query, output_ref) eq(default_match(seq_along(stritems), stritems, query), output_ref) end

T['default_match()']['works with active picker'] = function()
  start_with_items(test_items)
  type_keys('a')
  child.expect_screenshot()
  type_keys('b')
  child.expect_screenshot()
end

T['default_match()']['does not block query update'] = function()
  child.lua([[
    _G.log = {}
    _G.default_match_wrapper = function(inds, stritems, query)
      table.insert(_G.log, { n_match_inds = #inds, query = vim.deepcopy(query) })
      MiniPick.default_match(inds, stritems, query)
    end
  ]])
  child.lua_notify('MiniPick.start({ source = { match = _G.default_match_wrapper }, delay = { async = 1 } })')

  -- Set many items and wait until it completely sets
  set_picker_items(many_items)
  sleep(1000)

  -- Type three characters very quickly. If `default_match()` were blocking,
  -- each press would lead to calling `source.match` with the result of
  -- matching on prior query. In this test every key press should interrupt
  -- currently active matching and start a new one with the latest available
  -- set of `match_inds` (which should be all inds as match is, hopefully,
  -- never finishes).
  type_keys('a')
  sleep(1)
  type_keys('b')
  sleep(1)
  type_keys('c')
  sleep(1)
  child.expect_screenshot()
  eq(child.lua_get('_G.log'), {
    { n_match_inds = #many_items, query = {} },
    { n_match_inds = #many_items, query = { 'a' } },
    { n_match_inds = #many_items, query = { 'a', 'b' } },
    { n_match_inds = #many_items, query = { 'a', 'b', 'c' } },
  })
end

T['default_match()']['works without active picker'] = function()
  local stritems, query = { 'aab', 'ac', 'ab' }, { 'a', 'b' }
  eq(default_match({ 1, 2, 3 }, stritems, query), { 3, 1 })
  eq(default_match({ 2, 3 }, stritems, query), { 3 })
end

T['default_match()']['works with empty inputs'] = function()
  local match_inds, stritems, query = seq_along(test_items), { 'ab', 'cd' }, { 'a' }
  eq(default_match({}, stritems, query), {})
  eq(default_match({}, {}, query), {})
  eq(default_match(match_inds, stritems, {}), seq_along(stritems))
end

T['default_match()']['filters items that match query with gaps'] = function()
  -- Regular cases
  validate_match({ 'a__', 'b' }, { 'a' }, { 1 })
  validate_match({ '_a_', 'b' }, { 'a' }, { 1 })
  validate_match({ '__a', 'b' }, { 'a' }, { 1 })
  validate_match({ 'b', 'a__' }, { 'a' }, { 2 })
  validate_match({ 'b', '_a_' }, { 'a' }, { 2 })
  validate_match({ 'b', '__a' }, { 'a' }, { 2 })

  validate_match({ 'a', 'ab', 'a_b', 'a_b_b', 'ba' }, { 'a', 'b' }, { 2, 3, 4 })
  validate_match({ 'a', 'ab', 'a_b', 'a_b_b', 'ba' }, { 'a', 'b', 'b' }, { 4 })

  validate_match({ 'a', 'ab', 'axb', 'a?b', 'a\tb' }, { 'a', 'b' }, { 2, 3, 4, 5 })

  -- Non-single-char-entries queries (each should match exactly)
  validate_match({ 'a', 'b', 'ab_', 'a_b', '_ab' }, { 'ab' }, { 3, 5 })
  validate_match({ 'abcd_', '_abcd', 'a_bcd', 'ab_cd', 'abc_d' }, { 'ab', 'cd' }, { 1, 2, 4 })

  -- Edge casees
  validate_match({ 'a', 'b', '' }, { 'a' }, { 1 })

  validate_match({ 'a', 'b', '' }, { '' }, { 1, 2, 3 })
  validate_match({ 'a', 'b', '' }, { '', '' }, { 1, 2, 3 })
end

T['default_match()']['sorts by match width -> match start -> item index'] = function()
  local query_ab, query_abc = { 'a', 'b' }, { 'a', 'b', 'c' }

  -- Width differs
  validate_match({ 'ab', 'a_b', 'a__b' }, query_ab, { 1, 2, 3 })
  validate_match({ 'ab', 'a__b', 'a_b' }, query_ab, { 1, 3, 2 })
  validate_match({ 'a__b', 'ab', 'a_b' }, query_ab, { 2, 3, 1 })
  validate_match({ 'a_b', 'ab', 'a__b' }, query_ab, { 2, 1, 3 })
  validate_match({ 'a_b', 'a__b', 'ab' }, query_ab, { 3, 1, 2 })
  validate_match({ 'a__b', 'a_b', 'ab' }, query_ab, { 3, 2, 1 })

  validate_match({ '_a__b', '_a_b', '_ab' }, query_ab, { 3, 2, 1 })

  validate_match({ 'a__b_a___b', 'a_b_a___b', 'ab_a___b' }, query_ab, { 3, 2, 1 })

  validate_match({ 'a_b_c', 'a_bc', 'abc' }, query_abc, { 3, 2, 1 })
  validate_match({ '_a_b_c', '_a_bc', '_abc' }, query_abc, { 3, 2, 1 })
  validate_match({ 'a_b_c_a__b__c', 'a_bc_a__b__c', 'abc_a__b__c' }, query_abc, { 3, 2, 1 })

  validate_match({ 'ab__cd', 'ab_cd', 'abcd' }, { 'ab', 'cd' }, { 3, 2, 1 })

  -- Start differs with equal width
  validate_match({ 'ab', '_ab', '__ab' }, query_ab, { 1, 2, 3 })
  validate_match({ 'ab', '__ab', '_ab' }, query_ab, { 1, 3, 2 })
  validate_match({ '_ab', 'ab', '__ab' }, query_ab, { 2, 1, 3 })
  validate_match({ '__ab', 'ab', '_ab' }, query_ab, { 2, 3, 1 })
  validate_match({ '_ab', '__ab', 'ab' }, query_ab, { 3, 1, 2 })
  validate_match({ '__ab', '_ab', 'ab' }, query_ab, { 3, 2, 1 })

  validate_match({ '__abc', '_abc', 'abc' }, query_abc, { 3, 2, 1 })

  validate_match({ '__abc_a_b_c', '_abc_a_b_c', 'abc_a_b_c' }, query_abc, { 3, 2, 1 })
  validate_match({ 'a_b_c__abc', 'a_b_c_abc', 'a_b_cabc' }, query_abc, { 3, 2, 1 })

  validate_match({ '__a_b_c', '_a__bc', 'ab__c' }, query_abc, { 3, 2, 1 })

  validate_match({ '__ab_cd_e', '_ab__cde', 'abcd__e' }, { 'ab', 'cd', 'e' }, { 3, 2, 1 })

  -- Index differs with equal width and start
  validate_match({ 'a_b_c', 'a__bc', 'ab__c' }, query_abc, { 1, 2, 3 })
  validate_match({ 'axbxc', 'a??bc', 'ab\t\tc' }, query_abc, { 1, 2, 3 })

  validate_match({ 'ab_cd_e', 'ab__cde', 'abcd__e' }, { 'ab', 'cd', 'e' }, { 1, 2, 3 })
end

T['default_match()']['filters and sorts'] = function()
  validate_match({ 'a_b_c', 'abc', 'a_b_b', 'c_a_a', 'b_c_c' }, { 'a', 'b' }, { 2, 1, 3 })
  validate_match({ 'xabcd', 'axbcd', 'abxcd', 'abcxd', 'abcdx' }, { 'ab', 'cd' }, { 5, 1, 3 })
end

T['default_match()']['respects special queries'] = function()
  --stylua: ignore
  local stritems = {
    '*abc',    -- 1
    '_*_a_bc', -- 2
    "'abc",    -- 3
    "_'_a_bc", -- 4
    '^abc',    -- 5
    '_^_a_bc', -- 6
    'abc$',    -- 7
    'ab_c_$_', -- 8
    'a b c',   -- 9
    ' a  bc',  -- 10
  }
  local all_inds = seq_along(stritems)
  local validate = function(query, output_ref) validate_match(stritems, query, output_ref) end
  local validate_same_as = function(query, query_ref)
    eq(default_match(all_inds, stritems, query), default_match(all_inds, stritems, query_ref))
  end

  -- Precedence:
  -- "forced fuzzy" = "forced exact" > "exact start/end" > "grouped fuzzy"

  -- Forced fuzzy
  validate_same_as({ '*' }, { '' })
  validate_same_as({ '*', 'a' }, { 'a' })
  validate_same_as({ '*', 'a', 'b' }, { 'a', 'b' })

  validate({ '*', '*', 'a' }, { 1, 2 })
  validate({ '*', "'", 'a' }, { 3, 4 })
  validate({ '*', '^', 'a' }, { 5, 6 })
  validate({ '*', 'a', '$' }, { 7, 8 })
  validate({ '*', 'a', ' ', 'b' }, { 9, 10 })

  -- Forced exact
  validate_same_as({ "'" }, { '' })
  validate_same_as({ "'", 'a' }, { 'a' })
  validate_same_as({ "'", 'a', 'b' }, { 'ab' })

  validate({ "'", '*', 'a' }, { 1 })
  validate({ "'", "'", 'a' }, { 3 })
  validate({ "'", '^', 'a' }, { 5 })
  validate({ "'", 'c', '$' }, { 7 })
  validate({ "'", 'a', ' ', 'b' }, { 9 })

  -- Exact start
  validate_same_as({ '^' }, { '' })
  validate({ '^', 'a' }, { 7, 8, 9 })
  validate({ '^', 'a', 'b' }, { 7, 8 })

  validate({ '^', '^', 'a' }, { 5 })
  validate({ '^', "'", 'a' }, { 3 })
  validate({ '^', '*', 'a' }, { 1 })
  validate({ '^', ' ', 'a' }, { 10 })

  -- Exact end
  validate({ '$' }, all_inds)
  validate({ 'c', '$' }, { 1, 3, 5, 9, 10, 2, 4, 6 })
  validate({ 'b', 'c', '$' }, { 1, 3, 5, 10, 2, 4, 6 })

  validate({ ' ', 'c', '$' }, { 9 })

  -- Grouped
  validate_same_as({ 'a', ' ' }, { 'a' })
  validate_same_as({ 'a', ' ', ' ' }, { 'a' })
  validate_same_as({ 'a', ' ', 'b' }, { 'a', 'b' })
  validate_same_as({ 'a', ' ', ' ', 'b' }, { 'a', 'b' })
  validate_same_as({ 'a', ' ', 'b', ' ' }, { 'a', 'b' })
  validate_same_as({ 'a', ' ', 'b', ' ', 'c' }, { 'a', 'b', 'c' })
  validate_same_as({ 'a', ' ', 'b', ' ', ' ', 'c' }, { 'a', 'b', 'c' })
  validate_same_as({ 'a', ' ', 'b', ' ', 'c', ' ' }, { 'a', 'b', 'c' })

  validate({ 'a', 'b', ' ', 'c' }, { 7, 1, 3, 5, 8 })
  validate({ 'a', ' ', 'b', 'c' }, { 7, 1, 3, 5, 2, 4, 6, 10 })
  validate({ 'a', 'b', 'c', ' ' }, { 7, 1, 3, 5 })

  validate({ 'ab', ' ', 'c' }, { 7, 1, 3, 5, 8 })

  -- - Whitespace inside non-whitespace elements shouldn't matter
  validate({ 'a b', ' ', 'c' }, { 9 })

  -- - Amount and type of whitespace inside "split" elements shouldn't matter
  validate_same_as({ 'ab', '  ', 'c' }, { 'ab', ' ', 'c' })
  validate_same_as({ 'ab', '\t', 'c' }, { 'ab', ' ', 'c' })

  -- - Only whitespace is allowed
  validate_same_as({ ' ' }, { '' })
  validate_same_as({ ' ', ' ' }, { '' })

  -- Combination
  validate_same_as({ '^', '$' }, { '' })
  validate({ '^', 'a', ' ', 'b', ' ', 'c', '$' }, { 9 })

  -- Not special
  validate({ 'a', '*' }, {})
  validate({ 'a', "'" }, {})
  validate({ 'a', '^' }, {})
  validate({ '$', 'a' }, {})
end

T['default_match()']['only input indexes can be in the output'] = function()
  eq(default_match({ 1, 2, 4 }, { 'a', '_a', '__a', 'b' }, { 'a' }), { 1, 2 })

  -- Special modes
  eq(default_match({ 1, 2, 4 }, { 'a', '_a', '__a', 'b' }, { "'", 'a' }), { 1, 2 })
  eq(default_match({ 1, 2, 4 }, { 'a', '_a', '__a', 'b' }, { '*', 'a' }), { 1, 2 })
  eq(default_match({ 1, 2, 4 }, { 'a', 'a_', 'a__', 'b' }, { '^', 'a' }), { 1, 2 })
  eq(default_match({ 1, 2, 4 }, { 'a', '_a', '__a', 'b' }, { 'a', '$' }), { 1, 2 })

  eq(default_match({ 1, 2, 4 }, { 'abc', 'ab_c', 'ab__c', 'a_b_c' }, { 'a', 'b', ' ', 'c' }), { 1, 2 })
end

T['default_match()']['works with multibyte characters'] = function()
  -- In query
  validate_match({ 'ы', 'ф', 'd' }, { 'ы' }, { 1 })

  validate_match({ 'ы__ф', 'ы_ф', 'ыф', 'ы', 'фы' }, { 'ы', 'ф' }, { 3, 2, 1 })
  validate_match({ '__ыф', '_ыф', 'ыф' }, { 'ы', 'ф' }, { 3, 2, 1 })
  validate_match({ '__ы_ф_я', '__ы__фя', '__ыф__я' }, { 'ы', 'ф', 'я' }, { 1, 2, 3 })

  validate_match({ 'ы_ф', '_ыф', 'ы' }, { '*', 'ы', 'ф' }, { 2, 1 })
  validate_match({ 'ы_ф', '_ыф', 'ы' }, { "'", 'ы', 'ф' }, { 2 })
  validate_match({ 'ы_ф', '_ыф', 'ы' }, { '^', 'ы' }, { 1, 3 })
  validate_match({ 'ы_ф', '_ыф', 'ы' }, { 'ф', '$' }, { 1, 2 })
  validate_match({ 'ыы_ф', 'ы_ыф' }, { 'ы', 'ы', ' ', 'ф' }, { 1 })

  validate_match({ '_│_│', '│_│_', '_│_' }, { '│', '│' }, { 2, 1 })

  validate_match({ 'ыdф', '_ы_d_ф' }, { 'ы', 'd', 'ф' }, { 1, 2 })

  -- In stritems
  validate_match({ 'aыbыc', 'abыc' }, { 'a', 'b', 'c' }, { 2, 1 })
end

T['default_match()']['works with special characters'] = function()
  -- function() validate_match('(.+*%-)', 'a(a.a+a*a%a-a)', { 2, 4, 6, 8, 10, 12, 14 }) end
  local validate_match_special_char = function(char)
    local stritems = { 'a' .. char .. 'b', 'a_b' }
    validate_match(stritems, { char }, { 1 })
    validate_match(stritems, { 'a', char, 'b' }, { 1 })
  end

  validate_match_special_char('.')
  validate_match_special_char('+')
  validate_match_special_char('%')
  validate_match_special_char('-')
  validate_match_special_char('(')
  validate_match_special_char(')')

  validate_match({ 'a*b', 'a_b' }, { 'a', '*', 'b' }, { 1 })
  validate_match({ 'a^b', 'a_b' }, { 'a', '^', 'b' }, { 1 })
  validate_match({ 'a$b', 'a_b' }, { 'a', '$', 'b' }, { 1 })
end

T['default_match()']['respects case'] = function()
  -- Ignore and smart case should come from how picker uses `source.match`
  validate_match({ 'ab', 'aB', 'Ba', 'AB' }, { 'a', 'b' }, { 1 })
  validate_match({ 'ab', 'aB', 'Ba', 'AB' }, { 'a', 'B' }, { 2 })
end

T['default_show()'] = new_set({ hooks = { pre_case = function() child.set_size(10, 20) end } })

local default_show = forward_lua('MiniPick.default_show')

T['default_show()']['works'] = function()
  child.set_size(15, 40)
  start_with_items({ 'abc', 'a_bc', 'a__bc' })
  type_keys('a', 'b')
  child.expect_screenshot()
end

T['default_show()']['works without active picker'] = function()
  -- Allows 0 buffer id for current buffer
  default_show(0, { 'abc', 'a_bc', 'a__bc' }, { 'a', 'b' })
  child.expect_screenshot()

  -- Allows non-current buffer
  local new_buf_id = child.api.nvim_create_buf(false, true)
  default_show(new_buf_id, { 'def', 'd_ef', 'd__ef' }, { 'd', 'e' })
  child.api.nvim_set_current_buf(new_buf_id)
  child.expect_screenshot()
end

T['default_show()']['shows best match'] = function()
  default_show(0, { 'a__b_a__b_ab', 'a__b_ab_a__b', 'ab_a__b_a__b', 'ab__ab' }, { 'a', 'b' })
  child.expect_screenshot()

  default_show(0, { 'aabbccddee' }, { 'a', 'b', 'c', 'd', 'e' })
  child.expect_screenshot()
end

T['default_show()']['respects `opts.show_icons`'] = function()
  child.set_size(10, 45)
  local items = vim.tbl_map(real_file, vim.fn.readdir(real_files_dir))
  table.insert(items, test_dir)
  table.insert(items, 'non-existing')
  table.insert(items, { text = 'non-string' })
  local query = { 'i', 'i' }

  -- Without 'nvim-web-devicons'
  default_show(0, items, query, { show_icons = true })
  child.expect_screenshot()

  -- With 'nvim-web-devicons'
  child.cmd('set rtp+=tests/dir-pick')
  default_show(0, items, query, { show_icons = true })
  child.expect_screenshot()
end

T['default_show()']['handles stritems with non-trivial whitespace'] = function()
  child.o.tabstop = 3
  default_show(0, { 'With\nnewline', 'With\ttab' }, {})
  child.expect_screenshot()
end

T['default_show()']["respects 'ignorecase'/'smartcase'"] = function()
  child.set_size(7, 12)
  local items = { 'a_b', 'a_B', 'A_b', 'A_B' }

  local validate = function()
    default_show(0, items, { 'a', 'b' })
    child.expect_screenshot()
    default_show(0, items, { 'a', 'B' })
    child.expect_screenshot()
  end

  -- Respect case
  child.o.ignorecase, child.o.smartcase = false, false
  validate()

  -- Ignore case
  child.o.ignorecase, child.o.smartcase = true, false
  validate()

  -- Smart case
  child.o.ignorecase, child.o.smartcase = true, true
  validate()
end

T['default_show()']['handles query similar to `default_match`'] = function()
  child.set_size(15, 15)
  local items = { 'abc', '_abc', 'a_bc', 'ab_c', 'abc_', '*abc', "'abc", '^abc', 'abc$', 'a b c' }

  local validate = function(query)
    default_show(0, items, query)
    child.expect_screenshot()
  end

  validate({ '*', 'a', 'b' })
  validate({ "'", 'a', 'b' })
  validate({ '^', 'a', 'b' })
  validate({ 'b', 'c', '$' })
  validate({ 'a', 'b', ' ', 'c' })
end

T['default_show()']['works with multibyte characters'] = function()
  local items = { 'ыdф', 'ыы_d_ф', '_ыы_d_ф' }

  -- In query
  default_show(0, items, { 'ы', 'ф' })
  child.expect_screenshot()

  -- Not in query
  default_show(0, items, { 'd' })
  child.expect_screenshot()
end

T['default_show()']['works with non-single-char-entries queries'] = function()
  local items = { '_abc', 'a_bc', 'ab_c', 'abc_' }
  local validate = function(query)
    default_show(0, items, query)
    child.expect_screenshot()
  end

  validate({ 'ab', 'c' })
  validate({ 'abc' })
  validate({ 'a b', ' ', 'c' })
end

T['default_preview()'] = new_set()

local default_preview = forward_lua('MiniPick.default_preview')

local validate_preview = function(items)
  start_with_items(items)
  type_keys('<Tab>')
  child.expect_screenshot()

  for _ = 1, (#items - 1) do
    type_keys('<C-n>')
    child.expect_screenshot()
  end
end

T['default_preview()']['works'] = function() validate_preview({ real_file('b.txt') }) end

T['default_preview()']['works without active picker'] = function()
  -- Allows 0 buffer id for current buffer
  default_preview(0, real_file('b.txt'))
  child.expect_screenshot()

  -- Allows non-current buffer
  local new_buf_id = child.api.nvim_create_buf(false, true)
  default_preview(new_buf_id, real_file('LICENSE'))
  child.api.nvim_set_current_buf(new_buf_id)
  child.expect_screenshot()
end

T['default_preview()']['works for file path'] = function()
  local items = {
    -- Item as string
    real_file('b.txt'),

    -- Item as table with `path` field
    { text = real_file('LICENSE'), path = real_file('LICENSE') },

    -- Non-text file
    real_file('c.gif'),
  }
  validate_preview(items)
end

T['default_preview()']['shows line in file path'] = function()
  local path = real_file('b.txt')
  local items = {
    path .. ':3',
    { text = path .. ':line-in-path', path = path .. ':6' },
    { text = path .. ':line-separate', path = path, lnum = 8 },
  }
  validate_preview(items)
end

T['default_preview()']['shows position in file path'] = function()
  local path = real_file('b.txt')
  local items = {
    path .. ':3:4',
    { text = path .. ':pos-in-path', path = path .. ':6:2' },
    { text = path .. ':pos-separate', path = path, lnum = 8, col = 3 },
  }
  validate_preview(items)
end

T['default_preview()']['shows range in file path'] = function()
  local path = real_file('b.txt')
  local items = {
    { text = path .. ':range-oneline', path = path, lnum = 8, col = 3, end_lnum = 8, end_col = 5 },
    { text = path .. ':range-manylines', path = path, lnum = 9, col = 3, end_lnum = 11, end_col = 4 },
  }
  validate_preview(items)
end

T['default_preview()']['has syntax highlighting in file path'] = function()
  local items = {
    -- With tree-sitter
    real_file('a.lua'),

    -- With built-in syntax
    real_file('Makefile'),
  }
  validate_preview(items)
end

T['default_preview()']['loads context in file path'] = function()
  start_with_items({ real_file('b.txt') })
  type_keys('<Tab>')
  child.expect_screenshot()
  type_keys('<C-f>')
  child.expect_screenshot()
  type_keys('<C-f>')
  child.expect_screenshot()
end

T['default_preview()']['works for directory path'] =
  function() validate_preview({ test_dir, { text = real_files_dir, path = real_files_dir } }) end

T['default_preview()']['works for buffer'] = function()
  local buf_id_1 = child.api.nvim_create_buf(false, false)
  local buf_id_2 = child.api.nvim_create_buf(true, false)
  local buf_id_3 = child.api.nvim_create_buf(false, true)
  local buf_id_4 = child.api.nvim_create_buf(true, true)

  child.api.nvim_buf_set_lines(buf_id_1, 0, -1, false, { 'This is buffer #1' })
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { 'This is buffer #2' })
  child.api.nvim_buf_set_lines(buf_id_3, 0, -1, false, { 'This is buffer #3' })
  child.api.nvim_buf_set_lines(buf_id_4, 0, -1, false, { 'This is buffer #4' })

  local items = {
    -- As string convertible to number
    tostring(buf_id_1),

    -- As table with `bufnr` field
    { text = 'Buffer #2', bufnr = buf_id_2 },

    -- As table with `buf_id` field
    { text = 'Buffer #3', buf_id = buf_id_3 },

    -- As table with `buf` field
    { text = 'Buffer #4', buf = buf_id_4 },
  }
  validate_preview(items)
end

local mock_buffer = function()
  local buf_id = child.api.nvim_create_buf(true, false)
  local lines = {}
  for i = 1, 20 do
    table.insert(lines, string.format('Line %d in buffer %d', i, buf_id))
  end
  child.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  return buf_id
end

T['default_preview()']['shows line in buffer'] = function()
  local buf_id = mock_buffer()
  validate_preview({ { text = 'Line in buffer', bufnr = buf_id, lnum = 4 } })
end

T['default_preview()']['shows position in buffer'] = function()
  local buf_id = mock_buffer()
  validate_preview({ { text = 'Position in buffer', bufnr = buf_id, lnum = 6, col = 3 } })
end

T['default_preview()']['shows range in buffer'] = function()
  local buf_id = mock_buffer()
  local items = {
    { text = 'Oneline range in buffer', bufnr = buf_id, lnum = 8, col = 3, end_lnum = 8, end_col = 6 },
    { text = 'Manylines range in buffer', bufnr = buf_id, lnum = 10, col = 3, end_lnum = 12, end_col = 4 },
  }
  validate_preview(items)
end

T['default_preview()']['has syntax highlighting in buffer'] = function()
  child.cmd('edit ' .. real_file('a.lua'))
  local buf_id_lua = child.api.nvim_get_current_buf()
  child.cmd('edit ' .. real_file('Makefile'))
  local buf_id_makefile = child.api.nvim_get_current_buf()
  child.cmd('enew')

  local items = {
    { text = 'Tree-sitter highlighting', bufnr = buf_id_lua },
    { text = 'Built-in syntax', bufnr = buf_id_makefile },
  }
  validate_preview(items)
end

T['default_preview()']['loads context in buffer'] = function()
  child.cmd('edit ' .. real_file('b.txt'))
  local buf_id = child.api.nvim_get_current_buf()
  child.cmd('enew')

  start_with_items({ { text = 'Buffer', bufnr = buf_id } })
  type_keys('<Tab>')
  child.expect_screenshot()
  type_keys('<C-f>')
  child.expect_screenshot()
  type_keys('<C-f>')
  child.expect_screenshot()
end

T['default_preview()']['has fallback'] = function()
  child.set_size(10, 40)
  validate_preview({ -1, { text = 'Random table' } })
end

T['default_preview()']['respects `opts.n_context_lines`'] = function()
  child.lua([[MiniPick.config.source.preview = function(buf_id, item)
    return MiniPick.default_preview(buf_id, item, { n_context_lines = 2 })
  end]])
  local path = real_file('b.txt')
  child.cmd('edit ' .. path)
  local buf_id = child.api.nvim_get_current_buf()
  child.cmd('enew')

  local items = {
    -- File line
    path .. ':4',

    -- Buffer line
    { text = 'Buffer', bufnr = buf_id, lnum = 7 },
  }
  validate_preview(items)
end

T['default_preview()']['respects `opts.line_position`'] = new_set({
  parametrize = { { 'top' }, { 'center' }, { 'bottom' } },
}, {
  function(line_position)
    child.lua('_G.line_position = ' .. vim.inspect(line_position))
    child.lua([[MiniPick.config.source.preview = function(buf_id, item)
        return MiniPick.default_preview(buf_id, item, { line_position = _G.line_position })
      end]])
    local path = real_file('b.txt')
    child.cmd('edit ' .. path)
    local buf_id = child.api.nvim_get_current_buf()
    child.cmd('enew')

    local items = {
      -- File line
      path .. ':10',

      -- Buffer line
      { text = 'Buffer', bufnr = buf_id, lnum = 12 },
    }
    validate_preview(items)
  end,
})

T['default_choose()'] = new_set()

local default_choose = forward_lua('MiniPick.default_choose')

local choose_item = function(item)
  start_with_items({ item })
  type_keys('<CR>')
  eq(is_picker_active(), false)
end

T['default_choose()']['works'] = function()
  local path = real_file('b.txt')
  choose_item(path)
  validate_buf_name(0, path)
end

T['default_choose()']['respects picker target window'] = function()
  child.cmd('botright wincmd v')
  local buf_id_1 = child.api.nvim_create_buf(false, true)
  local win_id_1 = child.api.nvim_get_current_win()
  child.api.nvim_win_set_buf(win_id_1, buf_id_1)
  child.cmd('wincmd h')
  local buf_id_2 = child.api.nvim_create_buf(false, true)
  local win_id_2 = child.api.nvim_get_current_win()
  child.api.nvim_win_set_buf(win_id_2, buf_id_2)

  child.api.nvim_set_current_win(win_id_1)
  local path = real_file('b.txt')
  start_with_items({ path })
  child.lua(string.format('MiniPick.set_picker_target_window(%d)', win_id_2))
  type_keys('<CR>')

  eq(child.api.nvim_win_get_buf(win_id_1), buf_id_1)
  validate_buf_name(buf_id_1, '')
  eq(child.api.nvim_win_get_buf(win_id_2), buf_id_2)
  validate_buf_name(buf_id_2, path)
end

T['default_choose()']['works without active picker'] = function()
  child.cmd('botright wincmd v')
  local win_id_1 = child.api.nvim_get_current_win()
  child.cmd('wincmd h')
  local win_id_2 = child.api.nvim_get_current_win()

  child.api.nvim_set_current_win(win_id_1)
  local path = real_file('b.txt')
  default_choose(path)

  -- Should use current window as target
  validate_buf_name(child.api.nvim_win_get_buf(win_id_1), path)
  validate_buf_name(child.api.nvim_win_get_buf(win_id_2), '')
end

T['default_choose()']['works for file path'] = function()
  local validate = function(item, path, pos)
    local win_id = child.api.nvim_get_current_win()
    default_choose(item)

    local buf_id = child.api.nvim_win_get_buf(win_id)
    validate_buf_name(buf_id, path)
    if pos ~= nil then eq(child.api.nvim_win_get_cursor(win_id), pos) end

    -- Cleanup
    child.api.nvim_buf_delete(buf_id, { force = true })
  end

  local path = real_file('b.txt')

  -- Path
  validate(path, path, { 1, 0 })
  validate({ text = path, path = path }, path, { 1, 0 })

  -- Path with line
  validate(path .. ':4', path, { 4, 0 })
  validate({ text = path, path = path, lnum = 6 }, path, { 6, 0 })

  -- Path with position
  validate(path .. ':8:2', path, { 8, 1 })
  validate({ text = path, path = path, lnum = 10, col = 4 }, path, { 10, 3 })

  -- Path with range
  validate({ text = path, path = path, lnum = 12, col = 5, end_lnum = 14, end_col = 3 }, path, { 12, 4 })
end

T['default_choose()']['reuses opened buffer for file path'] = function()
  local path = real_file('b.txt')
  child.cmd('edit ' .. path)
  local buf_id_path = child.api.nvim_get_current_buf()
  validate_buf_name(buf_id_path, path)
  set_cursor(5, 3)

  local buf_id_alt = child.api.nvim_create_buf(true, false)

  local validate = function(pos)
    eq(child.api.nvim_win_get_buf(0), buf_id_path)
    validate_buf_name(buf_id_path, path)
    eq(child.api.nvim_win_get_cursor(0), pos)
  end

  -- Reuses without setting cursor
  child.api.nvim_set_current_buf(buf_id_alt)
  default_choose(path)
  validate({ 5, 3 })

  -- Reuses with setting cursor
  child.api.nvim_set_current_buf(buf_id_alt)
  default_choose(path .. ':7:2')
  validate({ 7, 1 })
end

T['default_choose()']['works for directory path'] = function()
  local validate = function(item, path)
    local buf_id_init = child.api.nvim_get_current_buf()
    default_choose(item)

    local buf_id_cur = child.api.nvim_get_current_buf()
    eq(child.bo.filetype, 'netrw')
    validate_buf_name(buf_id_init, path)

    -- Cleanup
    child.api.nvim_buf_delete(buf_id_init, { force = true })
    child.api.nvim_buf_delete(buf_id_cur, { force = true })
  end

  validate(test_dir, test_dir)
  validate({ text = test_dir, path = test_dir }, test_dir)
end

T['default_choose()']['works for buffer'] = function()
  local buf_id_tmp = child.api.nvim_create_buf(false, true)

  local setup_buffer = function(pos)
    local buf_id = child.api.nvim_create_buf(true, false)
    child.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.fn['repeat']({ 'aaaaaaaaaaaaaaaaaaaa' }, 20))

    local cur_buf = child.api.nvim_win_get_buf(0)
    child.api.nvim_set_current_buf(buf_id)
    child.api.nvim_win_set_cursor(0, pos)
    child.api.nvim_win_set_buf(0, cur_buf)

    return buf_id
  end

  local validate = function(item, buf_id, pos)
    local win_id = child.api.nvim_get_current_win()
    child.api.nvim_win_set_buf(0, buf_id_tmp)

    default_choose(item)

    eq(child.api.nvim_win_get_buf(win_id), buf_id)
    if pos ~= nil then eq(child.api.nvim_win_get_cursor(win_id), pos) end

    -- Cleanup
    child.api.nvim_buf_delete(buf_id, { force = true })
  end

  local buf_id

  -- Buffer without position should reuse current cursor
  buf_id = setup_buffer({ 1, 1 })
  validate(buf_id, buf_id, { 1, 1 })

  buf_id = setup_buffer({ 2, 2 })
  validate(tostring(buf_id), buf_id, { 2, 2 })

  -- Buffer in table
  buf_id = setup_buffer({ 3, 3 })
  validate({ text = 'buffer', bufnr = buf_id }, buf_id, { 3, 3 })

  buf_id = setup_buffer({ 4, 4 })
  validate({ text = 'buffer', buf_id = buf_id }, buf_id, { 4, 4 })

  buf_id = setup_buffer({ 5, 5 })
  validate({ text = 'buffer', buf = buf_id }, buf_id, { 5, 5 })

  -- Buffer with line
  buf_id = setup_buffer({ 6, 6 })
  validate({ text = 'buffer', bufnr = buf_id, lnum = 7 }, buf_id, { 7, 0 })

  -- Buffer with position
  buf_id = setup_buffer({ 6, 6 })
  validate({ text = 'buffer', bufnr = buf_id, lnum = 8, col = 8 }, buf_id, { 8, 7 })

  -- Buffer with range
  buf_id = setup_buffer({ 6, 6 })
  validate({ text = 'buffer', bufnr = buf_id, lnum = 9, col = 9, end_lnum = 10, end_col = 8 }, buf_id, { 9, 8 })

  -- Already shown buffer
  local setup_current_buf = function(pos)
    child.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn['repeat']({ 'aaaaaaaaaaaaaaaaaaaa' }, 20))
    child.api.nvim_win_set_cursor(0, pos)
    return child.api.nvim_get_current_buf()
  end

  buf_id = setup_current_buf({ 11, 11 })
  validate(buf_id, buf_id, { 11, 11 })

  buf_id = setup_current_buf({ 12, 12 })
  validate({ text = 'buffer', bufnr = buf_id, lnum = 13 }, buf_id, { 13, 0 })

  buf_id = setup_current_buf({ 12, 12 })
  validate({ text = 'buffer', bufnr = buf_id, lnum = 14, col = 14 }, buf_id, { 14, 13 })

  buf_id = setup_current_buf({ 12, 12 })
  validate({ text = 'buffer', bufnr = buf_id, lnum = 15, col = 15, end_lnum = 16, end_col = 14 }, buf_id, { 15, 14 })
end

T['default_choose()']['ensures valid target window'] = function()
  local choose_with_bad_target_window = function(item)
    child.cmd('botright wincmd v')
    local win_id = child.api.nvim_get_current_win()

    start_with_items({ item })
    local lua_cmd = string.format([[vim.api.nvim_win_call(%d, function() vim.cmd('close') end)]], win_id)
    child.lua(lua_cmd)

    type_keys('<CR>')
  end

  -- Path
  local path = real_file('b.txt')
  choose_with_bad_target_window(path)
  validate_buf_name(child.api.nvim_get_current_buf(), path)

  -- Buffer
  local buf_id = child.api.nvim_create_buf(true, false)
  choose_with_bad_target_window({ text = 'buffer', bufnr = buf_id })
  eq(child.api.nvim_get_current_buf(), buf_id)
end

T['default_choose()']['centers cursor'] = function()
  local validate = function(item, ref_topline)
    choose_item(item)
    eq(child.fn.line('w0'), ref_topline)
  end

  -- Path
  local path = real_file('b.txt')
  validate({ text = path, path = path, lnum = 10 }, 4)

  -- Buffer
  local buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.fn['repeat']({ 'aaaaaaaaaa' }, 100))
  validate({ text = 'buffer', bufnr = buf_id, lnum = 12 }, 6)
end

T['default_choose()']['opens just enough folds'] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn['repeat']({ 'aaaaaaaaaa' }, 100))
  child.cmd('2,3fold')
  child.cmd('12,13fold')

  eq(child.fn.foldclosed(2), 2)
  eq(child.fn.foldclosed(3), 2)
  eq(child.fn.foldclosed(12), 12)
  eq(child.fn.foldclosed(13), 12)

  default_choose({ text = 'buffer', bufnr = child.api.nvim_get_current_buf(), lnum = 12 })

  eq(child.fn.foldclosed(2), 2)
  eq(child.fn.foldclosed(3), 2)
  eq(child.fn.foldclosed(12), -1)
  eq(child.fn.foldclosed(13), -1)
end

T['default_choose()']['has print fallback'] = function()
  choose_item({ text = 'regular-table' })
  eq(child.cmd_capture('messages'), '\n{\n  text = "regular-table"\n}')
end

T['default_choose()']['does nothing for `nil` input'] = function()
  expect.no_error(function() default_choose() end)
  eq(child.cmd_capture('messages'), '')
end

T['default_choose_marked()'] = new_set()

local default_choose_marked = forward_lua('MiniPick.default_choose_marked')

local validate_qfitem = function(input, ref)
  local eq_if_nonnil = function(x, y)
    if y ~= nil then eq(x, y) end
  end

  eq_if_nonnil(input.bufnr, ref.bufnr)
  if ref.filename ~= nil then validate_buf_name(input.bufnr, ref.filename) end
  eq_if_nonnil(input.lnum, ref.lnum)
  eq_if_nonnil(input.col, ref.col)
  eq_if_nonnil(input.end_lnum, ref.end_lnum)
  eq_if_nonnil(input.end_col, ref.end_col)
  eq_if_nonnil(input.text, ref.text)
end

T['default_choose_marked()']['works'] = function()
  local path = real_file('b.txt')
  start_with_items({ path })
  type_keys('<C-x>', '<M-CR>')
  eq(is_picker_active(), false)

  -- Should create and open quickfix list
  eq(#child.api.nvim_list_wins(), 2)
  eq(child.bo.filetype, 'qf')

  local qflist = child.fn.getqflist()
  eq(#qflist, 1)
  validate_qfitem(qflist[1], { filename = path, lnum = 1, col = 1, end_lnum = 0, end_col = 0, text = '' })
end

T['default_choose_marked()']['creates proper title'] = function()
  local validate = function(keys, title)
    local path = real_file('b.txt')
    start_with_items({ path }, 'Picker name')
    type_keys(keys, '<C-x>', '<M-CR>')
    eq(is_picker_active(), false)
    eq(child.fn.getqflist({ title = true }).title, title)
  end

  validate({}, 'Picker name')
  validate({ 'b', '.', 't' }, 'Picker name : b.t')
end

T['default_choose_marked()']['sets as last list'] = function()
  local path = real_file('b.txt')
  child.fn.setqflist({}, ' ', { items = { { filename = path, lnum = 2, col = 2 } }, nr = '$' })
  child.fn.setqflist({}, ' ', { items = { { filename = path, lnum = 3, col = 3 } }, nr = '$' })
  child.cmd('colder')

  start_with_items({ path })
  type_keys('<C-x>', '<M-CR>')
  local list_data = child.fn.getqflist({ all = true })
  validate_qfitem(list_data.items[1], { filename = path, lnum = 1, col = 1 })
  eq(list_data.nr, 3)
end

T['default_choose_marked()']['works without active picker'] = function()
  local path_1, path_2 = real_file('b.txt'), real_file('LICENSE')
  default_choose_marked({ path_1, path_2 })

  eq(#child.api.nvim_list_wins(), 2)
  eq(child.bo.filetype, 'qf')

  local list_data = child.fn.getqflist({ all = true })
  eq(#list_data.items, 2)
  validate_qfitem(list_data.items[1], { filename = path_1, lnum = 1, col = 1, end_lnum = 0, end_col = 0, text = '' })
  validate_qfitem(list_data.items[2], { filename = path_2, lnum = 1, col = 1, end_lnum = 0, end_col = 0, text = '' })

  eq(list_data.title, '<No picker>')
end

T['default_choose_marked()']['creates quickfix list from file/buffer positions'] = function()
  local path = real_file('b.txt')
  local buf_id = child.api.nvim_create_buf(true, false)
  local buf_id_scratch = child.api.nvim_create_buf(false, true)

  local items = {
    -- File path
    path,

    { text = 'filepath', path = path },

    path .. ':3',
    { text = path, path = path, lnum = 4 },

    path .. ':5:5',
    path .. ':6:6:' .. 'extra text',
    { text = path, path = path, lnum = 7, col = 7 },

    { text = path, path = path, lnum = 8, col = 8, end_lnum = 9, end_col = 9 },
    { text = path, path = path, lnum = 8, col = 9, end_lnum = 9 },

    -- Buffer
    buf_id,
    tostring(buf_id),
    { text = 'buffer', bufnr = buf_id },

    buf_id_scratch,

    { text = 'buffer', bufnr = buf_id, lnum = 5 },

    { text = 'buffer', bufnr = buf_id, lnum = 6, col = 6 },

    { text = 'buffer', bufnr = buf_id, lnum = 7, col = 7, end_lnum = 8, end_col = 8 },
    { text = 'buffer', bufnr = buf_id, lnum = 7, col = 8, end_lnum = 8 },
  }

  start_with_items(items)
  type_keys('<C-a>', '<M-CR>')
  local qflist = child.fn.getqflist()
  eq(#qflist, #items)

  validate_qfitem(qflist[1], { filename = path, lnum = 1, col = 1, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[2], { filename = path, lnum = 1, col = 1, end_lnum = 0, end_col = 0, text = 'filepath' })
  validate_qfitem(qflist[3], { filename = path, lnum = 3, col = 1, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[4], { filename = path, lnum = 4, col = 1, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[5], { filename = path, lnum = 5, col = 5, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[6], { filename = path, lnum = 6, col = 6, end_lnum = 0, end_col = 0, text = 'extra text' })
  validate_qfitem(qflist[7], { filename = path, lnum = 7, col = 7, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[8], { filename = path, lnum = 8, col = 8, end_lnum = 9, end_col = 9 })
  validate_qfitem(qflist[9], { filename = path, lnum = 8, col = 9, end_lnum = 9, end_col = 0 })

  validate_qfitem(qflist[10], { bufnr = buf_id, lnum = 1, col = 1, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[11], { bufnr = buf_id, lnum = 1, col = 1, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[12], { bufnr = buf_id, lnum = 1, col = 1, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[13], { bufnr = buf_id_scratch, lnum = 1, col = 1, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[14], { bufnr = buf_id, lnum = 5, col = 1, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[15], { bufnr = buf_id, lnum = 6, col = 6, end_lnum = 0, end_col = 0 })
  validate_qfitem(qflist[16], { bufnr = buf_id, lnum = 7, col = 7, end_lnum = 8, end_col = 8 })
  validate_qfitem(qflist[17], { bufnr = buf_id, lnum = 7, col = 8, end_lnum = 8, end_col = 0 })
end

T['default_choose_marked()']['falls back to choosing first item'] = function()
  child.lua_notify(
    [[MiniPick.start({source = { items = { -1, { text = 'some_table' }, -3 }, choose = function(item) _G.chosen_item = item end, }})]]
  )
  type_keys('<C-n>', '<C-x>', '<C-n>', '<C-x>', '<M-CR>')
  eq(is_picker_active(), false)

  eq(child.lua_get('_G.chosen_item'), { text = 'some_table' })

  -- Can also be called without active picker and error
  expect.no_error(function() default_choose_marked({ -1, { text = 'some_table' } }) end)
end

T['default_choose_marked()']['works for edge case input'] = function()
  expect.error(default_choose_marked, '`items`.*array')
  expect.no_error(function() default_choose_marked({}) end)
end

T['default_choose_marked()']['respects `opts.list_type`'] = function()
  local win_id = child.api.nvim_get_current_win()
  local buf_id = child.api.nvim_create_buf(true, false)

  child.lua([[MiniPick.config.source.choose_marked = function(items)
    return MiniPick.default_choose_marked(items, { list_type = 'location' })
  end]])
  start_with_items({ { bufnr = buf_id } }, 'list_type test')
  type_keys('<C-x>', '<M-CR>')
  eq(is_picker_active(), false)

  -- Should create and open location list
  eq(#child.api.nvim_list_wins(), 2)
  eq(child.bo.filetype, 'qf')

  local loclist = child.fn.getloclist(win_id, { all = true })
  eq(#loclist.items, 1)
  validate_qfitem(loclist.items[1], { bufnr = buf_id, lnum = 1, col = 1, end_lnum = 0, end_col = 0, text = '' })

  eq(loclist.title, 'list_type test')

  -- No quickfix lists should be created
  eq(child.fn.getqflist({ nr = true }).nr, 0)
end

T['default_choose_marked()']['ensures valid target window for location list'] = function()
  local win_id_1 = child.api.nvim_get_current_win()
  child.cmd('botright wincmd v')
  local win_id_2 = child.api.nvim_get_current_win()
  child.api.nvim_set_current_win(win_id_1)

  local buf_id = child.api.nvim_create_buf(true, false)
  child.lua([[MiniPick.config.source.choose_marked = function(items)
    return MiniPick.default_choose_marked(items, { list_type = 'location' })
  end]])

  start_with_items({ { bufnr = buf_id } }, 'ensure valid window')
  local lua_cmd = string.format([[vim.api.nvim_win_call(%d, function() vim.cmd('close') end)]], win_id_1)
  child.lua(lua_cmd)
  type_keys('<C-x>', '<M-CR>')
  eq(is_picker_active(), false)

  eq(child.fn.getloclist(win_id_2, { title = true }).title, 'ensure valid window')
end

T['ui_select()'] = new_set()

local ui_select = function(items, opts, on_choice_str)
  opts = opts or {}
  on_choice_str = on_choice_str or 'function(...) _G.args = { ... } end'
  local lua_cmd = string.format('MiniPick.ui_select(%s, %s, %s)', vim.inspect(items), vim.inspect(opts), on_choice_str)
  child.lua_notify(lua_cmd)
end

T['ui_select()']['works'] = function()
  ui_select({ -1, -2 })
  child.expect_screenshot()
  type_keys('<C-n>', '<CR>')
  eq(child.lua_get('_G.args'), { -2, 2 })
end

T['ui_select()']['calls `on_choice(nil)` in case of abort'] = function()
  ui_select({ -1, -2 })
  type_keys('<C-c>')
  eq(child.lua_get('_G.args'), {})
end

T['ui_select()']['preserves target window after `on_choice`'] = function()
  local win_id_1 = child.api.nvim_get_current_win()
  child.cmd('botright wincmd v')
  local win_id_2 = child.api.nvim_get_current_win()
  child.api.nvim_set_current_win(win_id_1)

  local on_choice_str = string.format('function() vim.api.nvim_set_current_win(%d) end', win_id_2)
  ui_select({ -1, -2 }, {}, on_choice_str)
  type_keys('<CR>')
  eq(child.api.nvim_get_current_win(), win_id_2)
end

T['ui_select()']['respects `opts.prompt` and `opts.kind`'] = function()
  local validate = function(opts, source_name)
    ui_select({ -1, -2 }, opts)
    eq(child.lua_get('MiniPick.get_picker_opts().source.name'), source_name)
    stop()
  end

  -- Should try using use both as source name (preferring `kind` over `prompt`)
  validate({ prompt = 'Prompt' }, 'Prompt')
  validate({ prompt = 'Prompt', kind = 'Kind' }, 'Kind')
end

T['ui_select()']['respects `opts.format_item`'] = function()
  child.lua_notify([[MiniPick.ui_select(
    { { var = 'abc' }, { var = 'def' } },
    { format_item = function(x) return x.var end },
    function(...) _G.args = { ... } end
  )]])

  -- Should use formatted output as regular stritems
  eq(get_picker_stritems(), { 'abc', 'def' })
  type_keys('d', '<CR>')
  eq(child.lua_get('_G.args'), { { var = 'def' }, 2 })
end

T['ui_select()']['shows only original item in preview'] = function()
  child.lua_notify([[MiniPick.ui_select({ { var = 'abc' } }, { format_item = function(x) return x.var end })]])
  type_keys('<Tab>')
  child.expect_screenshot()
end

T['ui_select()']['respects `opts.preview_item`'] = function()
  child.lua_notify([[MiniPick.ui_select(
    { { var = 'abc' } },
    {
      format_item = function(x) return x.var end,
      preview_item = function(x) return { 'My preview', 'Var = ' .. x.var } end,
    }
  )]])
  type_keys('<Tab>')
  child.expect_screenshot()
end

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

T['set_picker_items()']['does not block picker'] = function()
  child.lua([[
    _G.log = {}
    _G.l_key = {
      char = 'l',
      func = function()
        table.insert(
          _G.log,
          { is_busy = MiniPick.get_picker_state().is_busy, items_type = type(MiniPick.get_picker_items()) }
        )
      end
    }
    _G.mappings = { append_log = _G.l_key }
  ]])
  child.lua_notify('MiniPick.start({ mappings = { append_log = _G.l_key }, delay = { async = 1 } })')

  -- Set many items and start typing right away. Key presses should be
  -- processed right away even though there is an items preprocessing is going.
  set_picker_items(many_items)
  type_keys('l')
  sleep(1)
  stop()
  eq(child.lua_get('_G.log'), { { is_busy = true, items_type = 'nil' } })
end

T['set_picker_items_from_cli()'] = new_set()

T['set_picker_items_from_cli()']['works'] = function() MiniTest.skip() end

T['set_picker_items_from_cli()']['can be called without active picker'] = function() MiniTest.skip() end

T['set_picker_items_from_cli()']['can have postprocess use Vimscript functions'] = function() MiniTest.skip() end

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
T[':Pick'] = new_set()

T[':Pick']['works'] = function() MiniTest.skip() end

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

T['Matching']['resets matched indexes after deleting'] = function() MiniTest.skip() end

T['Matching']['resets matched indexes after adding character inside query'] = function() MiniTest.skip() end

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
