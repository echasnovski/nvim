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
  local lua_cmd =
    string.format('vim.fn.maparg(%s, %s, false, true).desc', vim.inspect(replace_termcodes(keys)), vim.inspect(mode))
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

  -- Compute two correctly ordered edges
  local from = { child.fn.line('v'), child.fn.col('v') - 1 }
  local to = { child.fn.line('.'), child.fn.col('.') - 1 }
  if to[1] < from[1] or (to[1] == from[1] and to[2] < from[2]) then
    from, to = to, from
  end
  eq(from, selection_from)
  eq(to, selection_to)

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

T['setup()']['respects "human-readable" key names'] = function()
  -- In `clues` (`keys` and 'postkeys')

  -- In `triggers`
  MiniTest.skip()
end

T['setup()']['respects explicit `<Leader>`'] = function()
  -- In `clues` (`keys` and 'postkeys')

  -- In `triggers`
  MiniTest.skip()
end

T['setup()']['respects "raw" key names'] = function()
  -- In `clues` (`keys` and 'postkeys')

  -- In `triggers`
  MiniTest.skip()
end

T['setup()']['creates triggers for already created buffers'] = function() MiniTest.skip() end

T['enable_trigger()'] = new_set()

T['enable_trigger()']['works'] = function() MiniTest.skip() end

T['disable_trigger()'] = new_set()

T['disable_trigger()']['works'] = function() MiniTest.skip() end

T['execute_without_triggers()'] = new_set()

T['execute_without_triggers()']['works'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
T['Triggers'] = new_set()

T['Triggers']['works'] = function() MiniTest.skip() end

T['Triggers']['respect `vim.b.miniclue_disable`'] = function() MiniTest.skip() end

T['Querying keys'] = new_set()

T['Querying keys']['works'] = function()
  make_test_map('n', '<Space>f')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  type_keys(' ', 'f')
  eq(get_test_map_count('n', ' f'), 1)

  type_keys(10, ' ', 'f')
  eq(get_test_map_count('n', ' f'), 2)
end

T['Querying keys']["does not time out after 'timeoutlen'"] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>ff')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })

  -- Should wait for next key as there are still multiple clues available
  child.o.timeoutlen = 10
  type_keys(' ', 'f')
  sleep(20)
  eq(get_test_map_count('n', ' f'), 0)
end

T['Querying keys']['takes into account user-supplied clues'] = function()
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>f', desc = 'My space f' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
  })
  validate_trigger_keymap('n', '<Space>')

  type_keys(' ')
  MiniTest.skip('Use screenshot when window with clues is implemented')
  child.expect_screenshot()
end

T['Querying keys']['respects `<CR>`'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>ff')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  -- `<CR>` should execute current query
  child.o.timeoutlen = 10
  type_keys(' ', 'f', '<CR>')
  sleep(15)
  eq(get_test_map_count('n', ' f'), 1)
end

T['Querying keys']['respects `<Esc>`/`<C-c>`'] = function()
  make_test_map('n', '<Space>f')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  -- `<Esc>` and `<C-c>` should stop current query
  local validate = function(key)
    type_keys(' ', key, 'f')
    child.ensure_normal_mode()
    eq(get_test_map_count('n', ' f'), 0)
  end

  validate('<Esc>')
  validate('<C-c>')
end

T['Querying keys']['respects `<BS>`'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>ff')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  -- `<BS>` should remove latest key
  type_keys(' ', 'f', '<BS>', 'f', 'f')
  eq(get_test_map_count('n', ' f'), 0)
  eq(get_test_map_count('n', ' ff'), 1)
end

T['Querying keys']['can `<BS>` on first element'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', ',gg')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' }, { mode = 'n', keys = ',g' } } })
  validate_trigger_keymap('n', '<Space>')
  validate_trigger_keymap('n', ',g')

  type_keys(' ', '<BS>', ' ', 'f')
  eq(get_test_map_count('n', ' f'), 1)

  -- Removes first trigger element at once, not by characters
  type_keys(',g', '<BS>', ',g', 'g')
  eq(get_test_map_count('n', ',gg'), 1)
end

