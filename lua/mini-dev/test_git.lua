local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('git', config) end
local unload_module = function(config) child.mini_unload('git', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
local new_buf = function() return child.api.nvim_create_buf(true, false) end
local new_scratch_buf = function() return child.api.nvim_create_buf(false, true) end
local get_buf = function() return child.api.nvim_get_current_buf() end
local set_buf = function(buf_id) child.api.nvim_set_current_buf(buf_id) end
local edit = function(path) child.cmd('edit ' .. child.fn.fnameescape(path)) end
--stylua: ignore end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
local islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

local test_dir = 'tests/dir-git'
local test_dir_absolute = vim.fn.fnamemodify(test_dir, ':p'):gsub('(.)/$', '%1')

local git_repo_dir = test_dir_absolute .. '/git-repo'
local git_git_dir = git_repo_dir .. '/.git-dir'
local git_dir_path = git_repo_dir .. '/dir-in-git'
local git_file_basename = 'file-in-git'
local git_file_path = git_repo_dir .. '/dir-in-git/' .. git_file_basename

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local get_buf_data = forward_lua('require("mini-dev.git").get_buf_data')

local is_buf_enabled = function(buf_id) return get_buf_data(buf_id) ~= vim.NIL end

-- Common mocks
local small_time = 10

-- - Git mocks
local mock_change_git_index = function()
  local index_path = git_git_dir .. '/index'
  child.fn.writefile({}, index_path .. '.lock')
  sleep(1)
  child.fn.delete(index_path)
  child.loop.fs_rename(index_path .. '.lock', index_path)
end

local mock_executable = function()
  child.lua([[
    _G.orig_executable = vim.fn.executable
    vim.fn.executable = function(exec) return exec == 'git' and 1 or _G.orig_executable(exec) end
  ]])
end

local mock_spawn = function()
  local mock_file = test_dir_absolute .. '/mocks/spawn.lua'
  local lua_cmd = string.format('dofile(%s)', vim.inspect(mock_file))
  child.lua(lua_cmd)
end

local get_spawn_log = function() return child.lua_get('_G.spawn_log') end

local validate_git_spawn_log = function(ref_log)
  local spawn_log = get_spawn_log()

  local n = math.max(#spawn_log, #ref_log)
  for i = 1, n do
    local real, ref = spawn_log[i], ref_log[i]
    if real == nil then
      eq('Real spawn log does not have entry for present reference log entry', ref)
    elseif ref == nil then
      eq(real, 'Reference does not have entry for present spawn log entry')
    elseif islist(ref) then
      eq(real, { executable = 'git', options = { args = ref, cwd = real.options.cwd } })
    else
      eq(real, { executable = 'git', options = ref })
    end
  end
end

local get_process_log = function() return child.lua_get('_G.process_log') end

-- - Notifications
local mock_notify = function()
  child.lua([[
    _G.notify_log = {}
    vim.notify = function(...) table.insert(_G.notify_log, { ... }) end
  ]])
end

local get_notify_log = function() return child.lua_get('_G.notify_log') end

local validate_notifications = function(ref_log, msg_pattern)
  local notify_log = get_notify_log()
  local n = math.max(#notify_log, #ref_log)
  for i = 1, n do
    local real, ref = notify_log[i], ref_log[i]
    if real == nil then
      eq('Real notify log does not have entry for present reference log entry', ref)
    elseif ref == nil then
      eq(real, 'Reference does not have entry for present notify log entry')
    else
      local expect_msg = msg_pattern and expect.match or eq
      expect_msg(real[1], ref[1])
      eq(real[2], child.lua_get('vim.log.levels.' .. ref[2]))
    end
  end
end

local clear_notify_log = function() return child.lua('_G.notify_log = {}') end

-- Module helpers
local setup_enabled_buffer = function()
  -- Usually used to make tests on not initial (kind of special) buffer
  local init_buf_id = get_buf()
  set_buf(new_buf())
  -- TODO: Needs mocked spawn
  child.lua('require("mini-dev.git").enable(0)')
  child.api.nvim_buf_delete(init_buf_id, { force = true })
end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.set_size(10, 15)
      mock_notify()
      mock_executable()
      load_module()
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniGit)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniGit'), 1)

  -- User command
  eq(child.fn.exists(':Git'), 2)
end

T['setup()']['creates `config` field'] = function()
  load_module()

  eq(child.lua_get('type(_G.MiniGit.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniGit.config.' .. field), value) end

  expect_config('job.git_executable', 'git')
  expect_config('job.timeout', 30000)
  expect_config('command.split', 'auto')
end

T['setup()']['respects `config` argument'] = function()
  load_module({ command = { split = 'vertical' } })
  eq(child.lua_get('MiniGit.config.command.split'), 'vertical')
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ job = 'a' }, 'job', 'table')
  expect_config_error({ job = { git_executable = 1 } }, 'job.git_executable', 'string')
  expect_config_error({ job = { timeout = 'a' } }, 'job.timeout', 'number')

  expect_config_error({ command = 'a' }, 'command', 'table')
  expect_config_error({ command = { split = 1 } }, 'command.split', 'string')
