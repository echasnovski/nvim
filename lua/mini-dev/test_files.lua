local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('files', config) end
local unload_module = function() child.mini_unload('files') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

-- Tweak `expect_screenshot()` to test only on Neovim>=0.9 (as it introduced
-- titles). Use `expect_screenshot_orig()` for original testing.
local expect_screenshot_orig = child.expect_screenshot
child.expect_screenshot = function(...)
  if child.fn.has('nvim-0.9') == 0 then return end
  expect_screenshot_orig(...)
end

local mock_win_functions = function() child.cmd('source tests/dir-files/mock-win-functions.lua') end

local test_dir = 'tests/dir-files'
local make_path = function(...)
  local path = test_dir .. '/' .. table.concat({ ... }, '/')
  return child.fn.fnamemodify(path, ':p')
end

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

-- Output test set ============================================================
T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      mock_win_functions()
      child.set_size(15, 80)
      load_module()
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniFiles)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniFiles'), 1)

  -- Highlight groups
  local validate_hl_group = function(name, ref) expect.match(child.cmd_capture('hi ' .. name), ref) end

  validate_hl_group('MiniFilesBorder', 'links to FloatBorder')
  validate_hl_group('MiniFilesBorderModified', 'links to DiagnosticFloatingWarn')
  validate_hl_group('MiniFilesDirectory', 'links to Directory')
  eq(child.fn.hlexists('MiniFilesFile'), 1)
  validate_hl_group('MiniFilesNormal', 'links to NormalFloat')
  validate_hl_group('MiniFilesTitle', 'links to FloatTitle')
  validate_hl_group('MiniFilesTitleFocused', 'links to FloatTitle')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniFiles.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniFiles.config.' .. field), value) end

  expect_config('content.filter', vim.NIL)
  expect_config('content.sort', vim.NIL)

  expect_config('mappings.close', 'q')
  expect_config('mappings.go_in', 'l')
  expect_config('mappings.go_in_plus', 'L')
  expect_config('mappings.go_out', 'h')
  expect_config('mappings.go_out_plus', 'H')
  expect_config('mappings.reset', '<BS>')
  expect_config('mappings.show_help', 'g?')
  expect_config('mappings.synchronize', '=')
  expect_config('mappings.trim_left', '<')
  expect_config('mappings.trim_right', '>')

  expect_config('options.use_as_default_explorer', true)

  expect_config('windows.max_number', math.huge)
  expect_config('windows.preview', false)
  expect_config('windows.width_focus', 50)
  expect_config('windows.width_nofocus', 15)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ mappings = { close = 'gc' } })
  eq(child.lua_get('MiniFiles.config.mappings.close'), 'gc')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ content = 'a' }, 'content', 'table')
  expect_config_error({ content = { filter = 1 } }, 'content.filter', 'function')
  expect_config_error({ content = { sort = 1 } }, 'content.sort', 'function')

  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { close = 1 } }, 'mappings.close', 'string')
  expect_config_error({ mappings = { go_in = 1 } }, 'mappings.go_in', 'string')
  expect_config_error({ mappings = { go_in_plus = 1 } }, 'mappings.go_in_plus', 'string')
  expect_config_error({ mappings = { go_out = 1 } }, 'mappings.go_out', 'string')
  expect_config_error({ mappings = { go_out_plus = 1 } }, 'mappings.go_out_plus', 'string')
  expect_config_error({ mappings = { reset = 1 } }, 'mappings.reset', 'string')
  expect_config_error({ mappings = { show_help = 1 } }, 'mappings.show_help', 'string')
  expect_config_error({ mappings = { synchronize = 1 } }, 'mappings.synchronize', 'string')
  expect_config_error({ mappings = { trim_left = 1 } }, 'mappings.trim_left', 'string')
  expect_config_error({ mappings = { trim_right = 1 } }, 'mappings.trim_right', 'string')

  expect_config_error({ options = 'a' }, 'options', 'table')
  expect_config_error({ options = { use_as_default_explorer = 1 } }, 'options.use_as_default_explorer', 'boolean')

  expect_config_error({ windows = 'a' }, 'windows', 'table')
  expect_config_error({ windows = { max_number = 'a' } }, 'windows.max_number', 'number')
  expect_config_error({ windows = { preview = 1 } }, 'windows.preview', 'boolean')
  expect_config_error({ windows = { width_focus = 'a' } }, 'windows.width_focus', 'number')
  expect_config_error({ windows = { width_nofocus = 'a' } }, 'windows.width_nofocus', 'number')
