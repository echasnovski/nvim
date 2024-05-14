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
local get_win = function() return child.api.nvim_get_current_win() end
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

local show_at_cursor = forward_lua('MiniGit.show_at_cursor')

T['show_at_cursor()']['works on commit'] = function()
  set_lines({ 'abc1234.def' })
  set_cursor(1, 0)
  child.lua([[_G.stdio_queue = { { { 'out', 'commit abc123456\nHello' } } }]])

  show_at_cursor()

  local ref_git_spawn_log = { { args = { 'show', 'abc1234' }, cwd = child.fn.getcwd() } }
  validate_git_spawn_log(ref_git_spawn_log)

  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(get_lines(), { 'commit abc123456', 'Hello' })
  eq(child.o.filetype, 'git')

  -- Should use `<cword>`
  child.o.iskeyword = child.o.iskeyword .. ',.'
  show_at_cursor()
  -- - No extra calls because "abc1234.def" does not match commit pattern
  validate_git_spawn_log(ref_git_spawn_log)
end

T['show_at_cursor()']['uses correct pattern to match commit'] = function()
  log_calls('MiniGit.show_at_cursor')

  set_lines({ 'abc1234', 'abc123', 'abC1234', 'abc123x' })

  local validate = function(line, n_cli_calls)
    set_cursor(line, 0)
    show_at_cursor()
    eq(#get_spawn_log(), n_cli_calls)
  end

  eq(#get_spawn_log(), 0)
  validate(1, 1)
  validate(2, 1)
  validate(3, 1)
  validate(4, 1)
end

T['show_at_cursor()']['uses `opts` on commit'] = function()
  set_lines({ 'abc1234' })
  child.lua([[_G.stdio_queue = { { { 'out', 'commit abc123456\nHello' } } }]])

  local init_win_id = get_win()
  show_at_cursor({ split = 'vertical' })

  eq(child.api.nvim_tabpage_get_number(0), 1)
  eq(child.fn.winlayout(), { 'row', { { 'leaf', get_win() }, { 'leaf', init_win_id } } })
  eq(get_lines(), { 'commit abc123456', 'Hello' })
  eq(child.o.filetype, 'git')
end

T['show_at_cursor()']['works for diff source'] = function()
  child.lua('MiniGit.show_diff_source = function() end')
  log_calls('MiniGit.show_diff_source')

  local log_output = child.fn.readfile(test_dir_absolute .. '/log-output')
  set_lines(log_output)
  set_cursor(17, 0)

  local opts = { split = 'vertical', target = 'both' }
  show_at_cursor(opts)
  validate_calls({ { 'MiniGit.show_diff_source', opts } })
end

T['show_at_cursor()']['works for range history in tracked file'] = function()
  child.lua('MiniGit.show_range_history = function() end')
  log_calls('MiniGit.show_range_history')

  mock_init_track_stdio_queue()
  child.lua([[_G.stdio_queue = _G.init_track_stdio_queue]])
  edit(git_file_path)
  eq(is_buf_enabled(), true)

  local opts = { line_start = 1, line_end = 2, split = 'vertical', log_args = { '--oneline' } }
  show_at_cursor(opts)
  validate_calls({ { 'MiniGit.show_range_history', opts } })
end

T['show_at_cursor()']['works for range history in `show_diff_source()` output'] = function()
  child.lua('MiniGit.show_range_history = function() end')
  log_calls('MiniGit.show_range_history')

  child.lua([[_G.stdio_queue = { { { 'out', 'Line 1\nCurrent line 2\nLine 3' } } }]])
  local log_output = child.fn.readfile(test_dir_absolute .. '/log-output')
  set_lines(log_output)
  set_cursor(17, 0)
  child.lua('MiniGit.show_diff_source()')

  local opts = { line_start = 1, line_end = 2, split = 'vertical', log_args = { '--oneline' } }
  show_at_cursor(opts)
  validate_calls({ { 'MiniGit.show_range_history', opts } })
end

T['show_at_cursor()']['works on nothing'] = function()
  expect.no_error(show_at_cursor)
  validate_notifications({ { '(mini.git) Nothing Git-related to show at cursor', 'WARN' } })
end

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

local show_diff_source = forward_lua('MiniGit.show_diff_source')

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

T['show_diff_source()']['works when there is no "before" file'] = function()
  child.lua([[_G.stdio_queue = {
    { { 'out', 'Line 1\nCurrent line 2\nLine 3' } }, -- Diff source
  }]])
  set_lines({
    'commit 5ed8432441b495fa9bd4ad2e4f635bae64e95cc2',
    'Author: Neo McVim <neo.mcvim@gmail.com>',
    'Date:   Sat May 4 16:24:15 2024 +0300',
    '',
    'Add file.',
    '',
    'diff --git a/file b/file',
    'new file mode 100644',
    'index 0000000..f9264f7',
    '--- /dev/null',
    '+++ b/file',
    '@@ -0,0 +1,2 @@',
    '+Hello',
    '+World',
  })

  -- Target "before" should do nothing while showing notification
  local init_buf_id = get_buf()
  set_cursor(13, 0)

  show_diff_source({ target = 'before' })
  eq(get_buf(), init_buf_id)
  eq(child.api.nvim_buf_get_name(0), '')

  validate_git_spawn_log({})
  clear_spawn_log()
  validate_notifications({ { '(mini.git) Could not find "before" file', 'WARN' } })
  clear_notify_log()

  -- Target "both" should show only "after" in a specified split
  set_cursor(13, 0)
  show_diff_source({ target = 'both' })

  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(#child.api.nvim_tabpage_list_wins(0), 1)
  validate_minigit_name(0, 'show 5ed8432441b495fa9bd4ad2e4f635bae64e95cc2:file')

  validate_notifications({ { '(mini.git) Could not find "before" file', 'WARN' } })
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

      local init_win_id = get_win()
      show_diff_source({ split = split })
      local cur_win_id = get_win()

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

  local init_buf_id, init_win_id = get_buf(), get_win()

  -- Should open in new tabpage if there is a non-minigit buffer visible
  child.cmd('vertical split')
  local buf_id = new_scratch_buf()
  set_buf(buf_id)
  child.api.nvim_buf_set_name(buf_id, make_minigit_name(buf_id, 'some mini.git buffer'))
  eq(child.fn.winlayout()[1], 'row')

  child.api.nvim_set_current_win(init_win_id)
  set_cursor(17, 0)
  show_diff_source({ split = 'auto' })
  local win_id_1 = get_win()
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(child.fn.winlayout(), { 'leaf', win_id_1 })

  -- Should split vertically if there are only minigit buffers visible
  set_buf(init_buf_id)
  child.api.nvim_buf_set_name(0, make_minigit_name(0, 'log -L1,1:file'))
  set_cursor(17, 0)
  show_diff_source({ split = 'auto' })
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(child.fn.winlayout(), { 'row', { { 'leaf', get_win() }, { 'leaf', win_id_1 } } })
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
      local all_wins, cur_win = child.api.nvim_tabpage_list_wins(0), get_win()
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

T['show_range_history()']['works with `diff_foldexpr`'] = function()
  child.cmd('au FileType git setlocal foldmethod=expr foldexpr=v:lua.MiniGit.diff_foldexpr()')
  show_range_history()
  eq(child.wo.foldmethod, 'expr')
  eq(child.wo.foldexpr, 'v:lua.MiniGit.diff_foldexpr()')
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
      local init_win_id = get_win()
      show_range_history({ split = split })
      local cur_win_id = get_win()

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
  local win_id_1 = get_win()
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(child.fn.winlayout(), { 'leaf', win_id_1 })

  -- Should split vertically if there are only minigit buffers visible
  show_range_history({ split = 'auto' })
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(child.fn.winlayout(), { 'row', { { 'leaf', get_win() }, { 'leaf', win_id_1 } } })
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

T[':Git'] = new_set({
  hooks = {
    pre_case = function()
      load_module()

      -- Mock initial spawns for gathering subcommand data
      child.lua([[
        _G.stdio_queue = {
          -- Get supported subcommands
          { { 'out', 'add\nblame\ndiff\nlog\npush\npull\nshow\nreflog\nl' } },
          -- Get "info showing" subcommands
          { { 'out', 'blame\ndiff\nlog\nshow' } },
          -- Get aliases
          { { 'out', 'alias.l log -5' } },
        }
      ]])
    end,
  },
})

--stylua: ignore
local validate_command_init_setup = function(log_index, executable, cwd)
  log_index = log_index or 1
  executable = executable or 'git'
  cwd = cwd or child.fn.getcwd()

  local spawn_log = get_spawn_log()

  -- Get supported subcommands
  local supported_lists = table.concat({
    'list-mainporcelain',
    'list-ancillarymanipulators', 'list-ancillaryinterrogators',
    'list-foreignscminterface',
    'list-plumbingmanipulators', 'list-plumbinginterrogators',
    'others', 'alias',
  }, ',')
  eq(
    spawn_log[log_index],
    { executable = executable, options = {  args = { '--list-cmds=' .. supported_lists }, cwd = cwd } }
  )

  -- Get "info showing" subcommands
  local info_lists = table.concat({ 'list-info', 'list-ancillaryinterrogators', 'list-plumbinginterrogators' }, ',')
  eq(
    spawn_log[log_index + 1],
    { executable = executable, options = { args = { '--list-cmds=' .. info_lists }, cwd = cwd } }
  )

  -- Get aliases
  eq(
    spawn_log[log_index + 2],
    { executable = executable, options = { args = { 'config','--get-regexp','alias.*', }, cwd = cwd } }
  )
end

local validate_command_call = function(log_index, args, executable, cwd)
  executable = executable or 'git'
  cwd = cwd or child.fn.getcwd()

  local log_entry = get_spawn_log()[log_index]

  eq(log_entry.executable, executable)
  eq(log_entry.options.args, args)
  eq(log_entry.options.cwd, cwd)

  -- Should set proper environment variables
  local env_vars = { GIT_EDITOR = false, GIT_SEQUENCE_EDITOR = false, GIT_PAGER = false, NO_COLOR = false }

  for _, env_pair in ipairs(log_entry.options.env) do
    for var_name, _ in pairs(env_vars) do
      if vim.startswith(env_pair, var_name .. '=') then env_vars[var_name] = true end
    end
  end

  local ref_env_vars = vim.deepcopy(env_vars)
  for var_name, _ in pairs(ref_env_vars) do
    ref_env_vars[var_name] = true
  end
  eq(env_vars, ref_env_vars)
end

T[':Git']['works'] = function()
  child.lua([[
    -- Command stdout
    table.insert(_G.stdio_queue, { { 'out', 'abc1234 Hello\ndef4321 World' } })

    -- Mock non-trivial command execution time
    _G.process_mock_data = { [4] = { duration = 50 } }
  ]])

  -- Should execute command synchronously
  local start_time = vim.loop.hrtime()
  child.cmd('Git log --oneline')
  local duration = 0.000001 * (vim.loop.hrtime() - start_time)
  eq(50 <= duration and duration <= 70, true)

  -- Should properly gather subcommand data before executing command
  local spawn_log = get_spawn_log()
  validate_command_init_setup()
  validate_command_call(4, { 'log', '--oneline' })
  eq(#spawn_log, 4)

  -- Should in some way show the output
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(get_lines(), { 'abc1234 Hello', 'def4321 World' })
  eq(child.bo.filetype, 'git')
  eq(child.bo.buflisted, false)
  eq(child.bo.swapfile, false)
  eq(child.wo.foldlevel, 999)
end

T[':Git']['works asynchronously with bang modifier'] = function()
  child.lua([[
    -- Command stdout
    table.insert(_G.stdio_queue, { { 'out', 'abc1234 Hello\ndef4321 World' } })

    -- Mock non-trivial command execution time
    _G.process_mock_data = { [4] = { duration = 50 } }
  ]])

  -- Should execute command asynchronously
  local start_time = vim.loop.hrtime()
  child.cmd('Git! log')
  local duration = 0.000001 * (vim.loop.hrtime() - start_time)
  eq(duration <= small_time, true)

  -- Should properly gather subcommand data before executing command
  eq(#get_spawn_log(), 4)

  -- Should in some way show the output when the process is done
  eq(child.bo.filetype == 'git', false)
  sleep(50 - small_time)
  eq(child.bo.filetype == 'git', false)
  sleep(2 * small_time)
  eq(child.bo.filetype == 'git', true)
end

T[':Git']['respects command modifiers'] = function()
  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'abc1234 Hello\ndef4321 World' } })]])
  local init_win_id = get_win()
  -- Should also work with abbreviated versions
  child.cmd('vertical bel Git log')
  eq(child.bo.filetype, 'git')
  eq(child.fn.winlayout(), { 'row', { { 'leaf', init_win_id }, { 'leaf', get_win() } } })