end

T['setup()']['warns about missing executable'] = function()
  load_module({ job = { git_executable = 'no-git-is-available' } })
  validate_notifications({ { '(mini.git) There is no `no-git-is-available` executable', 'WARN' } })
end

T['setup()']['auto enables in all existing buffers'] = function()
  -- local buf_id_normal = new_buf()
  -- set_buf(buf_id_normal)
  --
  -- local buf_id_bad_1 = new_scratch_buf()
  -- local buf_id_bad_2 = new_buf()
  -- child.api.nvim_buf_set_lines(buf_id_bad_2, 0, -1, false, { '\0' })
  --
  -- -- Only normal valid text buffers should be auto enabled
  -- eq(is_buf_enabled(buf_id_normal), true)
  -- eq(is_buf_enabled(buf_id_bad_1), false)
  -- eq(is_buf_enabled(buf_id_bad_2), false)
  MiniTest.skip()
end

T['show_at_cursor()'] = new_set()

T['show_at_cursor()']['works'] = function() MiniTest.skip() end

T['show_diff_source()'] = new_set()

T['show_diff_source()']['works'] = function() MiniTest.skip() end

T['show_range_history()'] = new_set()

T['show_range_history()']['works'] = function() MiniTest.skip() end

T['log_foldexpr()'] = new_set()

T['log_foldexpr()']['works'] = function() MiniTest.skip() end

T['enable()'] = new_set()

local enable = forward_lua('MiniGit.enable')

T['enable()']['works in not normal buffer'] = function()
  -- local buf_id = new_scratch_buf()
  -- set_buf(buf_id)
  -- enable(buf_id)
  MiniTest.skip()
end

T['enable()']['works in not current buffer'] = function()
  -- local buf_id = new_buf()
  -- enable(buf_id)
  -- eq(is_buf_enabled(buf_id), true)
  MiniTest.skip()
end

T['enable()']['normalizes input buffer'] = function()
  -- local buf_id = new_scratch_buf()
  -- set_buf(buf_id)
  -- clean_dummy_log()
  -- enable(0)
  -- eq(is_buf_enabled(buf_id), true)
  MiniTest.skip()
end

T['enable()']['does not re-enable already enabled buffer'] = function()
  -- enable()
  -- validate_dummy_log({})
  MiniTest.skip()
end

T['enable()']['makes sure buffer is loaded'] = function()
  -- -- Set up not loaded but existing buffer with lines
  -- local new_buf_id = child.api.nvim_create_buf(true, false)
  -- child.api.nvim_buf_set_lines(new_buf_id, 0, -1, false, { 'aaa', 'bbb' })
  -- child.api.nvim_buf_set_option(new_buf_id, 'modified', false)
  -- child.api.nvim_buf_delete(new_buf_id, { unload = true })
  -- eq(child.api.nvim_buf_get_lines(new_buf_id, 0, -1, false), {})
  --
  -- -- Should also not trigger `*Enter` events
  -- child.cmd('au BufEnter,BufWinEnter * lua _G.n = (_G.n or 0) + 1')
  -- enable(new_buf_id)
  -- eq(child.fn.bufloaded(new_buf_id), 1)
  -- eq(child.lua_get('_G.n'), vim.NIL)
  MiniTest.skip()
end

