-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- Documentation ==============================================================
--- Extensive module for writing Neovim plugin tests.
---
--- Features:
--- - Define test action as a named callable entry of a table.
--- - Helper for creating child Neovim process which is designed to be used in
---   tests (including taking and verifying screenshots). See
---   |MiniTest.new_child_neovim()| and |Minitest.expect.reference_screenshot()|.
--- - Hierarchical organization of tests with custom hooks and user data. See
---   |MiniTest.new_testset()|.
--- - Emulation of 'Olivine-Labs/busted' interface (`describe`, `it`, etc.).
--- - Predefined small set of expectations (`assert`-like functions).
---   See |MiniTest.expect|.
--- - Test parametrization.
--- - Customizable definition of what files should be tested.
--- - Test filtering. There are predefined wrappers for testing a file
---   (|MiniTest.run_file()|) and case at a location like current cursor position
---   (|MiniTest.run_at_location()|).
--- - Customizable reporter of output results. There are two predefined ones:
---     - |MiniTest.gen_reporter.buffer| for interactive usage.
---     - |MiniTest.gen_reporter.stdout| for headless Neovim.
--- - Customizable project specific testing script.
---
--- What it doesn't support:
--- - Parallel execution. Due to idea of limiting implementation complexity.
--- - Mocks, stubs, etc. Use child Neovim process and  manually override what
---   needed. Reset it afterwards.
--- - "Overly specific" expectations. Tests for (no) equality and (absence of)
---   errors usually cover most of the needs. Adding new expectations is a
---   subject to weighing its usefulness against additional implementation
---   complexity. Use |MiniTest.new_expectation()| to create custom ones.
---
--- For more information see:
--- - 'TESTING.md' file for more examples.
--- - Code for this plugin's tests. Consider it to be an example of how
---   'mini.test' should be used to organize and create tests.
---
--- # Design
---
--- - Write test actions as callable entries of test set. Use child process
---   inside test actions (see |MiniTest.new_child_neovim|).
--- - Organize tests in separate files. Each test file should return test set.
--- - Collect into single hierarchical test set.
--- - Test set is flattened into array test cases.
--- - Filter test cases.
--- - Execute test cases in order.
---
--- # Setup~
---
--- This module needs a setup with `require('mini.test').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table
--- `MiniTest` which you can use for scripting or manually (with
--- `:lua MiniTest.*`). See |MiniTest.config| for available config settings.
---
--- # Disabling~
---
--- To disable, set `g:minitest_disable` (globally) or `b:minitest_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.test
---@tag MiniTest
---@toc_entry Test Neovim plugins

-- Module definition ==========================================================
-- TODO: make them local
MiniTest = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniTest.config|.
---
---@usage `require('mini.test').setup({})` (replace `{}` with your `config` table)
function MiniTest.setup(config)
  -- Export module
  _G.MiniTest = MiniTest

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Create highlighting
  local command = string.format(
    [[hi default MiniTestFail guifg=%s gui=bold
      hi default MiniTestPass guifg=%s gui=bold]],
    vim.g.terminal_color_1 or '#FF0000',
    vim.g.terminal_color_2 or '#00FF00'
  )
  vim.cmd(command)
end

--stylua: ignore start
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniTest.config = {
  -- Options controlling collection of test cases. See `:h MiniTest.collect()`.
  collect = {
    -- Emulate functions from 'busted' testing framework (`describe`, `it`, etc.)
    emulate_busted = false,

    -- Function returning array of file paths to be collected. Default: all Lua
    -- files starting with 'test_' located in 'tests' directory.
    find_files = function()
      return vim.fn.globpath('tests', '**/test_*.lua', true, true)
    end,

    -- Predicate function indicating if test case should be left for execution
    filter_cases = function(case) return true end,
  },

  -- Options controlling execution of test cases. See `:h MiniTest.execute()`.
  execute = {
    -- Table with callable fields `start()`, `update()`, and `finish()`
    reporter = nil,

    -- Whether to stop execution after first error
    stop_on_error = false,
  },

  -- Path (relative to current directory) to script which handles project
  -- specific test configuration
  script_path = 'scripts/minitest.lua',
}
--minidoc_afterlines_end
--stylua: ignore end

-- Module data ================================================================
--- Table with information about current state of test execution
---
--- It is reset at the beginning of every call to |MiniTest.execute()|.
---
--- At least these keys are supported:
--- - <all_cases> - array with all cases being currently executed. Basically,
---   an input of |MiniTest.execute()|.
--- - <case> - currently executed test case. See |MiniTest-test-case|.
MiniTest.current = { all_cases = nil, case = nil }