end

T['open()'] = new_set()

local open = forward_lua('MiniFiles.open')

T['open()']['works with directory path'] = function()
  open(make_path('common'))
  child.expect_screenshot()
end

T['open()']['works with file path'] = function() MiniTest.skip() end

T['open()']['works with relative paths'] = function() MiniTest.skip() end

T['open()']['focuses on file entry'] = function()
  -- If in branch, just focus

  -- If not in branch, reset
  MiniTest.skip()
end

T['open()']['works per tabpage'] = function() MiniTest.skip() end

T['open()']['respects `use_latest`'] = function()
  -- Should use latest previous state if present
  MiniTest.skip()
end

T['open()']['validates input'] = function()
  -- `path` should be a real path
  MiniTest.skip()
end

T['open()'][''] = function() MiniTest.skip() end

T['open()']['properly closes currently opened explorer'] = function()
  -- Both with and without modified buffers
  MiniTest.skip()
end

T['open()']['handles `config.mappings`'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('nmap ' .. lhs):find(pattern) ~= nil end

  -- Supplying empty string should mean "don't create keymap"
  child.lua('MiniFiles.config.mappings.go_in = ""')
  open()

  eq(has_map('q', 'Close'), true)
  eq(has_map('l', 'Go in'), false)
end

T['open()']['respects `vim.b.minifiles_config`'] = function() MiniTest.skip() end

T['refresh()'] = new_set()

local refresh = forward_lua('MiniFiles.refresh')

T['refresh()']['works'] = function() MiniTest.skip() end

T['refresh()']['non-nil `filter`/`sort` update buffers'] = function() MiniTest.skip() end

T['refresh()']['handles cursors if content is changes externally'] = function() MiniTest.skip() end

T['synchronize()'] = new_set()

local synchronize = forward_lua('MiniFiles.synchronize')

T['synchronize()']['works'] = function() MiniTest.skip() end

T['synchronize()']['should follow cursor on current file path'] = function() MiniTest.skip() end

T['synchronize()']['should follow cursor on new file path'] = function()
  -- File
  -- Directory
  -- Nested directories
  MiniTest.skip()
end

T['reset()'] = new_set()

local reset = forward_lua('MiniFiles.reset')

T['reset()']['works'] = function() MiniTest.skip() end

T['close()'] = new_set()

local close = forward_lua('MiniFiles.close')

T['close()']['works'] = function() MiniTest.skip() end

T['close()']['saves latest cursors'] = function()
  -- Like in "go right - go left - move cursor" and it should remember that
  -- cursor was in second to right window on some other line.
  MiniTest.skip()
end

T['close()']['checks for modified buffers'] = function() MiniTest.skip() end

T['go_in()'] = new_set()

local go_in = forward_lua('MiniFiles.go_in')

T['go_in()']['works'] = function() MiniTest.skip() end

T['go_in()']['works on files with "bad names"'] = function()
  -- Like files with names containing space or `%`
  MiniTest.skip()
end

T['go_in()']['can be applied consecutively on file'] = function()
  -- This might be an issue with set up auto-root from 'mini.misc'
  MiniTest.skip()
end

T['go_out()'] = new_set()

local go_out = forward_lua('MiniFiles.go_out')

T['go_out()']['works'] = function() MiniTest.skip() end

T['go_out()']['update root'] = new_set()

T['go_out()']['update root']['reuses buffers without their update'] = function() MiniTest.skip() end

T['go_out()']['update root']['puts cursor on entry describing current root'] = function() MiniTest.skip() end

T['trim_left()'] = new_set()

local trim_left = forward_lua('MiniFiles.trim_left')

T['trim_left()']['works'] = function() MiniTest.skip() end

T['trim_right()'] = new_set()

local trim_right = forward_lua('MiniFiles.trim_right')

T['trim_right()']['works'] = function() MiniTest.skip() end

T['show_help()'] = new_set()

local show_help = forward_lua('MiniFiles.show_help')

T['show_help()']['works'] = function() MiniTest.skip() end

T['show_help()']['handles empty mappings'] = function() MiniTest.skip() end

T['get_fs_entry()'] = new_set()

local get_fs_entry = forward_lua('MiniFiles.get_fs_entry')

T['get_fs_entry()']['works'] = function() MiniTest.skip() end

T['get_latest_path()'] = new_set()

local get_latest_path = forward_lua('MiniFiles.get_latest_path')

T['get_latest_path()']['works'] = function() MiniTest.skip() end

T['default_filter()'] = new_set()

local default_filter = forward_lua('MiniFiles.default_filter')

T['default_filter()']['works'] = function() MiniTest.skip() end

T['default_sort()'] = new_set()

local default_sort = forward_lua('MiniFiles.default_sort')

T['default_sort()']['works'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
T['File exploration'] = new_set()

T['File exploration']['works'] = function() MiniTest.skip() end

T['Windows'] = new_set()

T['Windows']['react on `VimResized`'] = function()
  -- Both increasing and decreasing dimensions
  MiniTest.skip()
end

T['Mappings'] = new_set()

T['Mappings']['`close` works'] = function() MiniTest.skip() end

T['Mappings']['`go_in` works'] = function() MiniTest.skip() end

T['Mappings']['`go_in` works in linewise Visual mode'] = function()
  -- Should open all files

  -- Should open only last directory with cursor moved to its entry
  MiniTest.skip()
end

T['Mappings']['`go_in` ignores non-linewise Visual mode'] = function() MiniTest.skip() end

T['Mappings']['`go_in_plus` works'] = function()
  -- Should not through error on non-entry (when `get_fs_entry()` returns `nil`)
  MiniTest.skip()
end

T['Mappings']['`go_out` works'] = function() MiniTest.skip() end

T['Mappings']['`go_out_plus` works'] = function() MiniTest.skip() end

T['Mappings']['`reset` works'] = function() MiniTest.skip() end

T['Mappings']['`show_help` works'] = function() MiniTest.skip() end

T['Mappings']['`synchronize` works'] = function() MiniTest.skip() end

T['Mappings']['`trim_left` works'] = function() MiniTest.skip() end

T['Mappings']['`trim_right` works'] = function() MiniTest.skip() end

T['File manipulation'] = new_set()

T['File manipulation']['respects modified hidden buffers'] = new_set()

T['File manipulation']['works to create'] = function() MiniTest.skip() end

T['File manipulation']['creates nested directories'] = function() MiniTest.skip() end

T['File manipulation']['works to delete'] = function() MiniTest.skip() end

T['File manipulation']['works to rename'] = function() MiniTest.skip() end

T['File manipulation']['works to copy'] = function() MiniTest.skip() end

T['File manipulation']['copies directory inside its child'] = function() MiniTest.skip() end

T['File manipulation']['works to move'] = function() MiniTest.skip() end

T['File manipulation']['handles move directory inside its child'] = function() MiniTest.skip() end

T['Cursors'] = new_set()

T['Cursors']['works'] = function() MiniTest.skip() end

T['Cursors']['works when directory content is changed externally'] = function() MiniTest.skip() end

T['Cursors']['preserved after hiding buffer'] = function() MiniTest.skip() end

T['Cursors']['preserved after opening from history'] = function() MiniTest.skip() end

T['Events'] = new_set()

T['Events']['works'] = function()
  -- Has `data` with both `buf_id` and `win_id` (where relevant)
  MiniTest.skip()
end

T['Events']['on buffer open can be used to create buffer-local mappings'] = function() MiniTest.skip() end

T['Events']['on window open can be used to set window-local options'] = function() MiniTest.skip() end

T['Default explorer'] = new_set()

T['Default explorer']['works in `nvim .`'] = function()
  -- Should hide scract buffer on file open
  MiniTest.skip()
end

T['Default explorer']['works in `:edit .`'] = function() MiniTest.skip() end

T['Default explorer']['works in `:vsplit .`'] = function() MiniTest.skip() end

T['Default explorer']['handles close without opening file'] = function()
  -- Should delete "scratch directory buffer"
  MiniTest.skip()
end

return T