end

T[':Git']['works for subcommands which were not recognized as supported'] = function()
  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'Success' } })]])
  child.cmd('Git doesnotexist --hello')
  validate_command_init_setup()
  validate_command_call(4, { 'doesnotexist', '--hello' })
  validate_notifications({ { '(mini.git) Success', 'INFO' } })
  eq(#child.api.nvim_list_tabpages(), 1)
end

T[':Git']['output'] = new_set()

T[':Git']['output']['in buffer when explicitly asked'] = function()
  local validate = function(modifier)
    child.cmd('%bwipeout')
    eq(get_lines(), { '' })
    local init_buf_id = get_buf()

    child.lua([[table.insert(_G.stdio_queue, { { 'out', 'Pushed successfully' } })]])
    child.cmd(modifier .. ' Git push')
    eq(get_buf() == init_buf_id, false)
    eq(get_lines(), { 'Pushed successfully' })
    validate_notifications({})
  end

  validate('tab')
  validate('vertical')
  validate('vert')

  if child.fn.has('nvim-0.8') == 1 then
    validate('horizontal')
    validate('hor')
  end
end

T[':Git']['output']['in notifications when not in buffer'] = function()
  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'Pushed successfully' } })]])
  local init_buf_id = get_buf()
  child.cmd('Git push')
  eq(get_buf() == init_buf_id, true)
  eq(get_lines(), { '' })
  validate_notifications({ { '(mini.git) Pushed successfully', 'INFO' } })
