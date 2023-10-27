local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('extra', config) end
local unload_module = function() child.mini_unload('extra') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

-- Tweak `expect_screenshot()` to test only on Neovim=0.9 (as it introduced
-- titles and 0.10 introduced footer).
-- Use `child.expect_screenshot_orig()` for original testing.
child.expect_screenshot_orig = child.expect_screenshot
child.expect_screenshot = function(opts, allow_past_09)
  -- TODO: Regenerate all screenshots with 0.10 after its stable release
  if child.fn.has('nvim-0.9') == 0 or child.fn.has('nvim-0.10') == 1 then return end
  child.expect_screenshot_orig(opts)
end

-- Test paths helpers
local join_path = function(...) return table.concat({ ... }, '/') end

local full_path = function(x)
  local res = vim.fn.fnamemodify(x, ':p'):gsub('/$', '')
  return res
end

local test_dir = 'tests/dir-extra'
local test_dir_absolute = full_path(test_dir)
local real_files_dir = 'tests/dir-extra/real-files'

local make_testpath = function(...) return join_path(test_dir, ...) end

local real_file = function(basename) return join_path(real_files_dir, basename) end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local forward_lua_notify = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_notify(lua_cmd, { ... }) end
end

local stop_picker = forward_lua('MiniPick.stop')
local get_picker_items = forward_lua('MiniPick.get_picker_items')
local get_picker_matches = forward_lua('MiniPick.get_picker_matches')
local get_picker_state = forward_lua('MiniPick.get_picker_state')
local is_picker_active = forward_lua('MiniPick.is_picker_active')

-- Use `child.api_notify` to allow user input while child process awaits for
-- `start()` to return a value
local start_picker = function(...) child.lua_notify('MiniPick.start(...)', { ... }) end

-- Common test helpers
local validate_buf_name = function(buf_id, name)
  buf_id = buf_id or child.api.nvim_get_current_buf()
  name = name ~= '' and full_path(name) or ''
  name = name:gsub('/+$', '')
  eq(child.api.nvim_buf_get_name(buf_id), name)
end

local validate_edit = function(lines_before, cursor_before, keys, lines_after, cursor_after)
  child.ensure_normal_mode()
  set_lines(lines_before)
  set_cursor(cursor_before[1], cursor_before[2])

  type_keys(keys)

  eq(get_lines(), lines_after)
  eq(get_cursor(), cursor_after)

  child.ensure_normal_mode()
end

local validate_edit1d = function(line_before, col_before, keys, line_after, col_after)
  validate_edit({ line_before }, { 1, col_before }, keys, { line_after }, { 1, col_after })
end

local validate_picker_name =
  function(ref_name) eq(child.lua_get('MiniPick.get_picker_opts().source.name'), ref_name) end

local validate_picker_cwd = function(ref_cwd) eq(child.lua_get('MiniPick.get_picker_opts().source.cwd'), ref_cwd) end

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

local get_extra_picker_extmarks = function(from, to)
  local ns_id = child.api.nvim_get_namespaces().MiniExtraPickers
  local extmarks = child.api.nvim_buf_get_extmarks(0, ns_id, from, to, { details = true })
  return vim.tbl_map(function(x) return { row = x[2], col = x[3], hl_group = x[4].hl_group } end, extmarks)
end

-- Common mocks
local mock_fn_executable = function(available_executables)
  local lua_cmd = string.format(
    'vim.fn.executable = function(x) return vim.tbl_contains(%s, x) and 1 or 0 end',
    vim.inspect(available_executables)
  )
  child.lua(lua_cmd)
end

local mock_git_repo = function(repo_dir)
  mock_fn_executable({ 'git' })

  local lua_cmd = string.format(
    [[
      _G.systemlist_orig = _G.systemlist_orig or vim.fn.systemlist
      vim.fn.systemlist = function(...)
        _G.systemlist_args = {...}
        return %s
      end]],
    vim.inspect({ repo_dir })
  )
  child.lua(lua_cmd)
end

local mock_no_git_repo = function()
  mock_fn_executable({ 'git' })
  child.lua([[
    _G.systemlist_orig = _G.systemlist_orig or vim.fn.systemlist
    -- Mock shell error after running check for Git repo
    vim.fn.systemlist = function() return _G.systemlist_orig('non-existing-cli-command') end
  ]])
end

local mock_spawn = function()
  local mock_file = join_path(test_dir, 'mocks', 'spawn.lua')
  local lua_cmd = string.format('dofile(%s)', vim.inspect(mock_file))
  child.lua(lua_cmd)
end

local mock_stdout_feed = function(feed) child.lua('_G.stdout_data_feed = ' .. vim.inspect(feed)) end

local mock_stderr_feed = function(feed) child.lua('_G.stderr_data_feed = ' .. vim.inspect(feed)) end

local mock_cli_return = function(lines)
  mock_stdout_feed({ table.concat(lines, '\n') })
  mock_stderr_feed({})
end

local mock_cli_error = function(lines)
  mock_stdout_feed({})
  mock_stderr_feed({ table.concat(lines, '\n') })
end

local get_spawn_log = function() return child.lua_get('_G.spawn_log') end

local clear_spawn_log = function() child.lua('_G.spawn_log = {}') end

local validate_spawn_log = function(ref, index)
  local present = get_spawn_log()
  if type(index) == 'number' then present = present[index] end
  eq(present, ref)
end

local get_process_log = function() return child.lua_get('_G.process_log') end

local clear_process_log = function() child.lua('_G.process_log = {}') end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()

      -- TODO: Adjust (remove?) when moved to 'mini.nvim'
      local mini_source = child.fn.getcwd() .. '/deps/mini.nvim'
      child.o.rtp = child.o.rtp .. ',' .. mini_source

      -- Make more comfortable screenshots
      child.set_size(15, 40)
      child.o.laststatus = 0
      child.o.ruler = false
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  child.lua([[require('mini-dev.extra').setup()]])

  -- Global variable
  eq(child.lua_get('type(_G.MiniExtra)'), 'table')
