local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('notify', config) end
local unload_module = function() child.mini_unload('notify') end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

local test_dir = 'tests/dir-visits'
local test_dir_absolute = vim.fn.fnamemodify(test_dir, ':p'):gsub('(.)/$', '%1')

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local get = forward_lua('MiniNotify.get')

-- Common mocks
local mock_no_format = function() child.lua('MiniNotify.config.content.format = function(notif) return notif.msg end') end

local mock_lsp_progress_handler = function()
  -- TODO
end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()

      -- Load module
      load_module()

      -- Make more comfortable screenshots
      child.set_size(7, 25)
      child.o.laststatus = 0
      child.o.ruler = false
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniNotify)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniNotify'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniNotifyBorder', 'links to FloatBorder')
  has_highlight('MiniNotifyNormal', 'links to NormalFloat')
  has_highlight('MiniNotifyTitle', 'links to FloatTitle')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniNotify.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniNotify.config.' .. field), value) end

  expect_config('content.format', vim.NIL)
  expect_config('content.sort', vim.NIL)

  expect_config('lsp_progress.enable', true)
  expect_config('lsp_progress.duration_last', 1000)

  expect_config('window.config', {})
  expect_config('window.winblend', 25)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ window = { winblend = 0 } })
  eq(child.lua_get('MiniNotify.config.window.winblend'), 0)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ content = 'a' }, 'content', 'table')
  expect_config_error({ content = { format = 'a' } }, 'content.format', 'function')
  expect_config_error({ content = { sort = 'a' } }, 'content.sort', 'function')

  expect_config_error({ lsp_progress = 'a' }, 'lsp_progress', 'table')
  expect_config_error({ lsp_progress = { enable = 'a' } }, 'lsp_progress.enable', 'boolean')
  expect_config_error({ lsp_progress = { duration_last = 'a' } }, 'lsp_progress.duration_last', 'number')

  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { config = 'a' } }, 'window.config', 'table or callable')
  expect_config_error({ window = { winblend = 'a' } }, 'window.winblend', 'number')
end

T['make_notify()'] = new_set()

local make_notify = forward_lua('MiniNotify.make_notify')

T['make_notify()']['works'] = function() MiniTest.skip() end

T['add()'] = new_set()

local add = forward_lua('MiniNotify.add')

T['add()']['works'] = function()
  mock_no_format()

  local cur_ts = vim.loop.gettimeofday()
  local id = add('Hello')

  -- Should return notification identifier number
  eq(type(id), 'number')

  -- Should show notification in a floating window
  child.expect_screenshot()

  -- Should add proper notification object to history
  local notif = get(id)
  local notif_fields = vim.tbl_keys(notif)
  table.sort(notif_fields)
  eq(notif_fields, { 'hl_group', 'level', 'msg', 'ts_add', 'ts_update' })

  eq(notif.msg, 'Hello')

  -- Non-message arguments should have defaults
  eq(notif.level, 'INFO')
  eq(notif.hl_group, 'MiniNotifyNormal')

  -- Timestamp fields should use Unix time
  eq(math.abs(cur_ts - notif.ts_add) <= 1, true)
  eq(notif.ts_update, notif.ts_add)
end

T['add()']['respects arguments'] = function()
  local validate = function(level)
    local id = add('Hello', level, 'Comment')
    eq(get(id).level, level)
    eq(get(id).hl_group, 'Comment')
  end

  validate('ERROR')
  validate('WARN')
  validate('INFO')
  validate('DEBUG')
  validate('TRACE')
  if child.fn.has('nvim-0.8') == 1 then validate('OFF') end
end

T['add()']['validates arguments'] = function()
  expect.error(function() add(1, 'ERROR', 'Comment') end, '`msg`.*string')
  expect.error(function() add('Hello', 1, 'Comment') end, '`level`.*key of `vim%.log%.levels`')
  expect.error(function() add('Hello', 'Error', 'Comment') end, '`level`.*key of `vim%.log%.levels`')
  expect.error(function() add('Hello', 'ERROR', 1) end, '`hl_group`.*string')
end

T['update()'] = new_set()

local update = forward_lua('MiniNotify.update')

T['update()']['works'] = function()
  mock_no_format()

  local id = add('Hello', 'ERROR', 'Comment')
  child.expect_screenshot()
  local init_notif = get(id)

  update(id, { msg = 'World', level = 'WARN', hl_group = 'String' })

  -- Should show updated notification in a floating window
  child.expect_screenshot()

  -- Should properly update notification object in history
  local notif = get(id)

  eq(notif.msg, 'World')
  eq(notif.level, 'WARN')
  eq(notif.hl_group, 'String')

  -- Add time should be untouched
  eq(notif.ts_add, init_notif.ts_add)

  -- Update time should be increased
  eq(init_notif.ts_update < notif.ts_update, true)
end

T['update()']['allows partial new data'] = function()
  local id = add('Hello', 'ERROR', 'Comment')
  update(id, { msg = 'World' })
  local notif = get(id)
  eq(notif.msg, 'World')
  eq(notif.level, 'ERROR')
  eq(notif.hl_group, 'Comment')

  -- Empty table
  update(id, {})
  eq(notif.msg, 'World')
  eq(notif.level, 'ERROR')
  eq(notif.hl_group, 'Comment')
end

T['update()']['can update only active notification'] = function()
  local id = child.lua([[
    local id = MiniNotify.add('Hello')
    MiniNotify.remove(id)
    return id
  ]])
  expect.error(function() update(id, { msg = 'World' }) end, '`id`.*not.*active')
end