T['Querying keys']['allows reaching longest keymap'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>fff')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  type_keys(' ', 'f', 'f', 'f')
  eq(get_test_map_count('n', ' f'), 0)
  eq(get_test_map_count('n', ' fff'), 1)
end

T['Querying keys']['executes even if no extra clues is set'] = function()
  load_module({ triggers = { { mode = 'c', keys = 'g' }, { mode = 'i', keys = 'g' } } })
  validate_trigger_keymap('c', 'g')
  validate_trigger_keymap('i', 'g')

  type_keys(':', 'g')
  eq(child.fn.getcmdline(), 'g')

  child.ensure_normal_mode()
  type_keys('i', 'g')
  eq(get_lines(), { 'g' })
end

T['Reproducing keys'] = new_set()

T['Reproducing keys']['works for builtin keymaps in Normal mode'] = function()
  load_module({ triggers = { { mode = 'n', keys = 'g' } } })
  validate_trigger_keymap('n', 'g')

  -- `ge` (basic test)
  validate_move1d('aa bb', 3, { 'g', 'e' }, 1)

  -- `gg` (should avoid infinite recursion)
  validate_move({ 'aa', 'bb' }, { 2, 0 }, { 'g', 'g' }, { 1, 0 })

  -- `g~` (should work with operators)
  validate_edit1d('aa bb', 0, { 'g', '~', 'iw' }, 'AA bb', 0)

  -- `g'a` (should work with more than one character ahead)
  set_lines({ 'aa', 'bb' })
  set_cursor(2, 0)
  type_keys('ma')
  set_cursor(1, 0)
  type_keys("g'", 'a')
  eq(get_cursor(), { 2, 0 })
end

T['Reproducing keys']['works for user keymaps in Normal mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('n', '<Space>f')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  make_test_map('n', '<Space>g')

  validate_trigger_keymap('n', '<Space>')

  type_keys(' ', 'f')
  eq(get_test_map_count('n', ' f'), 1)
  eq(get_test_map_count('n', ' g'), 0)

  type_keys(' ', 'g')
  eq(get_test_map_count('n', ' f'), 1)
  eq(get_test_map_count('n', ' g'), 1)
end

T['Reproducing keys']['respects `[count]` in Normal mode'] = function()
  load_module({ triggers = { { mode = 'n', keys = 'g' } } })
  validate_trigger_keymap('n', 'g')

  validate_move1d('aa bb cc', 6, { '2', 'g', 'e' }, 1)
end

T['Reproducing keys']['works in temporary Normal mode'] = function()
  -- Like after `<C-o>`
  MiniTest.skip()
end

T['Reproducing keys']['works for builtin keymaps in Insert mode'] = function()
  load_module({ triggers = { { mode = 'i', keys = '<C-x>' } } })
  validate_trigger_keymap('i', '<C-X>')

  set_lines({ 'aa aa', 'bb bb', '' })
  set_cursor(3, 0)
  type_keys('i', '<C-x>', '<C-l>')

  eq(child.fn.mode(), 'i')
  local complete_words = vim.tbl_map(function(x) return x.word end, child.fn.complete_info().items)
  eq(complete_words, { 'aa aa', 'bb bb' })
end

T['Reproducing keys']['works for user keymaps in Insert mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('i', '<Space>f')
  load_module({ triggers = { { mode = 'i', keys = '<Space>' } } })
  make_test_map('i', '<Space>g')

  validate_trigger_keymap('i', '<Space>')

  child.cmd('startinsert')

  type_keys(' ', 'f')
  eq(child.fn.mode(), 'i')
  eq(get_test_map_count('i', ' f'), 1)
  eq(get_test_map_count('i', ' g'), 0)

  type_keys(' ', 'g')
  eq(child.fn.mode(), 'i')
  eq(get_test_map_count('i', ' f'), 1)
  eq(get_test_map_count('i', ' g'), 1)
end

T['Reproducing keys']['works for builtin keymaps in Visual mode'] = function()
  load_module({ triggers = { { mode = 'x', keys = 'g' }, { mode = 'x', keys = 'a' } } })
  validate_trigger_keymap('x', 'g')
  validate_trigger_keymap('x', 'a')

  -- `a'` (should work to update selection)
  validate_selection1d("'aa'", 1, { 'v', 'a', "'" }, 0, 3)

  -- Should preserve Visual submode
  validate_selection({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'V', 'a', 'p' }, { 1, 0 }, { 3, 0 }, 'V')
  validate_selection1d("'aa'", 1, "<C-v>a'", 0, 3, replace_termcodes('<C-v>'))

  -- `g?` (should work to manipulation selection)
  validate_edit1d('aa bb', 0, { 'v', 'iw', 'g', '?' }, 'nn bb', 0)
end

T['Reproducing keys']['works for user keymaps in Visual mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('x', '<Space>f')
  load_module({ triggers = { { mode = 'x', keys = '<Space>' } } })
  make_test_map('x', '<Space>g')

  validate_trigger_keymap('x', '<Space>')

  type_keys('v')

  type_keys(' ', 'f')
  eq(child.fn.mode(), 'v')
  eq(get_test_map_count('x', ' f'), 1)
  eq(get_test_map_count('x', ' g'), 0)

  type_keys(' ', 'g')
  eq(child.fn.mode(), 'v')
  eq(get_test_map_count('x', ' f'), 1)
  eq(get_test_map_count('x', ' g'), 1)

  -- Should preserve Visual submode
  child.ensure_normal_mode()
  type_keys('V')
  type_keys(' ', 'f')
  eq(child.fn.mode(), 'V')
  eq(get_test_map_count('x', ' f'), 2)

  child.ensure_normal_mode()
  type_keys('<C-v>')
  type_keys(' ', 'f')
  eq(child.fn.mode(), replace_termcodes('<C-v>'))
  eq(get_test_map_count('x', ' f'), 3)
end

T['Reproducing keys']['respects `[count]` in Visual mode'] = function()
  load_module({ triggers = { { mode = 'x', keys = 'a' } } })
  validate_trigger_keymap('x', 'a')

  validate_selection1d('aa bb cc', 0, { 'v', '2', 'a', 'w' }, 0, 5)
end

T['Reproducing keys']['Operator-pending mode'] = new_set({
  hooks = {
    pre_case = function()
      -- Make user keymap
      child.api.nvim_set_keymap('o', 'if', 'iw', {})
      child.api.nvim_set_keymap('o', 'iF', 'ip', {})

      -- Register trigger
      load_module({ triggers = { { mode = 'o', keys = 'i' } } })
      validate_trigger_keymap('o', 'i')
    end,
  },
})

T['Reproducing keys']['Operator-pending mode']['c'] = function()
  validate_edit1d('aa bb cc', 3, { 'c', 'i', 'w', 'dd' }, 'aa dd cc', 5)

  -- Dot-repeat
  validate_edit1d('aa bb', 0, { 'c', 'i', 'w', 'dd', '<Esc>w.' }, 'dd dd', 4)

  -- Should respect register
  validate_edit1d('aaa', 0, { '"ac', 'i', 'w', 'xxx' }, 'xxx', 3)
  eq(child.fn.getreg('a'), 'aaa')

  -- User keymap
  validate_edit1d('aa bb cc', 3, { 'c', 'i', 'f', 'dd' }, 'aa dd cc', 5)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'c2', 'i', 'w', 'dd' }, 'ddbb cc', 2)
end

T['Reproducing keys']['Operator-pending mode']['d'] = function()
  validate_edit1d('aa bb cc', 3, { 'd', 'i', 'w' }, 'aa  cc', 3)

  -- Dot-rpeat
  validate_edit1d('aa bb cc', 0, { 'd', 'i', 'w', 'w.' }, '  cc', 1)

  -- Should respect register
  validate_edit1d('aaa', 0, { '"ad', 'i', 'w' }, '', 0)
  eq(child.fn.getreg('a'), 'aaa')

  -- User keymap
  validate_edit1d('aa bb cc', 3, { 'd', 'i', 'f' }, 'aa  cc', 3)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'd2', 'i', 'w' }, 'bb cc', 0)
end

T['Reproducing keys']['Operator-pending mode']['y'] = function()
  validate_edit1d('aa bb cc', 3, { 'y', 'i', 'w', 'P' }, 'aa bbbb cc', 4)

  -- Should respect register
  validate_edit1d('aaa', 0, { '"ay', 'i', 'w' }, 'aaa', 0)
  eq(child.fn.getreg('a'), 'aaa')

  -- User keymap
  validate_edit1d('aa bb cc', 3, { 'y', 'i', 'f', 'P' }, 'aa bbbb cc', 4)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'y2', 'i', 'w', 'P' }, 'aa aa bb cc', 2)
end

