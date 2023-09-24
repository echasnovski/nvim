local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('pick', config) end
local unload_module = function() child.mini_unload('pick') end
local type_keys = function(...) return child.type_keys(...) end
--stylua: ignore end

-- Tweak `expect_screenshot()` to test only on Neovim>=0.9 (as it introduced
-- titles). Use `expect_screenshot_orig()` for original testing.
local expect_screenshot_orig = child.expect_screenshot
child.expect_screenshot = function(...)
  if child.fn.has('nvim-0.9') == 0 then return end
  expect_screenshot_orig(...)
end

-- Test paths helpers
local test_dir = 'tests/dir-pick'

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local start = forward_lua('MiniPick.start')
local start_with_items = function(items, name) start({ source = { items = items, name = name } }) end

-- Common mocks

-- Data =======================================================================
local test_items = { 'abc', 'a_b_c', 'c_a_b', 'b_c_a' }

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.set_size(15, 40)
      load_module()
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

  expect_config('options.direction', 'from_top')
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
  expect_config_error({ options = { direction = 1 } }, 'options.direction', 'string')
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

T['start()'] = new_set()

T['start()']['works'] = function() MiniTest.skip() end

T['start()']['returns chosen value'] = function() MiniTest.skip() end

T['start()']['creates proper buffer'] = function() MiniTest.skip() end

T['start()']['creates proper window'] = function() MiniTest.skip() end

T['start()']['tracks lost focus'] = function() MiniTest.skip() end

T['start()']['validates `opts`'] = function() MiniTest.skip() end

T['start()']['correctly computes stritems'] = function() MiniTest.skip() end

T['start()']['respects `window.config`'] = function()
  -- As table

  -- As callable
  MiniTest.skip()
end

T['start()']['stops currently active picker'] = function() MiniTest.skip() end

T['start()']['stops impoperly aborted previous picker'] = function() MiniTest.skip() end

T['start()']['triggers `MiniPickStart` User event'] = function() MiniTest.skip() end

T['stop()'] = new_set()

T['stop()']['works'] = function() MiniTest.skip() end

T['stop()']['can be called without active picker'] = function() MiniTest.skip() end

T['stop()']['triggers `MiniPickStop` User event'] = function() MiniTest.skip() end

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

T['get_picker_matches()'] = new_set()

T['get_picker_matches()']['works'] = function() MiniTest.skip() end

T['get_picker_items()']['can be called without active picker'] = function() MiniTest.skip() end

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
  if child.fn.has('nvim-0.10') == 0 then return end

  -- Basic test

  -- Should update after marking

  MiniTest.skip()
end

T['Overall view']['correctly infers footer empty space'] = function()
  -- Check both `border = 'double'` and `border = <custom_array>`
  MiniTest.skip()
end

T['Overall view']['respects `options.direction`'] = function()
  if child.fn.has('nvim-0.10') == 0 then return end

  -- Should switch title and footer
  MiniTest.skip()
end

T['Overall view']['truncates border text'] = function()
  if child.fn.has('nvim-0.10') == 0 then return end

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

T['Main view']['works with `options.direction="from_bottom"`'] = function()
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

T['Matching']["respects 'ignorecase'"] = function() MiniTest.skip() end

T['Matching']["respects 'smartcase'"] = function() MiniTest.skip() end

T['Key query process'] = new_set()

T['Key query process']['works'] = function() MiniTest.skip() end

T['Key query process']['does not block'] = function()
  -- Allows actions to be executed: from RPC, inside a timer
  MiniTest.skip()
end

T['Key query process']['narrows matched indexes with query progression'] = function() MiniTest.skip() end

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

return T