end

T[':Git']['output']['is omitted if no or empty `stdout` was given'] = function()
  child.lua([[table.insert(_G.stdio_queue, { { 'out', '' } })]])
  child.cmd('Git log')
  eq(child.bo.filetype == 'git', false)
  validate_notifications({})
end

T[':Git']['output']['respects `:silent` modifier'] = function()
  local validate = function(command)
    child.cmd('%bwipeout')
    child.lua([[table.insert(_G.stdio_queue, { { 'out', 'Hello' } })]])
    local init_buf_id = get_buf()
    child.cmd(command)
    eq(get_buf() == init_buf_id, true)
    eq(get_lines(), { '' })
    validate_notifications({})
  end

  -- Should show nothing in buffer
  validate('silent Git log')

  -- Should show no notifications
  validate('silent Git push')

  -- Should prefer `:silent` over explicit split modifiers
  validate('silent vertical Git log')
end

T[':Git']['output']['respects `:unsilent` modifier'] = function()
  local validate = function(command)
    child.cmd('%bwipeout')
    child.lua([[table.insert(_G.stdio_queue, { { 'out', 'Hello' } })]])
    local init_buf_id = get_buf()
    child.cmd(command)
    eq(get_buf() == init_buf_id, false)
    eq(get_lines(), { 'Hello' })
  end

  -- Should prefer `:unsilent` over `:silent`
  validate('silent unsilent Git log')
  if child.fn.has('nvim-0.8') == 1 then validate('unsilent silent Git log') end