end

T['General'] = new_set()

T['General']['pickers are added to `MiniPick.registry`'] = new_set(
  { parametrize = { { 'pick_first' }, { 'extra_first' } } },
  {
    test = function(init_order)
      if init_order == 'extra_first' then
        load_module()
        child.lua([[require('mini.pick').setup()]])
      end
      if init_order == 'pick_first' then
        child.lua([[require('mini.pick').setup()]])
        load_module()
      end

      local extra_pickers = child.lua_get('vim.tbl_keys(MiniExtra.pickers)')
      for _, picker_name in ipairs(extra_pickers) do
        local lua_cmd = string.format([[type(MiniPick.registry['%s'])]], picker_name)
        eq(child.lua_get(lua_cmd), 'function')
      end
    end,
  }
)

T['gen_ai_spec'] = new_set({ hooks = { pre_case = load_module } })

T['gen_ai_spec']['line()'] = new_set()

T['gen_ai_spec']['line()']['works as `a` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { L = MiniExtra.gen_ai_spec.line() } })]])

  validate_edit1d('aa', 0, { 'caL', 'xx', '<Esc>' }, 'xx', 1)
  validate_edit1d('  aa', 0, { 'caL', 'xx', '<Esc>' }, 'xx', 1)
  validate_edit1d('\taa', 0, { 'caL', 'xx', '<Esc>' }, 'xx', 1)
  validate_edit1d('  aa', 2, { 'caL', 'xx', '<Esc>' }, 'xx', 1)

  -- Should operate charwise inside a line
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 1 }, { 'daL' }, { '', 'bb', 'cc' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 2, 1 }, { 'daL' }, { 'aa', '', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 3, 1 }, { 'daL' }, { 'aa', 'bb', '' }, { 3, 0 })

  -- Should work with dot-repeat
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'caL', 'xx', '<Esc>', 'j', '.' }, { 'xx', 'xx' }, { 2, 1 })
end

T['gen_ai_spec']['line()']['works as `i` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { L = MiniExtra.gen_ai_spec.line() } })]])

  validate_edit1d('aa', 0, { 'ciL', 'xx', '<Esc>' }, 'xx', 1)
  validate_edit1d('  aa', 0, { 'ciL', 'xx', '<Esc>' }, '  xx', 3)
  validate_edit1d('\taa', 0, { 'ciL', 'xx', '<Esc>' }, '\txx', 2)
  validate_edit1d(' \taa', 0, { 'ciL', 'xx', '<Esc>' }, ' \txx', 3)
  validate_edit1d('  aa', 2, { 'ciL', 'xx', '<Esc>' }, '  xx', 3)

  -- Should operate charwise inside a line
  validate_edit({ '  aa', '  bb', '  cc' }, { 1, 1 }, { 'diL' }, { '  ', '  bb', '  cc' }, { 1, 1 })
  validate_edit({ '  aa', '  bb', '  cc' }, { 2, 1 }, { 'diL' }, { '  aa', '  ', '  cc' }, { 2, 1 })
  validate_edit({ '  aa', '  bb', '  cc' }, { 3, 1 }, { 'diL' }, { '  aa', '  bb', '  ' }, { 3, 1 })

  -- Should work with dot-repeat
  validate_edit({ '  aa', '  bb' }, { 1, 0 }, { 'ciL', 'xx', '<Esc>', 'j', '.' }, { '  xx', '  xx' }, { 2, 3 })
end

T['gen_ai_spec']['buffer()'] = new_set()

T['gen_ai_spec']['buffer()']['works as `a` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { B = MiniExtra.gen_ai_spec.buffer() } })]])

  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'caB', 'xx', '<Esc>' }, { 'xx' }, { 1, 1 })
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'caB', 'xx', '<Esc>' }, { 'xx' }, { 1, 1 })

  local validate_delete =
    function(lines_before, cursor_before) validate_edit(lines_before, cursor_before, { 'daB' }, { '' }, { 1, 0 }) end

  validate_delete({ '', ' ', '\t', 'aa', '\t', ' ', '' }, { 1, 0 })
  validate_delete({ '', ' ', '\t', 'aa', '\t', ' ', '' }, { 4, 0 })
  validate_delete({ '', 'aa', '', 'cc', '' }, { 1, 0 })

  validate_delete({ 'aa' }, { 1, 0 })
  validate_delete({ 'aa', '' }, { 1, 0 })
  validate_delete({ '' }, { 1, 0 })
  validate_delete({ ' ', ' ', ' ' }, { 1, 0 })

  -- Should work with dot-repeat
  local buf_id_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { ' ', 'bb', ' ' })

  set_lines({ ' ', 'aa', ' ' })
  type_keys('caB', 'xx', '<Esc>')
  eq(get_lines(), { 'xx' })
  child.api.nvim_set_current_buf(buf_id_2)
  type_keys('.')
  eq(get_lines(), { 'xx' })
end

