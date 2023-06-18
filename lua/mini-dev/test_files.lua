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

-- Common mocks
local mock_win_functions = function() child.cmd('source tests/dir-files/mock-win-functions.lua') end

local mock_confirm = function(user_choice)
  local lua_cmd = string.format(
    [[vim.fn.confirm = function(...)
        _G.confirm_args = { ... }
        return %d
      end]],
    user_choice
  )
  child.lua(lua_cmd)
end

-- Test paths helpers
local test_dir = 'tests/dir-files'

local join_path = function(...) return table.concat({ ... }, '/') end

local make_test_path = function(...)
  local path = join_path(test_dir, join_path(...))
  return child.fn.fnamemodify(path, ':p')
end

local make_temp_dir = function(name, children)
  -- Make temporary directory and make sure it is removed after test is done
  local temp_dir = make_test_path('temp')
  vim.fn.mkdir(temp_dir, 'p')

  MiniTest.finally(function() vim.fn.delete(temp_dir, 'rf') end)

  -- Create children
  for _, path in ipairs(children) do
    local full_path = temp_dir .. '/' .. path
    if vim.endswith(path, '/') then
      vim.fn.mkdir(full_path)
    else
      vim.fn.writefile({}, full_path)
    end
  end

  return temp_dir
end

-- Common validators and helpers
local validate_cur_line = function(x) eq(get_cursor()[1], x) end

local validate_n_wins = function(n) eq(#child.api.nvim_tabpage_list_wins(0), n) end

local validate_fs_entries_arg = function(x)
  eq(vim.tbl_islist(x), true)
  for _, val in ipairs(x) do
    eq(type(val), 'table')
    eq(type(val.name), 'string')
    eq(val.fs_type == 'file' or val.fs_type == 'directory', true)
  end
end

local validate_confirm_args = function(ref_msg_pattern, ref_choices)
  local args = child.lua_get('_G.confirm_args')
  expect.match(args[1], ref_msg_pattern)
  eq(args[2], ref_choices)
  if args[3] ~= nil then eq(args[3], 1) end
  if args[4] ~= nil then eq(args[4], 'Question') end
end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local open = forward_lua('MiniFiles.open')
local close = forward_lua('MiniFiles.close')
local go_in = forward_lua('MiniFiles.go_in')
local go_out = forward_lua('MiniFiles.go_out')
local trim_left = forward_lua('MiniFiles.trim_left')
local trim_right = forward_lua('MiniFiles.trim_right')

-- Extmark helpers
local get_extmarks_hl = function()
  local ns_id = child.api.nvim_get_namespaces()['MiniFilesHighlight']
  local extmarks = child.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details = true })
  return vim.tbl_map(function(x) return x[4].hl_group end, extmarks)
end

-- Data =======================================================================
local test_dir_path = 'tests/dir-files/common'
local test_file_path = 'tests/dir-files/common/a-file'

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

T['open()']['works with directory path'] = function()
  -- Works with relative path
  open(test_dir_path)
  child.expect_screenshot()
  close()
  validate_n_wins(1)

  -- Works with absolute path
  open(vim.fn.fnamemodify(test_dir_path, ':p'))
  child.expect_screenshot()
  close()
  validate_n_wins(1)

  -- Works with trailing slash
  open(test_dir_path .. '/')
  child.expect_screenshot()
end

T['open()']['works with file path'] = function()
  -- Works with relative path
  open(test_file_path)
  -- Should focus on file entry
  child.expect_screenshot()
  close()

  -- Works with absolute path
  open(vim.fn.fnamemodify(test_file_path, ':p'))
  child.expect_screenshot()
end

T['open()']['works per tabpage'] = function()
  open(test_dir_path)
  child.expect_screenshot()

  child.cmd('tabedit')
  open(test_dir_path .. '/a-dir')
  child.expect_screenshot()

  child.cmd('tabnext')
  child.expect_screenshot()
end

