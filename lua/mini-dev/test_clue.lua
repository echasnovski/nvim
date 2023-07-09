local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('clue', config) end
local unload_module = function() child.mini_unload('clue') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

-- Mapping helpers
local replace_termcodes = function(x) return vim.api.nvim_replace_termcodes(x, true, false, true) end

local reset_test_map_count = function(mode, lhs)
  local lua_cmd = string.format([[_G['test_map_%s_%s'] = 0]], mode, replace_termcodes(lhs))
  child.lua(lua_cmd)
end

local get_test_map_count = function(mode, lhs)
  local lua_cmd = string.format([=[_G['test_map_%s_%s']]=], mode, replace_termcodes(lhs))
  return child.lua_get(lua_cmd)
end

local make_test_map = function(mode, lhs, opts)
  lhs = replace_termcodes(lhs)
  opts = opts or {}

  reset_test_map_count(mode, lhs)

  --stylua: ignore
  local lua_cmd = string.format(
    [[vim.keymap.set('%s', '%s', function() _G['test_map_%s_%s'] = _G['test_map_%s_%s'] + 1 end, %s)]],
    mode, lhs,
    mode, lhs,
    mode, lhs,
    vim.inspect(opts)
  )
  child.lua(lua_cmd)
end

-- Custom validators
local validate_trigger_keymap = function(mode, keys)
  local lua_cmd = string.format("vim.fn.maparg('%s', '%s', false, true).desc", replace_termcodes(keys), mode)
  local map_desc = child.lua_get(lua_cmd)

  -- Neovim<0.8 doesn't have `keytrans()` used inside description
  if child.fn.has('nvim-0.8') == 0 then
    eq(type(map_desc), 'string')
  else
    local desc_pattern = 'clues after.*"' .. vim.pesc(keys) .. '"'
    expect.match(map_desc, desc_pattern)
  end
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

local validate_move =
  function(lines, cursor_before, keys, cursor_after) validate_edit(lines, cursor_before, keys, lines, cursor_after) end

local validate_move1d =
  function(line, col_before, keys, col_after) validate_edit1d(line, col_before, keys, line, col_after) end

local validate_selection = function(lines, cursor, keys, selection_from, selection_to, visual_mode)
  visual_mode = visual_mode or 'v'
  child.ensure_normal_mode()
  set_lines(lines)
  set_cursor(cursor[1], cursor[2])

  type_keys(keys)
  eq(child.fn.mode(), visual_mode)
  eq({ child.fn.line('v'), child.fn.col('v') - 1 }, selection_from)
  eq({ child.fn.line('.'), child.fn.col('.') - 1 }, selection_to)

  child.ensure_normal_mode()
end

local validate_selection1d = function(line, col, keys, selection_col_from, selection_col_to, visual_mode)
  validate_selection({ line }, { 1, col }, keys, { 1, selection_col_from }, { 1, selection_col_to }, visual_mode)
end

-- Data =======================================================================

-- Output test set ============================================================
T = new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniClue)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniClue'), 1)

  -- Highlight groups
  local validate_hl_group = function(name, ref) expect.match(child.cmd_capture('hi ' .. name), ref) end

  validate_hl_group('MiniClueBorder', 'links to FloatBorder')
  validate_hl_group('MiniClueGroup', 'links to DiagnosticFloatingWarn')
  validate_hl_group('MiniClueNextKey', 'links to DiagnosticFloatingHint')
  validate_hl_group('MiniClueNoKeymap', 'links to DiagnosticFloatingError')
  validate_hl_group('MiniClueNormal', 'links to NormalFloat')
  validate_hl_group('MiniClueSingle', 'links to DiagnosticFloatingInfo')
  validate_hl_group('MiniClueTitle', 'links to FloatTitle')
end

T['setup()']['creates `config` field'] = function()
  load_module()

  eq(child.lua_get('type(_G.MiniClue.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniClue.config.' .. field), value) end

  -- expect_config('clues', {})
  -- expect_config('triggers', {})
  --
  -- expect_config('window.delay', 100)
  -- expect_config('window.config', {})
end

T['setup()']['respects `config` argument'] = function()
  load_module({ window = { delay = 10 } })
  eq(child.lua_get('MiniClue.config.window.delay'), 10)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')

  expect_config_error({ clues = 'a' }, 'clues', 'table')
  expect_config_error({ triggers = 'a' }, 'triggers', 'table')

  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { delay = 'a' } }, 'window.delay', 'number')
  expect_config_error({ window = { config = 'a' } }, 'window.config', 'table')
end

-- T['setup()']['respects "human-readable" key names'] = function()
--   -- In `clues` (`keys` and 'postkeys')
--
--   -- In `triggers`
--   MiniTest.skip()
-- end

-- T['setup()']['respects "raw" key names'] = function()
--   -- In `clues` (`keys` and 'postkeys')
--
--   -- In `triggers`
--   MiniTest.skip()
-- end

-- Integration tests ==========================================================
T['Emulating mappings'] = new_set()

T['Emulating mappings']['works for builtin keymaps in Normal mode'] = function()
  load_module({ triggers = { { mode = 'n', keys = 'g' } } })
  validate_trigger_keymap('n', 'g')

  -- `ge` (basic test)
  validate_move1d('aa bb', 3, 'ge', 1)

  -- `gg` (should avoid infinite recursion)
  validate_move({ 'aa', 'bb' }, { 2, 0 }, 'gg', { 1, 0 })

  -- `g~` (should work with operators)
  validate_edit1d('aa bb', 0, 'g~iw', 'AA bb', 0)

  -- `g'a` (should work with more than one character ahead)
  set_lines({ 'aa', 'bb' })
  set_cursor(2, 0)
  type_keys('ma')
  set_cursor(1, 0)
  type_keys("g'a")
  eq(get_cursor(), { 2, 0 })