T['gen_ai_spec']['buffer()']['works as `i` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { B = MiniExtra.gen_ai_spec.buffer() } })]])

  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'ciB', 'xx', '<Esc>' }, { 'xx' }, { 1, 1 })
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'ciB', 'xx', '<Esc>' }, { 'xx' }, { 1, 1 })

  local lines_with_blanks = { '', ' ', '\t', 'aa', '\t', ' ', '' }
  validate_edit(lines_with_blanks, { 1, 0 }, { 'diB' }, { '', ' ', '\t', '', '\t', ' ', '' }, { 4, 0 })
  validate_edit(lines_with_blanks, { 4, 0 }, { 'diB' }, { '', ' ', '\t', '', '\t', ' ', '' }, { 4, 0 })

  validate_edit({ '', 'aa', '', 'cc', '' }, { 1, 0 }, { 'ciB', 'xx', '<Esc>' }, { '', 'xx', '' }, { 2, 1 })
  validate_edit({ '  aa', '  ', 'bb  ' }, { 1, 0 }, { 'ciB', 'xx', '<Esc>' }, { 'xx' }, { 1, 1 })

  validate_edit({ 'aa' }, { 1, 0 }, { 'diB' }, { '' }, { 1, 0 })
  validate_edit({ 'aa', '' }, { 1, 0 }, { 'diB' }, { '', '' }, { 1, 0 })
  validate_edit({ '', 'aa' }, { 1, 0 }, { 'diB' }, { '', '' }, { 2, 0 })
  validate_edit({ '' }, { 1, 0 }, { 'diB' }, { '' }, { 1, 0 })
  validate_edit({ ' ', ' ', ' ' }, { 1, 0 }, { 'diB' }, { ' ', ' ', ' ' }, { 1, 0 })

  -- Should work with dot-repeat
  local buf_id_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { ' ', '  bb', ' ' })

  set_lines({ ' ', '  aa', ' ' })
  type_keys('ciB', 'xx', '<Esc>')
  eq(get_lines(), { ' ', 'xx', ' ' })
  child.api.nvim_set_current_buf(buf_id_2)
  type_keys('.')
  eq(get_lines(), { ' ', 'xx', ' ' })
end

T['gen_highlighter'] = new_set({ hooks = { pre_case = load_module } })

T['gen_highlighter']['words()'] = new_set()

local hi_words = forward_lua('MiniExtra.gen_highlighter.words')

T['gen_highlighter']['words()']['works'] = function()
  eq(hi_words({ 'aaa' }, 'Error'), { pattern = { '%f[%w]()aaa()%f[%W]' }, group = 'Error' })
  eq(
    hi_words({ 'aaa', 'bbb' }, 'Error'),
    { pattern = { '%f[%w]()aaa()%f[%W]', '%f[%w]()bbb()%f[%W]' }, group = 'Error' }
  )

  -- Should escape special characters
  eq(hi_words({ 'a.+?-b' }, 'Error'), { pattern = { '%f[%w]()a%.%+%?%-b()%f[%W]' }, group = 'Error' })

  -- Should use `extmark_opts` as is
  eq(
    hi_words({ 'aaa' }, 'Error', { priority = 100 }),
    { pattern = { '%f[%w]()aaa()%f[%W]' }, group = 'Error', extmark_opts = { priority = 100 } }
  )
end

T['gen_highlighter']['words()']['validates arugments'] = function()
  expect.error(function() hi_words('todo', 'Error') end, '`words`.*array')
  expect.error(function() hi_words({ 1 }, 'Error') end, '`words`.*strings')
  expect.error(function() hi_words({ 'todo' }, 1) end, '`group`.*string or callable')
end

T['pickers'] = new_set({
  hooks = {
    pre_case = function()
      load_module()
      child.lua([[require('mini.pick').setup()]])

      -- Make picker border differentiable in screenshots
      child.cmd('hi MiniPickBorder ctermfg=2')
    end,
  },
})

T['pickers']["validate no 'mini.pick'"] = function()
  child.lua([[require = function(module) error() end]])

  -- Possibly exclude some pickers from testing
  if child.fn.has('nvim-0.8') == 0 then
    child.lua('MiniExtra.pickers.lsp = nil')
    child.lua('MiniExtra.pickers.treesitter = nil')
  end

  local extra_pickers = child.lua_get('vim.tbl_keys(MiniExtra.pickers)')
  for _, picker_name in ipairs(extra_pickers) do
    local err_pattern = '%(mini%.extra%) `pickers%.' .. picker_name .. "%(%)` requires 'mini%.pick'"

    expect.error(function()
      local lua_cmd = string.format([[MiniExtra.pickers['%s']()]], picker_name)
      child.lua(lua_cmd)
    end, err_pattern)
  end
end

T['pickers']['diagnostic()'] = new_set({
  hooks = {
    pre_case = function()
      local mock_path = make_testpath('mocks', 'diagnostic.lua')
      child.lua(string.format('dofile("%s")', mock_path))
    end,
  },
})

local pick_diagnostic = forward_lua_notify('MiniExtra.pickers.diagnostic')

T['pickers']['diagnostic()']['works'] = function()
  child.set_size(25, 100)
  child.cmd('enew')

  child.lua_notify('_G.return_item = MiniExtra.pickers.diagnostic()')
  validate_picker_name('Diagnostic (all)')
  child.expect_screenshot()

  -- Should use proper highlight groups
  validate_partial_equal_arr(get_extra_picker_extmarks(0, -1), {
    { hl_group = 'DiagnosticFloatingError' },
    { hl_group = 'DiagnosticFloatingError' },
    { hl_group = 'DiagnosticFloatingError' },
    { hl_group = 'DiagnosticFloatingWarn' },
    { hl_group = 'DiagnosticFloatingWarn' },
    { hl_group = 'DiagnosticFloatingWarn' },
    { hl_group = 'DiagnosticFloatingInfo' },
    { hl_group = 'DiagnosticFloatingInfo' },
    { hl_group = 'DiagnosticFloatingInfo' },
    { hl_group = 'DiagnosticFloatingHint' },
    { hl_group = 'DiagnosticFloatingHint' },
    { hl_group = 'DiagnosticFloatingHint' },
  })

  -- Should have proper preview
  type_keys('<C-n>')
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should properly choose
  type_keys('<CR>')
  validate_buf_name(0, make_testpath('mocks', 'diagnostic-file-1'))
  eq(get_cursor(), { 2, 2 })

  --stylua: ignore
  -- Should return chosen value with proper structure
  eq(child.lua_get('_G.return_item'), {
    bufnr    = 1, namespace = child.lua_get('_G.diag_ns'),
    severity = 1,
    col      = 3, end_col   = 8,
    end_lnum = 2, lnum      = 2,
    path     = 'tests/dir-extra/mocks/diagnostic-file-1',
    message  = 'Error 2',
    text     = 'E │ tests/dir-extra/mocks/diagnostic-file-1 │ Error 2',
  })