T['enable()']['makes buffer update cache on `BufWinEnter`'] = function()
  -- eq(get_buf_data().config.delay.text_change, small_time)
  -- child.b.minidiff_config = { delay = { text_change = 200 } }
  -- child.api.nvim_exec_autocmds('BufWinEnter', { buffer = get_buf() })
  -- eq(get_buf_data().config.delay.text_change, 200)
  MiniTest.skip()
end

T['enable()']['makes buffer disabled when deleted'] = function()
  -- local alt_buf_id = new_buf()
  -- enable(alt_buf_id)
  -- clean_dummy_log()
  --
  -- local buf_id = get_buf()
  -- child.api.nvim_buf_delete(buf_id, { force = true })
  -- validate_dummy_log({ { 'detach', { buf_id } } })
  MiniTest.skip()
end

T['enable()']['makes buffer reset on rename'] = function()
  -- local buf_id = get_buf()
  -- child.api.nvim_buf_set_name(0, 'hello')
  -- validate_dummy_log({ { 'detach', { buf_id } }, { 'attach', { buf_id } } })
  MiniTest.skip()
end

T['enable()']['validates arguments'] = function()
  expect.error(function() enable({}) end, '`buf_id`.*valid buffer id')
end

T['enable()']['respects `vim.{g,b}.minigit_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    -- local buf_id = new_buf()
    -- if var_type == 'b' then child.api.nvim_buf_set_var(buf_id, 'minigit_disable', true) end
    -- if var_type == 'g' then child.api.nvim_set_var('minigit_disable', true) end
    -- enable(buf_id)
    -- validate_dummy_log({})
    -- eq(is_buf_enabled(buf_id), false)
    MiniTest.skip()
  end,
})

T['disable()'] = new_set()

local disable = forward_lua('MiniGit.disable')

T['disable()']['works'] = function()
  -- local buf_id = get_buf()
  -- eq(is_buf_enabled(buf_id), true)
  -- set_lines({ 'aaa', 'bbb' })
  -- set_ref_text(0, { 'aaa' })
  --
  -- disable(buf_id)
  -- eq(is_buf_enabled(buf_id), false)
  --
  -- -- Should delete buffer autocommands
  -- eq(child.api.nvim_get_autocmds({ buffer = buf_id }), {})
  --
  -- -- Should detach source
  -- validate_dummy_log({ { 'detach', { buf_id } } })
  --
  -- -- Should clear visualization
  -- child.expect_screenshot()
  MiniTest.skip()
end

T['disable()']['works in not current buffer'] = function()
  -- local buf_id = new_buf()
  -- enable(buf_id)
  -- clean_dummy_log()
  -- set_lines({ 'aaa', 'bbb' })
  -- set_ref_text(0, { 'aaa' })
  --
  -- disable(buf_id)
  -- eq(is_buf_enabled(buf_id), false)
  -- validate_dummy_log({ { 'detach', { buf_id } } })
  MiniTest.skip()
end

T['disable()']['works in not enabled buffer'] = function()
  -- local buf_id = new_buf()
  -- eq(is_buf_enabled(buf_id), false)
  -- expect.no_error(function() disable(buf_id) end)
  MiniTest.skip()
end

T['disable()']['normalizes input buffer'] = function()
  -- local buf_id = new_scratch_buf()
  -- set_buf(buf_id)
  --
  -- enable(buf_id)
  -- eq(is_buf_enabled(buf_id), true)
  -- disable(0)
  -- eq(is_buf_enabled(buf_id), false)
  MiniTest.skip()
end

T['disable()']['validates arguments'] = function()
  expect.error(function() disable('a') end, '`buf_id`.*valid buffer id')
end

T['toggle()'] = new_set()

local toggle = forward_lua('MiniGit.toggle')

