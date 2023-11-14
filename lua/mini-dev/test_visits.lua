local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('visits', config) end
local unload_module = function() child.mini_unload('visits') end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
local edit = function(path) child.cmd('edit ' .. child.fn.fnameescape(path)) end
--stylua: ignore end

-- Test paths helpers
local join_path = function(...) return table.concat({ ... }, '/') end

local full_path = function(x)
  local res = child.fn.fnamemodify(x, ':p'):gsub('(.)/$', '%1')
  return res
end

local test_dir = 'tests/dir-visits'
local test_dir_absolute = vim.fn.fnamemodify(test_dir, ':p'):gsub('(.)/$', '%1')

local make_testpath = function(...) return join_path(test_dir_absolute, ...) end

local cleanup_dirs = function()
  -- Clean up any possible side effects in `XDG_DATA_HOME` directory
  vim.fn.delete(join_path(test_dir, 'nvim'), 'rf')
end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local get_index = forward_lua('MiniVisits.get_index')

-- Common test helpers
local validate_buf_name = function(buf_id, name)
  buf_id = buf_id or child.api.nvim_get_current_buf()
  name = name ~= '' and full_path(name) or ''
  name = name:gsub('/+$', '')
  eq(child.api.nvim_buf_get_name(buf_id), name)
end

local validate_partial_equal_arr = function(test_arr, ref_arr)
  -- Same length
  eq(#test_arr, #ref_arr)

  -- Partial values
  local test_arr_mod = {}
  for i = 1, #ref_arr do
    local test_with_ref_keys = {}
    for key, _ in pairs(ref_arr[i]) do
      test_with_ref_keys[key] = test_arr[i][key]
    end
    test_arr_mod[i] = test_with_ref_keys
  end
  eq(test_arr_mod, ref_arr)
end

local validate_partial_equal = function(test_tbl, ref_tbl)
  eq(type(test_tbl), 'table')

  local test_with_ref_keys = {}
  for key, _ in pairs(ref_tbl) do
    test_with_ref_keys[key] = test_tbl[key]
  end
  eq(test_with_ref_keys, ref_tbl)
end

local validate_index_entry = function(cwd, path, ref)
  local index = child.lua_get('MiniVisits.get_index()')
  local out = (index[full_path(cwd)] or {})[full_path(path)]
  if ref == nil then
    eq(out, nil)
  else
    validate_partial_equal(out, ref)
  end
end

local validate_index = function(index_out, index_ref)
  -- Convert to absolute paths (beware that this depends on current directory)
  local index_ref_compare = {}
  for cwd, cwd_tbl in pairs(index_ref) do
    local cwd_tbl_ref_compare = {}
    for path, path_tbl in pairs(cwd_tbl) do
      cwd_tbl_ref_compare[full_path(path)] = path_tbl
    end
    index_ref_compare[full_path(cwd)] = cwd_tbl_ref_compare
  end

  eq(index_out, index_ref)
end

-- Data =======================================================================
local test_index = {
  [make_testpath('dir_1')] = {
    [make_testpath('dir_1', 'file_1-1')] = { count = 1, latest = os.time() },
    [make_testpath('dir_1', 'file_1-2')] = { count = 2, latest = os.time() + 1 },
  },
  [make_testpath('dir_2')] = {
    [make_testpath('dir_2', 'file_2-1')] = { count = 3, latest = os.time() + 3 },
    [make_testpath('dir_1', 'file_1-2')] = { count = 4, latest = os.time() + 4 },
  },
}

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      cleanup_dirs()

      -- Make `stdpath('data')` point to test directory
      local lua_cmd = string.format([[vim.loop.os_setenv('XDG_DATA_HOME', %s)]], vim.inspect(test_dir))
      child.lua(lua_cmd)

      -- Load module
      load_module()

      -- Make more comfortable screenshots
      child.set_size(15, 40)
      child.o.laststatus = 0
      child.o.ruler = false
    end,
    post_once = function()
      child.stop()
      cleanup_dirs()
    end,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniVisits)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniVisits'), 1)
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniVisits.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniVisits.config.' .. field), value) end

  expect_config('list.filter', vim.NIL)
  expect_config('list.filter', vim.NIL)

  expect_config('silent', false)

  expect_config('store.autowrite', true)
  expect_config('store.normalize', vim.NIL)
  expect_config('store.path', child.fn.stdpath('data') .. '/mini-visits-index')

  expect_config('track.event', 'BufEnter')
  expect_config('track.delay', 1000)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ silent = true })
  eq(child.lua_get('MiniVisits.config.silent'), true)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ list = 'a' }, 'list', 'table')
  expect_config_error({ list = { filter = 'a' } }, 'list.filter', 'function')
  expect_config_error({ list = { sort = 'a' } }, 'list.sort', 'function')

  expect_config_error({ silent = 'a' }, 'silent', 'boolean')

  expect_config_error({ store = 'a' }, 'store', 'table')
  expect_config_error({ store = { autowrite = 'a' } }, 'store.autowrite', 'boolean')
  expect_config_error({ store = { normalize = 'a' } }, 'store.normalize', 'function')
  expect_config_error({ store = { path = 1 } }, 'store.path', 'string')

  expect_config_error({ track = 'a' }, 'track', 'table')
  expect_config_error({ track = { event = 1 } }, 'track.event', 'string')
  expect_config_error({ track = { delay = 'a' } }, 'track.delay', 'number')