end

T[':Git']['output']['defines proper window/buffer cleanup'] = function()
  -- Should delete buffer when window is closed
  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'Hello' } })]])
  child.cmd('vertical Git log')

  local buf_id_1 = get_buf()
  eq(child.bo.filetype, 'git')
  eq(get_lines(), { 'Hello' })

  child.cmd('quit')
  eq(child.api.nvim_buf_is_valid(buf_id_1), false)

  -- Should close window when buffer is deleted
  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'World' } })]])
  child.cmd('vertical Git log')
  local buf_id_2, win_id_2 = get_buf(), get_win()
  set_buf(new_scratch_buf())
  eq(#child.api.nvim_tabpage_list_wins(0), 2)
  child.api.nvim_buf_delete(buf_id_2, { force = true })
  eq(#child.api.nvim_tabpage_list_wins(0), 1)
  eq(get_win() == win_id_2, false)
end

T[':Git']['output']['respects aliases'] = function()
  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'Commit abc12345\nHello' } })]])
  -- The `l` is a an alias for `log -5` according to initial command setup
  -- Thus should show output in a split (because 'log' does)
  child.cmd('Git l')
  eq(get_lines(), { 'Commit abc12345', 'Hello' })
  eq(child.bo.filetype, 'git')
end

T[':Git']['can show process errors'] = function()
  child.lua([[
    table.insert(_G.stdio_queue, { { 'out', 'Extra info' }, { 'err', 'Error!' } })
    _G.process_mock_data = { [4] = { exit_code = 1 } }
  ]])

  child.cmd('Git log')
  eq(child.api.nvim_tabpage_get_number(0), 1)
  eq(child.bo.filetype == 'git', false)
  eq(get_lines(), { '' })

  validate_notifications({ { '(mini.git) Error!\nExtra info', 'ERROR' } })