T['open()']["uses 'nvim-web-devicons' if present"] = function()
  -- Mock 'nvim-web-devicons'
  child.cmd('set rtp+=tests/dir-files')

  open(make_test_path('real'))
  child.expect_screenshot()
  eq(
    get_extmarks_hl(),
    { 'DevIconLua', 'MiniFilesFile', 'DevIconTxt', 'MiniFilesFile', 'DevIconLicense', 'MiniFilesFile' }
  )
end

T['open()']['history'] = new_set()

T['open()']['history']['opens from history by default'] = function()
  open(test_dir_path)
  type_keys('j')
  go_in()
  type_keys('2j')
  child.expect_screenshot()

  close()
  validate_n_wins(1)
  open(test_dir_path)
  -- Should be exactly the same, including cursors
  child.expect_screenshot()
end

T['open()']['history']['handles external changes between calls'] = function()
  local temp_dir = make_temp_dir('temp', { 'subdir/' })

  open(temp_dir)
  go_in()
  child.expect_screenshot()

  close()
  child.fn.delete(join_path(temp_dir, 'subdir'), 'rf')
  open(temp_dir)
  child.expect_screenshot()
end

T['open()']['history']['respects `use_latest`'] = function()
  open(test_dir_path)
  type_keys('j')
  go_in()
  type_keys('2j')
  child.expect_screenshot()

  close()
  validate_n_wins(1)
  open(test_dir_path, false)
  -- Should be as if opened first time
  child.expect_screenshot()
end

T['open()']['history']['prefers global config before taking from history'] = function()
  child.lua([[
    _G.filter_starts_from_a = function(fs_entries)
      return vim.tbl_filter(function(x) return vim.startswith(x.name, 'a') end, fs_entries)
    end
    _G.filter_starts_from_b = function(fs_entries)
      return vim.tbl_filter(function(x) return vim.startswith(x.name, 'b') end, fs_entries)
    end
  ]])

  local lua_cmd = string.format(
    'MiniFiles.open(%s, false, { content = { filter = _G.filter_starts_from_a } })',
    vim.inspect(test_dir_path)
  )
  child.lua(lua_cmd)
  child.expect_screenshot()

  close()
  child.lua('MiniFiles.config.content.filter = _G.filter_starts_from_b')
  open(test_dir_path, true)
  child.expect_screenshot()
end

T['open()']['history']['stores whole branch and not only visible windows'] = function()
  child.set_size(15, 60)
  open(test_dir_path)
  go_in()
  child.expect_screenshot()
  close()

  child.set_size(15, 80)
  -- Should show two windows
  open(test_dir_path, true)
  child.expect_screenshot()
end

T['open()']['history']['is shared across tabpages'] = function()
  -- Prepare history
  open(test_dir_path)
  go_in()
  child.expect_screenshot()
  close()

  -- Open in new tabpage
  child.cmd('tabedit')
  open(test_dir_path, true)
  child.expect_screenshot()
  go_out()
  close()

  child.cmd('tabnext')
  open(test_dir_path, true)
  child.expect_screenshot()
end

T['open()']['focuses on file entry when opened from history'] = function()
  local path = make_test_path('common/a-dir/ab-file')

  -- If in branch, just focus on entry
  open(path)
  type_keys('j')
  go_out()
  child.expect_screenshot()

  close()
  open(path)
  child.expect_screenshot()

  -- If not in branch, reset
  go_out()
  trim_right()
  child.expect_screenshot()
  close()

  open(path)
  child.expect_screenshot()
end

T['open()']['normalizes before first refresh when focused on file'] = function()
  -- Prepare explorer state to be opened from history
  open(make_test_path('common'))
  go_in()
  validate_n_wins(3)
  close()

  -- Mock `nvim_open_win()`
  child.lua([[
    _G.init_nvim_open_win = vim.api.nvim_open_win
    _G.open_win_count = 0
    vim.api.nvim_open_win = function(...)
      _G.open_win_count = _G.open_win_count + 1
      return init_nvim_open_win(...)
    end
  ]])

  -- Test. Opening file in 'common' directory makes previous two-window view
  -- not synchronized with cursor (pointing at file while right window is for
  -- previously opened directory). Make sure that it is made one window prior
  -- to rendering, otherwise it might result in flickering.
  open(make_test_path('common/a-file'))
  child.expect_screenshot()
  eq(child.lua_get('_G.open_win_count'), 1)