end

T['register_visit()'] = new_set()

local register_visit = forward_lua('MiniVisits.register_visit')

T['register_visit()']['works'] = function()
  -- Should not check if arguments represent present paths on disk
  local dir_full, dir_2_full = full_path('dir'), full_path('dir-2')
  local file_full, file_2_full = full_path('file'), full_path('dir/file-2')

  -- Should create entry if it is not present treating input as file system
  -- entries (relative to current directory in this case)
  eq(get_index(), {})
  register_visit('file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 1, latest = os.time() } } })

  register_visit('file', 'dir')
  local latest_1 = os.time()
  eq(get_index(), { [dir_full] = { [file_full] = { count = 2, latest = latest_1 } } })

  register_visit('dir/file-2', 'dir')
  local latest_2 = os.time()
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 2, latest = latest_1 },
      [file_2_full] = { count = 1, latest = latest_2 },
    },
  })

  register_visit('file', 'dir-2')
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 2, latest = latest_1 },
      [file_2_full] = { count = 1, latest = latest_2 },
    },
    [dir_2_full] = {
      [file_full] = { count = 1, latest = os.time() },
    },
  })
end

T['register_visit()']['uses current data as defaults'] = function()
  local path = make_testpath('file')
  edit(path)
  register_visit()
  eq(get_index(), { [child.fn.getcwd()] = { [path] = { count = 1, latest = os.time() } } })
end

T['register_visit()']['handles paths with "~" for home directory'] = function()
  register_visit('~/file', '~/dir')
  local home_dir = child.loop.os_homedir()
  eq(
    get_index(),
    { [join_path(home_dir, 'dir')] = { [join_path(home_dir, 'file')] = { count = 1, latest = os.time() } } }
  )
end

T['register_visit()']['does not affect other stored data'] = function()
  local path, cwd = make_testpath('file'), test_dir_absolute
  child.lua([[MiniVisits.set_index(...)]], { { [cwd] = { [path] = { count = 0, latest = 0, aaa = { bbb = true } } } } })
  register_visit(path, cwd)
  eq(get_index(), { [cwd] = { [path] = { count = 1, latest = os.time(), aaa = { bbb = true } } } })
end

T['register_visit()']['validates arguments'] = function()
  local validate = function(error_pattern, ...)
    local args = { ... }
    expect.error(function() register_visit(unpack(args)) end, error_pattern)
  end

  validate('`path`.*string', 1, 'dir')
  validate('`cwd`.*string', 'file', 1)
  validate('`path` and `cwd`.*not.*empty', '', 'dir')
  validate('`path` and `cwd`.*not.*empty', 'file', '')
end

T['add_path()'] = new_set()

local add_path = forward_lua('MiniVisits.add_path')