-- Module functionality =======================================================
--- Create test set
---
--- Test set is a hierarchical organization of test actions.
---
--- TODO: document how to use it (with/without order preservation,
--- `table.insert()` doesn't work).
---
---@param opts table|nil Allowed options:
---   - <hooks> - table with fields:
---       - <pre_once> - before first filtered node.
---       - <pre_case> - before each case (even nested).
---       - <post_case> - after each case (even nested).
---       - <post_once> - after last filtered node.
---   - <parametrize> - array where each element is a table of parameters to be
---     appended to "current parameters" of callable fields.
---   - <data> - user data to be forwarded to steps.
---@param tbl table|nil Initial test items (possibly nested). Will be executed
---   without any guarantees on order.
function MiniTest.new_testset(opts, tbl)
  opts = opts or {}
  tbl = tbl or {}

  -- Keep track of new elements order. This allows to iterate through elements
  -- in order they were added.
  local metatbl = { class = 'testset', key_order = vim.tbl_keys(tbl), opts = opts }
  metatbl.__newindex = function(t, key, value)
    table.insert(metatbl.key_order, key)
    rawset(t, key, value)
  end

  return setmetatable(tbl, metatbl)
end

--- Test case
---
--- Items of sequential organization of test actions.
---
---@class testcase
---
---@field args table Array of arguments with which `test` will be called.
---@field data table User data: all fields of `opts.data` from nested testsets.
---@field desc table Description: array of fields from nested testsets.
---@field hooks table Hooks to be executed as part of test case. Has fields
---   <pre> and <post> with arrays to be consecutively executed before and
---   after execution of `test`.
---@field exec table|nil Information about test case execution. Value of `nil` means
---   that this particular case was not (yet) executed. Has following fields:
---     - <fails> - array of strings with failing information.
---     - <notes> - array of strings with non-failing information.
---     - <state> - state of test execution. One of:
---         - 'Executing <name of what is being executed>' (during execution).
---         - 'Pass' (no fails, no notes).
---         - 'Pass with notes' (no fails, some notes).
---         - 'Fail' (some fails, no notes).
---         - 'Fail with notes' (some fails, some notes).
---@field test function|table Main callable object representing test action.
---@tag MiniTest-test-case

--- Skip rest of current callable execution
---
--- Can be used inside hooks and main test callable of test case.
---
---@param msg string|nil Message to be added to current case notes.
function MiniTest.skip(msg)
  H.cache.error_is_from_skip = true
  error(msg)
end

--- Register callable execution after current callable
---
--- Can be used inside hooks and main test callable of test case.
---
---@param f function Callable to be executed after current step is finished
---   executing (regardless of whether it ended with error or not).
function MiniTest.finally(f)
  H.cache.finally = f
end

--- Run tests
---
--- - Try executing project specific script at path `opts.script_path`. If
---   successful (no errors), then stop.
--- - Collect cases with |MiniTest.collect()| and `opts.collect`.
--- - Execute collected cases with |MiniTest.execute()| and `opts.execute`.
---
---@param opts table|nil Options with structure similar to |MiniTest.config|.
---   Absent values are taken from there.
function MiniTest.run(opts)
  if H.is_disabled() then
    return
  end

  -- Try sourcing project specific script first
  local success = H.execute_project_script(opts)
  if success then
    return
  end

  -- Collect and execute
  opts = vim.tbl_deep_extend('force', MiniTest.config, opts or {})
  local cases = MiniTest.collect(opts.collect)
  MiniTest.execute(cases, opts.execute)
end

--- Run specific test file
---
--- Basically a |MiniTest.run()| wrapper with custom `collect.find_files` option.
---
---@param file string|nil Path to test file. By default a path of current buffer.
---@param opts table|nil Options for |MiniTest.run()|.
function MiniTest.run_file(file, opts)
  file = file or vim.api.nvim_buf_get_name(0)

  --stylua: ignore
  local stronger_opts = { collect = { find_files = function() return { file } end } }
  opts = vim.tbl_deep_extend('force', opts or {}, stronger_opts)

  MiniTest.run(opts)
end

--- Run case(s) covering location
---
--- Try filtering case(s) covering location, meaning that definition of its
--- main `test` action (as taken from builtin `debug.getinfo`) is located in
--- specified file and covers specified line. Note that it can result in
--- multiple cases if they come from parametrized test set (see `parametrize`
--- key in |MiniTest.new_testset()|).
---
--- Basically a |MiniTest.run()| wrapper with custom `collect.find_files` option.
---
---@param location table|nil Table with fields <file> (path to file) and <line>
---   (line in that file). Default is taken from current cursor position.
function MiniTest.run_at_location(location, opts)
  if location == nil then
    local cur_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':.')
    local cur_pos = vim.api.nvim_win_get_cursor(0)
    location = { file = cur_file, line = cur_pos[1] }
  end

  local stronger_opts = {
    collect = {
      filter_cases = function(case)
        local info = debug.getinfo(case.test)

        return info.short_src == location.file
          and info.linedefined <= location.line
          and location.line <= info.lastlinedefined
      end,
    },
  }
  opts = vim.tbl_deep_extend('force', opts or {}, stronger_opts)

  MiniTest.run(opts)
end

