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
local test_file_absolute = test_dir_absolute .. '/file'

local git_root_dir = test_dir_absolute .. '/git-repo'
local git_repo_dir = git_root_dir .. '/.git-dir'
local git_dir_path = git_root_dir .. '/dir-in-git'
local git_file_path = git_root_dir .. '/file-in-git'

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local log_calls = function(fun_name)
  --stylua: ignore
  local lua_cmd = string.format(
    [[local orig = %s
      _G.call_log = _G.call_log or {}
      %s = function(...) table.insert(_G.call_log, { %s, ... }); return orig(...) end]],
    fun_name, fun_name, vim.inspect(fun_name)
  )
  child.lua(lua_cmd)
end

local validate_calls = function(ref) eq(child.lua_get('_G.call_log'), ref) end

local get_buf_data = forward_lua('require("mini-dev.git").get_buf_data')

local is_buf_enabled = function(buf_id) return get_buf_data(buf_id) ~= vim.NIL end

-- Common mocks
local small_time = 10

-- - Git mocks
local mock_change_git_index = function()
  local index_path = git_repo_dir .. '/index'
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

local mock_init_track_stdio_queue = function()
  child.lua([[
    _G.init_track_stdio_queue = {
      { { 'out', _G.rev_parse_track } }, -- Get path to root and repo
      { { 'out', 'abc1234\nmain' } },    -- Get HEAD data
      { { 'out', '?? file-in-git' } },   -- Get file status data
    }
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

local clear_spawn_log = function() child.lua('_G.spawn_log = {}') end

local get_process_log = function() return child.lua_get('_G.process_log') end

local clear_process_log = function() child.lua('_G.process_log = {}') end

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
      mock_spawn()
      mock_notify()
      mock_executable()

      -- Populate child with frequently used paths
      child.lua('_G.git_root_dir, _G.git_repo_dir = ' .. vim.inspect(git_root_dir) .. ', ' .. vim.inspect(git_repo_dir))
      child.lua([[_G.rev_parse_track = _G.git_repo_dir .. '\n' .. _G.git_root_dir]])
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
  mock_init_track_stdio_queue()
  child.lua('_G.stdio_queue = _G.init_track_stdio_queue')

  edit(git_file_path)
  load_module()
  eq(is_buf_enabled(), true)
end

T['show_at_cursor()'] = new_set({ hooks = { pre_case = load_module } })

T['show_at_cursor()']['works'] = function() MiniTest.skip() end

T['show_diff_source()'] = new_set({ hooks = { pre_case = load_module } })

T['show_diff_source()']['works'] = function() MiniTest.skip() end

T['show_range_history()'] = new_set({ hooks = { pre_case = load_module } })

T['show_range_history()']['works'] = function() MiniTest.skip() end

T['diff_foldexpr()'] = new_set({ hooks = { pre_case = load_module } })

T['diff_foldexpr()']['works in `git log` output'] = function()
  child.set_size(70, 50)
  child.o.laststatus = 0
  edit(test_dir_absolute .. '/log-output')
  child.cmd('setlocal foldmethod=expr foldexpr=v:lua.MiniGit.diff_foldexpr(v:lnum)')

  -- Should be one line per patch
  child.o.foldlevel = 0
  child.expect_screenshot()

  -- Should be one line per patched file
  child.o.foldlevel = 1
  child.expect_screenshot()

  -- Should be one line per hunk
  child.o.foldlevel = 2
  child.expect_screenshot()

  -- Should be no folds
  child.o.foldlevel = 3
  child.expect_screenshot()
end

T['diff_foldexpr()']['works in diff patch'] = function()
  child.set_size(25, 50)
  child.o.laststatus = 0
  edit(test_dir_absolute .. '/diff-output')
  child.cmd('setlocal foldmethod=expr foldexpr=v:lua.MiniGit.diff_foldexpr(v:lnum)')

  -- Should be one line per patch
  child.o.foldlevel = 0
  child.expect_screenshot()

  -- Should be one line per patched file
  child.o.foldlevel = 1
  child.expect_screenshot()

  -- Should be one line per hunk
  child.o.foldlevel = 2
  child.expect_screenshot()

  -- Should be no folds
  child.o.foldlevel = 3
  child.expect_screenshot()
end

T['enable()'] = new_set({
  hooks = {
    pre_case = function()
      mock_init_track_stdio_queue()
      child.lua('_G.stdio_queue = _G.init_track_stdio_queue')
      load_module()

      -- Set up enableable buffer which is not yet enabled
      child.g.minigit_disable = true
      edit(git_file_path)
      child.g.minigit_disable = nil
    end,
  },
})

local enable = forward_lua('MiniGit.enable')

T['enable()']['works'] = function()
  enable()
  --stylua: ignore
  local ref_git_spawn_log = {
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' },
      cwd = git_root_dir,
    },
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
      cwd = git_root_dir,
    },
    {
      args = { '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z', '--', 'file-in-git' },
      cwd = git_root_dir,
    },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  local summary = {
    head = 'abc1234',
    head_name = 'main',
    in_progress = '',
    repo = git_repo_dir,
    root = git_root_dir,
    status = '??',
  }
  eq(get_buf_data(), summary)
  eq(child.b.minigit_summary, summary)

  -- Should not re-enable alreaady enabled buffer
  enable()
  validate_git_spawn_log(ref_git_spawn_log)

  -- Makes buffer disabled when deleted
  log_calls('MiniGit.disable')
  local buf_id = get_buf()
  child.api.nvim_buf_delete(buf_id, { force = true })
  validate_calls({ { 'MiniGit.disable', buf_id } })
end

T['enable()']['works in not normal buffer'] = function()
  child.bo.buftype = 'acwrite'
  enable()
  eq(is_buf_enabled(), true)
end

T['enable()']['works in not current buffer'] = function()
  local buf_id = get_buf()
  set_buf(new_scratch_buf())
  enable(buf_id)
  eq(is_buf_enabled(buf_id), true)
  eq(get_buf() ~= buf_id, true)
end

T['enable()']['does not work in non-file buffer'] = function()
  set_buf(new_buf())
  enable()
  eq(is_buf_enabled(), false)
  validate_git_spawn_log({})
end

T['enable()']['normalizes input buffer'] = function()
  enable(0)
  eq(is_buf_enabled(), true)
end

T['enable()']['makes buffer reset on rename'] = function()
  enable()
  local buf_id = get_buf()
  log_calls('MiniGit.enable')
  log_calls('MiniGit.disable')

  child.api.nvim_buf_set_name(0, child.fn.fnamemodify(git_file_path, ':h') .. '/new-file')
  validate_calls({ { 'MiniGit.disable', buf_id }, { 'MiniGit.enable', buf_id } })
end

T['enable()']['validates arguments'] = function()
  expect.error(function() enable({}) end, '`buf_id`.*valid buffer id')
end

T['enable()']['respects `vim.{g,b}.minigit_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    local buf_id = new_buf()
    if var_type == 'b' then child.api.nvim_buf_set_var(buf_id, 'minigit_disable', true) end
    if var_type == 'g' then child.api.nvim_set_var('minigit_disable', true) end
    enable(buf_id)
    eq(is_buf_enabled(buf_id), false)
    validate_git_spawn_log({})
  end,
})

T['disable()'] = new_set({
  hooks = {
    pre_case = function()
      mock_init_track_stdio_queue()
      child.lua('_G.stdio_queue = _G.init_track_stdio_queue')
      load_module()

      -- Set up enabled buffer
      edit(git_file_path)
      eq(is_buf_enabled(), true)
    end,
  },
})

local disable = forward_lua('MiniGit.disable')

T['disable()']['works'] = function()
  local buf_id = get_buf()
  clear_spawn_log()

  disable()
  eq(is_buf_enabled(buf_id), false)
  validate_git_spawn_log({})
  eq(child.api.nvim_get_autocmds({ buffer = buf_id }), {})
  eq(child.b.minigit_summary, vim.NIL)
end

T['disable()']['works in not current buffer'] = function()
  local buf_id = get_buf()
  set_buf(new_scratch_buf())
  disable(buf_id)
  eq(is_buf_enabled(buf_id), false)
end

T['disable()']['works in not enabled buffer'] = function()
  set_buf(new_scratch_buf())
  eq(is_buf_enabled(), false)
  expect.no_error(disable)
end

T['disable()']['normalizes input buffer'] = function()
  local buf_id = get_buf()
  disable(0)
  eq(is_buf_enabled(buf_id), false)
end

T['disable()']['validates arguments'] = function()
  expect.error(function() disable('a') end, '`buf_id`.*valid buffer id')
end

T['toggle()'] = new_set({ hooks = { pre_case = load_module } })

local toggle = forward_lua('MiniGit.toggle')

T['toggle()']['works'] = function()
  mock_init_track_stdio_queue()
  child.lua('_G.stdio_queue = _G.init_track_stdio_queue')
  log_calls('MiniGit.enable')
  log_calls('MiniGit.disable')

  edit(git_file_path)
  local buf_id = get_buf()
  eq(is_buf_enabled(buf_id), true)
  validate_calls({ { 'MiniGit.enable', buf_id } })

  toggle()
  eq(is_buf_enabled(buf_id), false)
  validate_calls({ { 'MiniGit.enable', buf_id }, { 'MiniGit.disable', buf_id } })

  toggle(buf_id)
  eq(is_buf_enabled(buf_id), true)
  validate_calls({ { 'MiniGit.enable', buf_id }, { 'MiniGit.disable', buf_id }, { 'MiniGit.enable', buf_id } })
end

T['get_buf_data()'] = new_set({
  hooks = {
    pre_case = function()
      mock_init_track_stdio_queue()
      child.lua('_G.stdio_queue = _G.init_track_stdio_queue')
      load_module()

      -- Set up enabled buffer
      edit(git_file_path)
      eq(is_buf_enabled(), true)
    end,
  },
})

T['get_buf_data()']['works'] = function()
  local buf_id = get_buf()
  local summary = {
    head = 'abc1234',
    head_name = 'main',
    in_progress = '',
    repo = git_repo_dir,
    root = git_root_dir,
    status = '??',
  }
  eq(get_buf_data(), summary)
  eq(get_buf_data(0), summary)
  eq(get_buf_data(buf_id), summary)

  -- Works on not enabled buffer
  set_buf(new_scratch_buf())
  eq(is_buf_enabled(), false)
  eq(get_buf_data(), vim.NIL)

  -- Works on not current buffer
  eq(get_buf_data(buf_id), summary)
end

T['get_buf_data()']['works for file not in repo'] = function()
  mock_spawn()
  child.lua('_G.process_mock_data = { { exit_code = 1 } }')
  edit(test_file_absolute)
  eq(get_buf_data(), {})
end

T['get_buf_data()']['validates arguments'] = function()
  expect.error(function() get_buf_data('a') end, '`buf_id`.*valid buffer id')
end

T['get_buf_data()']['returns copy of underlying data'] = function()
  local out = child.lua([[
    local buf_data = MiniGit.get_buf_data()
    buf_data.head = 'aaa'
    return MiniGit.get_buf_data().head ~= 'aaa'
  ]])
  eq(out, true)
end

T['get_buf_data()']['works with several actions in progress'] = function()
  child.fn.writefile({ '' }, git_repo_dir .. '/MERGE_HEAD')
  child.fn.writefile({ '' }, git_repo_dir .. '/REVERT_HEAD')
  MiniTest.finally(function()
    child.fn.delete(git_repo_dir .. '/MERGE_HEAD')
    child.fn.delete(git_repo_dir .. '/REVERT_HEAD')
  end)

  mock_spawn()
  child.lua('_G.stdio_queue = _G.init_track_stdio_queue')
  child.cmd('edit')
  sleep(small_time)
  eq(get_buf_data().in_progress, 'merge,revert')
end

-- Integration tests ==========================================================
T['Auto enable'] = new_set({ hooks = { pre_case = load_module } })

T['Auto enable']['properly enables on `BufEnter`'] = function()
  mock_init_track_stdio_queue()
  child.lua([[_G.stdio_queue = {
      _G.init_track_stdio_queue[1],
      _G.init_track_stdio_queue[2],
      _G.init_track_stdio_queue[3],

      _G.init_track_stdio_queue[1],
      _G.init_track_stdio_queue[2],
      _G.init_track_stdio_queue[3],

      _G.init_track_stdio_queue[1],
      _G.init_track_stdio_queue[2],
      _G.init_track_stdio_queue[3],
    }
  ]])

  edit(git_file_path)
  local buf_id = get_buf()
  sleep(small_time)
  eq(get_buf_data(buf_id).status, '??')

  -- Should try auto enable in `BufEnter`
  set_buf(new_scratch_buf())
  disable(buf_id)
  eq(is_buf_enabled(buf_id), false)
  set_buf(buf_id)
  sleep(small_time)
  eq(get_buf_data(buf_id).status, '??')

  -- Should auto enable even in unlisted buffers
  set_buf(new_scratch_buf())
  disable(buf_id)
  child.api.nvim_buf_set_option(buf_id, 'buflisted', false)
  set_buf(buf_id)
  sleep(small_time)
  eq(get_buf_data(buf_id).status, '??')
end

T['Auto enable']['does not enable in not proper buffers'] = function()
  -- Has set `vim.b.minigit_disable`
  local buf_id_disabled = new_buf()
  child.api.nvim_buf_set_name(buf_id_disabled, git_file_path)
  child.api.nvim_buf_set_var(buf_id_disabled, 'minigit_disable', true)
  set_buf(buf_id_disabled)
  eq(is_buf_enabled(buf_id_disabled), false)

  -- Is not normal
  set_buf(new_scratch_buf())
  eq(is_buf_enabled(), false)

  -- Is not file buffer
  set_buf(new_buf())
  eq(is_buf_enabled(), false)

  -- Should infer all above cases without CLI runs
  validate_git_spawn_log({})
end

T['Auto enable']['works after `:edit`'] = function()
  mock_init_track_stdio_queue()
  child.lua([[_G.stdio_queue = {
      _G.init_track_stdio_queue[1],
      _G.init_track_stdio_queue[2],
      _G.init_track_stdio_queue[3],

      _G.init_track_stdio_queue[1],
      _G.init_track_stdio_queue[2],
      _G.init_track_stdio_queue[3],
    }
  ]])

  edit(git_file_path)
  local buf_id = get_buf()
  eq(is_buf_enabled(buf_id), true)

  log_calls('MiniGit.enable')
  log_calls('MiniGit.disable')

  child.cmd('edit')
  validate_calls({ { 'MiniGit.disable', buf_id }, { 'MiniGit.enable', buf_id } })
  eq(get_buf_data(buf_id).root, git_root_dir)
end

T['Tracking'] = new_set({ hooks = { pre_case = load_module } })

T['Tracking']['works outside of Git repo'] = function()
  child.lua('_G.process_mock_data = { { exit_code = 1 } }')
  edit(test_file_absolute)
  eq(get_buf_data().repo, nil)
end

T['Tracking']['updates all buffers from same repo on repo change'] = function()
  child.lua([[_G.stdio_queue = {
      { { 'out', _G.rev_parse_track } }, -- Get path to root and repo for first file
      { { 'out', 'abc1234\nmain' } },    -- Get HEAD data for first file
      { { 'out', 'MM file-in-git' } },   -- Get file status data for first file

      { { 'out', _G.rev_parse_track } },                 -- Get path to root and repo for second file
      { { 'out', 'abc1234/main' } },                     -- Get HEAD data for second file
      { { 'out', '?? dir-in-git/file-in-dir-in-git' } }, -- Get file status data for second file

      -- Reaction to repo change
      { { 'out', 'abc1234\nmain' } },
      { { 'out', 'MM file-in-git\0A  dir-in-git/file-in-dir-in-git' } },
    }
  ]])

  edit(git_file_path)
  local buf_id_1 = get_buf()
  sleep(small_time)

  edit(git_root_dir .. '/dir-in-git/file-in-dir-in-git')
  local buf_id_2 = get_buf()
  sleep(small_time)

  -- Make change in '.git' directory
  mock_change_git_index()
  sleep(50 + small_time)

  eq(get_buf_data(buf_id_1).status, 'MM')
  eq(get_buf_data(buf_id_2).status, 'A ')

  --stylua: ignore
  local ref_git_spawn_log = {
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' },
      cwd = git_root_dir,
    },
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
      cwd = git_root_dir,
    },
    {
      args = {
        '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z',
        '--', 'file-in-git'
      },
      cwd = git_root_dir,
    },
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' },
      cwd = git_root_dir .. '/dir-in-git',
    },
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
      cwd = git_root_dir,
    },
    {
      args = {
        '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z',
        '--', 'dir-in-git/file-in-dir-in-git'
      },
      cwd = git_root_dir,
    },
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
      cwd = git_root_dir,
    },
    {
      args = {
        '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z',
        '--', 'file-in-git', 'dir-in-git/file-in-dir-in-git'
      },
      cwd = git_root_dir,
    },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['Tracking']['reacts to content change outside of current session'] = function()
  child.lua([[_G.stdio_queue = {
      { { 'out', _G.rev_parse_track } }, -- Get path to root and repo
      { { 'out', 'abc1234\nmain' } },    -- Get HEAD data
      { { 'out', 'M  file-in-git' } },   -- Get file status data

      { { 'out', 'abc1234\nmain' } },    -- Get HEAD data second time
      { { 'out', 'MM file-in-git' } },   -- Get file status data second time
    }
  ]])

  edit(git_file_path)
  vim.fn.writefile({ '' }, git_file_path)
  child.cmd('checktime')
  sleep(small_time)

  local ref_data =
    { head = 'abc1234', head_name = 'main', in_progress = '', repo = git_repo_dir, root = git_root_dir, status = 'MM' }
  eq(get_buf_data(), ref_data)

  --stylua: ignore
  local ref_git_spawn_log = {
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' },
      cwd = git_root_dir,
    },
    { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
    { '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z', '--', 'file-in-git' },
    { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
    { '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z', '--', 'file-in-git' },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['Tracking']['reacts to buffer rename'] = function()
  -- This is the chosen way to track change in root/repo.
  -- Rely on manual `:edit` otherwise.
  local new_root, new_repo = child.fn.getcwd(), test_dir_absolute
  local new_rev_parse_track = new_repo .. '\n' .. new_root
  child.lua('_G.new_rev_parse_track = ' .. vim.inspect(new_rev_parse_track))
  child.lua([[_G.stdio_queue = {
      { { 'out', _G.rev_parse_track } }, -- First get path to root and repo
      { { 'out', 'abc1234\nmain' } },    -- First get HEAD data
      { { 'out', 'M  file-in-git' } },   -- First get file status data

      { { 'out', _G.new_rev_parse_track } },  -- Second get path to root and repo
      { { 'out', 'def4321\ntmp' } },          -- Second get HEAD data
      { { 'out', 'MM tests/dir-git/file' } }, -- Second get file status data
    }
  ]])

  edit(git_file_path)
  sleep(small_time)

  child.api.nvim_buf_set_name(0, test_file_absolute)
  sleep(small_time)

  --stylua: ignore
  local ref_git_spawn_log = {
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' },
      cwd = git_root_dir,
    },
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
      cwd = git_root_dir,
    },
    {
      args = { '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z', '--', 'file-in-git' },
      cwd = git_root_dir,
    },
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' },
      cwd = test_dir_absolute,
    },
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
      cwd = new_root,
    },
    {
      args = { '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z', '--', 'tests/dir-git/file' },
      cwd = new_root,
    },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  eq(get_buf_data(), {
    head = 'def4321',
    head_name = 'tmp',
    in_progress = '',
    repo = new_repo,
    root = new_root,
    status = 'MM',
  })