T['add_path()']['works'] = function()
  -- Should not check if arguments represent present paths on disk
  local dir_full = full_path('dir')
  local file_full, file_2_full = full_path('file'), full_path('file-2')

  add_path('file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, latest = 0 } } })

  -- Should do nothing if path-cwd already exists
  add_path('file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, latest = 0 } } })

  add_path('file-2', 'dir')
  eq(
    get_index(),
    { [dir_full] = { [file_full] = { count = 0, latest = 0 }, [file_2_full] = { count = 0, latest = 0 } } }
  )
end

T['add_path()']['works with empty string arguments'] = function()
  local dir_full, dir_2_full = full_path('dir'), full_path('dir-2')
  local file_full, file_2_full = full_path('file'), full_path('file-2')
  local init_tbl = { count = 0, latest = 0 }

  -- If no visits, should result into no added paths
  add_path('', 'dir')
  eq(get_index(), {})
  add_path('file', '')
  eq(get_index(), {})
  add_path('', '')
  eq(get_index(), {})

  -- Empty string for `path` should mean "add all present paths in cwd".
  -- Not useful, but should be allowed for consistency with other functions.
  add_path('file', 'dir')
  add_path('', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = init_tbl } })

  -- Empty string for `cwd` should mean "add path to all visited cwds".
  add_path('file', 'dir-2')
  add_path('file-2', '')
  eq(get_index(), {
    [dir_full] = { [file_full] = init_tbl, [file_2_full] = init_tbl },
    [dir_2_full] = { [file_full] = init_tbl, [file_2_full] = init_tbl },
  })
end

T['add_path()']['uses current data as defaults'] = function()
  local path = make_testpath('file')
  edit(path)
  add_path()
  eq(get_index(), { [child.fn.getcwd()] = { [path] = { count = 0, latest = 0 } } })
end

T['add_path()']['does not affect other stored data'] = function()
  local path, cwd = make_testpath('file'), test_dir_absolute
  child.lua([[MiniVisits.set_index(...)]], { { [cwd] = { [path] = { count = 0, latest = 0, aaa = { bbb = true } } } } })
  add_path(path, cwd)
  eq(get_index(), { [cwd] = { [path] = { count = 0, latest = 0, aaa = { bbb = true } } } })
end

T['add_path()']['validates arguments'] = function()
  expect.error(function() add_path(1, 'dir') end, '`path`.*string')
  expect.error(function() add_path('file', 1) end, '`cwd`.*string')
end

T['add_label()'] = new_set()

local add_label = forward_lua('MiniVisits.add_label')

T['add_label()']['works'] = function() MiniTest.skip() end

T['add_label()']['validates arguments'] = function() MiniTest.skip() end

T['remove_path()'] = new_set()

local remove_path = forward_lua('MiniVisits.remove_path')

T['remove_path()']['works'] = function() MiniTest.skip() end

T['remove_path()']['validates arguments'] = function() MiniTest.skip() end

T['remove_label()'] = new_set()

local remove_label = forward_lua('MiniVisits.remove_label')

T['remove_label()']['works'] = function() MiniTest.skip() end

T['remove_label()']['validates arguments'] = function() MiniTest.skip() end

T['list_paths()'] = new_set()

local list_paths = forward_lua('MiniVisits.list_paths')

T['list_paths()']['works'] = function() MiniTest.skip() end

T['list_paths()']['validates arguments'] = function() MiniTest.skip() end

T['list_labels()'] = new_set()

local list_labels = forward_lua('MiniVisits.list_labels')

T['list_labels()']['works'] = function() MiniTest.skip() end

T['list_labels()']['validates arguments'] = function() MiniTest.skip() end

T['select_path()'] = new_set()

local select_path = forward_lua('MiniVisits.select_path')

T['select_path()']['works'] = function() MiniTest.skip() end

T['select_path()']['validates arguments'] = function() MiniTest.skip() end

T['select_label()'] = new_set()

local select_label = forward_lua('MiniVisits.select_label')

T['select_label()']['works'] = function() MiniTest.skip() end

T['select_label()']['validates arguments'] = function() MiniTest.skip() end

T['goto_path()'] = new_set()