end

T[':Git']['can show process warnings'] = function()
  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'Hello' }, { 'err', 'Diagnostic' } })]])

  child.cmd('Git log')
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(child.bo.filetype, 'git')
  eq(get_lines(), { 'Hello' })

  validate_notifications({ { '(mini.git) Diagnostic', 'WARN' } })
end

T[':Git']['preserves environment variables'] = function()
  child.loop.os_setenv('HELLO', 'WORLD')

  child.cmd('Git log')
  local environ = get_spawn_log()[4].options.env
  local has_var = false
  for _, env_pair in ipairs(environ) do
    if env_pair == 'HELLO=WORLD' then has_var = true end
  end
  eq(has_var, true)
end

T[':Git']['opens `GIT_EDITOR` in current instance'] = function()
  -- Should also ignore timeout
  MiniTest.skip()
end

T[':Git']['uses correct working directory'] = function()
  local root, repo = test_dir_absolute, git_repo_dir
  local rev_parse_track = repo .. '\n' .. root
  child.lua('_G.rev_parse_track = ' .. vim.inspect(rev_parse_track))
  child.lua([[_G.stdio_queue = {
      -- File tracking
      { { 'out', _G.rev_parse_track } }, -- Get path to root and repo
      { { 'out', 'abc1234\nmain' } },    -- Get HEAD data
      { { 'out', 'M  file-in-git' } },   -- Get file status data

      -- Command initial setup
      { { 'out', 'add\nblame\ndiff\nlog\npush\npull\nshow\nl' } }, -- Get supported subcommands
      { { 'out', 'blame\ndiff\nlog\nshow' } },                     -- Get "info showing" subcommands
      { { 'out', 'alias.l log -5' } },                             -- Get aliases

      -- Command output
      { { 'out', 'Comment abc1234\nHello' } }
    }
  ]])

  edit(git_file_path)
  eq(get_buf_data().root, root)
  child.fn.chdir(git_dir_path)

  child.cmd('Git log')

  -- Actual command should be run in file's Git root
  validate_command_init_setup(4, 'git', child.fn.getcwd())
  validate_command_call(7, { 'log' }, 'git', root)
end

T[':Git']['caches subcommand data'] = function()
  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'Hello' } })]])
  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'World' } })]])

  child.cmd('Git log --one')
  child.cmd('Git log --two')
  child.cmd('Git log --three')

  -- Should collect helper subcommand data only once
  validate_command_init_setup()
  validate_command_call(4, { 'log', '--one' })
  validate_command_call(5, { 'log', '--two' })
  validate_command_call(6, { 'log', '--three' })
  eq(#get_spawn_log(), 6)
end

T[':Git']['works with no initial subcommand data'] = function()
  child.lua([[_G.stdio_queue = {
    { { 'out', '' } },                          -- Not successful `--list-cmds` for supported commands
    { { 'out', ''}, { 'err', 'What\nError' } }, -- Not successful `--list-cmds` for info commands
    { { 'out', '' }, { 'err', 'Error' } },      -- Not successful alias data gathering

    { {'out', 'Hello'} } -- Command output
  }]])

  -- Should use some defaults. Like "log" should still show output in buffer.
  child.cmd('Git log')
  eq(child.api.nvim_tabpage_get_number(0), 2)
  eq(child.bo.filetype, 'git')
end

T[':Git']['checks for present executable'] = function()
  child.lua('vim.fn.executable = function() return 0 end')
  load_module()
  validate_notifications({ { '(mini.git) There is no `git` executable', 'WARN' } })
  clear_notify_log()

  child.cmd('Git log')
  eq(#get_spawn_log(), 0)
  validate_notifications({ { '(mini.git) There is no `git` executable', 'ERROR' } })
end

T[':Git']['respects `job.git_executable`'] = function()
  child.lua('vim.fn.executable = function() return 1 end')
  load_module({ job = { git_executable = 'my_git' } })

  child.cmd('Git log')
  eq(get_spawn_log()[4].executable, 'my_git')
end

T[':Git']['respects `job.timeout`'] = function()
  child.lua([[
    table.insert(_G.stdio_queue, { { 'out', 'Hello' } })

    _G.process_mock_data = { [4] = { duration = 50 } }
  ]])

  child.lua('MiniGit.config.job.timeout = 20')

  local start_time = vim.loop.hrtime()
  child.cmd('Git log')
  local duration = 0.000001 * (vim.loop.hrtime() - start_time)
  eq(15 <= duration and duration <= 25, true)

  local ref_notify_log = {
    { '(mini.git) PROCESS REACHED TIMEOUT', 'WARN' },
    -- Should still process `stdout`/`stderr` which was already supplied
    -- Shown as error because timeout is treated same as error
    { '(mini.git) \nHello', 'ERROR' },
  }
  validate_notifications(ref_notify_log)
end

T[':Git']['respects `command.split`'] = function()
  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'Hello' } })]])
  child.lua([[MiniGit.config.command.split = 'vertical']])

  local init_win_id = get_win()
  child.cmd('Git log')
  eq(child.bo.filetype, 'git')
  eq(child.fn.winlayout(), { 'row', { { 'leaf', get_win() }, { 'leaf', init_win_id } } })