T['Reproducing keys']['Operator-pending mode']['~'] = function()
  child.o.tildeop = true

  validate_edit1d('aa bb', 0, { '~', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 1, { '~', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 3, { '~', 'i', 'w' }, 'aa BB', 3)

  -- Dot-repeat
  validate_edit1d('aa bb', 0, { '~', 'i', 'w', 'w.' }, 'AA BB', 3)

  -- User keymap
  validate_edit1d('aa bb', 0, { '~', 'i', 'f' }, 'AA bb', 0)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { '~3', 'i', 'w' }, 'AA BB cc', 0)
end

T['Reproducing keys']['Operator-pending mode']['g~'] = function()
  validate_edit1d('aa bb', 0, { 'g~', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 1, { 'g~', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 3, { 'g~', 'i', 'w' }, 'aa BB', 3)

  -- Dot-repeat
  validate_edit1d('aa bb', 0, { 'g~', 'i', 'w', 'w.' }, 'AA BB', 3)

  -- User keymap
  validate_edit1d('aa bb', 0, { 'g~', 'i', 'f' }, 'AA bb', 0)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'g~3', 'i', 'w' }, 'AA BB cc', 0)
end

T['Reproducing keys']['Operator-pending mode']['gu'] = function()
  validate_edit1d('AA BB', 0, { 'gu', 'i', 'w' }, 'aa BB', 0)
  validate_edit1d('AA BB', 1, { 'gu', 'i', 'w' }, 'aa BB', 0)
  validate_edit1d('AA BB', 3, { 'gu', 'i', 'w' }, 'AA bb', 3)

  -- Dot-repeat
  validate_edit1d('AA BB', 0, { 'gu', 'i', 'w', 'w.' }, 'aa bb', 3)

  -- User keymap
  validate_edit1d('AA BB', 0, { 'gu', 'i', 'f' }, 'aa BB', 0)

  -- Should respect `[count]`
  validate_edit1d('AA BB CC', 0, { 'gu3', 'i', 'w' }, 'aa bb CC', 0)
end

T['Reproducing keys']['Operator-pending mode']['gU'] = function()
  validate_edit1d('aa bb', 0, { 'gU', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 1, { 'gU', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 3, { 'gU', 'i', 'w' }, 'aa BB', 3)

  -- Dot-repeat
  validate_edit1d('aa bb', 0, { 'gU', 'i', 'w', 'w.' }, 'AA BB', 3)

  -- User keymap
  validate_edit1d('aa bb', 0, { 'gU', 'i', 'f' }, 'AA bb', 0)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'gU3', 'i', 'w' }, 'AA BB cc', 0)
end

T['Reproducing keys']['Operator-pending mode']['gq'] = function()
  child.lua([[_G.formatexpr = function()
    local from, to = vim.v.lnum, vim.v.lnum + vim.v.count - 1
    local new_lines = {}
    for _ = 1, vim.v.count do table.insert(new_lines, 'xxx') end
    vim.api.nvim_buf_set_lines(0, from - 1, to, false, new_lines)
  end]])
  child.bo.formatexpr = 'v:lua.formatexpr()'

  validate_edit({ 'aa', 'aa', '', 'bb' }, { 1, 0 }, { 'gq', 'i', 'p' }, { 'xxx', 'xxx', '', 'bb' }, { 1, 0 })

  -- Dot-repeat
  validate_edit(
    { 'aa', 'aa', '', 'bb', 'bb' },
    { 1, 0 },
    { 'gq', 'i', 'p', 'G.' },
    { 'xxx', 'xxx', '', 'xxx', 'xxx' },
    { 4, 0 }
  )

  -- User keymap
  validate_edit({ 'aa', 'aa', '', 'bb' }, { 1, 0 }, { 'gq', 'i', 'F' }, { 'xxx', 'xxx', '', 'bb' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { 'aa', '', 'bb', '', 'cc' },
    { 1, 0 },
    { 'gq3', 'i', 'p' },
    { 'xxx', 'xxx', 'xxx', '', 'cc' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['gw'] = function()
  child.o.textwidth = 5

  validate_edit({ 'aaa aaa', '', 'bb' }, { 1, 0 }, { 'gw', 'i', 'p' }, { 'aaa', 'aaa', '', 'bb' }, { 1, 0 })

  -- Dot-repeat
  validate_edit(
    { 'aaa aaa', '', 'bbb bbb' },
    { 1, 0 },
    { 'gw', 'i', 'p', 'G.' },
    { 'aaa', 'aaa', '', 'bbb', 'bbb' },
    { 4, 0 }
  )

  -- User keymap
  validate_edit({ 'aaa aaa', '', 'bb' }, { 1, 0 }, { 'gw', 'i', 'F' }, { 'aaa', 'aaa', '', 'bb' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { 'aaa aaa', '', 'bbb bbb', '', 'cc' },
    { 1, 0 },
    { 'gw3i', 'p', '' },
    { 'aaa', 'aaa', '', 'bbb', 'bbb', '', 'cc' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['g?'] = function()
  validate_edit1d('aa bb', 0, { 'g?', 'i', 'w' }, 'nn bb', 0)
  validate_edit1d('aa bb', 1, { 'g?', 'i', 'w' }, 'nn bb', 0)
  validate_edit1d('aa bb', 3, { 'g?', 'i', 'w' }, 'aa oo', 3)

  -- Dot-repeat
  validate_edit1d('aa bb', 0, { 'g?', 'i', 'w', 'w.' }, 'nn oo', 3)

  -- User keymap
  validate_edit1d('aa bb', 0, { 'g?', 'i', 'f' }, 'nn bb', 0)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'g?3', 'i', 'w' }, 'nn oo cc', 0)
end

T['Reproducing keys']['Operator-pending mode']['!'] = function()
  validate_edit({ 'cc', 'bb', '', 'aa' }, { 1, 0 }, { '!', 'i', 'p', 'sort<CR>' }, { 'bb', 'cc', '', 'aa' }, { 1, 0 })

  -- Dot-repeat
  validate_edit(
    { 'cc', 'bb', '', 'dd', 'aa' },
    { 1, 0 },
    { '!', 'i', 'p', 'sort<CR>G.' },
    { 'bb', 'cc', '', 'aa', 'dd' },
    { 4, 0 }
  )

  -- User keymap
  validate_edit({ 'cc', 'bb', '', 'aa' }, { 1, 0 }, { '!', 'i', 'F', 'sort<CR>' }, { 'bb', 'cc', '', 'aa' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { 'cc', 'bb', '', 'ee', 'dd', '', 'aa' },
    { 1, 0 },
    { '!3', 'i', 'p', 'sort<CR>' },
    { '', 'bb', 'cc', 'dd', 'ee', '', 'aa' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['='] = function()
  validate_edit({ 'aa', '\taa', '', 'bb' }, { 1, 0 }, { '=', 'i', 'p' }, { 'aa', 'aa', '', 'bb' }, { 1, 0 })

  -- Dot-repeat
  validate_edit(
    { 'aa', '\taa', '', 'bb', '\tbb' },
    { 1, 0 },
    { '=', 'i', 'p', 'G.' },
    { 'aa', 'aa', '', 'bb', 'bb' },
    { 4, 0 }
  )

  -- User keymap
  validate_edit({ 'aa', '\taa', '', 'bb' }, { 1, 0 }, { '=', 'i', 'F' }, { 'aa', 'aa', '', 'bb' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { 'aa', '\taa', '', 'bb', '\tbb', '', 'cc' },
    { 1, 0 },
    { '=3', 'i', 'p' },
    { 'aa', 'aa', '', 'bb', 'bb', '', 'cc' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['>'] = function()
  validate_edit({ 'aa', '', 'bb' }, { 1, 0 }, { '>', 'i', 'p' }, { '\taa', '', 'bb' }, { 1, 0 })

  -- Dot-repeat
  validate_edit({ 'aa', '', 'bb' }, { 1, 0 }, { '>', 'i', 'p', '.2j.' }, { '\t\taa', '', '\tbb' }, { 3, 0 })

  -- User keymap
  validate_edit({ 'aa', '', 'bb' }, { 1, 0 }, { '>', 'i', 'F' }, { '\taa', '', 'bb' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit({ 'aa', '', 'bb', '', 'cc' }, { 1, 0 }, { '>3', 'i', 'p' }, { '\taa', '', '\tbb', '', 'cc' }, { 1, 0 })
end

T['Reproducing keys']['Operator-pending mode']['<'] = function()
  validate_edit({ '\t\taa', '', 'bb' }, { 1, 0 }, { '<', 'i', 'p' }, { '\taa', '', 'bb' }, { 1, 0 })

  -- Dot-repeat
  validate_edit({ '\t\t\taa', '', '\tbb' }, { 1, 0 }, { '<', 'i', 'p', '.2j.' }, { '\taa', '', 'bb' }, { 3, 1 })

  -- User keymap
  validate_edit({ '\t\taa', '', 'bb' }, { 1, 0 }, { '<', 'i', 'F' }, { '\taa', '', 'bb' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { '\t\taa', '', '\t\tbb', '', 'cc' },
    { 1, 0 },
    { '<', '3', 'i', 'p' },
    { '\taa', '', '\tbb', '', 'cc' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['zf'] = function()
  local validate = function(keys, ref_last_folded_line)
    local lines = { 'aa', 'aa', '', 'bb', '', 'cc' }
    set_lines(lines)
    set_cursor(1, 0)

    type_keys(keys)

    for i = 1, ref_last_folded_line do
      eq(child.fn.foldclosed(i), 1)
    end

    for i = ref_last_folded_line + 1, #lines do
      eq(child.fn.foldclosed(i), -1)
    end
  end

  validate({ 'zf', 'i', 'p' }, 2)
  validate({ 'zf', 'i', 'F' }, 2)

  -- Should respect `[count]`
  validate({ 'zf3', 'i', 'p' }, 4)
end

T['Reproducing keys']['Operator-pending mode']['g@'] = function()
  child.o.operatorfunc = 'v:lua.operatorfunc'

  -- Charwise
  child.lua([[_G.operatorfunc = function()
    local from, to = vim.fn.col("'["), vim.fn.col("']")
    local line = vim.fn.line('.')

    vim.api.nvim_buf_set_text(0, line - 1, from - 1, line - 1, to, { 'xx' })
  end]])

  validate_edit1d('aa bb cc', 3, { 'g@', 'i', 'w' }, 'aa xx cc', 3)

  -- - Dot-repeat
  validate_edit1d('aa bb cc', 3, { 'g@', 'i', 'w', 'w.' }, 'aa xx xx', 6)

  -- - User keymap
  validate_edit1d('aa bb cc', 3, { 'g@', 'i', 'f' }, 'aa xx cc', 3)

  -- - Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'g@3', 'i', 'w' }, 'xx cc', 0)

  -- Linewise
  child.lua([[_G.operatorfunc = function() vim.cmd("'[,']sort") end]])

  validate_edit({ 'cc', 'bb', '', 'aa' }, { 1, 0 }, { 'g@', 'i', 'p' }, { 'bb', 'cc', '', 'aa' }, { 1, 0 })

  -- - Dot-repeat
  validate_edit(
    { 'cc', 'bb', '', 'dd', 'aa' },
    { 1, 0 },
    { 'g@', 'i', 'p', 'G.' },
    { 'bb', 'cc', '', 'aa', 'dd' },
    { 4, 0 }
  )

  -- - User keymap
  validate_edit({ 'cc', 'bb', '', 'aa' }, { 1, 0 }, { 'g@', 'i', 'F' }, { 'bb', 'cc', '', 'aa' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { 'cc', 'bb', '', 'ee', 'dd', '', 'aa' },
    { 1, 0 },
    { 'g@3', 'i', 'p' },
    { '', 'bb', 'cc', 'dd', 'ee', '', 'aa' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['works with operator and textobject from triggers'] = function()
  load_module({ triggers = { { mode = 'n', keys = 'g' }, { mode = 'o', keys = 'i' } } })
  validate_trigger_keymap('n', 'g')
  validate_trigger_keymap('o', 'i')

  -- `g~`
  validate_edit1d('aa bb', 0, { 'g~', 'i', 'w' }, 'AA bb', 0)

  -- `g@`
  child.lua([[_G.operatorfunc = function() vim.cmd("'[,']sort") end]])
  child.o.operatorfunc = 'v:lua.operatorfunc'

  validate_edit({ 'cc', 'bb', '', 'aa' }, { 1, 0 }, { 'g@', 'i', 'p' }, { 'bb', 'cc', '', 'aa' }, { 1, 0 })
end

T['Reproducing keys']['Operator-pending mode']['respects forced submode'] = function()
  load_module({ triggers = { { mode = 'o', keys = '`' } } })
  validate_trigger_keymap('o', '`')

  -- Linewise
  set_lines({ 'aa', 'bbbb', 'cc' })
  set_cursor(2, 1)
  type_keys('mb')
  set_cursor(1, 0)
  type_keys('dV', '`', 'b')
  eq(get_lines(), { 'cc' })

  -- Blockwise
  set_lines({ 'aa', 'bbbb', 'cc' })
  set_cursor(3, 1)
  type_keys('mc')
  set_cursor(1, 0)
  type_keys('d\22', '`', 'c')
  eq(get_lines(), { '', 'bb', '' })
end

T['Reproducing keys']['works for builtin keymaps in Terminal mode'] = function()
  load_module({ triggers = { { mode = 't', keys = [[<C-\>]] } } })
  validate_trigger_keymap('t', [[<C-\>]])

  child.cmd('wincmd v')
  child.cmd('terminal')
  -- Wait for terminal to load
  vim.loop.sleep(100)
  child.cmd('startinsert')
  eq(child.fn.mode(), 't')

  type_keys([[<C-\>]], '<C-n>')
  eq(child.fn.mode(), 'n')
end

T['Reproducing keys']['works for user keymaps in Terminal mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('t', '<Space>f')
  load_module({ triggers = { { mode = 't', keys = '<Space>' } } })
  make_test_map('t', '<Space>g')

  validate_trigger_keymap('t', '<Space>')

  child.cmd('wincmd v')
  child.cmd('terminal')
  -- Wait for terminal to load
  vim.loop.sleep(100)
  child.cmd('startinsert')
  eq(child.fn.mode(), 't')

  type_keys(' ', 'f')
  eq(child.fn.mode(), 't')
  eq(get_test_map_count('t', ' f'), 1)
  eq(get_test_map_count('t', ' g'), 0)

  type_keys(' ', 'g')
  eq(child.fn.mode(), 't')
  eq(get_test_map_count('t', ' f'), 1)
  eq(get_test_map_count('t', ' g'), 1)
end

T['Reproducing keys']['works for builtin keymaps in Command-line mode'] = function()
  load_module({ triggers = { { mode = 'c', keys = '<C-r>' } } })
  validate_trigger_keymap('c', '<C-R>')

  set_lines({ 'aaa' })
  set_cursor(1, 0)
  type_keys(':', '<C-r>', '<C-w>')
  eq(child.fn.getcmdline(), 'aaa')
end

T['Reproducing keys']['works for user keymaps in Command-line mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('c', '<Space>f')
  load_module({ triggers = { { mode = 'c', keys = '<Space>' } } })
  make_test_map('c', '<Space>g')

  validate_trigger_keymap('c', '<Space>')

  type_keys(':')

  type_keys(' ', 'f')
  eq(child.fn.mode(), 'c')
  eq(get_test_map_count('c', ' f'), 1)
  eq(get_test_map_count('c', ' g'), 0)

  type_keys(' ', 'g')
  eq(child.fn.mode(), 'c')
  eq(get_test_map_count('c', ' f'), 1)
  eq(get_test_map_count('c', ' g'), 1)
end

T['Reproducing keys']['works for registers'] = function()
  load_module({ triggers = { { mode = 'n', keys = '"' }, { mode = 'x', keys = '"' } } })
  validate_trigger_keymap('n', '"')
  validate_trigger_keymap('x', '"')

  -- Normal mode
  set_lines({ 'aa' })
  set_cursor(1, 0)
  type_keys('"', 'a', 'yiw')
  eq(child.fn.getreg('"a'), 'aa')

  -- Visual mode
  set_lines({ 'bb' })
  set_cursor(1, 0)
  type_keys('viw', '"', 'b', 'y')
  eq(child.fn.getreg('"b'), 'bb')
end

T['Reproducing keys']['works for marks'] = function()
  load_module({ triggers = { { mode = 'n', keys = "'" }, { mode = 'n', keys = '`' } } })
  validate_trigger_keymap('n', "'")
  validate_trigger_keymap('n', '`')

  set_lines({ 'aa', 'bb' })
  set_cursor(1, 1)
  type_keys('ma')

  -- Line jump
  set_cursor(2, 0)
  type_keys("'", 'a')
  eq(get_cursor(), { 1, 0 })

  -- Exact jump
  set_cursor(2, 0)
  type_keys('`', 'a')
  eq(get_cursor(), { 1, 1 })
end

T['Reproducing keys']['works with macros'] = function()
  -- Inside single buffer

  -- Inside multiple buffers
  MiniTest.skip()
end

T['Reproducing keys']['works with `<Cmd>` mappings'] = function() MiniTest.skip() end

T['Reproducing keys']['works with buffer-local mappings'] = function() MiniTest.skip() end

T['Reproducing keys']['respects `vim.b.miniclue_config`'] = function() MiniTest.skip() end

T['Reproducing keys']['does not register new triggers'] = function()
  load_module({ triggers = { { mode = 'o', keys = 'i' } } })
  validate_trigger_keymap('o', 'i')

  set_lines('aaa')
  type_keys('"adiw')

  validate_trigger_keymap('o', 'i')
end

T['Reproducing keys']['works when key query is executed in presence of longer keymaps'] = function()
  -- Imitate Lua commenting
  child.lua([[
    _G.comment_operator = function()
      vim.o.operatorfunc = 'v:lua.operatorfunc'
      return 'g@'
    end

    _G.comment_line = function() return _G.comment_operator() .. '_' end

    _G.operatorfunc = function()
      local from, to = vim.fn.line("'["), vim.fn.line("']")
      local lines = vim.api.nvim_buf_get_lines(0, from - 1, to, false)
      local new_lines = vim.tbl_map(function(x) return '-- ' .. x end, lines)
      vim.api.nvim_buf_set_lines(0, from - 1, to, false, new_lines)
    end

    vim.keymap.set('n', 'gc', _G.comment_operator, { expr = true, replace_keycodes = false })
    vim.keymap.set('n', 'gcc', _G.comment_line, { expr = true, replace_keycodes = false })
  ]])

  load_module({ triggers = { { mode = 'n', keys = 'g' }, { mode = 'o', keys = 'i' } } })
  validate_trigger_keymap('n', 'g')
  validate_trigger_keymap('o', 'i')

  validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, 'gcip', { '-- aa', '-- bb', '', 'cc' }, { 1, 0 })
end

T['Reproducing keys']['mini modules'] = new_set({
  hooks = {
    pre_case = function()
      -- TODO: Update during move into 'mini.nvim'
      child.cmd('set rtp+=deps/mini.nvim')
    end,
  },
})

local setup_mini_module = function(name, config)
  local lua_cmd = string.format([[_G.has_module, _G.module = pcall(require, 'mini.%s')]], name)
  child.lua(lua_cmd)
  if not child.lua_get('_G.has_module') then return false end
  child.lua('module.setup()', { config })
  return true
end

T['Reproducing keys']['mini modules']['mini.ai'] = function()
  local has_ai = setup_mini_module('ai')
  if not has_ai then MiniTest.skip("Could not load 'mini.ai'.") end

  load_module({ triggers = { { mode = 'o', keys = 'i' }, { mode = 'o', keys = 'a' } } })
  validate_trigger_keymap('o', 'i')
  validate_trigger_keymap('o', 'a')

  -- `i` in Visual mode
  validate_selection1d('aa(bb)', 0, 'vi)', 3, 4)
  validate_selection1d('aa ff(bb)', 0, 'vif', 6, 7)

  validate_selection1d('(a(b(cc)b)a)', 5, 'v2i)', 3, 8)
  validate_selection1d('(a(b(cc)b)a)', 5, 'vi)i)', 3, 8)

  validate_selection1d('(aa) (bb) (cc)', 6, 'vil)', 1, 2)
  validate_selection1d('(aa) (bb) (cc)', 11, 'v2il)', 1, 2)

  validate_selection1d('(aa) (bb) (cc)', 6, 'vin)', 11, 12)
  validate_selection1d('(aa) (bb) (cc)', 1, 'v2in)', 11, 12)

  -- `a` in Visual mode
  validate_selection1d('aa(bb)', 0, 'va)', 2, 5)
  validate_selection1d('aa ff(bb)', 0, 'vaf', 3, 8)

  validate_selection1d('(a(b(cc)b)a)', 5, 'v2a)', 2, 9)
  validate_selection1d('(a(b(cc)b)a)', 5, 'va)a)', 2, 9)

  validate_selection1d('(aa) (bb) (cc)', 6, 'val)', 0, 3)
  validate_selection1d('(aa) (bb) (cc)', 11, 'v2al)', 0, 3)

  validate_selection1d('(aa) (bb) (cc)', 6, 'van)', 10, 13)
  validate_selection1d('(aa) (bb) (cc)', 1, 'v2an)', 10, 13)

  -- `i` in Operator-pending mode
  validate_edit1d('aa(bb)', 0, 'di)', 'aa()', 3)
  validate_edit1d('aa(bb)', 0, 'ci)cc', 'aa(cc)', 5)
  validate_edit1d('aa(bb)', 0, 'yi)P', 'aa(bbbb)', 4)
  validate_edit1d('aa ff(bb)', 0, 'dif', 'aa ff()', 6)

  validate_edit1d('(a(b(cc)b)a)', 5, 'd2i)', '(a()a)', 3)

  validate_edit1d('(a(b(cc)b)a)', 5, 'di).', '(a()a)', 3)
  validate_edit1d('(aa) (bb)', 1, 'ci)cc<Esc>W.', '(cc) (cc)', 7)

  validate_edit1d('(aa) (bb) (cc)', 6, 'dil)', '() (bb) (cc)', 1)
  validate_edit1d('(aa) (bb) (cc)', 11, 'd2il)', '() (bb) (cc)', 1)

  validate_edit1d('(aa) (bb) (cc)', 6, 'din)', '(aa) (bb) ()', 11)
  validate_edit1d('(aa) (bb) (cc)', 1, 'd2in)', '(aa) (bb) ()', 11)

  -- `a` in Operator-pending mode
  validate_edit1d('aa(bb)', 0, 'da)', 'aa', 1)
  validate_edit1d('aa(bb)', 0, 'ca)cc', 'aacc', 4)
  validate_edit1d('aa(bb)', 0, 'ya)P', 'aa(bb)(bb)', 5)
  validate_edit1d('aa ff(bb)', 0, 'daf', 'aa ', 2)

  validate_edit1d('(a(b(cc)b)a)', 5, 'd2a)', '(aa)', 2)

  validate_edit1d('(a(b(cc)b)a)', 5, 'da).', '(aa)', 2)
  validate_edit1d('(aa) (bb)', 1, 'ca)cc<Esc>W.', 'cc cc', 4)

  validate_edit1d('(aa) (bb) (cc)', 6, 'dal)', ' (bb) (cc)', 0)
  validate_edit1d('(aa) (bb) (cc)', 11, 'd2al)', ' (bb) (cc)', 0)

  validate_edit1d('(aa) (bb) (cc)', 6, 'dan)', '(aa) (bb) ', 9)
  validate_edit1d('(aa) (bb) (cc)', 1, 'd2an)', '(aa) (bb) ', 9)
end

T['Reproducing keys']['mini modules']['mini.align'] = function()
  child.set_size(10, 30)
  child.o.cmdheight = 5

  local has_align = setup_mini_module('align')
  if not has_align then MiniTest.skip("Could not load 'mini.align'.") end

  -- Works together with 'mini.ai' without `g` as trigger
  local has_ai = setup_mini_module('ai')
  if has_ai then
    load_module({ triggers = { { mode = 'o', keys = 'i' } } })
    validate_edit({ 'f(', 'a_b', 'aa_b', ')' }, { 2, 0 }, { 'ga', 'if', '_' }, { 'f(', 'a _b', 'aa_b', ')' }, { 1, 1 })
  end

  -- Works with `g` as trigger
  load_module({ triggers = { { mode = 'n', keys = 'g' }, { mode = 'o', keys = 'i' } } })
  validate_trigger_keymap('n', 'g')

  -- - No preview
  validate_edit({ 'a_b', 'aa_b' }, { 1, 0 }, 'vapga_', { 'a _b', 'aa_b' }, { 2, 0 })
  validate_edit({ 'a_b', 'aa_b' }, { 1, 0 }, 'gaap_', { 'a _b', 'aa_b' }, { 1, 0 })

  validate_edit(
    { 'a_b', 'aa_b', '', 'c_d', 'cc_d' },
    { 1, 0 },
    'gaap_G.',
    { 'a _b', 'aa_b', '', 'c _d', 'cc_d' },
    { 3, 0 }
  )

  -- - With preview
  local validate_preview = function(keys)
    set_lines({ 'a_b', 'aa_b' })
    set_cursor(1, 0)
    type_keys(keys)
    child.expect_screenshot()
    type_keys('_<CR>')
    eq(get_lines(), { 'a _b', 'aa_b' })
  end

  validate_preview('vapgA')
  validate_preview('gAap')

  -- Works together with 'mini.ai' with `g` as trigger
  if has_ai then
    validate_edit({ 'f(', 'a_b', 'aa_b', ')' }, { 2, 0 }, { 'ga', 'if', '_' }, { 'f(', 'a _b', 'aa_b', ')' }, { 1, 1 })
  end
end

T['Reproducing keys']['mini modules']['mini.bracketed'] = function()
  local has_bracketed = setup_mini_module('bracketed')
  if not has_bracketed then MiniTest.skip("Could not load 'mini.bracketed'.") end

  load_module({
    triggers = {
      { mode = 'n', keys = '[' },
      { mode = 'x', keys = '[' },
      { mode = 'o', keys = '[' },
      { mode = 'n', keys = ']' },
      { mode = 'x', keys = ']' },
      { mode = 'o', keys = ']' },
    },
  })
  validate_trigger_keymap('n', '[')
  validate_trigger_keymap('x', '[')
  validate_trigger_keymap('o', '[')
  validate_trigger_keymap('n', ']')
  validate_trigger_keymap('x', ']')
  validate_trigger_keymap('o', ']')

  -- Normal mode
  -- - Not same buffer
  local get_buf = child.api.nvim_get_current_buf
  local init_buf_id = get_buf()
  local new_buf_id = child.api.nvim_create_buf(true, false)

  type_keys(']b')
  eq(get_buf(), new_buf_id)

  type_keys('[b')
  eq(get_buf(), init_buf_id)

  type_keys(']B')
  eq(get_buf(), new_buf_id)

  type_keys('[B')
  eq(get_buf(), init_buf_id)

  type_keys('2[b')
  eq(get_buf(), init_buf_id)

  -- - Same buffer
  local indent_lines = { 'aa', '\tbb', '\t\tcc', '\tdd', 'ee' }
  validate_move(indent_lines, { 3, 2 }, '[i', { 2, 1 })
  validate_move(indent_lines, { 3, 2 }, ']i', { 4, 1 })
  validate_move(indent_lines, { 3, 2 }, '2[i', { 1, 0 })

  -- Visual mode
  validate_selection(indent_lines, { 3, 2 }, 'v[i', { 2, 1 }, { 3, 2 })
  validate_selection(indent_lines, { 3, 2 }, 'v]i', { 3, 2 }, { 4, 1 })
  validate_selection(indent_lines, { 3, 2 }, 'v2[i', { 1, 0 }, { 3, 2 })

  validate_selection(indent_lines, { 3, 2 }, 'V[i', { 2, 1 }, { 3, 2 }, 'V')

  -- Operator-pending mode
  validate_edit(indent_lines, { 3, 2 }, 'd[i', { 'aa', '\tdd', 'ee' }, { 2, 2 })
  validate_edit(indent_lines, { 3, 2 }, 'd]i', { 'aa', '\tbb', 'ee' }, { 3, 1 })
  validate_edit(indent_lines, { 3, 2 }, 'd2[i', { '\tdd', 'ee' }, { 1, 2 })
end

T['Reproducing keys']['mini modules']['mini.comment'] = function()
  child.o.commentstring = '## %s'

  local has_comment = setup_mini_module('comment')
  if not has_comment then MiniTest.skip("Could not load 'mini.comment'.") end

  -- Works together with 'mini.ai' without `g` as trigger
  local has_ai = setup_mini_module('ai')
  if has_ai then
    load_module({ triggers = { { mode = 'o', keys = 'i' } } })
    validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gc', 'ip' }, { '## aa', '## bb', '', 'cc' }, { 1, 0 })
  end

  -- Works with `g` as trigger
  load_module({
    triggers = {
      { mode = 'n', keys = 'g' },
      { mode = 'x', keys = 'g' },
      { mode = 'o', keys = 'g' },

      { mode = 'o', keys = 'i' },
    },
  })
  validate_trigger_keymap('n', 'g')

  -- Normal mode
  validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gc', 'ap' }, { '## aa', '## bb', '##', 'cc' }, { 1, 0 })
  validate_edit(
    { 'aa', '', 'bb', '', 'cc' },
    { 1, 0 },
    { '2gc', 'ap' },
    { '## aa', '##', '## bb', '##', 'cc' },
    { 1, 0 }
  )
  validate_edit(
    { 'aa', '', 'bb', '', 'cc' },
    { 1, 0 },
    { 'gc', 'ap', '.' },
    { '## ## aa', '## ##', '## bb', '##', 'cc' },
    { 1, 0 }
  )

  validate_edit({ 'aa', 'bb', '' }, { 1, 0 }, { 'gcc' }, { '## aa', 'bb', '' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', '' }, { 1, 0 }, { '2gcc' }, { '## aa', '## bb', '' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', '' }, { 1, 0 }, { 'gcc', 'j', '.' }, { '## aa', '## bb', '' }, { 2, 0 })

  -- Visual mode
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'V', 'gc' }, { '## aa', 'bb' }, { 1, 0 })

  -- Operator-pending mode
  validate_edit({ '## aa', 'bb' }, { 1, 0 }, { 'dgc' }, { 'bb' }, { 1, 0 })
  validate_edit({ '## aa', 'bb', '## cc' }, { 1, 0 }, { 'dgc', 'j', '.' }, { 'bb' }, { 1, 0 })

  -- Works together with 'mini.ai' when `g` is trigger
  if has_ai then
    validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gc', 'ip' }, { '## aa', '## bb', '', 'cc' }, { 1, 0 })
  end
end

T['Reproducing keys']['mini modules']['mini.indentscope'] = function()
  local has_indentscope = setup_mini_module('indentscope')
  if not has_indentscope then MiniTest.skip("Could not load 'mini.indentscope'.") end

  load_module({
    triggers = {
      { mode = 'n', keys = '[' },
      { mode = 'n', keys = ']' },

      { mode = 'x', keys = '[' },
      { mode = 'x', keys = ']' },
      { mode = 'x', keys = 'a' },
      { mode = 'x', keys = 'i' },

      { mode = 'o', keys = '[' },
      { mode = 'o', keys = ']' },
      { mode = 'o', keys = 'a' },
      { mode = 'o', keys = 'i' },
    },
  })
  validate_trigger_keymap('n', '[')
  validate_trigger_keymap('n', ']')
  validate_trigger_keymap('x', '[')
  validate_trigger_keymap('x', ']')
  validate_trigger_keymap('x', 'a')
  validate_trigger_keymap('x', 'i')
  validate_trigger_keymap('o', '[')
  validate_trigger_keymap('o', ']')
  validate_trigger_keymap('o', 'a')
  validate_trigger_keymap('o', 'i')

  local lines = { 'aa', '\tbb', '\t\tcc', '\tdd', 'ee' }
  local cursor = { 3, 2 }

  -- Normal mode
  validate_move(lines, cursor, '[i', { 2, 1 })
  validate_move(lines, cursor, '2[i', { 1, 0 })

  validate_move(lines, cursor, ']i', { 4, 1 })
  validate_move(lines, cursor, '2]i', { 5, 0 })

  -- Visual mode
  validate_selection(lines, cursor, 'v[i', { 2, 1 }, { 3, 2 })
  validate_selection(lines, cursor, 'v2[i', { 1, 0 }, { 3, 2 })

  validate_selection(lines, cursor, 'v]i', { 3, 2 }, { 4, 1 })
  validate_selection(lines, cursor, 'v2]i', { 3, 2 }, { 5, 0 })

  validate_selection(lines, cursor, 'vai', { 2, 1 }, { 4, 1 }, 'V')
  validate_selection(lines, cursor, 'v2ai', { 1, 0 }, { 5, 0 }, 'V')

  validate_selection(lines, cursor, 'vii', { 3, 2 }, { 3, 2 }, 'V')
  validate_selection(lines, cursor, 'v2ii', { 3, 2 }, { 3, 2 }, 'V')

  -- Operator-pending mode
  validate_edit(lines, cursor, 'd[i', { 'aa', '\tcc', '\tdd', 'ee' }, { 2, 1 })
  validate_edit(lines, cursor, 'd2[i', { 'cc', '\tdd', 'ee' }, { 1, 0 })
  validate_edit(lines, cursor, 'd[i.', { 'cc', '\tdd', 'ee' }, { 1, 0 })

  validate_edit(lines, cursor, 'd]i', { 'aa', '\tbb', '\t\tdd', 'ee' }, { 3, 2 })
  validate_edit(lines, cursor, 'd2]i', { 'aa', '\tbb', 'ee' }, { 3, 0 })
  validate_edit(lines, cursor, 'd]i.', { 'aa', '\tbb', 'ee' }, { 3, 0 })

  validate_edit(lines, cursor, 'dai', { 'aa', 'ee' }, { 2, 1 })
  validate_edit(lines, cursor, 'd2ai', { '' }, { 1, 0 })
  validate_edit(lines, cursor, 'dai.', { 'aa', 'ee' }, { 2, 1 })

  validate_edit(lines, cursor, 'dii', { 'aa', '\tbb', '\tdd', 'ee' }, { 3, 2 })
  validate_edit(lines, cursor, 'd2ii', { 'aa', '\tbb', '\tdd', 'ee' }, { 3, 2 })
  validate_edit(lines, cursor, 'dii.', { 'aa', 'ee' }, { 2, 1 })
end

T['Reproducing keys']['mini modules']['mini.surround'] = function()
  -- `saiw` works as expected when `s` and `i` are triggers: doesn't move cursor, no messages.

  local has_surround = setup_mini_module('surround')
  if not has_surround then MiniTest.skip("Could not load 'mini.surround'.") end

  -- Works together with 'mini.ai' without `s` as trigger
  local has_ai = setup_mini_module('ai')
  if has_ai then
    load_module({ triggers = { { mode = 'o', keys = 'i' } } })
    validate_edit1d('aa bb', 0, { 'sa', 'iw', ')' }, '(aa) bb', 1)
    validate_edit1d('aa ff(bb)', 0, { 'sa', 'if', ']' }, 'aa ff([bb])', 7)
  end

  -- Works with `s` as trigger
  load_module({ triggers = { { mode = 'n', keys = 's' }, { mode = 'o', keys = 'i' } } })
  validate_trigger_keymap('n', 's')
  validate_trigger_keymap('o', 'i')

  -- Add
  validate_edit1d('aa bb', 0, { 'sa', 'iw', ')' }, '(aa) bb', 1)
  validate_edit1d('aa bb', 0, { '2sa', 'iw', ')' }, '((aa)) bb', 2)
  validate_edit1d('aa bb', 0, { 'sa', '3iw', ')' }, '(aa bb)', 1)
  validate_edit1d('aa bb', 0, { '2sa', '3iw', ')' }, '((aa bb))', 2)

  validate_edit1d('aa bb', 0, { 'viw', 'sa', ')' }, '(aa) bb', 1)
  validate_edit1d('aa bb', 0, { 'viw', '2sa', ')' }, '((aa)) bb', 2)

  validate_edit1d('aa bb', 0, { 'sa', 'iw', ')', 'W', '.' }, '(aa) (bb)', 6)

  -- Delete
  validate_edit1d('(a(b(cc)b)a)', 5, 'sd)', '(a(bccb)a)', 4)
  validate_edit1d('(a(b(cc)b)a)', 5, '2sd)', '(ab(cc)ba)', 2)

  validate_edit1d('(a(b(cc)b)a)', 5, 'sd).', '(abccba)', 2)

  validate_edit1d('(aa) (bb) (cc)', 6, 'sdl)', 'aa (bb) (cc)', 0)
  validate_edit1d('(aa) (bb) (cc)', 11, '2sdl)', 'aa (bb) (cc)', 0)

  validate_edit1d('(aa) (bb) (cc)', 6, 'sdn)', '(aa) (bb) cc', 10)
  validate_edit1d('(aa) (bb) (cc)', 1, '2sdn)', '(aa) (bb) cc', 10)

  -- Replace
  validate_edit1d('(a(b(cc)b)a)', 5, 'sr)>', '(a(b<cc>b)a)', 5)
  validate_edit1d('(a(b(cc)b)a)', 5, '2sr)>', '(a<b(cc)b>a)', 3)

  validate_edit1d('(a(b(cc)b)a)', 5, 'sr)>.', '(a<b<cc>b>a)', 3)

  validate_edit1d('(aa) (bb) (cc)', 6, 'srl)>', '<aa> (bb) (cc)', 1)
  validate_edit1d('(aa) (bb) (cc)', 11, '2srl)>', '<aa> (bb) (cc)', 1)

  validate_edit1d('(aa) (bb) (cc)', 6, 'srn)>', '(aa) (bb) <cc>', 11)
  validate_edit1d('(aa) (bb) (cc)', 1, '2srn)>', '(aa) (bb) <cc>', 11)
end

return T