end

T['Emulating mappings']['works for user keymaps in Normal mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('n', '<Space>f')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  make_test_map('n', '<Space>g')

  validate_trigger_keymap('n', '<Space>')

  type_keys(' f')
  eq(get_test_map_count('n', ' f'), 1)
  eq(get_test_map_count('n', ' g'), 0)

  type_keys(' g')
  eq(get_test_map_count('n', ' f'), 1)
  eq(get_test_map_count('n', ' g'), 1)
end

T['Emulating mappings']['works for builtin keymaps in Insert mode'] = function()
  load_module({ triggers = { { mode = 'i', keys = '<C-x>' } } })
  validate_trigger_keymap('i', '<C-X>')

  set_lines({ 'aa aa', 'bb bb', '' })
  set_cursor(3, 0)
  type_keys('i', '<C-x><C-l>')

  eq(child.fn.mode(), 'i')
  local complete_words = vim.tbl_map(function(x) return x.word end, child.fn.complete_info().items)
  eq(complete_words, { 'aa aa', 'bb bb' })
end

T['Emulating mappings']['works for user keymaps in Insert mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('i', '<Space>f')
  load_module({ triggers = { { mode = 'i', keys = '<Space>' } } })
  make_test_map('i', '<Space>g')

  validate_trigger_keymap('i', '<Space>')

  child.cmd('startinsert')

  type_keys(' f')
  eq(child.fn.mode(), 'i')
  eq(get_test_map_count('i', ' f'), 1)
  eq(get_test_map_count('i', ' g'), 0)

  type_keys(' g')
  eq(child.fn.mode(), 'i')
  eq(get_test_map_count('i', ' f'), 1)
  eq(get_test_map_count('i', ' g'), 1)
end

T['Emulating mappings']['works for builtin keymaps in Visual mode'] = function()
  load_module({ triggers = { { mode = 'x', keys = 'g' }, { mode = 'x', keys = 'a' } } })
  validate_trigger_keymap('x', 'g')
  validate_trigger_keymap('x', 'a')

  -- `a'` (should work to update selection)
  validate_selection1d("'aa'", 1, "va'", 0, 3)

  -- Should preserve Visual submode
  validate_selection({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, 'Vap', { 1, 0 }, { 3, 0 }, 'V')
  validate_selection1d("'aa'", 1, "<C-v>a'", 0, 3, replace_termcodes('<C-v>'))

  -- `g?` (should work to manipulation selection)
  validate_edit1d('aa bb', 0, 'viwg?', 'nn bb', 0)
end

T['Emulating mappings']['works for user keymaps in Visual mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('x', '<Space>f')
  load_module({ triggers = { { mode = 'x', keys = '<Space>' } } })
  make_test_map('x', '<Space>g')

  validate_trigger_keymap('x', '<Space>')

  type_keys('v')

  type_keys(' f')
  eq(child.fn.mode(), 'v')
  eq(get_test_map_count('x', ' f'), 1)
  eq(get_test_map_count('x', ' g'), 0)

  type_keys(' g')
  eq(child.fn.mode(), 'v')
  eq(get_test_map_count('x', ' f'), 1)
  eq(get_test_map_count('x', ' g'), 1)

  -- Should preserve Visual submode
  child.ensure_normal_mode()
  type_keys('V')
  type_keys(' f')
  eq(child.fn.mode(), 'V')
  eq(get_test_map_count('x', ' f'), 2)

  child.ensure_normal_mode()
  type_keys('<C-v>')
  type_keys(' f')
  eq(child.fn.mode(), replace_termcodes('<C-v>'))
  eq(get_test_map_count('x', ' f'), 3)
end

T['Emulating mappings']['works for builtin keymaps in Operator-pending mode'] = function()
  -- Should test with all operators (`:h operators`)
  MiniTest.skip()
end

T['Emulating mappings']['works for user keymaps in Operator-pending mode'] = function()
  -- Should test with all operators (`:h operators`)
  MiniTest.skip()
end

T['Emulating mappings']['works for builtin keymaps in Terminal mode'] = function() MiniTest.skip() end

T['Emulating mappings']['works for user keymaps in Terminal mode'] = function() MiniTest.skip() end

T['Emulating mappings']['works when both operator and textobject result from triggers'] = function() MiniTest.skip() end

T['Emulating mappings']['respects `[count]`'] = function() MiniTest.skip() end

T['Emulating mappings']["works with 'mini.ai'"] = function() MiniTest.skip() end

T['Emulating mappings']["works with 'mini.bracketed'"] = function() MiniTest.skip() end

T['Emulating mappings']["works with 'mini.comment'"] = function() MiniTest.skip() end

T['Emulating mappings']["works with 'mini.indentscope'"] = function() MiniTest.skip() end

T['Emulating mappings']["works with 'mini.surround'"] = function() MiniTest.skip() end

-- T['Emulating mappings']['works with `<Cmd>` mappings'] = function() MiniTest.skip() end

-- T['Emulating mappings']['works buffer-local mappings'] = function() MiniTest.skip() end

return T