end

T[':Git']['completion'] = new_set({
  hooks = {
    pre_case = function()
      child.fn.chdir(test_dir_absolute)
      child.lua([[_G.help_lines = vim.fn.readfile('help-output')]])
      child.lua([[_G.help_output = { { 'out', table.concat(_G.help_lines, '\n') } }]])

      child.set_size(16, 32)
      child.o.cmdheight = 2
      child.o.laststatus = 0
    end,
  },
})

local validate_command_completion = function(line, col)
  local line_len = vim.api.nvim_strwidth(line)
  col = col or (line_len + 1)
  if col < 0 then col = line_len + 1 + col end

  type_keys('<C-c>', line)
  for _ = line_len, col, -1 do
    type_keys('<Left>')
  end
  type_keys('<Tab>')
  child.expect_screenshot()
end

T[':Git']['completion']['works with subcommands'] = function()
  validate_command_completion(':Git ')
  validate_command_completion(':Git l')

  -- Should work if there is text afterwards
  validate_command_completion(':Git  -v', -3)

  -- Should also work with two word subcommands
  validate_command_completion(':Git reflog')
  validate_command_completion(':Git reflog -v', -3)
end

T[':Git']['collects data about available subcommands'] = function()
  type_keys(':Git ', '<Tab>')
  validate_command_init_setup()

  -- Should cache result and do this only once
  type_keys('<C-c>', ':Git ', '<Tab>')
  eq(#get_spawn_log(), 3)
end

T[':Git']['completion']['works with options'] = function()
  child.set_size(20, 32)
  child.lua('table.insert(_G.stdio_queue, _G.help_output)')

  -- Should get output by making CLI call
  validate_command_completion(':Git push -')

  local spawn_log = get_spawn_log()
  eq(#spawn_log, 4)
  eq(spawn_log[4].options, { args = { 'help', '--man', 'push' }, cwd = child.fn.getcwd() })

  -- Should work several times
  type_keys(' --', '<Tab>')
  child.expect_screenshot()

  -- Should pre-filter candidates
  validate_command_completion(':Git push --')
  validate_command_completion(':Git push --no')

  -- Should work when there is text afterwards
  validate_command_completion(':Git push -- origin', -7)

  -- Should cache option candidates for particular subcommand
  eq(get_spawn_log(), spawn_log)

  -- Works with aliases
  child.lua([[table.insert(_G.stdio_queue, { { 'out', '' } })]])
  validate_command_completion(':Git l -')

  spawn_log = get_spawn_log()
  eq(#spawn_log, 5)
  -- - Should try to parse help page for the command it is aliased to
  eq(spawn_log[5].options, { args = { 'help', '--man', 'log' }, cwd = child.fn.getcwd() })
end

T[':Git']['completion']['works with explicit paths'] = function()
  child.set_size(15, 40)

  -- Should incrementally suggest paths relative to root after explicit " -- "
  type_keys(':Git add -- ', '<Tab>')
  child.expect_screenshot()

  -- Should allow pressing "/" to continue completion immediately
  type_keys('/', '<Tab>')
  child.expect_screenshot()

  -- Should not error if there is no present paths to complete from
  type_keys('aa', '<Tab>')
  child.expect_screenshot()

  -- Should work multiple times
  type_keys(' f', '<Tab>')
  child.expect_screenshot()
end

T[':Git']['completion']['uses correct working directory for paths'] = function()
  mock_init_track_stdio_queue()
  child.lua([[_G.stdio_queue = {
    _G.init_track_stdio_queue[1],
    _G.init_track_stdio_queue[2],
    _G.init_track_stdio_queue[3],

    -- Get initial data about subcommands
    { { 'out', 'add\nblame\ndiff\nlog\npush\npull\nshow\nreflog\nl' } },
    { { 'out', 'blame\ndiff\nlog\nshow' } },
    { { 'out', 'alias.l log -5' } },
  }]])

  child.fn.chdir(test_dir_absolute)
  edit(git_file_path)
  validate_command_completion(':Git add -- ')
end

--stylua: ignore
T[':Git']['completion']['works with subcommand targets'] = function()
  child.set_size(15, 20)
  child.lua([[
    _G.subcommands_with_special_targets = {
      'add', 'mv', 'restore', 'rm',
      'diff', 'grep', 'log', 'show',
      'branch', 'commit', 'merge', 'rebase', 'reset', 'switch', 'tag',
      'fetch', 'push', 'pull',
      'checkout', 'config', 'help'
    }
    _G.supported = table.concat(_G.subcommands_with_special_targets, '\n')

    _G.stdio_queue = {
      -- Get initial data about subcommands
      { { 'out', _G.supported .. '\nl' } },
      { { 'out', 'blame\ndiff\nlog\nshow' } },
      { { 'out', 'alias.l log -5' } },

      -- Mock calls for getting completion candidates
      { {'out', 'main\nv0.1.0'} },              -- log
      { {'out', 'main\nv0.2.0'} },              -- show
      { {'out', 'main\ntmp'} },                 -- branch
      { {'out', 'main\ntmp2'} },                -- merge
      { {'out', 'main\ntmp3'} },                -- rebase
      { {'out', 'main\nv0.3.0'} },              -- reset
      { {'out', 'main\ntmp4'} },                -- switch
      { {'out', 'v0.1.0\nv0.2.0'} },            -- tag
      { {'out', 'origin\nupstream'} },          -- remote
      { {'out', 'origin\nupstream2'} },         -- push
      { {'out', 'origin\norigin2'} },           -- push 2
      { {'out', 'main\nv0.4.0'} },              -- push 3
      { {'out', 'main\nv0.4.0'} },              -- push 4
      { {'out', 'main\nv0.4.0'} },              -- push 5
      { {'out', 'origin\nupstream3'} },         -- pull
      { {'out', 'origin\norigin3'} },           -- pull 2
      { {'out', 'main\nv0.5.0'} },              -- pull 3
      { {'out', 'main\nv0.5.0'} },              -- pull 4
      { {'out', 'main\nv0.5.0'} },              -- pull 5
      { {'out', 'main\nv0.6.0'} },              -- checkout
      { {'out', 'author.email\nauthor.name'} }, -- config
      { {'out', 'main\nv0.1.0'} },              -- l (`log` alias)
    }]])

  local validate_latest_spawn_args = function(ref_args)
    local spawn_log = get_spawn_log()
    eq(spawn_log[#spawn_log].options.args, ref_args)
  end

  validate_command_completion(':Git add ')     -- path
  validate_command_completion(':Git mv ')      -- path
  validate_command_completion(':Git restore ') -- path
  validate_command_completion(':Git rm ')      -- path
  validate_command_completion(':Git diff ')    -- path
  validate_command_completion(':Git grep ')    -- path

  validate_command_completion(':Git log ') -- CLI
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags' })

  validate_command_completion(':Git show ') -- CLI
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags' })

  validate_command_completion(':Git branch ') -- CLI
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches' })

  validate_command_completion(':Git commit ') -- path

  validate_command_completion(':Git merge ') -- CLI
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches' })

  validate_command_completion(':Git rebase ') -- CLI
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches' })

  validate_command_completion(':Git reset ') -- CLI
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags' })

  validate_command_completion(':Git switch ') -- CLI
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches' })

  validate_command_completion(':Git tag ') -- CLI
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--tags' })

  validate_command_completion(':Git fetch ') -- CLI
  validate_latest_spawn_args({ 'remote' })

  validate_command_completion(':Git push ') -- CLI
  validate_latest_spawn_args({ 'remote' })
  validate_command_completion(':Git push origin')
  validate_latest_spawn_args({ 'remote' })
  validate_command_completion(':Git push origin ')
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags' })
  validate_command_completion(':Git push origin v')
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags' })
  validate_command_completion(':Git push origin main ')
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags' })

  validate_command_completion(':Git pull ') -- CLI
  validate_latest_spawn_args({ 'remote' })
  validate_command_completion(':Git pull origin')
  validate_latest_spawn_args({ 'remote' })
  validate_command_completion(':Git pull origin ')
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags' })
  validate_command_completion(':Git pull origin v')
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags' })
  validate_command_completion(':Git pull origin main ')
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags' })

  validate_command_completion(':Git checkout ') -- CLI
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags', '--remotes' })

  validate_command_completion(':Git config ') -- CLI
  validate_latest_spawn_args({ 'help', '--config-for-completion' })

  validate_command_completion(':Git help ') -- Supported commands plus a bit

  -- Should also work with aliases
  validate_command_completion(':Git l ') -- CLI, same as log
  validate_latest_spawn_args({ 'rev-parse', '--symbolic', '--branches', '--tags' })
end

T[':Git']['completion']['works with not supported command'] = function()
  -- Should suggest commands
  type_keys(':Git doesnotexist ', '<Tab>')
  child.expect_screenshot()

  -- Should suggest nothing
  type_keys('<C-w>', '-', '<Tab>')
  child.expect_screenshot()

  -- Should suggest paths
  type_keys('- ', '<Tab>')
  child.expect_screenshot()
end

T[':Git']['completion']['works with present command modifiers'] = function()
  type_keys(':vert silent Git ', '<Tab>')
  child.expect_screenshot()
end

T[':Git']['events are triggered'] = function()
  child.lua([[
    -- Command stdout
    table.insert(_G.stdio_queue, { { 'out', 'abc1234 Hello\ndef4321 World' } })
    table.insert(_G.stdio_queue, { { 'out', '' }, { 'err', 'There was error' } })

    _G.process_mock_data = { [#_G.stdio_queue] = { exit_code = 1 }}
  ]])

  child.lua([[
    _G.au_log = {}
    local track = function(data) table.insert(_G.au_log, data) end
    local opts = { pattern = { 'MiniGitCommandDone', 'MiniGitCommandSplit' }, callback = track }
    vim.api.nvim_create_autocmd('User', opts)
  ]])

  local init_win_id = get_win()
  child.cmd(':vertical Git log')
  child.cmd(':Git push origin main')

  local au_log = child.lua_get('_G.au_log')
  local events = vim.tbl_map(function(t) return t.match end, au_log)
  eq(events, { 'MiniGitCommandDone', 'MiniGitCommandSplit', 'MiniGitCommandDone' })

  -- Supplies proper data table in Neovim>=0.8
  if child.fn.has('nvim-0.8') == 0 then return end

  local log_done = au_log[1].data
  eq(type(log_done.cmd_input), 'table')
  eq(log_done.cmd_input.fargs, { 'log' })
  log_done.cmd_input = nil
  eq(log_done, {
    cwd = child.fn.getcwd(),
    exit_code = 0,
    git_command = { 'git', 'log' },
    git_subcommand = 'log',
    stderr = '',
    stdout = 'abc1234 Hello\ndef4321 World',
  })

  local log_split = au_log[2].data
  eq(log_split.git_command, { 'git', 'log' })
  eq(log_split.win_source, init_win_id)
  eq(log_split.win_stdout, get_win())

  local push_err = au_log[3].data
  push_err.cmd_input = nil
  eq(push_err, {
    cwd = child.fn.getcwd(),
    exit_code = 1,
    git_command = { 'git', 'push', 'origin', 'main' },
    git_subcommand = 'push',
    stderr = 'There was error',
    stdout = '',
  })
end

T[':Git']['event `MiniGitCommandSplit` can be used to tweak window-local options'] = function()
  if child.fn.has('nvim-0.8') == 0 then MiniTest.skip('Requires `data` field supplied to autocommand callback.') end

  child.lua([[table.insert(_G.stdio_queue, { { 'out', 'abc1234 Hello\ndef4321 World' } })]])
  child.lua([[
    local modify_win_opts = function(data)
      local win_source, win_stdout = data.data.win_source, data.data.win_stdout
      vim.wo[win_source].scrollbind = true
      vim.wo[win_stdout].scrollbind = true
      vim.wo[win_stdout].foldlevel = 0
    end
    local opts = { pattern = 'MiniGitCommandSplit', callback = modify_win_opts }
    vim.api.nvim_create_autocmd('User', opts)
  ]])

  local init_win_id = get_win()
  child.cmd(':Git log')
  eq(child.api.nvim_win_get_option(init_win_id, 'scrollbind'), true)
  eq(child.api.nvim_win_get_option(0, 'scrollbind'), true)
  eq(child.api.nvim_win_get_option(0, 'foldlevel'), 0)
end

return T