--- Collect test cases
---
--- TODO: describe collection algorithm.
---
---@param opts table|nil Options controlling case collection. Possible fields:
---   - <emulate_busted> - whether to emulate 'Olivine-Labs/busted' interface.
---     It makes custom global functions emulating `describe`, `it`, `setup`,
---     `teardown`, `before_each`, `after_each`.
---   - <find_files> - function which when called without arguments returns
---     array with file paths. Each file should be a Lua file returning single
---     test set or `nil`.
---   - <filter_cases> - function which when called with single test case
---     (see |MiniTest-test-case|) returns `false` if this case should be filtered
---     out; `true` otherwise.
function MiniTest.collect(opts)
  opts = vim.tbl_deep_extend('force', MiniTest.config.collect, opts or {})

  -- Make single test set
  local set = MiniTest.new_testset()
  if opts.emulate_busted then
    H.busted_emulate(set)
  end

  for _, file in ipairs(opts.find_files()) do
    local ok, t = pcall(dofile, file)
    if not ok then
      local msg = string.format('Sourcing %s resulted into following error: %s', vim.inspect(file), t)
      H.error(msg)
    end
    if t ~= nil and not H.is_instance(t, 'testset') then
      local msg = string.format(
        'Output of %s is not a test set. Did you use `MiniTest.new_testset()`?',
        vim.inspect(file)
      )
      H.error(msg)
    end

    set[file] = t
  end

  H.busted_deemulate()

  -- Convert to test cases. This also creates separate aligned array of hooks
  -- which should be executed once regarding test case. This is needed to
  -- correctly inject those hooks after filtering is done.
  local raw_cases, raw_hooks_once = H.set_to_testcases(set)

  -- Filter cases (at this stage don't have injected `hooks_once`)
  local cases, hooks_once = {}, {}
  for i, c in ipairs(raw_cases) do
    if opts.filter_cases(c) then
      table.insert(cases, c)
      table.insert(hooks_once, raw_hooks_once[i])
    end
  end

  -- Inject `hooks_once` into appropriate cases
  H.inject_hooks_once(cases, hooks_once)

  return cases
end

function MiniTest.execute(cases, opts)
  -- Verify correct arguments
  if #cases == 0 then
    H.message('No cases to execute.')
    return
  end

  opts = vim.tbl_deep_extend('force', MiniTest.config.execute, opts or {})
  local reporter = opts.reporter or (H.is_headless and MiniTest.gen_reporter.stdout() or MiniTest.gen_reporter.buffer())
  if type(reporter) ~= 'table' then
    H.message('`opts.reporter` should be table or `nil`.')
    return
  end
  opts.reporter = reporter

  -- Start execution
  H.cache = {}

  MiniTest.current.all_cases = cases

  --stylua: ignore
  vim.schedule(function() H.exec_callable(reporter.start, cases) end)

  for case_num, cur_case in ipairs(cases) do
    -- Schedule execution in async fashion. This allows doing other things
    -- while tests are executed.
    local schedule_step = H.make_step_scheduler(cur_case, case_num, opts)

    --stylua: ignore
    vim.schedule(function() MiniTest.current.case = cur_case end)

    for i, hook_pre in ipairs(cur_case.hooks.pre) do
      schedule_step(hook_pre, [[Executing 'pre' hook #]] .. i)
    end

    --stylua: ignore
    schedule_step(function() cur_case.test(unpack(cur_case.args)) end, 'Executing test')

    for i, hook_post in ipairs(cur_case.hooks.post) do
      schedule_step(hook_post, [[Executing 'post' hook #]] .. i)
    end

    -- Finalize state
    --stylua: ignore
    schedule_step(nil, function() return H.case_final_state(cur_case) end)
  end

  --stylua: ignore
  vim.schedule(function() H.exec_callable(reporter.finish) end)
end

--- Stop test execution
---
---@param opts table|nil Options with fields:
---   - <close_all_child_neovim> - whether to close all child neovim processes
---     created with |MiniTest.new_child_neovim|. Default: `true`.
function MiniTest.stop(opts)
  opts = vim.tbl_deep_extend('force', { close_all_child_neovim = true }, opts or {})

  -- Register intention to stop execution
  H.cache.should_stop_execution = true

  -- Possibly stop all child Neovim processes
  --stylua: ignore
  if not opts.close_all_child_neovim then return end

  for _, child in ipairs(H.child_neovim_registry) do
    pcall(child.stop)
  end
  H.child_neovim_registry = {}
end

-- Expectations ---------------------------------------------------------------
MiniTest.expect = {}

function MiniTest.expect.equality(left, right)
  --stylua: ignore
  if vim.deep_equal(left, right) then return true end

  local context = string.format('Left: %s\nRight: %s', vim.inspect(left), vim.inspect(right))
  H.error_expect('equality', context)
end

function MiniTest.expect.no_equality(left, right)
  --stylua: ignore
  if not vim.deep_equal(left, right) then return true end

  local context = string.format('Object: %s', vim.inspect(left))
  H.error_expect('*no* equality', context)
end

function MiniTest.expect.error(f, match, ...)
  vim.validate({ match = { match, 'string', true } })

  local ok, err = pcall(f, ...)
  err = err or ''
  local has_matched_error = not ok and string.find(err, match or '') ~= nil
  --stylua: ignore
  if has_matched_error then return true end

  local with_match = match == nil and '' or (' with match %s'):format(vim.inspect(match))
  local cause = 'error' .. with_match
  local context = ok and 'Observed no error' or ('Observed error: ' .. err)

  H.error_expect(cause, context)
end

function MiniTest.expect.no_error(f, ...)
  local ok, err = pcall(f, ...)
  --stylua: ignore
  if ok then return true end

  H.error_expect('*no* error', 'Observed error: ' .. err)
end

function MiniTest.expect.match(str, pattern)
  --stylua: ignore
  if str:find(pattern) ~= nil then return true end

  local context = string.format('Pattern: %s\nObserved string: %s', vim.inspect(pattern), str)
  H.error_expect('string matching', context)
end

--- Expect equality to reference screenshot
---
--- With headless execution error report directly prints both screenshots into
--- terminal.
---
---@param screenshot table Array with screenshot information. Usually an output
---   of `child.get_screenshot()` (see |MiniTest.new_child_neovim()|).
---@param path string|nil Path to reference screenshot. If `nil`, constructed
---   automatically in directory 'tests/screenshots' from current case info.
---   If there is no file at `path`, it is created with content of `screenshot`.
function MiniTest.expect.reference_screenshot(screenshot, path)
  if path == nil then
    -- Sanitize path
    local name = H.case_to_stringid(MiniTest.current.case):gsub('[%s/]', '-')
    path = 'tests/screenshots/' .. name
  end

  -- If there is no readable screenshot file, create it. Pass with note.
  if vim.fn.filereadable(path) == 0 then
    local dir_path = vim.fn.fnamemodify(path, ':p:h')
    vim.fn.mkdir(dir_path, 'p')

    vim.fn.writefile(screenshot, path)

    table.insert(MiniTest.current.case.exec.notes, 'Created reference screenshot at path ' .. vim.inspect(path))
    return true
  end

  local reference = vim.fn.readfile(path)

  --stylua: ignore
  if vim.deep_equal(reference, screenshot) then return true end

  local cause = 'screenshot equality to reference at ' .. vim.inspect(path)
  local disable_highlighting = H.is_headless and '\27[0m' or ''
  --stylua: ignore
  local context = string.format(
    'Reference: %s%s\n\nObserved: %s%s',
    H.screenshot_to_string(reference), disable_highlighting,
    H.screenshot_to_string(screenshot), disable_highlighting
  )
  H.error_expect(cause, context)
end

function MiniTest.new_expectation(predicate, cause, format_context)
  return function(...)
    --stylua: ignore
    if predicate(...) then return true end

    cause = vim.is_callable(cause) and cause(...) or cause
    H.error_expect(cause, format_context(...))
  end
end

-- Reporters ------------------------------------------------------------------
MiniTest.gen_reporter = {}

-- Open window with special buffer and update with throttled redraws
function MiniTest.gen_reporter.buffer(opts)
  opts = vim.tbl_deep_extend(
    'force',
    { group_depth = 1, throttle_delay = 10, window = H.buffer_reporter.default_window_opts() },
    opts or {},
    { quit_on_finish = false }
  )

  local buf_id, win_id
  local is_valid_buf_win = function()
    return vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_win_is_valid(win_id)
  end

  -- Define "replace last line" function with throttled redraw
  local latest_draw_time = 0
  local replace_last_lines = function(n_latest, lines, force)
    if not is_valid_buf_win() then
      return
    end

    local n_lines = vim.api.nvim_buf_line_count(buf_id)
    H.buffer_reporter.set_lines(buf_id, lines, n_lines - n_latest - 1, n_lines - 1)
    vim.api.nvim_win_set_cursor(win_id, { vim.api.nvim_buf_line_count(buf_id), 0 })

    -- Throttle redraw to reduce flicker
    local cur_time = vim.loop.hrtime()
    local is_enough_time_passed = cur_time - latest_draw_time > opts.throttle_delay * 1000000
    if is_enough_time_passed or force then
      vim.cmd('redraw')
      latest_draw_time = cur_time
    end
  end

  -- Create and tweak generic overview reporter
  local res = H.overview_reporter.generate(replace_last_lines, opts)

  local start = res.start
  res.start = function(cases)
    -- Set up buffer and window
    buf_id, win_id = H.buffer_reporter.setup_buf_and_win(opts)
    start(cases)
  end

  local finish = res.finish
  res.finish = function()
    if not is_valid_buf_win() then
      return
    end

    -- Restore cursor at start of 'Fails and notes' section
    local cur_pos = vim.api.nvim_win_get_cursor(win_id)
    finish()
    vim.api.nvim_win_set_cursor(win_id, { cur_pos[1] - 2, cur_pos[2] })
  end

  return res
end

-- Write to `stdout` with throttled redraws
function MiniTest.gen_reporter.stdout(opts)
  opts = vim.tbl_deep_extend('force', { group_depth = 1, throttle_delay = 10, quit_on_finish = true }, opts or {})

  -- Define "replace last lines" function with throttled draw
  local latest_draw_time, draw_queue = 0, {}
  local replace_last_lines = function(n_latest, lines, force)
    -- Remove latest lines
    if n_latest > 0 then
      table.insert(draw_queue, ('\27[%sF\27[0J'):format(n_latest))
    end

    -- Write new lines
    for _, l in ipairs(lines) do
      table.insert(draw_queue, l)
      table.insert(draw_queue, '\n')
    end

    -- Throttle redraw to reduce flicker
    local cur_time = vim.loop.hrtime()
    local is_enough_time_passed = cur_time - latest_draw_time > opts.throttle_delay * 1000000
    if is_enough_time_passed or force then
      for _, l in ipairs(draw_queue) do
        io.stdout:write(l)
      end
      io.flush()
      draw_queue = {}
      latest_draw_time = cur_time
    end
  end

  return H.overview_reporter.generate(replace_last_lines, opts)
end

-- Exported utility functions -------------------------------------------------
--- Create child Neovim process
---
--- TODO: Write more documentation about:
--- - General approach: current and child processes "talk" with |RPC|, etc.
--- - Limitations: not being able to pass functions, "hanging" state while
---   waiting for user input (hit-enter-prompt, Operator-pending mode).
--- - Methods
---     - Job-related: `start`, `stop`, `restart`, etc.
---     - Wrappers for executing Lua inside child process: `api`, `fn`, `lsp`,
---       `loop`, etc.
---     - Wrappers: `type_keys()`, `is_blocking()` (also write about "blocking"
---       concept), etc.
---
---@usage
--- -- Initiate
--- local child = MiniTest.new_child_neovim()
--- child.start()
---
--- -- Use API functions
--- child.api.nvim_buf_set_lines(0, 0, -1, true, { 'This is inside child Neovim' })
---
--- -- Execute Lua code, commands, etc.
--- child.lua('_G.n = 0')
--- child.cmd('au CursorMoved * lua _G.n = _G.n + 1')
--- child.type_keys('l')
--- print(child.lua_get('_G.n')) -- Should be 1
---
--- -- Use other `vim.xxx` Lua wrappers (get executed inside child process)
--- vim.b.aaa = 'current process'
--- child.b.aaa = 'child process'
--- print(child.lua_get('vim.b.aaa')) -- Should be 'child process'
---
--- -- Stop
--- child.stop()
function MiniTest.new_child_neovim()
  local child = { address = vim.fn.tempname() }

  -- TODO:
  -- - Add some automated safety mechanism to prevent hanging child process.
  --   Something like timer checking if process is blocked.

  -- Start fully functional Neovim instance (not '--embed' or '--headless',
  -- because they don't provide full functionality)
  function child.start(args, opts)
    args = args or {}
    opts = vim.tbl_deep_extend('force', { nvim_executable = 'nvim', connection_timeout = 5000 }, opts or {})

    local t = { '--clean', '--listen', child.address }
    vim.list_extend(t, args)
    args = t

    -- Using 'libuv' for creating a job is crucial for getting this to work in
    -- Github Actions. Other approaches:
    -- - Use built-in `vim.fn.jobstart(args)`. Works locally but doesn't work
    --   in Github Action.
    -- - Use `plenary.job`. Works fine both locally and in Github Action, but
    --   needs a 'plenary.nvim' dependency (not exactly bad, but undesirable).
    local job = {}
    job.stdin, job.stdout, job.stderr = vim.loop.new_pipe(false), vim.loop.new_pipe(false), vim.loop.new_pipe(false)
    job.handle, job.pid = vim.loop.spawn(opts.nvim_executable, {
      stdio = { job.stdin, job.stdout, job.stderr },
      args = args,
    }, function() end)

    child.job = job
    child.start_args, child.start_opts = args, opts

    local step = 10
    local connected, i, max_tries = nil, 0, math.floor(opts.connection_timeout / step)
    repeat
      i = i + 1
      vim.loop.sleep(step)
      connected, child.channel = pcall(vim.fn.sockconnect, 'pipe', child.address, { rpc = true })
    until connected or i >= max_tries

    if not connected then
      vim.notify('Failed to make connection to child Neovim.')
      child.stop()
    end

    -- Enable method chaining
    return child
  end

  function child.stop()
    pcall(vim.fn.chanclose, child.channel)

    if child.job ~= nil then
      -- TODO: consider figuring out a way to do it better (should actually
      -- close/kill all child processes when running interactively)
      child.job.handle:kill(9)
      child.job = nil
    end

    -- Enable method chaining
    return child
  end

  function child.restart(args, opts)
    args = args or {}
    opts = vim.tbl_deep_extend('force', child.start_opts or {}, opts or {})

    if child.job ~= nil then
      child.stop()
    end

    child.address = vim.fn.tempname()
    child.start(args, opts)
  end

  -- Wrappers for common `vim.xxx` objects (will get executed inside child)
  child.api = setmetatable({}, {
    __index = function(_, key)
      return function(...)
        return vim.rpcrequest(child.channel, key, ...)
      end
    end,
  })

  -- Variant of `api` functions called with `vim.rpcnotify`. Useful for
  -- making blocking requests (like `getchar()`).
  child.api_notify = setmetatable({}, {
    __index = function(_, key)
      return function(...)
        return vim.rpcnotify(child.channel, key, ...)
      end
    end,
  })

  ---@return table Emulates `vim.xxx` table (like `vim.fn`)
  ---@private
  local forward_to_child = function(tbl_name)
    -- TODO: try to figure out the best way to operate on tables with function
    -- values (needs "deep encode/decode" of function objects)
    return setmetatable({}, {
      __index = function(_, key)
        local obj_name = ('vim[%s][%s]'):format(vim.inspect(tbl_name), vim.inspect(key))
        local value_type = child.api.nvim_exec_lua(('return type(%s)'):format(obj_name), {})

        if value_type == 'function' then
          -- This allows syntax like `child.fn.mode(1)`
          return function(...)
            return child.api.nvim_exec_lua(('return %s(...)'):format(obj_name), { ... })
          end
        end

        -- This allows syntax like `child.bo.buftype`
        return child.api.nvim_exec_lua(('return %s'):format(obj_name), {})
      end,
      __newindex = function(_, key, value)
        local obj_name = ('vim[%s][%s]'):format(vim.inspect(tbl_name), vim.inspect(key))
        -- This allows syntax like `child.b.aaa = function(x) return x + 1 end`
        -- (inherits limitations of `string.dump`: no upvalues, etc.)
        if type(value) == 'function' then
          local dumped = vim.inspect(string.dump(value))
          value = ('loadstring(%s)'):format(dumped)
        else
          value = vim.inspect(value)
        end

        child.api.nvim_exec_lua(('%s = %s'):format(obj_name, value), {})
      end,
    })
  end

  --stylua: ignore start
  local supported_vim_tables = {
    -- Collections
    'diagnostic', 'fn', 'highlight', 'json', 'loop', 'lsp', 'mpack', 'treesitter', 'ui',
    -- Variables
    'g', 'b', 'w', 't', 'v', 'env',
    -- Options (no 'opt' becuase not really usefult due to use of metatables)
    'o', 'go', 'bo', 'wo',
  }
  --stylua: ignore end
  for _, v in ipairs(supported_vim_tables) do
    child[v] = forward_to_child(v)
  end

  -- Convenience wrappers
  --- Type keys
  ---
  --- Basically a wrapper for |nvim_input()| applied inside child process.
  --- Differences:
  --- - Can wait after each group of characters.
  --- - Raises error if typing keys resulted into error in chidl process (its
  ---   |v:errmsg| was updated).
  --- - Key '<' as separate entry may not be escaped as '<LT>'.
  ---
  ---@param wait number Number of milliseconds to wait after each entry. May be
  ---   omitted, in which case no waiting is done.
  ---@param ... string|table<number, string> Separate entries for |nvim_input|, after
  ---   which `wait` will be applied. Can be either string or array of strings.
  ---
  ---@usage
  --- -- All of these type keys 'c', 'a', 'w'
  --- `child.type_keys('caw')`
  --- `child.type_keys('c', 'a', 'w')`
  --- `child.type_keys('c', { 'a', 'w' })`
  ---
  --- -- Waits 5 ms after `c` and after 'w'
  --- `child.type_keys(5, 'c', { 'a', 'w' })`
  ---
  --- -- Special keys can also be used
  --- `child.type_keys('i', 'Hello world', '<Esc>')`
  ---@private
  function child.type_keys(wait, ...)
    local has_wait = type(wait) == 'number'
    local keys = has_wait and { ... } or { wait, ... }
    keys = vim.tbl_flatten(keys)

    for _, k in ipairs(keys) do
      if type(k) ~= 'string' then
        error('In `type_keys()` each argument should be either string or array of strings.')
      end

      -- From `nvim_input` docs: "On execution error: does not fail, but
      -- updates v:errmsg.". So capture it manually.
      local cur_errmsg
      -- But do that only if Neovim is not "blocking". Otherwise, usage of
      -- `child.v` will block execution.
      if not child.is_blocking() then
        cur_errmsg = child.v.errmsg
        child.v.errmsg = ''
      end

      -- Need to escape bare `<` (see `:h nvim_input`)
      child.api.nvim_input(k == '<' and '<LT>' or k)

      -- Possibly throw error manually
      if not child.is_blocking() then
        if child.v.errmsg ~= '' then
          error(child.v.errmsg, 2)
        else
          child.v.errmsg = cur_errmsg
        end
      end

      -- Possibly wait
      if has_wait and wait > 0 then
        child.loop.sleep(wait)
      end
    end
  end

  function child.cmd(str)
    return child.api.nvim_exec(str, false)
  end

  function child.cmd_capture(str)
    return child.api.nvim_exec(str, true)
  end

  function child.lua(str, args)
    return child.api.nvim_exec_lua(str, args or {})
  end

  function child.lua_notify(str, args)
    return child.api_notify.nvim_exec_lua(str, args or {})
  end

  function child.lua_get(str, args)
    return child.api.nvim_exec_lua('return ' .. str, args or {})
  end

  function child.is_blocking()
    return child.api.nvim_get_mode()['blocking']
  end

  -- Various wrappers
  function child.ensure_normal_mode()
    local cur_mode = child.fn.mode()

    -- Exit from Visual mode
    local ctrl_v = vim.api.nvim_replace_termcodes('<C-v>', true, true, true)
    if cur_mode == 'v' or cur_mode == 'V' or cur_mode == ctrl_v then
      child.type_keys(cur_mode)
      return
    end

    -- Exit from Terminal mode
    if cur_mode == 't' then
      child.type_keys([[<C-\>]], '<C-n>')
      return
    end

    -- Exit from other modes
    child.type_keys('<Esc>')
  end

  function child.get_screenshot()
    local temp_file = child.fn.tempname()
    -- TODO: consider making it officially exported in Neovim core
    child.api.nvim__screenshot(temp_file)
    local res = child.fn.readfile(temp_file)
    child.fn.delete(temp_file)
    return res
  end

  -- Register `child` for automatic stop in case of emergency
  table.insert(H.child_neovim_registry, child)

  return child
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniTest.config

-- Whether instance is running in headless mode
H.is_headless = #vim.api.nvim_list_uis() == 0

-- Cache for various data
H.cache = {
  -- Whether error is initiated from `MiniTest.skip()`
  error_is_from_skip = false,
  -- Callable to be executed after step (hook or test function)
  finally = nil,
  -- Whether to stop async execution
  should_stop_execution = false,
}

-- Registry of all Neovim child processes
H.child_neovim_registry = {}

-- ANSI codes for common cases
H.ansi_codes = {
  fail = '\27[1;31m', -- Bold red
  pass = '\27[1;32m', -- Bold green
  emphasis = '\27[1m', -- Bold
  reset = '\27[0m',
}

-- Highlight groups for common ANSI codes
H.hl_groups = {
  ['\27[1;31m'] = 'MiniTestFail',
  ['\27[1;32m'] = 'MiniTestPass',
  ['\27[1m'] = 'Bold',
}

-- Symbols used in reporter output
--stylua: ignore
H.reporter_symbols = setmetatable({
  ['Pass']            = H.ansi_codes.pass .. 'o' .. H.ansi_codes.reset,
  ['Pass with notes'] = H.ansi_codes.pass .. 'O' .. H.ansi_codes.reset,
  ['Fail']            = H.ansi_codes.fail .. 'x' .. H.ansi_codes.reset,
  ['Fail with notes'] = H.ansi_codes.fail .. 'X' .. H.ansi_codes.reset,
}, {
  __index = function() return H.ansi_codes.emphasis .. '?' .. H.ansi_codes.reset end,
})

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    collect = { config.collect, 'table' },
    execute = { config.execute, 'table' },
    script_path = { config.script_path, 'string' },
  })

  vim.validate({
    ['collect.emulate_busted'] = { config.collect.emulate_busted, 'boolean' },
    ['collect.find_files'] = { config.collect.find_files, 'function' },
    ['collect.filter_cases'] = { config.collect.filter_cases, 'function' },

    ['execute.reporter'] = { config.execute.reporter, 'table', true },
    ['execute.stop_on_error'] = { config.execute.stop_on_error, 'boolean' },
  })

  return config
end

function H.apply_config(config)
  MiniTest.config = config
end

function H.is_disabled()
  return vim.g.minitest_disable == true or vim.b.minitest_disable == true
end

-- Work with collection -------------------------------------------------------
function H.busted_emulate(set)
  local cur_set = set

  _G.describe = function(name, f)
    local cur_set_parent = cur_set
    cur_set_parent[name] = MiniTest.new_testset()
    cur_set = cur_set_parent[name]
    f()
    cur_set = cur_set_parent
  end

  _G.it = function(name, f)
    cur_set[name] = f
  end

  local setting_hook = function(hook_name)
    return function(hook)
      local metatbl = getmetatable(cur_set)
      metatbl.opts.hooks = metatbl.opts.hooks or {}
      metatbl.opts.hooks[hook_name] = hook
    end
  end

  _G.setup = setting_hook('pre_once')
  _G.before_each = setting_hook('pre_case')
  _G.after_each = setting_hook('post_case')
  _G.teardown = setting_hook('post_once')
end

function H.busted_deemulate()
  local fun_names = { 'describe', 'it', 'setup', 'before_each', 'after_each', 'teardown' }
  for _, f_name in ipairs(fun_names) do
    _G[f_name] = nil
  end
end

-- Work with execution --------------------------------------------------------
function H.execute_project_script(...)
  -- Don't process script if there are more than one active `run` calls
  if H.is_inside_script then
    return false
  end

  -- Don't process script if at least one argument is not default (`nil`)
  if #{ ... } > 0 then
    return
  end

  -- Store information
  local config_cache = MiniTest.config

  -- Pass information to a possible `run()` call inside script
  H.is_inside_script = true

  -- Execute script
  local success = pcall(vim.cmd, 'luafile ' .. MiniTest.config.script_path)

  -- Restore information
  MiniTest.config = config_cache
  H.is_inside_script = nil

  return success
end

function H.make_step_scheduler(case, case_num, opts)
  local report_update_case = function()
    H.exec_callable(opts.reporter.update, case_num)
  end

  local on_err = function(e)
    if H.cache.error_is_from_skip then
      -- Add error message to 'notes' rather than 'fails'
      table.insert(case.exec.notes, tostring(e))
      H.cache.error_is_from_skip = false
      return
    end

    table.insert(case.exec.fails, tostring(e))

    if opts.stop_on_error then
      MiniTest.stop()
      case.exec.state = H.case_final_state(case)
      report_update_case()
    end
  end

  return function(f, state)
    f = f or function() end

    vim.schedule(function()
      --stylua: ignore
      if H.cache.should_stop_execution then return end

      case.exec = case.exec or { fails = {}, notes = {} }
      case.exec.state = vim.is_callable(state) and state() or state
      report_update_case()
      xpcall(f, on_err)

      H.exec_callable(H.cache.finally)
      H.cache.finally = nil
    end)
  end
end

-- Work with test cases -------------------------------------------------------
--- Convert test set to array of test cases
---
---@return ... Tuple of aligned arrays: with test cases and hooks that should
---   be executed only once before corresponding item.
---@private
function H.set_to_testcases(set, template, hooks_once)
  template = template or { args = {}, desc = {}, hooks = { pre = {}, post = {} }, data = {} }
  hooks_once = hooks_once or { pre = {}, post = {} }

  local metatbl = getmetatable(set)
  local opts, key_order = metatbl.opts, metatbl.key_order
  local hooks, parametrize, data = opts.hooks or {}, opts.parametrize or { {} }, opts.data or {}

  -- Convert to steps only callable or test set nodes
  local node_keys = vim.tbl_filter(function(key)
    local node = set[key]
    return vim.is_callable(node) or H.is_instance(node, 'testset')
  end, key_order)

  if #node_keys == 0 then
    return {}
  end

  -- Ensure that newly added hooks are represented by new functions.
  -- This is needed to count them later only within current set. Example: use
  -- the same function in several `_once` hooks. In `H.inject_hooks_once` it
  -- will be injected only once overall whereas it should be injected only once
  -- within corresponding test set.
  hooks_once = H.extend_hooks(
    hooks_once,
    { pre = H.wrap_callable(hooks.pre_once), post = H.wrap_callable(hooks.post_once) }
  )

  local testcase_arr, hooks_once_arr = {}, {}
  -- Process nodes in order they were added as `T[...] = x`
  for _, key in ipairs(node_keys) do
    local node = set[key]
    for _, args in ipairs(parametrize) do
      local cur_template = H.extend_template(template, {
        args = args,
        desc = key,
        hooks = { pre = hooks.pre_case, post = hooks.post_case },
        data = data,
      })

      if vim.is_callable(node) then
        table.insert(testcase_arr, H.new_testcase(cur_template, node))
        table.insert(hooks_once_arr, hooks_once)
      elseif H.is_instance(node, 'testset') then
        local nest_testcase_arr, nest_hooks_once_arr = H.set_to_testcases(node, cur_template, hooks_once)
        vim.list_extend(testcase_arr, nest_testcase_arr)
        vim.list_extend(hooks_once_arr, nest_hooks_once_arr)
      end
    end
  end

  return testcase_arr, hooks_once_arr
end

function H.inject_hooks_once(cases, hooks_once)
  -- NOTE: this heavily relies on the equivalence of "have same object id" and
  -- "are same hooks"
  local already_injected = {}
  local n = #cases

  -- Inject 'pre' hooks moving forwards
  for i = 1, n do
    local case, hooks = cases[i], hooks_once[i].pre
    local target_tbl_id = 1
    for j = 1, #hooks do
      local h = hooks[j]
      if not already_injected[h] then
        table.insert(case.hooks.pre, target_tbl_id, h)
        target_tbl_id, already_injected[h] = target_tbl_id + 1, true
      end
    end
  end

  -- Inject 'post' hooks moving backwards
  for i = n, 1, -1 do
    local case, hooks = cases[i], hooks_once[i].post
    local target_table_id = #case.hooks.post + 1
    for j = #hooks, 1, -1 do
      local h = hooks[j]
      if not already_injected[h] then
        table.insert(case.hooks.post, target_table_id, h)
        already_injected[h] = true
      end
    end
  end

  return cases
end

function H.new_testcase(template, test)
  template.test = test
  return template
end

function H.extend_template(template, layer)
  local res = vim.deepcopy(template)

  vim.list_extend(res.args, layer.args)
  table.insert(res.desc, layer.desc)
  res.hooks = H.extend_hooks(res.hooks, layer.hooks, false)
  res.data = vim.tbl_deep_extend('force', res.data, layer.data)

  return res
end

function H.extend_hooks(hooks, layer, do_deepcopy)
  local res = hooks
  if do_deepcopy == nil or do_deepcopy then
    res = vim.deepcopy(hooks)
  end

  -- Closer (in terms of nesting) hooks should be closer to test callable
  if vim.is_callable(layer.pre) then
    table.insert(res.pre, layer.pre)
  end
  if vim.is_callable(layer.post) then
    table.insert(res.post, 1, layer.post)
  end

  return res
end

function H.case_to_stringid(case)
  local desc = vim.inspect(table.concat(case.desc, ' | '))
  if #case.args == 0 then
    return desc
  end
  local args = vim.inspect(case.args, { newline = '', indent = '' })
  return ('%s with args %s'):format(desc, args)
end

function H.case_final_state(case)
  local pass_fail = #case.exec.fails == 0 and 'Pass' or 'Fail'
  local with_notes = #case.exec.notes == 0 and '' or ' with notes'
  return string.format('%s%s', pass_fail, with_notes)
end

-- Dynamic overview reporter --------------------------------------------------
H.overview_reporter = {}

-- General idea:
-- - Group cases by concatenating first `group_depth` elements of `desc`. With
--   defaults, `group_depth = 1` means "group by collected files".
-- - In `start()` show some stats to know how much is scheduled to be executed.
-- - In `update()` show symbolic overview of current group and state of current
--   case. Do this by replacing some amount of last lines in output medium.
-- - In `finish()` show all fails and notes ordered by case. Also replace lines
--   with state of current case.
function H.overview_reporter.generate(replace_last_lines, opts)
  local all_cases, all_groups, latest_group
  local res = {}

  res.start = function(cases)
    all_cases = cases

    local symbol = H.reporter_symbols[nil]
    all_groups = vim.tbl_map(function(c)
      local desc_trunc = vim.list_slice(c.desc, 1, opts.group_depth)
      local group = table.concat(desc_trunc, ' | ')
      return { group = group, symbol = symbol }
    end, cases)

    local lines = H.overview_reporter.start_summary(all_cases, all_groups)
    replace_last_lines(0, lines)
  end

  res.update = function(case_num)
    local case = all_cases[case_num]
    local cur_group = all_groups[case_num].group

    -- Update symbol
    local state = type(case.exec) == 'table' and case.exec.state or nil
    all_groups[case_num].symbol = H.reporter_symbols[state]

    local n_replace = H.overview_reporter.update_n_replace(latest_group, cur_group)
    local lines = H.overview_reporter.update_lines(case_num, all_cases, all_groups)
    replace_last_lines(n_replace, lines)

    latest_group = cur_group
  end

  res.finish = function()
    local lines = H.overview_reporter.finish_summary(all_cases)
    -- Force drawing to show everything queued up
    replace_last_lines(2, lines, true)

    -- Possibly quit
    --stylua: ignore
    if not opts.quit_on_finish then return end

    local has_fails = false
    for _, c in ipairs(all_cases) do
      local n_fails = c.exec == nil and 0 or #c.exec.fails
      has_fails = has_fails or n_fails > 0
    end

    vim.cmd(has_fails and '1cquit!' or '0cquit!')
  end

  return res
end

function H.overview_reporter.start_summary(cases, groups)
  local unique_groups = {}
  for _, g in ipairs(groups) do
    unique_groups[g.group] = true
  end
  local n_groups = #vim.tbl_keys(unique_groups)

  return {
    string.format('%s %s', H.add_style('Total number of cases:', 'emphasis'), #cases),
    string.format('%s %s', H.add_style('Total number of groups:', 'emphasis'), n_groups),
    '',
  }
end

function H.overview_reporter.update_lines(case_num, cases, groups)
  local cur_case = cases[case_num]
  local cur_group = groups[case_num].group

  --stylua: ignore
  local cur_group_symbols = vim.tbl_map(
    function(g) return g.symbol end,
    vim.tbl_filter(function(g) return g.group == cur_group end, groups)
  )

  return {
    -- Group overview
    string.format('%s: %s', cur_group, table.concat(cur_group_symbols)),
    '',
    H.add_style('Current case state', 'emphasis'),
    string.format('%s: %s', H.case_to_stringid(cur_case), cur_case.exec.state),
  }
end

function H.overview_reporter.update_n_replace(latest_group, cur_group)
  -- By default rewrite latest group symbol overview
  local res = 4

  if latest_group == nil then
    -- Nothing to rewrite on first ever call
    res = 0
  elseif latest_group ~= cur_group then
    -- Write just under latest group symbol overview
    res = 3
  end

  return res
end

function H.overview_reporter.finish_summary(cases)
  local res = {}

  -- Show all fails and notes
  for _, c in ipairs(cases) do
    local stringid = H.case_to_stringid(c)
    local exec = c.exec == nil and { fails = {}, notes = {} } or c.exec

    local fail_prefix = string.format('%s in %s: ', H.add_style('FAIL', 'fail'), stringid)
    local note_color = #exec.fails > 0 and 'fail' or 'pass'
    local note_prefix = string.format('%s in %s: ', H.add_style('NOTE', note_color), stringid)

    local cur_fails_notes = {}
    vim.list_extend(cur_fails_notes, H.add_prefix(exec.fails, fail_prefix))
    vim.list_extend(cur_fails_notes, H.add_prefix(exec.notes, note_prefix))

    cur_fails_notes = table.concat(cur_fails_notes, '\n')
    cur_fails_notes = cur_fails_notes == '' and {} or vim.split(cur_fails_notes, '\n')

    vim.list_extend(res, cur_fails_notes)
  end

  local header = #res > 0 and 'Fails and notes' or 'No fails. No notes.'
  table.insert(res, 1, H.add_style(header, 'emphasis'))

  return res
end

-- Buffer reporter utilities --------------------------------------------------
H.buffer_reporter = { ns_id = vim.api.nvim_create_namespace('MiniTestBuffer'), n_buffer = 0 }

function H.buffer_reporter.setup_buf_and_win(opts)
  local buf_id = vim.api.nvim_create_buf(true, true)

  local win_id
  if vim.is_callable(opts.window) then
    win_id = opts.window()
  elseif type(opts.window) == 'table' then
    win_id = vim.api.nvim_open_win(buf_id, true, opts.window)
  end
  win_id = win_id or vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win_id, buf_id)

  H.buffer_reporter.set_options(buf_id, win_id)
  H.buffer_reporter.set_mappings(buf_id)

  return buf_id, win_id
end

function H.buffer_reporter.default_window_opts()
  return {
    relative = 'editor',
    width = math.floor(0.618 * vim.o.columns),
    height = math.floor(0.618 * vim.o.lines),
    row = math.floor(0.191 * vim.o.lines),
    col = math.floor(0.191 * vim.o.columns),
    zindex = 99,
  }
end

function H.buffer_reporter.set_options(buf_id, win_id)
  -- Set unique name
  local n_buffer = H.buffer_reporter.n_buffer + 1
  local prefix = n_buffer == 1 and '' or (' ' .. n_buffer)
  vim.api.nvim_buf_set_name(buf_id, 'MiniTest' .. prefix)
  H.buffer_reporter.n_buffer = n_buffer

  -- Having `noautocmd` is crucial for performance: ~9ms without it, ~1.6ms with it
  vim.cmd('noautocmd silent! set filetype=minitest')

  -- Set options for "temporary" buffer
  --stylua: ignore start
  local buf_options = { buflisted = false, buftype = 'nofile', modeline = false, swapfile = false }
  for name, value in pairs(buf_options) do
    vim.api.nvim_buf_set_option(buf_id, name, value)
  end
  -- Doesn't work inside `nvim_buf_set_option()`
  vim.cmd('setlocal bufhidden=wipe')

  local win_options = {
    colorcolumn = '', fillchars = 'eob: ',    foldcolumn = '0', foldlevel = 999,
    number = false,   relativenumber = false, spell = false,    signcolumn = 'no',
    wrap = true,
  }
  for name, value in pairs(win_options) do
    vim.api.nvim_win_set_option(win_id, name, value)
  end
  --stylua: ignore end
end

function H.buffer_reporter.set_mappings(buf_id)
  local map_buf = function(key, rhs, opts)
    -- Use mapping description only in Neovim>=0.7
    if vim.fn.has('nvim-0.7') == 0 then
      opts.desc = nil
    end

    vim.api.nvim_buf_set_keymap(buf_id, 'n', key, rhs, opts)
  end

  map_buf('<Esc>', '<Cmd>lua MiniTest.stop()<CR>', { noremap = true, desc = 'Stop execution' })
  --stylua: ignore
  map_buf('q', [[<Cmd>lua MiniTest.stop(); vim.cmd('close')<CR>]], { noremap = true, desc = 'Stop execution and close window' })
end

function H.buffer_reporter.set_lines(buf_id, lines, start, finish)
  local ns_id = H.buffer_reporter.ns_id

  -- Remove ANSI codes while tracking appropriate highlight data
  local new_lines, hl_ranges = {}, {}
  for i, l in ipairs(lines) do
    local n_removed = 0
    local new_l = l:gsub('()(\27%[.-m)(.-)\27%[0m', function(...)
      local dots = { ... }
      local left = dots[1] - n_removed
      table.insert(
        hl_ranges,
        { hl = H.hl_groups[dots[2]], line = start + i - 1, left = left - 1, right = left + dots[3]:len() - 1 }
      )

      -- Here `4` is `string.len('\27[0m')`
      n_removed = n_removed + dots[2]:len() + 4
      return dots[3]
    end)
    table.insert(new_lines, new_l)
  end

  -- Set lines
  vim.api.nvim_buf_set_lines(buf_id, start, finish, true, new_lines)

  -- Highlight
  for _, hl_data in ipairs(hl_ranges) do
    vim.highlight.range(buf_id, ns_id, hl_data.hl, { hl_data.line, hl_data.left }, { hl_data.line, hl_data.right }, {})
  end
end

-- Predicates -----------------------------------------------------------------
function H.is_instance(x, class)
  local metatbl = getmetatable(x)
  return type(metatbl) == 'table' and metatbl.class == class
end

-- Expectation utilities ------------------------------------------------------
function H.error_expect(cause, ...)
  local lines = { ... }
  local first_line = '\n' .. H.add_style(string.format('Failed expectation for %s.', cause), 'emphasis')
  table.insert(lines, 1, first_line)

  -- Add traceback
  table.insert(lines, 'Traceback:')
  vim.list_extend(lines, H.traceback())

  -- Indent lines
  local msg = table.concat(lines, '\n'):gsub('\n', '\n  ')
  error(msg, 0)
end

function H.traceback()
  local level, res = 1, {}
  local info = debug.getinfo(level, 'Snl')
  local this_short_src = info.short_src
  while info ~= nil do
    local is_from_file = info.source:sub(1, 1) == '@'
    local is_from_this_file = info.short_src == this_short_src
    if is_from_file and not is_from_this_file then
      local line = string.format([[  %s:%s]], info.short_src, info.currentline)
      table.insert(res, line)
    end
    level = level + 1
    info = debug.getinfo(level, 'Snl')
  end

  return res
end

function H.screenshot_to_string(x)
  local res = vim.deepcopy(x)
  if H.is_headless then
    -- Show screenshot inline (without going home and deleting lines)
    res[2] = res[2]:gsub('\27%[%d?H\27%[%d?J', '', 1)

    -- Neutralize possible indentation
    for i = 2, #res do
      res[i] = string.format('\r%s', res[i])
    end
  end
  return table.concat(res, '\n')
end

-- Utilities ------------------------------------------------------------------
function H.message(msg)
  vim.cmd('echomsg ' .. vim.inspect('(mini.test) ' .. msg))
end

function H.error(msg)
  error(string.format('(mini.test) %s', msg))
end

--stylua: ignore
function H.wrap_callable(f)
  if not vim.is_callable(f) then return end
  return function(...) return f(...) end
end

--stylua: ignore
function H.exec_callable(f, ...)
  if not vim.is_callable(f) then return end
  return f(...)
end

function H.add_prefix(tbl, prefix)
  --stylua: ignore
  return vim.tbl_map(function(x) return ('%s%s'):format(prefix, x) end, tbl)
end

function H.add_style(x, ansi_code)
  return string.format('%s%s%s', H.ansi_codes[ansi_code], x, H.ansi_codes.reset)
end

return MiniTest