end

T['pickers']['diagnostic()']['respects `local_opts.get_opts`'] = function()
  local hint_severity = child.lua_get('vim.diagnostic.severity.HINT')
  pick_diagnostic({ get_opts = { severity = hint_severity } })
  validate_partial_equal_arr(
    get_picker_items(),
    { { severity = hint_severity }, { severity = hint_severity }, { severity = hint_severity } }
  )
end

T['pickers']['diagnostic()']['respects `local_opts.scope`'] = function()
  local buf_id = child.api.nvim_get_current_buf()
  pick_diagnostic({ scope = 'current' })
  validate_picker_name('Diagnostic (current)')
  validate_partial_equal_arr(
    get_picker_items(),
    { { bufnr = buf_id }, { bufnr = buf_id }, { bufnr = buf_id }, { bufnr = buf_id } }
  )
end

T['pickers']['diagnostic()']['respects `local_opts.sort_by`'] = function()
  local sev_error = child.lua_get('_G.vim.diagnostic.severity.ERROR')
  local sev_warn = child.lua_get('_G.vim.diagnostic.severity.WARN')
  local sev_info = child.lua_get('_G.vim.diagnostic.severity.INFO')
  local sev_hint = child.lua_get('_G.vim.diagnostic.severity.HINT')

  local path_1 = make_testpath('mocks', 'diagnostic-file-1')
  local path_2 = make_testpath('mocks', 'diagnostic-file-2')

  pick_diagnostic({ sort_by = 'severity' })
  --stylua: ignore
  validate_partial_equal_arr(
    get_picker_items(),
    {
      { severity = sev_error, path = path_1, message = 'Error 1' },
      { severity = sev_error, path = path_1, message = 'Error 2' },
      { severity = sev_error, path = path_2, message = 'Error 3' },
      { severity = sev_warn,  path = path_1, message = 'Warning 1' },
      { severity = sev_warn,  path = path_1, message = 'Warning 2' },
      { severity = sev_warn,  path = path_2, message = 'Warning 3' },
      { severity = sev_info,  path = path_1, message = 'Info 1' },
      { severity = sev_info,  path = path_1, message = 'Info 2' },
      { severity = sev_info,  path = path_2, message = 'Info 3' },
      { severity = sev_hint,  path = path_1, message = 'Hint 1' },
      { severity = sev_hint,  path = path_1, message = 'Hint 2' },
      { severity = sev_hint,  path = path_2, message = 'Hint 3' },
    }
  )
  stop_picker()

  pick_diagnostic({ sort_by = 'path' })
  --stylua: ignore
  validate_partial_equal_arr(
    get_picker_items(),
    {
      { severity = sev_error, path = path_1, message = 'Error 1' },
      { severity = sev_error, path = path_1, message = 'Error 2' },
      { severity = sev_warn,  path = path_1, message = 'Warning 1' },
      { severity = sev_warn,  path = path_1, message = 'Warning 2' },
      { severity = sev_info,  path = path_1, message = 'Info 1' },
      { severity = sev_info,  path = path_1, message = 'Info 2' },
      { severity = sev_hint,  path = path_1, message = 'Hint 1' },
      { severity = sev_hint,  path = path_1, message = 'Hint 2' },
      { severity = sev_error, path = path_2, message = 'Error 3' },
      { severity = sev_warn,  path = path_2, message = 'Warning 3' },
      { severity = sev_info,  path = path_2, message = 'Info 3' },
      { severity = sev_hint,  path = path_2, message = 'Hint 3' },
    }
  )
  stop_picker()
end

