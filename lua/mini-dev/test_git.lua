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

local make_minigit_name = function(buf_id, name)
  if buf_id == 0 then buf_id = get_buf() end
  return 'minigit://' .. buf_id .. '/' .. name
end

local validate_minigit_name = function(buf_id, ref_name)
  eq(child.api.nvim_buf_get_name(buf_id), make_minigit_name(buf_id, ref_name))
end

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

local show_diff_source = forward_lua('MiniGit.show_diff_source')

T['show_at_cursor()']['works'] = function() MiniTest.skip() end

T['show_diff_source()'] = new_set({
  hooks = {
    pre_case = function()
      -- Show log output
      local log_output = child.fn.readfile(test_dir_absolute .. '/log-output')
      set_lines(log_output)

      load_module()
    end,
  },
})

T['show_diff_source()']['works'] = function()
  child.lua([[_G.stdio_queue = {
    { { 'out', 'Line 1\nCurrent line 2\nLine 3' } }, -- Diff source
  }]])

  -- Show diff source
  set_cursor(17, 0)
  show_diff_source()

  local ref_git_spawn_log = {
    {
      args = { 'show', '5ed8432441b495fa9bd4ad2e4f635bae64e95cc2:dir/file-after' },
      cwd = child.fn.getcwd(),
    },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  eq(#child.api.nvim_list_tabpages(), 2)
  eq(child.api.nvim_tabpage_get_number(0), 2)

  validate_minigit_name(0, 'show 5ed8432441b495fa9bd4ad2e4f635bae64e95cc2:dir/file-after')
  eq(get_lines(), { 'Line 1', 'Current line 2', 'Line 3' })
  eq(get_cursor(), { 2, 0 })
end

T['show_diff_source()']['works in not diff file'] = function()
  set_lines({ 'Not', 'a', 'patch' })
  set_cursor(3, 0)
  expect.no_error(show_diff_source)
  validate_notifications({
    { '(mini.git) Could not find diff source. Ensure that cursor is inside a valid diff lines of git log.', 'WARN' },
  })
end

T['show_diff_source()']['correctly identifies source'] = function()
  local log_output = child.fn.readfile(test_dir_absolute .. '/log-output')
  child.lua([[
    _G.source_lines = {}
    for i = 1, 500 do
      table.insert(_G.source_lines, 'Line ' .. i)
    end
    _G.show_out = table.concat(_G.source_lines, '\n')
  ]])
  local source_lines = child.lua_get('_G.source_lines')

  local validate_ok = function(lnum, ref_commit, ref_path, ref_lnum)
    mock_spawn()
    child.lua([[_G.stdio_queue = { { { 'out', _G.show_out } } }]])
    set_lines(log_output)
    set_cursor(lnum, 0)

    show_diff_source()
    local ref_git_spawn_log = { { args = { 'show', ref_commit .. ':' .. ref_path }, cwd = child.fn.getcwd() } }
    validate_git_spawn_log(ref_git_spawn_log)

    eq(get_lines(), source_lines)
    eq(get_cursor(), { ref_lnum, 0 })
    validate_minigit_name(0, 'show ' .. ref_commit .. ':' .. ref_path)

    -- Clean up
    child.cmd('%bwipeout!')
  end

  local validate_no_ok = function(lnum)
    mock_spawn()
    set_lines(log_output)
    set_cursor(lnum, 0)

    expect.no_error(show_diff_source)
    eq(get_spawn_log(), {})
    validate_notifications({
      { '(mini.git) Could not find diff source. Ensure that cursor is inside a valid diff lines of git log.', 'WARN' },
    })
    clear_notify_log()
  end

  local commit_after = '5ed8432441b495fa9bd4ad2e4f635bae64e95cc2'
  local commit_before = commit_after .. '~'

  -- Cursor should be placed inside valid hunk
  validate_no_ok(1)
  validate_no_ok(2)
  validate_no_ok(3)
  validate_no_ok(10)
  validate_no_ok(11)

  -- Should place on the first line for lines showing target files
  validate_ok(12, commit_before, 'dir/file-before', 1)
  validate_ok(13, commit_after, 'dir/file-after', 1)

  -- Should work inside hunks and place cursor on the corresponding line.
  -- Should (with default `target = 'auto'`) pick "before" if on the deleted
  -- line, "after" otherwise.
  validate_ok(14, commit_after, 'dir/file-after', 1)
  validate_ok(15, commit_after, 'dir/file-after', 1)
  validate_ok(16, commit_before, 'dir/file-before', 2)
  validate_ok(17, commit_after, 'dir/file-after', 2)
  validate_ok(18, commit_after, 'dir/file-after', 3)

  validate_ok(19, commit_after, 'dir/file-after', 316)
  validate_ok(20, commit_after, 'dir/file-after', 317)
  validate_ok(21, commit_after, 'dir/file-after', 318)
  validate_ok(22, commit_after, 'dir/file-after', 319)
  validate_ok(23, commit_after, 'dir/file-after', 320)

  validate_no_ok(24)
  validate_no_ok(25)

  -- Should get proper (nearest from above) file
  validate_ok(26, commit_before, 'file', 1)
  validate_ok(27, commit_after, 'file', 1)

  validate_ok(28, commit_after, 'file', 282)
  validate_ok(29, commit_after, 'file', 283)
  validate_ok(30, commit_before, 'file', 284)
  validate_ok(31, commit_before, 'file', 285)
  validate_ok(32, commit_after, 'file', 284)

  -- - Between log entries is also not a valid diff line
  validate_no_ok(33)

  validate_no_ok(34)
  validate_no_ok(35)

  -- Should get proper (nearest from above) commit
  local commit_after_2 = '7264474d3bda16d0098a7f89a4143fe4db3d82cf'
  local commit_before_2 = commit_after_2 .. '~'
  validate_ok(42, commit_before_2, 'dir/file1', 1)
  validate_ok(43, commit_after_2, 'dir/file1', 1)
  validate_ok(44, commit_after_2, 'dir/file1', 246)
  validate_ok(45, commit_before_2, 'dir/file1', 247)
  validate_ok(46, commit_after_2, 'dir/file1', 247)
end

T['show_diff_source()']['does not depend on cursor column'] = function()
  local buf_id = get_buf()
  for i = 0, 10 do
    set_buf(buf_id)
    set_cursor(17, i)
    show_diff_source()
    eq(get_cursor(), { 2, 0 })
  end
end

T['show_diff_source()']['tries to infer and set filetype'] = function()
  if child.fn.has('nvim-0.8') == 0 then MiniTest.skip('Proper filetype detecttion is present only on Neovim>=0.8.') end

  child.lua([[_G.stdio_queue = { { { 'out', 'local a = 1\n-- This is a Lua comment' } } }]])
  set_cursor(57, 0)
  show_diff_source()

  validate_minigit_name(0, 'show 7264474d3bda16d0098a7f89a4143fe4db3d82cf:file.lua')
  eq(get_lines(), { 'local a = 1', '-- This is a Lua comment' })
  eq(get_cursor(), { 1, 0 })
  eq(child.bo.filetype, 'lua')
end

T['show_diff_source()']['respects `opts.split`'] = new_set(
  { parametrize = { { 'horizontal' }, { 'vertical' }, { 'tab' } } },
  {
    test = function(split)
      child.lua([[_G.stdio_queue = {
        { { 'out', 'Line 1\nCurrent line 2\nLine 3' } }, -- Diff source
      }]])
      set_cursor(17, 0)

      local init_win_id = child.api.nvim_get_current_win()
      show_diff_source({ split = split })
      local cur_win_id = child.api.nvim_get_current_win()

      local ref_git_spawn_log = {
        {
          args = { 'show', '5ed8432441b495fa9bd4ad2e4f635bae64e95cc2:dir/file-after' },
          cwd = child.fn.getcwd(),
        },
      }
      validate_git_spawn_log(ref_git_spawn_log)

      validate_minigit_name(0, 'show 5ed8432441b495fa9bd4ad2e4f635bae64e95cc2:dir/file-after')

      -- Validate proper split
      eq(#child.api.nvim_list_tabpages(), split == 'tab' and 2 or 1)
      eq(child.api.nvim_tabpage_get_number(0), split == 'tab' and 2 or 1)

      local ref_layout = ({
        horizontal = { 'col', { { 'leaf', cur_win_id }, { 'leaf', init_win_id } } },
        vertical = { 'row', { { 'leaf', cur_win_id }, { 'leaf', init_win_id } } },
        tab = { 'leaf', cur_win_id },
      })[split]
      eq(child.fn.winlayout(), ref_layout)
    end,
  }
)

T['show_diff_source()']['works with `opts.split = "auto"`'] = function()
  child.lua([[_G.stdio_queue = {
    { { 'out', 'Line 1\nCurrent line 2\nLine 3' } }, -- Diff source
    { { 'out', 'Line 4\nCurrent line 5\nLine 6' } }, -- Diff source
  }]])

  local init_buf_id, init_win_id = get_buf(), child.api.nvim_get_current_win()

  -- Should open in new tabpage if there is a non-minigit buffer visible
  child.cmd('vertical split')
  local buf_id = new_scratch_buf()
  set_buf(buf_id)
  child.api.nvim_buf_set_name(buf_id, make_minigit_name(buf_id, 'some mini.git buffer'))
  eq(child.fn.winlayout()[1], 'row')

  child.api.nvim_set_current_win(init_win_id)
  set_cursor(17, 0)
  show_diff_source({ split = 'auto' })
  local win_id_1 = child.api.nvim_get_current_win()
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(child.fn.winlayout(), { 'leaf', win_id_1 })

  -- Should split vertically if there are only minigit buffers visible
  set_buf(init_buf_id)
  child.api.nvim_buf_set_name(0, make_minigit_name(0, 'log -L1,1:file'))
  set_cursor(17, 0)
  show_diff_source({ split = 'auto' })
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(child.fn.winlayout(), { 'row', { { 'leaf', child.api.nvim_get_current_win() }, { 'leaf', win_id_1 } } })
end

T['show_diff_source()']['respects `opts.target`'] = function()
  child.lua([[
    local item = { { 'out', 'Line 1\nCurrent line 2\nLine 3' } }
    _G.stdio_queue = {
      item, -- 'before'
      item, -- 'before'
      item, -- 'after'
      item, -- 'after'
      item, item, -- 'both'
      item, item, -- 'both'
      item, item, -- 'both'
      item, item, -- 'both'
    }]])

  local init_lines = get_lines()
  local commit_after = '5ed8432441b495fa9bd4ad2e4f635bae64e95cc2'
  local commit_before = commit_after .. '~'
  local name_after = 'show ' .. commit_after .. ':dir/file-after'
  local name_before = 'show ' .. commit_before .. ':dir/file-before'

  local validate = function(target, lnum, layout_type, name, cursor)
    child.cmd('%bwipeout!')
    set_lines(init_lines)

    set_cursor(lnum, 0)
    show_diff_source({ target = target, split = 'tab' })

    local layout = child.fn.winlayout()
    eq(layout[1], layout_type)
    validate_minigit_name(0, name)
    eq(get_cursor(), cursor)

    if layout_type == 'row' then
      -- Current window with "after" file should be on the right
      local all_wins, cur_win = child.api.nvim_tabpage_list_wins(0), child.api.nvim_get_current_win()
      local other_win = all_wins[1] == cur_win and all_wins[2] or all_wins[1]
      eq(layout, { 'row', { { 'leaf', other_win }, { 'leaf', cur_win } } })

      -- Other window should contain "before" file
      local other_buf = child.api.nvim_win_get_buf(other_win)
      validate_minigit_name(other_buf, name_before)
    end
  end

  -- "Before" should always show "before" file
  validate('before', 17, 'leaf', name_before, { 2, 0 })
  -- - Even when cursor is on "+++ b/yyy" line
  validate('before', 13, 'leaf', name_before, { 1, 0 })

  -- "After" should always show "after" file
  validate('after', 16, 'leaf', name_after, { 1, 0 })
  -- - Even when cursor is on "--- a/xxx" line
  validate('after', 12, 'leaf', name_after, { 1, 0 })

  -- "Both" should always show vertical split with "after" to the right
  validate('both', 16, 'row', name_after, { 1, 0 })
  validate('both', 17, 'row', name_after, { 2, 0 })
  validate('both', 12, 'row', name_after, { 1, 0 })
  validate('both', 13, 'row', name_after, { 1, 0 })
end

T['show_diff_source()']['uses correct working directory'] = function()
  local root, repo = test_dir_absolute, git_repo_dir
  local rev_parse_track = repo .. '\n' .. root
  child.lua('_G.rev_parse_track = ' .. vim.inspect(rev_parse_track))
  child.lua([[_G.stdio_queue = {
      { { 'out', _G.rev_parse_track } }, -- Get path to root and repo
      { { 'out', 'abc1234\nmain' } },    -- Get HEAD data
      { { 'out', 'A  log-output' } },    -- Get file status data

      { { 'out', 'Line 1\nCurrent line 2\nLine 3' } } -- Show diff source
    }
  ]])

  edit(test_dir_absolute .. '/log-output')
  child.fn.chdir(git_dir_path)

  set_cursor(17, 0)
  show_diff_source()

  --stylua: ignore
  local ref_git_spawn_log = {
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' },
      cwd = test_dir_absolute,
    },
    {
      args = { '-c', 'gc.auto=0', 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' },
      cwd = root,
    },
    {
      args = {
        '-c', 'gc.auto=0', 'status', '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z',
        '--', 'log-output'
      },
      cwd = root,
    },
    -- Should prefer buffer's Git root over Neovim's cwd. This is relevant if,
    -- for some reason, log output is tracked in Git repo.
    {
      args = { 'show', '5ed8432441b495fa9bd4ad2e4f635bae64e95cc2:dir/file-after' },
      cwd = root,
    },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['show_diff_source()']['validates arguments'] = function()
  local validate = function(opts, error_pattern)
    expect.error(function() show_diff_source(opts) end, error_pattern)
  end

  validate({ split = 'a' }, 'opts%.split.*one of')
  validate({ target = 'a' }, 'opts%.target.*one of')
end

T['show_range_history()'] = new_set({
  hooks = {
    pre_case = function()
      load_module()
      set_lines({ 'aaa', 'bbb', 'ccc' })
      child.fn.chdir(git_root_dir)
      child.api.nvim_buf_set_name(0, git_root_dir .. '/dir/tmp-file')
      child.lua([[_G.stdio_queue = {
        { { 'out', '' } },                           -- No uncommitted changes
        { { 'out', 'commit abc1234\nLog output' } }, -- Asked logs
      }]])
    end,
  },
})

local show_range_history = forward_lua('MiniGit.show_range_history')

T['show_range_history()']['works in Normal mode'] = function()
  show_range_history()

  local ref_git_spawn_log = {
    { args = { 'diff', '-U0', 'HEAD', '--', 'dir/tmp-file' }, cwd = git_root_dir },
    { args = { 'log', '-L1,1:dir/tmp-file', 'HEAD' }, cwd = git_root_dir },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- Should show in a new tabpage (with default `opts.split`) in proper buffer
  eq(#child.api.nvim_list_tabpages(), 2)
  eq(child.api.nvim_tabpage_get_number(0), 2)

  validate_minigit_name(0, 'log -L1,1:dir/tmp-file HEAD')
  eq(child.bo.filetype, 'git')
  eq(get_lines(), { 'commit abc1234', 'Log output' })
end

T['show_range_history()']['works in Visual mode'] = function()
  set_cursor(2, 0)
  type_keys('vj')

  show_range_history()
  local ref_git_spawn_log = {
    { args = { 'diff', '-U0', 'HEAD', '--', 'dir/tmp-file' }, cwd = git_root_dir },
    -- Should use lines of Visual selection
    { args = { 'log', '-L2,3:dir/tmp-file', 'HEAD' }, cwd = git_root_dir },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  validate_minigit_name(0, 'log -L2,3:dir/tmp-file HEAD')
end

T['show_range_history()']['works in output of `show_diff_source()`'] = function()
  child.lua([[_G.stdio_queue = {
    { { 'out', 'Line 1\nCurrent line 2\nLine 3' } }, -- Diff source
    -- Should not ask for presence of uncommitted changes
    { { 'out', 'commit abc1234\nLog output' } },    -- Asked logs
  }]])

  -- Show diff source
  local log_output = child.fn.readfile(test_dir_absolute .. '/log-output')
  set_lines(log_output)
  set_cursor(17, 0)

  show_diff_source()
  eq(get_lines(), { 'Line 1', 'Current line 2', 'Line 3' })
  eq(get_cursor(), { 2, 0 })

  -- Should properly parse file name and commit
  show_range_history()

  local ref_git_spawn_log = {
    { args = { 'show', '5ed8432441b495fa9bd4ad2e4f635bae64e95cc2:dir/file-after' }, cwd = git_root_dir },
    { args = { 'log', '-L2,2:dir/file-after', '5ed8432441b495fa9bd4ad2e4f635bae64e95cc2' }, cwd = git_root_dir },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  validate_minigit_name(0, 'log -L2,2:dir/file-after 5ed8432441b495fa9bd4ad2e4f635bae64e95cc2')
end

T['show_range_history()']['respects `opts.line_start` and `opts.line_end`'] = function()
  show_range_history({ line_start = 2, line_end = 3 })

  local ref_git_spawn_log = {
    { args = { 'diff', '-U0', 'HEAD', '--', 'dir/tmp-file' }, cwd = git_root_dir },
    { args = { 'log', '-L2,3:dir/tmp-file', 'HEAD' }, cwd = git_root_dir },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  validate_minigit_name(0, 'log -L2,3:dir/tmp-file HEAD')
end

T['show_range_history()']['respects `opts.log_args`'] = function()
  show_range_history({ log_args = { '--oneline', '--topo-order' } })

  local ref_git_spawn_log = {
    { args = { 'diff', '-U0', 'HEAD', '--', 'dir/tmp-file' }, cwd = git_root_dir },
    { args = { 'log', '-L1,1:dir/tmp-file', 'HEAD', '--oneline', '--topo-order' }, cwd = git_root_dir },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  validate_minigit_name(0, 'log -L1,1:dir/tmp-file HEAD --oneline --topo-order')
end

T['show_range_history()']['respects `opts.split`'] = new_set(
  { parametrize = { { 'horizontal' }, { 'vertical' }, { 'tab' } } },
  {
    test = function(split)
      local init_win_id = child.api.nvim_get_current_win()
      show_range_history({ split = split })
      local cur_win_id = child.api.nvim_get_current_win()

      local ref_git_spawn_log = {
        { args = { 'diff', '-U0', 'HEAD', '--', 'dir/tmp-file' }, cwd = git_root_dir },
        { args = { 'log', '-L1,1:dir/tmp-file', 'HEAD' }, cwd = git_root_dir },
      }
      validate_git_spawn_log(ref_git_spawn_log)

      validate_minigit_name(0, 'log -L1,1:dir/tmp-file HEAD')

      -- Validate proper split
      eq(#child.api.nvim_list_tabpages(), split == 'tab' and 2 or 1)
      eq(child.api.nvim_tabpage_get_number(0), split == 'tab' and 2 or 1)

      local ref_layout = ({
        horizontal = { 'col', { { 'leaf', cur_win_id }, { 'leaf', init_win_id } } },
        vertical = { 'row', { { 'leaf', cur_win_id }, { 'leaf', init_win_id } } },
        tab = { 'leaf', cur_win_id },
      })[split]
      eq(child.fn.winlayout(), ref_layout)
    end,
  }
)

T['show_range_history()']['works with `opts.split = "auto"`'] = function()
  child.lua([[_G.stdio_queue = {
    { { 'out', '' } },                           -- No uncommitted changes
    { { 'out', 'commit abc1234\nLog output' } }, -- Asked logs
    { { 'out', '' } },                           -- No uncommitted changes
    { { 'out', 'commit def4321\nSomething' } },  -- Asked logs
  }]])

  -- Should open in new tabpage if there is a non-minigit buffer visible
  child.cmd('vertical split')
  local buf_id = new_scratch_buf()
  set_buf(buf_id)
  child.api.nvim_buf_set_name(buf_id, make_minigit_name(buf_id, 'some mini.git buffer'))
  eq(child.fn.winlayout()[1], 'row')

  show_range_history({ split = 'auto' })
  local win_id_1 = child.api.nvim_get_current_win()
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(child.fn.winlayout(), { 'leaf', win_id_1 })

  -- Should split vertically if there are only minigit buffers visible
  show_range_history({ split = 'auto' })
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(child.fn.winlayout(), { 'row', { { 'leaf', child.api.nvim_get_current_win() }, { 'leaf', win_id_1 } } })
end

T['show_range_history()']['does nothing in presence of uncommitted changes'] = function()
  child.lua([[_G.stdio_queue = {
    { { 'out', 'diff --git aaa bbb\nSomething' } }, -- There are uncommitted changes
  }]])

  show_range_history()

  local ref_git_spawn_log = {
    { args = { 'diff', '-U0', 'HEAD', '--', 'dir/tmp-file' }, cwd = git_root_dir },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  validate_notifications({
    { '(mini.git) Current file has uncommitted lines. Commit or stash before exploring history.', 'WARN' },
  })
end

T['show_range_history()']['uses correct working directory'] = function()
  mock_init_track_stdio_queue()
  child.lua([[_G.stdio_queue = {
    _G.init_track_stdio_queue[1],
    _G.init_track_stdio_queue[2],
    _G.init_track_stdio_queue[3],

    { { 'out', '' } },                           -- No uncommitted changes
    { { 'out', 'commit abc1234\nLog output' } }, -- Asked logs
  }]])

  edit(git_root_dir .. '/dir-in-git/file-in-dir-in-git')
  child.fn.chdir(test_dir_absolute)

  show_range_history()

  --stylua: ignore
  local ref_git_spawn_log = {
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
    -- Should prefer buffer's Git root over Neovim's cwd
    { args = { 'diff', '-U0', 'HEAD', '--', 'dir-in-git/file-in-dir-in-git' }, cwd = git_root_dir },
    { args = { 'log', '-L1,1:dir-in-git/file-in-dir-in-git', 'HEAD' }, cwd = git_root_dir },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['show_range_history()']['validates arguments'] = function()
  local validate = function(opts, error_pattern)
    expect.error(function() show_range_history(opts) end, error_pattern)
  end

  validate({ line_start = 'a' }, 'line_start.*number')
  validate({ line_end = 'a' }, 'line_end.*number')
  -- - Supplying only one line means that the other won't be inferred
  validate({ line_start = 1 }, 'number')
  validate({ line_end = 1 }, 'number')
  validate({ line_start = 2, line_end = 1 }, 'non%-decreasing')
  validate({ log_args = 1 }, 'log_args.*array')
  validate({ log_args = { a = 1 } }, 'log_args.*array')
  validate({ split = 'a' }, 'opts%.split.*one of')
end

T['diff_foldexpr()'] = new_set({ hooks = { pre_case = load_module } })

T['diff_foldexpr()']['works in `git log` output'] = function()
  child.set_size(70, 50)
  child.o.laststatus = 0
  edit(test_dir_absolute .. '/log-output')
  child.cmd('setlocal foldmethod=expr foldexpr=v:lua.MiniGit.diff_foldexpr()')

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
  child.cmd('setlocal foldmethod=expr foldexpr=v:lua.MiniGit.diff_foldexpr()')

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

T['diff_foldexpr()']['accepts optional line number'] = function()
  edit(test_dir_absolute .. '/log-output')
  eq(child.lua_get('MiniGit.diff_foldexpr(1)'), 0)
  eq(child.lua_get('MiniGit.diff_foldexpr(2)'), '=')
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