local goto_path = forward_lua('MiniVisits.goto_path')

T['goto_path()']['works'] = function() MiniTest.skip() end

T['goto_path()']['validates arguments'] = function() MiniTest.skip() end

T['get_index()'] = new_set()

T['get_index()']['works'] = function() MiniTest.skip() end

T['get_index()']['validates arguments'] = function() MiniTest.skip() end

T['set_index()'] = new_set()

local set_index = forward_lua('MiniVisits.set_index')

T['set_index()']['works'] = function() MiniTest.skip() end

T['set_index()']['validates arguments'] = function() MiniTest.skip() end

T['reset_index()'] = new_set()

local reset_index = forward_lua('MiniVisits.reset_index')

T['reset_index()']['works'] = function() MiniTest.skip() end

T['reset_index()']['validates arguments'] = function() MiniTest.skip() end

T['normalize_index()'] = new_set()

local normalize_index = forward_lua('MiniVisits.normalize_index')

T['normalize_index()']['works'] = function() MiniTest.skip() end

T['normalize_index()']['validates arguments'] = function() MiniTest.skip() end

T['read_index()'] = new_set()

local read_index = forward_lua('MiniVisits.read_index')

T['read_index()']['works'] = function() MiniTest.skip() end

T['read_index()']['validates arguments'] = function() MiniTest.skip() end

T['write_index()'] = new_set()

local write_index = forward_lua('MiniVisits.write_index')

T['write_index()']['works'] = function() MiniTest.skip() end

T['write_index()']['validates arguments'] = function() MiniTest.skip() end

T['gen_filter'] = new_set()

T['gen_filter']['default()'] = new_set()

T['gen_filter']['default()']['works'] = function() MiniTest.skip() end

T['gen_filter']['this_session()'] = new_set()

T['gen_filter']['this_session()']['works'] = function() MiniTest.skip() end

T['gen_sort'] = new_set()

T['gen_sort']['default()'] = new_set()

T['gen_sort']['default()']['works'] = function() MiniTest.skip() end

T['gen_sort']['z()'] = new_set()

T['gen_sort']['z()']['works'] = function() MiniTest.skip() end

T['gen_normalize'] = new_set()

T['gen_normalize']['default()'] = new_set()

T['gen_normalize']['default()']['works'] = function() MiniTest.skip() end

-- Integration tests ----------------------------------------------------------
T['Tracking'] = new_set()

T['Tracking']['works'] = function()
  local path, path_2 = make_testpath('file'), make_testpath('dir1', 'file1-1')

  edit(path)
  eq(get_index(), {})

  sleep(980)
  eq(get_index(), {})

  -- Should implement debounce style delay
  edit(path_2)
  sleep(980)
  eq(get_index(), {})
  sleep(20)
  -- - "Latest" time should use time of actual registration
  local latest = os.time()

  -- Sleep small time to reduce flakiness
  sleep(5)
  eq(get_index(), { [child.fn.getcwd()] = { [path_2] = { count = 1, latest = latest } } })
end

T['Tracking']['registers only normal buffers'] = function()
  child.lua('MiniVisits.config.track.delay = 10')

  -- Scratch buffer
  local buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(buf_id)
  sleep(10 + 5)
  eq(get_index(), {})

  -- Help buffer
  child.cmd('help')
  sleep(10 + 5)
  eq(get_index(), {})
end

T['Tracking']['can register directories'] = function()
  child.lua('MiniVisits.config.track.delay = 10')

  local path = make_testpath('dir1')
  edit(path)
  sleep(10 + 5)
  validate_index_entry('', path, { count = 1 })
end

T['Tracking']['does not register same path twice in a row'] = function()
  child.lua('MiniVisits.config.track.delay = 10')

  local path = make_testpath('file')
  edit(path)
  sleep(10 + 5)
  validate_index_entry('', path, { count = 1 })

  child.cmd('help')
  sleep(10 + 5)
  validate_index_entry('', path, { count = 1 })

  edit(path)
  sleep(10 + 5)
  validate_index_entry('', path, { count = 1 })
end