T['pickers']['diagnostic()']['respects `opts`'] = function()
  pick_diagnostic({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['diagnostic()']['does not modify diagnostic table'] = function()
  local diagnostic_current = child.lua_get('vim.diagnostic.get()')
  pick_diagnostic()
  stop_picker()
  eq(child.lua_get('vim.diagnostic.get()'), diagnostic_current)
end

T['pickers']['diagnostic()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.diagnostic(...)', { local_opts }) end, error_pattern)
  end
  validate({ scope = '1' }, '`pickers%.diagnostic`.*"scope".*"1".*one of')
  validate({ sort_by = '1' }, '`pickers%.diagnostic`.*"sort_by".*"1".*one of')
end

T['pickers']['oldfiles()'] = new_set()

local pick_oldfiles = forward_lua_notify('MiniExtra.pickers.oldfiles')

T['pickers']['oldfiles()']['works'] = function()
  child.set_size(10, 70)
  local path_1, path_2 = real_file('LICENSE'), make_testpath('mocks', 'diagnostic.lua')
  local ref_oldfiles = { full_path(path_1), full_path(path_2), 'not-existing' }
  child.v.oldfiles = ref_oldfiles

  child.lua_notify('_G.return_item = MiniExtra.pickers.oldfiles()')
  validate_picker_name('Old files')
  child.expect_screenshot()

  -- Should have proper items (only readable files with short paths)
  eq(get_picker_items(), { path_1, path_2 })

  -- Should properly choose
  type_keys('<CR>')
  validate_buf_name(0, path_1)
  eq(get_cursor(), { 1, 0 })

  --stylua: ignore
  -- Should return chosen value with proper structure
  eq(child.lua_get('_G.return_item'), path_1)
end

T['pickers']['oldfiles()']['works with empty `v:oldfiles`'] = function()
  child.v.oldfiles = {}
  pick_oldfiles()
  eq(get_picker_items(), {})
end

T['pickers']['oldfiles()']['can not show icons'] = function()
  child.set_size(10, 70)
  local ref_oldfiles = { full_path(real_file('LICENSE')), full_path(make_testpath('mocks', 'diagnostic.lua')) }
  child.v.oldfiles = ref_oldfiles

  child.lua('MiniPick.config.source.show = MiniPick.default_show')
  pick_oldfiles()
  child.expect_screenshot()
end

T['pickers']['oldfiles()']['respects `opts`'] = function()
  pick_oldfiles({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['oldfiles()']['respects `opts.source.cwd`'] = function()
  child.set_size(10, 70)
  local ref_oldfiles = { full_path(real_file('LICENSE')), full_path(make_testpath('mocks', 'diagnostic.lua')) }
  child.v.oldfiles = ref_oldfiles

  pick_oldfiles({}, { source = { cwd = real_files_dir } })
  local items = get_picker_items()
  eq(items[1], 'LICENSE')
  expect.match(items[2], vim.pesc(ref_oldfiles[2]))
end

T['pickers']['buf_lines()'] = new_set()

local pick_buf_lines = forward_lua_notify('MiniExtra.pickers.buf_lines')

local setup_buffers = function()
  -- Normal buffer with name
  local buf_id_1 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_1, 0, -1, false, { 'This is', '  buffer 1' })
  child.api.nvim_buf_set_name(buf_id_1, 'buffer-1')

  -- Normal buffer without name
  local buf_id_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { 'This is', '  buffer 2' })

  -- Normal buffer without lines
  local buf_id_3 = child.api.nvim_create_buf(true, false)

  -- Not listed normal buffer
  local buf_id_4 = child.api.nvim_create_buf(false, false)

  -- Not normal buffer
  local buf_id_5 = child.api.nvim_create_buf(false, true)

  -- Set current buffer
  local buf_init = child.api.nvim_get_current_buf()
  child.api.nvim_set_current_buf(buf_id_1)
  child.api.nvim_buf_delete(buf_init, { force = true })

  return { buf_id_1, buf_id_2, buf_id_3, buf_id_4, buf_id_5 }
end

T['pickers']['buf_lines()']['works'] = function()
  local buffers = setup_buffers()

  child.lua_notify('_G.return_item = MiniExtra.pickers.buf_lines()')
  validate_picker_name('Buffer lines (all)')
  child.expect_screenshot()

  -- Should properly choose (and also support choosing in same buffer)
  type_keys('<C-n>')
  type_keys('<CR>')
  validate_buf_name(0, 'buffer-1')
  eq(get_cursor(), { 2, 0 })

  -- Should return chosen value with proper structure
  eq(child.lua_get('_G.return_item'), { bufnr = 2, lnum = 2, text = 'buffer-1:2:  buffer 1' })
end

T['pickers']['buf_lines()']['respects `local_opts.scope`'] = function()
  setup_buffers()
  pick_buf_lines({ scope = 'current' })
  validate_picker_name('Buffer lines (current)')
  child.expect_screenshot()
end

T['pickers']['buf_lines()']['can not show icons'] = function()
  setup_buffers()
  child.lua('MiniPick.config.source.show = MiniPick.default_show')
  pick_buf_lines()
  child.expect_screenshot()
end

T['pickers']['buf_lines()']['respects `opts`'] = function()
  pick_buf_lines({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['buf_lines()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.buf_lines(...)', { local_opts }) end, error_pattern)
  end
  validate({ scope = '1' }, '`pickers%.buf_lines`.*"scope".*"1".*one of')
end

T['pickers']['history()'] = new_set({
  hooks = {
    pre_case = function()
      child.cmd('set history=100')

      -- Command-line history
      child.lua('_G.n = 0')
      type_keys(':lua _G.n = _G.n + 1<CR>')
      type_keys(':lua _G.n = _G.n + 2<CR>')

      -- Search history
      child.api.nvim_buf_set_lines(0, 0, -1, false, { 'aaa', 'bbb' })
      type_keys('/aaa<CR>')
      type_keys('/bbb<CR>')

      -- Expressions history
      type_keys('O', '<C-r>=1+1<CR>', '<Esc>')
      type_keys('o', '<C-r>=2+2<CR>', '<Esc>')

      -- Input history
      child.lua_notify([[vim.fn.input('Prompt')]])
      type_keys('input 1', '<CR>')
      child.lua_notify([[vim.fn.input('Prompt')]])
      type_keys('input 2', '<CR>')

      -- Debug mode
      -- Can't really emulate debug mode

      child.api.nvim_buf_set_lines(0, 0, -1, false, {})
    end,
  },
})

local pick_history = forward_lua_notify('MiniExtra.pickers.history')

T['pickers']['history()']['works'] = function()
  child.set_size(20, 70)

  child.lua_notify('_G.return_item = MiniExtra.pickers.history()')
  -- - Should by default list all history
  validate_picker_name('History (all)')
  child.expect_screenshot()

  -- Should have no preview
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should return chosen value with proper structure
  type_keys('<CR>')
  eq(child.lua_get('_G.return_item'), ': lua _G.n = _G.n + 2')
end

T['pickers']['history()']['works for command-line history'] = function()
  -- Works
  pick_history({ scope = 'cmd' })
  eq(get_picker_items(), { ': lua _G.n = _G.n + 2', ': lua _G.n = _G.n + 1' })
  validate_picker_name('History (cmd)')

  -- Should execute command on choose
  local n = child.lua_get('_G.n')
  type_keys('<C-n>', '<CR>')
  eq(child.lua_get('_G.n'), n + 1)

  -- Should work with aliases
  pick_history({ scope = ':' })
  validate_picker_name('History (:)')
  -- - NOTE: now it doesn't update command line history, but probably should
  --   (just couldn't find a way to achieve this)
  eq(get_picker_items(), { ': lua _G.n = _G.n + 2', ': lua _G.n = _G.n + 1' })
end

T['pickers']['history()']['works for search history'] = function()
  set_lines({ 'bbb', '  aaa' })

  -- Works
  pick_history({ scope = 'search' })
  validate_picker_name('History (search)')
  eq(get_picker_items(), { '/ bbb', '/ aaa' })

  -- Should restart search on choose (and update history)
  type_keys('<C-n>', '<CR>')
  eq(get_cursor(), { 2, 2 })
  eq(child.o.hlsearch, true)
  -- - `:history` lists from oldest to newest
  expect.match(child.cmd_capture('history search'), 'bbb.*aaa')

  -- Should work with aliases
  pick_history({ scope = '/' })
  validate_picker_name('History (/)')
  eq(get_picker_items(), { '/ aaa', '/ bbb' })
  stop_picker()

  -- - For `?` alias should search backward
  set_lines({ 'aaa', 'bbb', 'aaa' })
  set_cursor(2, 0)
  pick_history({ scope = '?' })
  validate_picker_name('History (?)')
  eq(get_picker_items(), { '? aaa', '? bbb' })

  type_keys('<CR>')
  eq(get_cursor(), { 1, 0 })
  eq(child.o.hlsearch, true)
end

T['pickers']['history()']['works for expression register history'] = function()
  pick_history({ scope = 'expr' })
  validate_picker_name('History (expr)')
  eq(get_picker_items(), { '= 2+2', '= 1+1' })

  -- Nothing is expected to be done on choose
  type_keys('<CR>')

  -- Should work with aliases
  pick_history({ scope = '=' })
  validate_picker_name('History (=)')
  eq(get_picker_items(), { '= 2+2', '= 1+1' })
end

T['pickers']['history()']['works for input history'] = function()
  pick_history({ scope = 'input' })
  validate_picker_name('History (input)')
  eq(get_picker_items(), { '@ input 2', '@ input 1' })

  -- Nothing is expected to be done on choose
  type_keys('<CR>')

  -- Should work with aliases
  pick_history({ scope = '@' })
  validate_picker_name('History (@)')
  eq(get_picker_items(), { '@ input 2', '@ input 1' })
end

T['pickers']['history()']['respects `opts`'] = function()
  pick_history({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['history()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.history(...)', { local_opts }) end, error_pattern)
  end
  validate({ scope = '1' }, '`pickers%.history`.*"scope".*"1".*one of')
end

T['pickers']['hl_groups()'] = new_set()

local pick_hl_groups = forward_lua_notify('MiniExtra.pickers.hl_groups')

T['pickers']['hl_groups()']['works'] = function()
  child.cmd('colorscheme default')
  child.set_size(10, 80)

  child.lua_notify('_G.return_item = MiniExtra.pickers.hl_groups()')
  validate_picker_name('Highlight groups')
  type_keys('^Diff')
  child.expect_screenshot()

  -- Should use same group for line highlighting
  local matches = get_picker_matches().all
  validate_partial_equal_arr(get_extra_picker_extmarks(0, -1), {
    { row = 0, col = 0, hl_group = matches[1] },
    { row = 1, col = 0, hl_group = matches[2] },
    { row = 2, col = 0, hl_group = matches[3] },
    { row = 3, col = 0, hl_group = matches[4] },
  })

  -- Should have proper preview
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should properly choose
  type_keys('<CR>')
  eq(child.fn.getcmdline(), 'hi DiffAdd ctermbg=4 guibg=DarkBlue')
  eq(child.fn.getcmdpos(), 36)

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), 'DiffAdd')
end

T['pickers']['hl_groups()']['respects non-default/linked highlight groups'] = function()
  child.set_size(10, 40)
  child.cmd('hi AAAA guifg=#aaaaaa')
  child.cmd('hi link AAAB AAAA')

  pick_hl_groups()
  type_keys('^AAA')
  child.expect_screenshot()
  validate_partial_equal_arr(get_extra_picker_extmarks(0, -1), {
    { row = 0, col = 0, hl_group = 'AAAA' },
    { row = 1, col = 0, hl_group = 'AAAB' },
  })
end

T['pickers']['hl_groups()']['respects `opts`'] = function()
  pick_hl_groups({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['commands()'] = new_set()

local pick_commands = forward_lua_notify('MiniExtra.pickers.commands')

T['pickers']['commands()']['works'] = function()
  child.set_size(10, 80)

  child.lua_notify('_G.return_item = MiniExtra.pickers.commands()')
  validate_picker_name('Commands')
  type_keys("'chdir")
  child.expect_screenshot()

  -- Should have proper preview
  type_keys('<Tab>')
  -- - No data for built-in commands is yet available
  child.expect_screenshot()

  -- Should properly choose
  type_keys('<CR>')
  eq(child.fn.getcmdline(), 'chdir ')
  eq(child.fn.getcmdpos(), 7)

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), 'chdir')
end

T['pickers']['commands()']['respects user commands'] = function()
  child.set_size(25, 75)
  child.cmd('command -nargs=0 MyCommand lua _G.my_command = true')
  child.cmd('command -nargs=* -buffer MyCommandBuf lua _G.my_command_buf = true')

  -- Both global and buffer-local
  pick_commands()
  type_keys('^MyCommand')
  eq(get_picker_matches().all, { 'MyCommand', 'MyCommandBuf' })

  -- Should have proper preview with data
  type_keys('<Tab>')
  child.expect_screenshot()
  type_keys('<C-n>')
  child.expect_screenshot()

  -- Should on choose execute command if it is without arguments
  type_keys('<C-p>', '<CR>')
  eq(is_picker_active(), false)
  eq(child.lua_get('_G.my_command'), true)
  eq(child.lua_get('_G.my_command_buf'), vim.NIL)
end

T['pickers']['commands()']['respects `opts`'] = function()
  pick_commands({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['git_branches()'] = new_set({ hooks = { pre_case = mock_spawn } })

local pick_git_branches = forward_lua_notify('MiniExtra.pickers.git_branches')

T['pickers']['git_branches()']['works'] = function()
  child.set_size(10, 90)

  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  local branch_lines = {
    '* main              0123456 Commit message.',
    'remotes/origin/HEAD -> origin/main',
    'remotes/origin/main aaaaaaa Another commit message.',
  }
  mock_cli_return(branch_lines)

  local buf_init = child.api.nvim_get_current_buf()
  child.lua_notify('_G.return_item = MiniExtra.pickers.git_branches()')
  validate_picker_name('Git branches (all)')
  child.expect_screenshot()

  eq(get_spawn_log(), {
    { executable = 'git', options = { args = { 'branch', '--all', '-v', '--no-color', '--list' }, cwd = repo_dir } },
  })
  clear_spawn_log()
  clear_process_log()

  -- Should have proper preview
  child.lua([[_G.stream_type_queue = { 'stdout', 'stderr' }]])
  local log_lines = { '0123456 Commit message.', 'aaaaaaa Another commit message.' }
  mock_cli_return(log_lines)
  type_keys('<Tab>')
  child.expect_screenshot()

  eq(get_spawn_log(), {
    { executable = 'git', options = { args = { '-C', repo_dir, 'log', 'main', '--format=format:%h %s' } } },
  })
  -- - It should properly close both stdout and stderr
  eq(get_process_log(), { 'stdout_2 was closed.', 'stderr_1 was closed.', 'Process Pid_2 was closed.' })

  -- Should properly choose by showing history in the new scratch buffer
  child.lua([[_G.stream_type_queue = { 'stdout', 'stderr' }]])
  mock_cli_return(log_lines)
  type_keys('<CR>')

  eq(get_lines(), log_lines)
  eq(buf_init ~= child.api.nvim_get_current_buf(), true)
  eq(child.bo.buftype, 'nofile')

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), branch_lines[1])
end

T['pickers']['git_branches()']['respects `local_opts.path`'] = function()
  local repo_dir = test_dir_absolute
  mock_git_repo(repo_dir)
  local dir_path = make_testpath('git-files')
  local dir_path_full = full_path(dir_path)

  local validate = function(path, ref_repo_dir)
    pick_git_branches({ path = path })
    eq(get_spawn_log()[1].options, { args = { 'branch', '--all', '-v', '--no-color', '--list' }, cwd = ref_repo_dir })
    validate_picker_cwd(ref_repo_dir)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
  end

  -- Should always use parent repository path
  -- - Directory path
  validate(dir_path_full, repo_dir)

  -- - File path
  validate(join_path(dir_path, 'git-file-1'), repo_dir)

  --  - Default with different current directory
  child.fn.chdir(dir_path_full)
  validate(nil, repo_dir)
end

T['pickers']['git_branches()']['respects `local_opts.scope`'] = function()
  mock_git_repo(test_dir_absolute)
  child.fn.chdir(test_dir_absolute)

  local validate = function(scope, ref_args, ref_picker_name)
    pick_git_branches({ scope = scope })
    eq(get_spawn_log()[1].options.args, ref_args)
    validate_picker_name(ref_picker_name)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
  end

  validate('all', { 'branch', '--all', '-v', '--no-color', '--list' }, 'Git branches (all)')
  validate('local', { 'branch', '-v', '--no-color', '--list' }, 'Git branches (local)')
  validate('remotes', { 'branch', '--remotes', '-v', '--no-color', '--list' }, 'Git branches (remotes)')
end

T['pickers']['git_branches()']['respects `opts`'] = function()
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  pick_git_branches({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['git_branches()']['validates git'] = function()
  -- CLI
  mock_fn_executable({})
  expect.error(
    function() child.lua('MiniExtra.pickers.git_branches()') end,
    '`pickers%.git_branches` requires executable `git`'
  )

  -- Repo
  mock_no_git_repo()
  expect.error(
    function() child.lua('MiniExtra.pickers.git_branches()') end,
    '`pickers%.git_branches` could not find Git repo for ' .. vim.pesc(child.fn.getcwd())
  )
end

T['pickers']['git_branches()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.git_branches(...)', { local_opts }) end, error_pattern)
  end

  validate({ path = '1' }, 'Path.*1 is not a valid path')
  validate({ path = '' }, 'Path.*is empty')
  validate({ scope = '1' }, '`pickers%.git_branches`.*"scope".*"1".*one of')
end

T['pickers']['git_commits()'] = new_set({ hooks = { pre_case = mock_spawn } })

local pick_git_commits = forward_lua_notify('MiniExtra.pickers.git_commits')

T['pickers']['git_commits()']['works'] = function() MiniTest.skip() end

T['pickers']['git_commits()']['respects `opts`'] = function() MiniTest.skip() end

T['pickers']['git_files()'] = new_set({ hooks = { pre_case = mock_spawn } })

local pick_git_files = forward_lua_notify('MiniExtra.pickers.git_files')

T['pickers']['git_files()']['works'] = function()
  child.set_size(10, 50)

  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  mock_cli_return({ 'git-files/git-file-1', 'git-files/git-file-2' })

  child.lua_notify('_G.return_item = MiniExtra.pickers.git_files()')
  validate_picker_name('Git files (tracked)')
  child.expect_screenshot()
  eq(get_spawn_log(), {
    { executable = 'git', options = { args = { '-C', repo_dir, 'ls-files', '--cached' }, cwd = repo_dir } },
  })

  -- Should have proper preview
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should properly choose
  type_keys('<CR>')
  validate_buf_name(0, make_testpath('git-files', 'git-file-1'))

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), 'git-files/git-file-1')
end

T['pickers']['git_files()']['respects `local_opts.path`'] = function()
  local repo_dir = test_dir_absolute
  mock_git_repo(repo_dir)
  local dir_path = make_testpath('git-files')
  local dir_path_full = full_path(dir_path)

  local validate = function(path, ref_cwd)
    pick_git_files({ path = path })
    eq(get_spawn_log()[1].options, { args = { '-C', ref_cwd, 'ls-files', '--cached' }, cwd = ref_cwd })
    validate_picker_cwd(ref_cwd)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
  end

  -- Directory path
  validate(dir_path_full, dir_path_full)

  -- File path (should use its parent directory path)
  validate(join_path(dir_path, 'git-file-1'), dir_path_full)

  -- By default should not use parent repo and use current directory instead
  child.fn.chdir(dir_path_full)
  validate(nil, dir_path_full)
end

T['pickers']['git_files()']['respects `local_opts.scope`'] = function()
  mock_git_repo(test_dir_absolute)
  child.fn.chdir(test_dir_absolute)

  local validate = function(scope, flags, ref_picker_name)
    pick_git_files({ scope = scope })
    local ref_args = { '-C', test_dir_absolute, 'ls-files' }
    vim.list_extend(ref_args, flags)
    eq(get_spawn_log()[1].options.args, ref_args)
    validate_picker_name(ref_picker_name)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
  end

  validate('tracked', { '--cached' }, 'Git files (tracked)')
  validate('modified', { '--modified' }, 'Git files (modified)')
  validate('untracked', { '--others' }, 'Git files (untracked)')
  validate('ignored', { '--others', '--ignored', '--exclude-standard' }, 'Git files (ignored)')
  validate('deleted', { '--deleted' }, 'Git files (deleted)')
end

T['pickers']['git_files()']['can not show icons'] = function()
  child.set_size(10, 50)
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  mock_cli_return({ 'git-files/git-file-1', 'git-files/git-file-2' })

  child.lua('MiniPick.config.source.show = MiniPick.default_show')
  pick_git_files()
  child.expect_screenshot()
end

T['pickers']['git_files()']['respects `opts`'] = function()
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  pick_git_files({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['git_files()']['validates git'] = function()
  -- CLI
  mock_fn_executable({})
  expect.error(
    function() child.lua('MiniExtra.pickers.git_files()') end,
    '`pickers%.git_files` requires executable `git`'
  )

  -- Repo
  mock_no_git_repo()
  expect.error(
    function() child.lua('MiniExtra.pickers.git_files()') end,
    '`pickers%.git_files` could not find Git repo for ' .. vim.pesc(child.fn.getcwd())
  )
end

T['pickers']['git_files()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.git_files(...)', { local_opts }) end, error_pattern)
  end

  validate({ path = '1' }, 'Path.*1 is not a valid path')
  validate({ path = '' }, 'Path.*is empty')
  validate({ scope = '1' }, '`pickers%.git_files`.*"scope".*"1".*one of')
end

T['pickers']['git_hunks()'] = new_set({ hooks = { pre_case = mock_spawn } })

local pick_git_hunks = forward_lua_notify('MiniExtra.pickers.git_hunks')

T['pickers']['git_hunks()']['works'] = function() MiniTest.skip() end

T['pickers']['git_hunks()']['respects `opts`'] = function() MiniTest.skip() end

T['pickers']['options()'] = new_set()

local pick_options = forward_lua_notify('MiniExtra.pickers.options')

T['pickers']['options()']['works'] = function() MiniTest.skip() end

T['pickers']['options()']['respects `opts`'] = function() MiniTest.skip() end

T['pickers']['keymaps()'] = new_set()

local pick_keymaps = forward_lua_notify('MiniExtra.pickers.keymaps')

T['pickers']['keymaps()']['works'] = function() MiniTest.skip() end

T['pickers']['keymaps()']['respects `opts`'] = function() MiniTest.skip() end

T['pickers']['registers()'] = new_set()

local pick_registers = forward_lua_notify('MiniExtra.pickers.registers')

T['pickers']['registers()']['works'] = function() MiniTest.skip() end

T['pickers']['registers()']['respects `opts`'] = function() MiniTest.skip() end

T['pickers']['marks()'] = new_set()

local pick_marks = forward_lua_notify('MiniExtra.pickers.marks')

T['pickers']['marks()']['works'] = function() MiniTest.skip() end

T['pickers']['marks()']['respects `opts`'] = function() MiniTest.skip() end

T['pickers']['lsp()'] = new_set()

local pick_lsp = forward_lua_notify('MiniExtra.pickers.lsp')

T['pickers']['lsp()']['works'] = function() MiniTest.skip() end

T['pickers']['lsp()']['respects `opts`'] = function() MiniTest.skip() end

T['pickers']['treesitter()'] = new_set()

local pick_treesitter = forward_lua_notify('MiniExtra.pickers.treesitter')

T['pickers']['treesitter()']['works'] = function() MiniTest.skip() end

T['pickers']['treesitter()']['respects `opts`'] = function() MiniTest.skip() end

T['pickers']['list()'] = new_set()

local pick_list = forward_lua_notify('MiniExtra.pickers.list')

T['pickers']['list()']['works'] = function() MiniTest.skip() end

T['pickers']['list()']['respects `opts`'] = function() MiniTest.skip() end

T['pickers']['explorer()'] = new_set()

local pick_explorer = forward_lua_notify('MiniExtra.pickers.explorer')

T['pickers']['explorer()']['works'] = function() MiniTest.skip() end

T['pickers']['explorer()']['respects `opts`'] = function() MiniTest.skip() end

T['pickers']['hipatterns()'] = new_set()

local pick_hipatterns = forward_lua_notify('MiniExtra.pickers.hipatterns')

T['pickers']['hipatterns()']['works'] = function() MiniTest.skip() end

T['pickers']['hipatterns()']['respects `opts`'] = function() MiniTest.skip() end

return T