end

T['open()']['normalizes before first refresh when focused on directory with `windows.preview`'] = function()
  -- Prepare explorer state to be opened from history
  open(test_dir_path)
  validate_n_wins(2)
  close()

  -- Mock `nvim_open_win()`
  child.lua([[
    _G.init_nvim_open_win = vim.api.nvim_open_win
    _G.open_win_count = 0
    vim.api.nvim_open_win = function(...)
      _G.open_win_count = _G.open_win_count + 1
      return init_nvim_open_win(...)
    end
  ]])

  -- Test. It should preview right away without extra window manipulations.
  open(test_dir_path, true, { windows = { preview = true } })
  child.expect_screenshot()
  eq(child.lua_get('_G.open_win_count'), 2)
end

T['open()']['respects `content.filter`'] = function()
  child.lua([[
    _G.filter_arg = {}
    MiniFiles.config.content.filter = function(fs_entries)
      _G.filter_arg = fs_entries

      -- Show only directories
      return vim.tbl_filter(function(x) return x.fs_type == 'directory' end, fs_entries)
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()
  validate_fs_entries_arg(child.lua_get('_G.filter_arg'))

  -- Local value from argument should take precedence
  child.lua([[
    _G.filter_starts_from_a = function(fs_entries)
      return vim.tbl_filter(function(x) return vim.startswith(x.name, 'a') end, fs_entries)
    end
  ]])

  local lua_cmd = string.format(
    [[MiniFiles.open(%s, false, { content = { filter = _G.filter_starts_from_a } })]],
    vim.inspect(test_dir_path)
  )
  child.lua(lua_cmd)
  child.expect_screenshot()
end

T['open()']['respects `content.sort`'] = function()
  child.lua([[
    _G.sort_arg = {}
    MiniFiles.config.content.sort = function(fs_entries)
      _G.sort_arg = fs_entries

      -- Sort alphabetically without paying attention to file system type
      local res = vim.deepcopy(fs_entries)
      table.sort(res, function(a, b) return a.name < b.name end)
      return res
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()
  validate_fs_entries_arg(child.lua_get('_G.sort_arg'))

  -- Local value from argument should take precedence
  child.lua([[
    _G.sort_rev_alpha = function(fs_entries)
      local res = vim.deepcopy(fs_entries)
      table.sort(res, function(a, b) return a.name > b.name end)
      return res
    end
  ]])

  local lua_cmd =
    string.format([[MiniFiles.open(%s, false, { content = { sort = _G.sort_rev_alpha } })]], vim.inspect(test_dir_path))
  child.lua(lua_cmd)
  child.expect_screenshot()
end

T['open()']['`content.sort` can be used to also filter items'] = function()
  child.lua([[
    MiniFiles.config.content.sort = function(fs_entries)
      -- Sort alphabetically without paying attention to file system type
      local res = vim.tbl_filter(function(x) return x.fs_type == 'directory' end, fs_entries)
      table.sort(res, function(a, b) return a.name > b.name end)
      return res
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()
end

T['open()']['respects `mappings`'] = function()
  child.lua([[MiniFiles.config.mappings.go_in = '<CR>']])
  open(test_dir_path)
  type_keys('<CR>')
  child.expect_screenshot()
  close()

  -- Local value from argument should take precedence
  open(test_dir_path, false, { mappings = { go_in = 'K' } })
  type_keys('K')
  child.expect_screenshot()
end

T['open()']['does not create mapping for emptry string'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('nmap ' .. lhs):find(pattern) ~= nil end

  -- Supplying empty string should mean "don't create keymap"
  child.lua('MiniFiles.config.mappings.go_in = ""')
  open()

  eq(has_map('q', 'Close'), true)
  eq(has_map('l', 'Go in'), false)
end

T['open()']['respects `windows.max_number`'] = function()
  child.lua('MiniFiles.config.windows.max_number = 1')
  open(test_dir_path)
  go_in()
  child.expect_screenshot()
  close()

  -- Local value from argument should take precedence
  open(test_dir_path, false, { windows = { max_number = 2 } })
  go_in()
  child.expect_screenshot()
end

T['open()']['respects `windows.preview`'] = function()
  child.lua('MiniFiles.config.windows.preview = true')
  open(test_dir_path)
  child.expect_screenshot()
  close()

  -- Local value from argument should take precedence
  open(test_dir_path, false, { windows = { preview = false } })
  child.expect_screenshot()
end

T['open()']['respects `windows.width_focus` and `windows.width_nofocus`'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 40')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')
  open(test_dir_path)
  go_in()
  child.expect_screenshot()
  close()

  -- Local value from argument should take precedence
  open(test_dir_path, false, { windows = { width_focus = 30, width_nofocus = 20 } })
  go_in()
  child.expect_screenshot()
end

T['open()']['properly closes currently opened explorer'] = function()
  local path_1, path_2 = make_test_path('common'), make_test_path('common/a-dir')
  open(path_1)
  go_in()
  validate_n_wins(3)

  -- Should properly close current opened explorer (at least save to history)
  open(path_2)
  close()

  open(path_1, true)
  child.expect_screenshot()
end

T['open()']['properly closes currently opened explorer with modified buffers'] = function()
  child.set_size(100, 100)

  local path_1, path_2 = make_test_path('common'), make_test_path('common/a-dir')
  open(path_1)
  type_keys('o', 'hello')

  -- Should mention modified buffers and ask for confirmation
  mock_confirm(1)
  open(path_2)
  validate_confirm_args('modified buffer.*close without sync', '&Yes\n&No')
end

T['open()']['validates input'] = function()
  -- `path` should be a real path
  expect.error(function() open('aaa') end, 'path.*not a valid path.*aaa')
end

T['open()']['respects `vim.b.minifiles_config`'] = function()
  child.lua([[
    _G.filter_starts_from_a = function(fs_entries)
      return vim.tbl_filter(function(x) return vim.startswith(x.name, 'a') end, fs_entries)
    end
  ]])
  child.lua('vim.b.minifiles_config = { content = { filter = _G.filter_starts_from_a } }')

  open(test_dir_path)
  child.expect_screenshot()
end

T['refresh()'] = new_set()

local refresh = forward_lua('MiniFiles.refresh')

T['refresh()']['works'] = function()
  open(test_dir_path)
  refresh({ windows = { width_focus = 30 } })
  child.expect_screenshot()
end

T['refresh()']['works when no explorer is opened'] = function() expect.no_error(refresh) end

T['refresh()']['preserves explorer options'] = function()
  open(test_dir_path, false, { windows = { width_focus = 45, width_nofocus = 5 } })
  go_in()
  child.expect_screenshot()
  -- Current explorer options should be preserved
  refresh({ windows = { width_focus = 30 } })
  child.expect_screenshot()
end

T['refresh()']['does not update buffers with `nil` `filter` and `sort`'] = function()
  local temp_dir = make_temp_dir('temp', { 'subdir/' })

  open(temp_dir)
  local buf_id_1 = child.api.nvim_get_current_buf()
  go_in()
  local buf_id_2 = child.api.nvim_get_current_buf()
  child.expect_screenshot()

  local changedtick_1 = child.api.nvim_buf_get_var(buf_id_1, 'changedtick')
  local changedtick_2 = child.api.nvim_buf_get_var(buf_id_2, 'changedtick')

  -- Should not update buffers
  refresh()
  eq(child.api.nvim_buf_get_var(buf_id_1, 'changedtick'), changedtick_1)
  eq(child.api.nvim_buf_get_var(buf_id_2, 'changedtick'), changedtick_2)

  -- Should not update even if there are external changes (there is
  -- `synchronize()` for that)
  vim.fn.mkdir(join_path(temp_dir, 'subdir', 'subsubdir'))
  refresh()
  child.expect_screenshot()
  eq(child.api.nvim_buf_get_var(buf_id_1, 'changedtick'), changedtick_1)
  eq(child.api.nvim_buf_get_var(buf_id_2, 'changedtick'), changedtick_2)
end

T['refresh()']['updates buffers with non-`nil` `filter` or `sort`'] = function()
  child.lua([[
    _G.hide_dotfiles = function(fs_entries)
      return vim.tbl_filter(function(x) return not vim.startswith(x.name, '.') end, fs_entries)
    end
    _G.sort_rev_alpha = function(fs_entries)
      local res = vim.deepcopy(fs_entries)
      table.sort(res, function(a, b) return a.name > b.name end)
      return res
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()

  child.lua('MiniFiles.refresh({ content = { filter = _G.hide_dotfiles } })')
  child.expect_screenshot()

  child.lua('MiniFiles.refresh({ content = { sort = _G.sort_rev_alpha } })')
  child.expect_screenshot()
end

-- More extensive testing is done in 'File Manipulation'
T['synchronize()'] = new_set()

local synchronize = forward_lua('MiniFiles.synchronize')

T['synchronize()']['works to update external file system changes'] = function()
  local temp_dir = make_temp_dir('temp', { 'subdir/' })

  open(temp_dir)
  validate_cur_line(1)

  vim.fn.mkdir(join_path(temp_dir, 'aaa'))
  synchronize()
  child.expect_screenshot()

  -- Cursor should be "sticked" to current entry
  validate_cur_line(2)
end

T['synchronize()']['works to apply file system actions'] = function()
  local temp_dir = make_temp_dir('temp', {})

  open(temp_dir)
  type_keys('i', 'new-file', '<Esc>')

  local new_file_path = join_path(temp_dir, 'new-file')
  mock_confirm(1)
  eq(vim.fn.filereadable(new_file_path), 0)

  synchronize()
  eq(vim.fn.filereadable(new_file_path), 1)
end

T['synchronize()']['works when no explorer is opened'] = function() expect.no_error(synchronize) end

T['synchronize()']['should follow cursor on current entry path'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file' })

  open(temp_dir)
  type_keys('G', 'o', 'new-dir/', '<Esc>')
  type_keys('k')

  validate_cur_line(2)

  mock_confirm(1)
  synchronize()
  validate_cur_line(3)
end

T['synchronize()']['should follow cursor on new path'] = function()
  mock_confirm(1)
  local temp_dir = make_temp_dir('temp', { 'dir/' })
  open(temp_dir)

  -- File
  type_keys('O', 'new-file', '<Esc>')
  validate_cur_line(1)
  synchronize()
  validate_cur_line(2)

  -- Directory
  type_keys('o', 'new-dir/', '<Esc>')
  validate_cur_line(3)
  synchronize()
  validate_cur_line(2)

  -- Nested directories
  type_keys('o', 'a/b', '<Esc>')
  validate_cur_line(3)
  synchronize()
  validate_cur_line(1)
end

T['reset()'] = new_set()

local reset = forward_lua('MiniFiles.reset')

T['reset()']['works'] = function()
  open(test_dir_path)
  type_keys('j')
  go_in()
  child.expect_screenshot()

  reset()
  child.expect_screenshot()
end

T['reset()']['works when no explorer is opened'] = function() expect.no_error(reset) end

T['reset()']['works when anchor is not in branch'] = function()
  open(join_path(test_dir_path, 'a-dir'))
  go_out()
  type_keys('k')
  go_in()
  child.expect_screenshot()

  reset()
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end
end

T['reset()']['resets all cursors'] = function()
  open(test_dir_path)
  type_keys('j')
  go_in()
  type_keys('G')
  validate_cur_line(3)

  -- Should reset cursors in both visible and invisible buffers
  go_out()
  type_keys('G')
  child.expect_screenshot()

  reset()
  child.expect_screenshot()
  type_keys('j')
  go_in()
  validate_cur_line(1)
end

T['close()'] = new_set()

T['close()']['works'] = function()
  open(test_dir_path)
  child.expect_screenshot()

  -- Should return `true` if closing was successful
  eq(close(), true)
  child.expect_screenshot()

  -- Should close all windows and delete all buffers
  validate_n_wins(1)
  eq(#child.api.nvim_list_bufs(), 1)
end

T['close()']['works per tabpage'] = function()
  open(test_dir_path)
  child.cmd('tabedit')
  open(test_file_path)

  child.cmd('tabprev')
  close()

  -- On different tabpage explorer should still be present
  child.cmd('tabnext')
  child.expect_screenshot()
end

T['close()']['works when no explorer is opened'] = function() eq(close(), vim.NIL) end

T['close()']['checks for modified buffers'] = function()
  open(test_dir_path)
  type_keys('o', 'new', '<Esc>')
  child.expect_screenshot()

  -- Should confirm close and do nothing if there is none (and return `false`)
  mock_confirm(2)
  eq(close(), false)
  child.expect_screenshot()
  validate_confirm_args('modified buffer.*close without sync', '&Yes\n&No')

  -- Should close if there is confirm
  mock_confirm(1)
  eq(close(), true)
  child.expect_screenshot()
end

T['go_in()'] = new_set()

T['go_in()']['works'] = function() MiniTest.skip() end

T['go_in()']['works when no explorer is opened'] = function() expect.no_error(go_in) end

T['go_in()']['works on files with "bad names"'] = function()
  -- Like files with names containing space or `%`
  MiniTest.skip()
end

T['go_in()']['can be applied consecutively on file'] = function()
  -- This might be an issue with set up auto-root from 'mini.misc'
  MiniTest.skip()
end

T['go_out()'] = new_set()

T['go_out()']['works'] = function() MiniTest.skip() end

T['go_out()']['works when no explorer is opened'] = function() expect.no_error(go_out) end

T['go_out()']['puts cursor on entry describing current directory'] = function() MiniTest.skip() end

T['go_out()']['update root'] = new_set()

T['go_out()']['update root']['reuses buffers without their update'] = function() MiniTest.skip() end

T['go_out()']['update root']['puts cursor on entry describing current root'] = function() MiniTest.skip() end

T['trim_left()'] = new_set()

T['trim_left()']['works'] = function() MiniTest.skip() end

T['trim_left()']['works when no explorer is opened'] = function() expect.no_error(trim_left) end

T['trim_right()'] = new_set()

local trim_right = forward_lua('MiniFiles.trim_right')

T['trim_right()']['works'] = function() MiniTest.skip() end

T['trim_right()']['works when no explorer is opened'] = function() expect.no_error(trim_right) end

T['show_help()'] = new_set()

local show_help = forward_lua('MiniFiles.show_help')

T['show_help()']['works'] = function() MiniTest.skip() end

T['show_help()']['works when no explorer is opened'] = function() expect.no_error(show_help) end

T['show_help()']['handles empty mappings'] = function() MiniTest.skip() end

T['get_fs_entry()'] = new_set()

local get_fs_entry = forward_lua('MiniFiles.get_fs_entry')

T['get_fs_entry()']['works'] = function() MiniTest.skip() end

T['get_latest_path()'] = new_set()

local get_latest_path = forward_lua('MiniFiles.get_latest_path')

T['get_latest_path()']['works'] = function() MiniTest.skip() end

T['get_latest_path()']['is updated on `open()`'] = function() MiniTest.skip() end

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

T['Windows']['does not wrap content'] = function()
  child.set_size(10, 20)
  child.lua('MiniFiles.config.windows.width_focus = 10')
  local temp_dir = make_temp_dir('temp', { 'a a a a a a a a a a', 'file' })

  open(temp_dir)
  child.expect_screenshot()
end

T['Windows']['correctly computes part of branch to show'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')

  open(make_test_path('nested'))
  for _ = 1, 5 do
    go_in()
  end
  child.expect_screenshot()

  go_out()
  child.expect_screenshot()
  go_out()
  child.expect_screenshot()
  go_out()
  child.expect_screenshot()
  go_out()
  child.expect_screenshot()
  go_out()
  child.expect_screenshot()
end

T['Windows']['is in sync with cursor'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')

  open(make_test_path('nested'))
  go_in()
  go_in()
  go_in()

  -- No trimming when moving left-right
  go_out()
  child.expect_screenshot()
  go_out()
  go_out()
  go_in()
  child.expect_screenshot()

  -- Trims everything to the right when going up-down
  type_keys('j')
  child.expect_screenshot()

  -- Also trims if cursor is moved in Insert mode
  go_out()
  child.expect_screenshot()
  type_keys('o')
  child.expect_screenshot()
end

T['Windows']['properly previews'] = function()
  child.lua('MiniFiles.config.windows.preview = true')
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')

  -- Should open preview right after `open()`
  open(test_dir_path)
  child.expect_screenshot()

  -- Should update preview after cursor move
  type_keys('j')
  child.expect_screenshot()

  -- Should open preview right after `go_in()`
  go_in()
  child.expect_screenshot()

  -- Should not open preview for files
  go_in()
  child.expect_screenshot()

  -- Should keep opened windows until next preview is active
  go_out()
  go_out()
  child.expect_screenshot()
end

T['Windows']['handles preview for user created lines'] = function()
  child.lua('MiniFiles.config.windows.preview = true')

  open(test_dir_path)
  type_keys('o', 'new_entry', '<Esc>')
  type_keys('k')

  child.expect_screenshot()
  type_keys('j')
  child.expect_screenshot()
  type_keys('j')
  child.expect_screenshot()
end

T['Windows']['reacts on `VimResized`'] = function()
  open(test_dir_path)
  go_in()

  -- Decreasing width
  child.o.columns = 60
  child.expect_screenshot()

  -- Increasing width
  child.o.columns = 80
  child.expect_screenshot()

  -- Decreasing height
  child.o.lines = 8
  child.expect_screenshot()

  -- Increasing height
  child.o.lines = 15
  child.expect_screenshot()
end

T['Windows']['works with too small dimensions'] = function()
  child.set_size(8, 15)
  open(test_dir_path)
  child.expect_screenshot()
end

T['Windows']['respects tabline when computing position'] = function()
  child.o.showtabline = 2
  open(test_dir_path)
  child.expect_screenshot()
end

T['Windows']['respects tabline and statusline when computing height'] = function()
  child.set_size(8, 60)

  local validate = function()
    open(test_dir_path)
    child.expect_screenshot()
    close()
  end

  child.o.showtabline, child.o.laststatus = 2, 2
  validate()

  child.o.showtabline, child.o.laststatus = 0, 2
  validate()

  child.o.showtabline, child.o.laststatus = 2, 0
  validate()

  child.o.showtabline, child.o.laststatus = 0, 0
  validate()
end

T['Windows']['uses correct UI highlight groups'] = function()
  local validate_winhl_match = function(win_id, from_hl, to_hl)
    -- Setting non-existing highlight group in 'winhighlight' is not supported
    -- in Neovim=0.7
    if child.fn.has('nvim-0.8') == 0 and from_hl == 'FloatTitle' then return end

    local winhl = child.api.nvim_win_get_option(win_id, 'winhighlight')

    -- Make sure entry is match in full
    local base_pattern = from_hl .. ':' .. to_hl
    local is_matched = winhl:find(base_pattern .. ',') ~= nil or winhl:find(base_pattern .. '$') ~= nil
    eq(is_matched, true)
  end

  open(test_dir_path)
  local win_id_1 = child.api.nvim_get_current_win()
  go_in()
  local win_id_2 = child.api.nvim_get_current_win()

  validate_winhl_match(win_id_1, 'NormalFloat', 'MiniFilesNormal')
  validate_winhl_match(win_id_1, 'FloatBorder', 'MiniFilesBorder')
  validate_winhl_match(win_id_1, 'FloatTitle', 'MiniFilesTitle')
  validate_winhl_match(win_id_2, 'NormalFloat', 'MiniFilesNormal')
  validate_winhl_match(win_id_2, 'FloatBorder', 'MiniFilesBorder')
  validate_winhl_match(win_id_2, 'FloatTitle', 'MiniFilesTitleFocused')

  -- Simply going in Insert mode should not add "modified"
  type_keys('i')
  validate_winhl_match(win_id_2, 'FloatBorder', 'MiniFilesBorder')
  validate_winhl_match(win_id_2, 'FloatBorder', 'MiniFilesBorder')

  type_keys('x')
  validate_winhl_match(win_id_1, 'FloatBorder', 'MiniFilesBorder')
  validate_winhl_match(win_id_2, 'FloatBorder', 'MiniFilesBorderModified')
end

T['Windows']['uses correct content highlight groups'] = function()
  open(test_dir_path)
  --stylua: ignore
  eq(
    get_extmarks_hl(),
    {
      "MiniFilesDirectory", "MiniFilesDirectory",
      "MiniFilesDirectory", "MiniFilesDirectory",
      "MiniFilesDirectory", "MiniFilesDirectory",
      "MiniFilesFile",      "MiniFilesFile",
      "MiniFilesFile",      "MiniFilesFile",
      "MiniFilesFile",      "MiniFilesFile",
      "MiniFilesFile",      "MiniFilesFile",
    }
  )
end

T['Windows']['correctly highlight content during editing'] = function()
  open(test_dir_path)
  type_keys('C', 'new-dir', '<Esc>')
  -- Highlighting of typed text should be the same as directories
  -- - Move cursor away for cursorcolumn to not obstruct the view
  type_keys('G')
  child.expect_screenshot()
end

T['Windows']['can be closed manually'] = function()
  open(test_dir_path)
  child.cmd('wincmd l | only')
  validate_n_wins(1)

  open(test_dir_path)
  validate_n_wins(2)

  close(test_dir_path)
  validate_n_wins(1)
end

T['Mappings'] = new_set()

T['Mappings']['`close` works'] = function()
  -- Both with default and custom one
  MiniTest.skip()
end

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

T['File manipulation']['respects modified hidden buffers'] = function() MiniTest.skip() end

T['File manipulation']['never shows past end of buffer'] = function() MiniTest.skip() end

T['File manipulation']['works to create'] = function() MiniTest.skip() end

T['File manipulation']['creates nested directories'] = function() MiniTest.skip() end

T['File manipulation']['works to delete'] = function() MiniTest.skip() end

T['File manipulation']['works to rename'] = function() MiniTest.skip() end

T['File manipulation']['works to copy'] = function() MiniTest.skip() end

T['File manipulation']['copies directory inside its child'] = function() MiniTest.skip() end

T['File manipulation']['works to move'] = function() MiniTest.skip() end

T['File manipulation']['handles move directory inside its child'] = function() MiniTest.skip() end

T['Cursors'] = new_set()

T['Cursors']['preserved during navigation'] = function() MiniTest.skip() end

T['Cursors']['preserved after hiding buffer'] = function() MiniTest.skip() end

T['Cursors']['preserved after opening from history'] = function() MiniTest.skip() end

T['Cursors']['not allowed to the left of the entry name in Normal mode'] = function() MiniTest.skip() end

T['Cursors']['not allowed to the left of the entry name in Insert mode'] = function() MiniTest.skip() end

T['Cursors']['shows whole line after moving to line start'] = function() MiniTest.skip() end

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