T['toggle()']['works'] = function()
  -- child.lua([[
  --   _G.log = {}
  --   local cur_enable = MiniGit.enable
  --   MiniGit.enable = function(...)
  --     table.insert(_G.log, { 'enabled', { ... } })
  --     cur_enable(...)
  --   end
  --   local cur_disable = MiniGit.disable
  --   MiniGit.disable = function(...)
  --     cur_disable(...)
  --     table.insert(_G.log, { 'disabled', { ... } })
  --   end
  -- ]])
  --
  -- local buf_id = get_buf()
  -- eq(is_buf_enabled(buf_id), true)
  -- toggle(buf_id)
  -- eq(is_buf_enabled(buf_id), false)
  -- toggle(buf_id)
  -- eq(is_buf_enabled(buf_id), true)
  --
  -- eq(child.lua_get('_G.log'), { { 'disabled', { buf_id } }, { 'enabled', { buf_id } } })
  MiniTest.skip()
end

T['get_buf_data()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

T['get_buf_data()']['works'] = function()
  -- set_lines({ 'aaa', 'bbb' })
  -- set_ref_text(0, { 'aaa' })
  --
  -- child.lua('_G.buf_data = MiniDiff.get_buf_data()')
  --
  -- -- Should have proper structure
  -- local fields = child.lua_get('vim.tbl_keys(_G.buf_data)')
  -- table.sort(fields)
  -- eq(fields, { 'config', 'hunks', 'overlay', 'ref_text', 'summary' })
  --
  -- eq(child.lua_get('vim.deep_equal(MiniDiff.config, _G.buf_data.config)'), true)
  -- eq(child.lua_get('_G.buf_data.summary'), { source_name = 'dummy', add = 1, change = 0, delete = 0, n_ranges = 1 })
  -- eq(
  --   child.lua_get('_G.buf_data.hunks'),
  --   { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' } }
  -- )
  -- eq(child.lua_get('_G.buf_data.ref_text'), 'aaa\n')
  --
  -- eq(child.lua_get('_G.buf_data.overlay'), false)
  -- toggle_overlay()
  -- eq(child.lua_get('MiniDiff.get_buf_data().overlay'), true)
  MiniTest.skip()
end

T['get_buf_data()']['works with not set reference text'] = function()
  -- local buf_data = get_buf_data()
  -- eq(buf_data.hunks, {})
  -- eq(buf_data.summary, {})
  -- eq(buf_data.ref_text, nil)
  MiniTest.skip()
end

T['get_buf_data()']['works on not enabled buffer'] = function()
  -- local out = child.lua([[
  --   local buf_id = vim.api.nvim_create_buf(true, false)
  --   return MiniDiff.get_buf_data(buf_id) == nil
  -- ]])
  -- eq(out, true)
  MiniTest.skip()
end

T['get_buf_data()']['validates arguments'] = function()
  -- expect.error(function() get_buf_data('a') end, '`buf_id`.*valid buffer id')
  MiniTest.skip()
end

T['get_buf_data()']['returns copy of underlying data'] = function()
  -- local out = child.lua([[
  --   local buf_data = MiniDiff.get_buf_data()
  --   buf_data.hunks = 'aaa'
  --   return MiniDiff.get_buf_data().hunks ~= 'aaa'
  -- ]])
  -- eq(out, true)
  MiniTest.skip()
end

T['get_buf_data()']['correctly computes summary numbers'] = function()
  -- child.lua('MiniDiff.config.options.linematch = 0')
  -- local buf_id = new_buf()
  -- set_buf(buf_id)
  -- enable(buf_id)
  -- eq(get_buf_data(buf_id).config.options.linematch, 0)
  --
  -- local validate = function(ref_summary) eq(get_buf_data(buf_id).summary, ref_summary) end
  --
  -- -- Delete lines
  -- set_lines({ 'BBB', 'DDD' })
  -- set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD' })
  -- -- NOTE: Number of ranges is 1 because in buffer two delete hunks start on
  -- -- consecutive lines
  -- validate({ source_name = 'dummy', add = 0, change = 0, delete = 2, n_ranges = 1 })
  --
  -- -- Add lines
  -- set_lines({ 'AAA', 'uuu', 'BBB', 'vvv' })
  -- set_ref_text(0, { 'AAA', 'BBB' })
  -- validate({ source_name = 'dummy', add = 2, change = 0, delete = 0, n_ranges = 2 })
  --
  -- -- Changed lines are computed per hunk as minimum number of added and deleted
  -- -- lines. Excess is counted as corresponding lines (added/deleted)
  -- set_lines({ 'aaa', 'CCC', 'ddd', 'eee', 'uuu' })
  -- set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  -- local ref_hunks = {
  --   { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 2, type = 'change' },
  --   { buf_start = 3, buf_count = 3, ref_start = 4, ref_count = 2, type = 'change' },
  -- }
  -- eq(get_buf_hunks(buf_id), ref_hunks)
  -- validate({ source_name = 'dummy', add = 1, change = 3, delete = 1, n_ranges = 2 })
  MiniTest.skip()
end

T['get_buf_data()']['uses number of contiguous ranges in summary'] = function()
  -- if child.fn.has('nvim-0.9') == 0 then MiniTest.skip('Contiguous regions are relevant with `linematch` option.') end
  --
  -- set_lines({ 'AAA', 'uuu', 'BbB', 'DDD', 'www', 'EEE' })
  -- set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  -- local buf_data = get_buf_data()
  -- eq(buf_data.hunks, {
  --   { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' },
  --   { buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 1, type = 'change' },
  --   { buf_start = 3, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' },
  --   { buf_start = 5, buf_count = 1, ref_start = 4, ref_count = 0, type = 'add' },
  -- })
  --
  -- eq(buf_data.summary.n_ranges, 2)
  MiniTest.skip()
end

-- Integration tests ==========================================================
T['Auto enable'] = new_set()

T['Auto enable']['properly enables on `BufEnter`'] = function()
  -- local buf_id = new_buf()
  -- set_buf(buf_id)
  -- eq(is_buf_enabled(buf_id), true)
  --
  -- -- Should auto enable even in unlisted buffers
  -- local buf_id_unlisted = child.api.nvim_create_buf(false, false)
  -- set_buf(buf_id_unlisted)
  -- eq(is_buf_enabled(buf_id_unlisted), true)
  --
  -- -- Should try auto enable in `BufEnter`
  -- disable(buf_id)
  -- eq(is_buf_enabled(buf_id), false)
  -- set_buf(buf_id)
  -- eq(is_buf_enabled(buf_id), true)
  MiniTest.skip()
end

T['Auto enable']['does not enable in not proper buffers'] = function()
  -- -- Has set `vim.b.minidiff_disable`
  -- local buf_id_disabled = new_buf()
  -- child.api.nvim_buf_set_var(buf_id_disabled, 'minidiff_disable', true)
  -- set_buf(buf_id_disabled)
  -- eq(is_buf_enabled(buf_id_disabled), false)
  --
  -- -- Is not normal
  -- set_buf(new_scratch_buf())
  -- eq(is_buf_enabled(0), false)
  --
  -- -- Is not text buffer
  -- local buf_id_not_text = new_buf()
  -- child.api.nvim_buf_set_lines(buf_id_not_text, 0, -1, false, { 'aa', '\0', 'bb' })
  -- set_buf(buf_id_not_text)
  -- eq(is_buf_enabled(buf_id_not_text), false)
  MiniTest.skip()
end

T['Auto enable']['works after `:edit`'] = function()
  -- child.lua([[
  --   MiniDiff.config.source = { attach = function(buf_id) MiniDiff.set_ref_text(buf_id, { 'aaa' }) end }
  -- ]])
  --
  -- edit(test_file_path)
  -- eq(is_buf_enabled(0), true)
  -- local ref_hunks = { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' } }
  -- eq(get_buf_hunks(0), ref_hunks)
  --
  -- -- - It should be able to use `:edit` to update buffer config
  -- child.b.minidiff_config = { options = { algorithm = 'minimal' } }
  -- eq(get_buf_data(0).config.options.algorithm, 'histogram')
  --
  -- child.cmd('edit')
  -- eq(get_lines(), { 'aaa', 'uuu' })
  --
  -- eq(is_buf_enabled(0), true)
  -- eq(get_buf_hunks(0), ref_hunks)
  -- eq(get_buf_data(0).config.options.algorithm, 'minimal')
  -- validate_viz_extmarks(0, { { line = 2, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' } })
  MiniTest.skip()
end

T[':Git'] = new_set()

T[':Git']['works'] = function() MiniTest.skip() end

T[':Git']['completion'] = new_set()

T[':Git']['completion']['works'] = function() MiniTest.skip() end

return T