T['Tracking']['is done on `BufEnter` by default'] = function()
  child.lua('MiniVisits.config.track.delay = 10')

  local path, path_2 = make_testpath('file'), make_testpath('dir1', 'file1-1')
  edit(path)
  sleep(10 + 5)

  child.cmd('vertical split | edit ' .. child.fn.fnameescape(path_2))
  sleep(10 + 5)

  -- Going back and forth should count as visits
  child.cmd('wincmd w')
  sleep(10 + 5)
  child.cmd('wincmd w')
  sleep(10 + 5)

  validate_index_entry('', path, { count = 2 })
  validate_index_entry('', path_2, { count = 2 })
end

T['Tracking']['respects `config.track.event`'] = function()
  child.cmd('autocmd! MiniVisits')
  load_module({ track = { event = 'BufHidden', delay = 10 } })

  local path = make_testpath('file')
  edit(path)
  sleep(10 + 5)
  eq(get_index(), {})

  child.api.nvim_set_current_buf(child.api.nvim_create_buf(false, true))
  sleep(10 + 5)
  validate_index_entry('', path, { count = 1 })
end

T['Tracking']['can have `config.track.event = ""` to disable tracking'] = function()
  child.cmd('autocmd! MiniVisits')
  load_module({ track = { event = '', delay = 10 } })
  eq(child.cmd_capture('au MiniVisits'):find('BufEnter'), nil)

  local path = make_testpath('file')
  edit(path)
  sleep(10 + 5)
  eq(get_index(), {})
end

T['Tracking']['can have `config.track.delay = 0`'] = function()
  child.lua('MiniVisits.config.track.delay = 0')
  local path = make_testpath('file')
  edit(path)
  validate_index_entry('', path, { count = 1 })
end

T['Tracking']['respects `vim.{g,b}.minivisits_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child.lua('MiniVisits.config.track.delay = 10')
    local path, path_2 = make_testpath('file'), make_testpath('dir1', 'file1-1')

    -- Setting variable after event but before delay expired should work
    edit(path)
    sleep(1)
    child[var_type].minivisits_disable = true
    sleep(9 + 5)
    eq(get_index(), {})

    -- Global variable should disable globally, buffer - per buffer
    edit(path_2)
    sleep(10 + 5)
    if var_type == 'g' then
      eq(get_index(), {})
    else
      validate_index_entry('', path_2, { count = 1 })
    end

    -- Buffer-local variable should still work
    edit(path)
    sleep(10 + 5)
    validate_index_entry('', path, nil)
  end,
})

T['Storing'] = new_set()

T['Storing']['works'] = function()
  child.cmd('doautocmd VimLeavePre')
  local store_path = child.lua_get('MiniVisits.config.store.path')
  eq(child.fn.readfile(store_path), { 'return {}' })
end

T['Storing']['respects `config.store.autowrite`'] = function()
  -- Should be respected even if set after `setup()`
  child.lua('MiniVisits.config.store.autowrite = false')
  child.cmd('doautocmd VimLeavePre')
  local store_path = child.lua_get('MiniVisits.config.store.path')
  eq(child.fn.filereadable(store_path), 0)
end

T['Storing']['respects `config.store.normalize`'] = function()
  child.lua([[MiniVisits.config.store.normalize = function(...)
    _G.normalize_args = { ... }
    return { dir = { file = { count = 10, latest = 100 } } }
  end]])
  child.cmd('doautocmd VimLeavePre')
  local store_path = child.lua_get('MiniVisits.config.store.path')
  eq(
    table.concat(child.fn.readfile(store_path), '\n'),
    'return {\n  dir = {\n    file = {\n      count = 10,\n      latest = 100\n    }\n  }\n}'
  )

  eq(child.lua_get('_G.normalize_args'), { {} })
end

T['Storing']['respects `config.store.path`'] = function()
  local store_path = make_testpath('test-index')
  MiniTest.finally(function() vim.fn.delete(store_path) end)
  child.lua('MiniVisits.config.store.path = ' .. vim.inspect(store_path))

  child.stop()
  eq(vim.fn.readfile(store_path), { 'return {}' })
end

return T