end

T['Tracking']['reacts to moving to not Git repo'] = function()
  child.lua([[_G.stdio_queue = {
      { { 'out', _G.rev_parse_track } }, -- Get path to root and repo
      { { 'out', 'abc1234\nmain' } },    -- Get HEAD data
      { { 'out', 'M  file-in-git' } },   -- Get file status data
    }
    _G.process_mock_data = { [4] = { exit_code = 1 } }
  ]])

  edit(git_file_path)
  eq(is_buf_enabled(), true)
  child.api.nvim_buf_set_name(0, test_file_absolute)
  eq(get_buf_data(), {})
  eq(#get_spawn_log(), 4)
end

T['Tracking']['reacts to staging'] = function()
  child.lua([[_G.stdio_queue = {
      { { 'out', _G.rev_parse_track } }, -- Get path to root and repo
      { { 'out', 'abc1234\nmain' } },    -- Get HEAD data
      { { 'out', 'MM file-in-git' } },   -- Get file status data

      -- Emulate staging file
      { { 'out', 'abc1234\nmain' } },  -- Get HEAD data
      { { 'out', 'M  file-in-git' } }, -- Get file status data
    }
  ]])

  edit(git_file_path)
  sleep(small_time)

  -- Should react to change in index
  eq(get_buf_data().status, 'MM')
  mock_change_git_index()

  -- - Reaction to change in '.git' directory is debouned with delay of 50 ms
  sleep(50 - small_time)
  eq(get_buf_data().status, 'MM')
  eq(#get_spawn_log(), 3)

  sleep(2 * small_time)
  eq(get_buf_data().status, 'M ')
  eq(#get_spawn_log(), 5)

  --stylua: ignore
  local ref_git_spawn_log = {
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' },
      cwd = git_root_dir,
    },
    { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
    { '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z', '--', 'file-in-git' },
    { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
    { '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z', '--', 'file-in-git' },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['Tracking']['reacts to change in HEAD'] = function()
  child.lua([[_G.stdio_queue = {
      { { 'out', _G.rev_parse_track } }, -- Get path to root and repo
      { { 'out', 'abc1234\nmain' } },    -- Get HEAD data
      { { 'out', 'MM file-in-git' } },   -- Get file status data

      -- Emulate changing branch
      { { 'out', 'def4321\ntmp' } },   -- Get HEAD data
      { { 'out', '?? file-in-git' } }, -- Get file status data
    }
  ]])

  edit(git_file_path)
  sleep(small_time)

  -- Should react to change of HEAD
  eq(get_buf_data().head_name, 'main')
  child.fn.writefile({ 'ref: refs/heads/tmp' }, git_repo_dir .. '/HEAD')

  sleep(50 - small_time)
  eq(get_buf_data().head_name, 'main')
  eq(#get_spawn_log(), 3)

  sleep(2 * small_time)
  eq(get_buf_data().head_name, 'tmp')
  eq(#get_spawn_log(), 5)

  --stylua: ignore
  local ref_git_spawn_log = {
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' },
      cwd = git_root_dir,
    },
    { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
    { '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z', '--', 'file-in-git' },
    { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
    { '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z', '--', 'file-in-git' },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['Tracking']['detects action in progress immediately'] = function()
  mock_init_track_stdio_queue()
  child.lua('_G.stdio_queue = _G.init_track_stdio_queue')

  child.fn.writefile({ '' }, git_repo_dir .. '/BISECT_LOG')
  MiniTest.finally(function() child.fn.delete(git_repo_dir .. '/BISECT_LOG') end)

  edit(git_file_path)
  sleep(small_time)
  eq(get_buf_data().in_progress, 'bisect')
end

T['Tracking']['reacts to new action in progress'] = function()
  mock_init_track_stdio_queue()
  child.lua('_G.stdio_queue = _G.init_track_stdio_queue')
  edit(git_file_path)

  local action_files = { 'BISECT_LOG', 'CHERRY_PICK_HEAD', 'MERGE_HEAD', 'REVERT_HEAD', 'rebase-apply', 'rebase-merge' }
  local output_in_progress = {}

  for _, name in ipairs(action_files) do
    local path = git_repo_dir .. '/' .. name
    child.fn.writefile({ '' }, path)
    sleep(50 + small_time)
    output_in_progress[name] = get_buf_data().in_progress
    child.fn.delete(path)
  end

  local ref_in_progress = {
    BISECT_LOG = 'bisect',
    CHERRY_PICK_HEAD = 'cherry-pick',
    MERGE_HEAD = 'merge',
    REVERT_HEAD = 'revert',
    ['rebase-apply'] = 'apply',
    ['rebase-merge'] = 'rebase',
  }
  eq(output_in_progress, ref_in_progress)
end

T['Tracking']['does not react to ".lock" files in repo directory'] = function()
  mock_init_track_stdio_queue()
  child.lua('_G.stdio_queue = _G.init_track_stdio_queue')
  edit(git_file_path)
  eq(#get_spawn_log(), 3)

  child.fn.writefile({ '' }, git_repo_dir .. '/tmp.lock')
  MiniTest.finally(function() child.fn.delete(git_repo_dir .. '/tmp.lock') end)
  sleep(50 + small_time)
  eq(#get_spawn_log(), 3)
end

T[':Git'] = new_set({ hooks = { pre_case = load_module } })

T[':Git']['works'] = function() MiniTest.skip() end

T[':Git']['completion'] = new_set()

T[':Git']['completion']['works'] = function() MiniTest.skip() end

T[':Git']['events'] = new_set()

T[':Git']['events']['`MiniGitCommandDone` works'] = function() MiniTest.skip() end

T[':Git']['events']['`MiniGitCommandSplit` works'] = function() MiniTest.skip() end

T[':Git']['events']['`MiniGitCommandSplit` can be used to tweak window-local options'] = function()
  -- Like vim.wo.foldlevel
  MiniTest.skip()
end

return T