T['update()']['validates arguments'] = function()
  local id = add('Hello')
  expect.error(function() update('a', { msg = 'World' }) end, '`id`.*identifier')
  expect.error(function() update(id, 1) end, '`new_data`.*table')
  expect.error(function() update(id, { msg = 1 }) end, '`msg`.*string')
  expect.error(function() update(id, { level = 1 }) end, '`level`.*key of `vim%.log%.levels`')
  expect.error(function() update(id, { level = 'Error' }) end, '`level`.*key of `vim%.log%.levels`')
  expect.error(function() update(id, { hl_group = 1 }) end, '`hl_group`.*string')
end

T['remove()'] = new_set()

local remove = forward_lua('MiniNotify.remove')

T['remove()']['works'] = function()
  mock_no_format()

  local id = add('Hello', 'ERROR', 'Comment')
  child.expect_screenshot()
  local init_notif = get(id)
  eq(init_notif.ts_remove, nil)

  local cur_ts = vim.loop.gettimeofday()
  remove(id)

  -- Should update notification window (and remove it completely in this case)
  child.expect_screenshot()

  -- Should only udpate `ts_remove` field
  local notif = get(id)

  eq(math.abs(cur_ts - notif.ts_remove) <= 1, true)

  init_notif.ts_remove, notif.ts_remove = nil, nil
  eq(init_notif, notif)
end

T['remove()']['works with several active notifications'] = function()
  mock_no_format()

  local id_1 = add('Hello', 'ERROR', 'Comment')
  local id_2 = add('World', 'ERROR', 'String')
  child.expect_screenshot()

  remove(id_2)
  child.expect_screenshot()

  eq(get(id_1).ts_remove, nil)
  eq(type(get(id_2).ts_remove), 'number')
end

T['remove()']['does nothing on not proper input'] = function()
  local id = add('Hello', 'ERROR', 'Comment')
  local validate = function(...)
    local args = { ... }
    expect.no_error(function() remove(unpack(args)) end)
  end

  validate(nil)
  validate(id + 1)
  validate('a')
end

T['clear()'] = new_set()

local clear = forward_lua('MiniNotify.clear')

T['clear()']['works'] = function()
  mock_no_format()

  local id_1 = add('Hello', 'ERROR', 'Comment')
  local id_2 = add('World', 'ERROR', 'String')
  child.expect_screenshot()

  clear()
  child.expect_screenshot()

  eq(type(get(id_1).ts_remove), 'number')
  eq(type(get(id_2).ts_remove), 'number')
end

T['clear()']['affects only active notifications'] = function()
  local id_1 = add('Hello', 'ERROR', 'Comment')
  local id_2 = add('World', 'ERROR', 'String')
  remove(id_1)
  local ts_remove_1 = get(id_1).ts_remove
  eq(type(ts_remove_1), 'number')
  eq(get(id_2).ts_remove, nil)

  clear()
  eq(get(id_1).ts_remove, ts_remove_1)
  local ts_remove_2 = get(id_2).ts_remove
  eq(type(ts_remove_2), 'number')
  eq(ts_remove_1 < ts_remove_2, true)
end

T['refresh()'] = new_set()

local refresh = forward_lua('MiniNotify.refresh')

T['refresh()']['works'] = function() MiniTest.skip() end

T['refresh()']['respects `vim.{g,b}.mininotify_disable`'] = new_set({ parametrize = { { 'g' }, { 'b' } } }, {
  test = function(var_type)
    -- TODO
  end,
})

T['get()'] = new_set()

T['get()']['returns copy'] = function()
  local res = child.lua([[
    local id = MiniNotify.add('Hello')
    local notif = MiniNotify.get(id)
    notif.msg = 'Should not change history'
    return MiniNotify.get(id).msg == 'Hello'
  ]])
  eq(res, true)
end

T['get_all()'] = new_set()

local get_all = forward_lua('MiniNotify.get_all')

T['get_all()']['works'] = function()
  local id_1 = add('Hello')
  local id_2 = add('World')
  remove(id_2)

  local history = get_all()
  eq(vim.tbl_count(history), 2)

  eq(history[id_1].msg, 'Hello')
  eq(history[id_2].msg, 'World')
end

T['get_all()']['returns copy'] = function()
  local res = child.lua([[
    local id_1 = MiniNotify.add('Hello')
    local id_2 = MiniNotify.add('World')
    local history = MiniNotify.get_all()
    history[id_1].msg = 'Should not change history'
    history[id_2].msg = 'Nowhere'

    local new_history = MiniNotify.get_all()
    return new_history[id_1].msg == 'Hello' and new_history[id_2].msg == 'World'
  ]])
  eq(res, true)
end

T['show_history()'] = new_set()

local show_history = forward_lua('MiniNotify.show_history')

T['show_history()']['works'] = function() MiniTest.skip() end

T['default_format()'] = new_set()

local default_format = forward_lua('MiniNotify.default_format')

T['default_format()']['works'] = function() MiniTest.skip() end

T['default_sort()'] = new_set()

local default_sort = forward_lua('MiniNotify.default_sort')

T['default_sort()']['works'] = function() MiniTest.skip() end

T['default_sort()']['does not affect input'] = function() MiniTest.skip() end

-- Integration tests ----------------------------------------------------------
T['Window'] = new_set()

T['Window']['works'] = function() MiniTest.skip() end

T['Window']['persists in new tabpage'] = function() MiniTest.skip() end

T['Window']['respects tabline/statusline/cmdline'] = function() MiniTest.skip() end

T['Window']['uses notification `hl_group` to highlight its lines'] = function() MiniTest.skip() end

T['Window']['computes default dimensions based on buffer content'] = function() MiniTest.skip() end

T['Window']['handles width computation for empty lines inside notification'] = function() MiniTest.skip() end

T['Window']['handles notification with empty string message'] = function() MiniTest.skip() end

T['LSP progress'] = new_set()

T['LSP progress']['works'] = function() MiniTest.skip() end

return T
