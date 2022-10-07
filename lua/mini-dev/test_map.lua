local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('map', config) end
local unload_module = function() child.mini_unload('map') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

local tbl_repeat = function(x, n)
  local res = {}
  for _ = 1, n do
    table.insert(res, x)
  end
  return res
end

local eq_keys = function(tbl, ref_keys)
  local test_keys = vim.tbl_keys(tbl)
  local ref_keys_copy = vim.deepcopy(ref_keys)

  table.sort(test_keys)
  table.sort(ref_keys_copy)
  eq(test_keys, ref_keys_copy)
end

local get_latest_message = function() return child.cmd_capture('1messages') end

local get_mode = function() return child.api.nvim_get_mode()['mode'] end

local get_resolution_test_file = function(id) return 'tests/dir-map/resolution_' .. id end

local open_map = function(opts) child.lua('MiniMap.open(...)', { opts }) end

local refresh_map = function(opts, parts) child.lua('MiniMap.refresh(...)', { opts, parts }) end

local close_map = function() child.lua('MiniMap.close()') end

local get_map_buf_id = function() return child.lua_get('MiniMap.current.buf_data.map') end

local get_map_win_id =
  function() return child.lua_get('MiniMap.current.win_data[vim.api.nvim_get_current_tabpage()]') end

local get_current = function() return child.lua_get('MiniMap.current') end

-- Output test set
T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
})

-- Data =======================================================================
-- All possible encodings of '3x2' resolution
local example_lines = {
  '  a  aaa  a  aaa',
  '        a a a a ',
  '                ',
  '  a  aaa  a  aaa',
  ' a a a aaaaaaaaa',
  '                ',
  '  a  aaa  a  aaa',
  '        a a a a ',
  'a a a a a a a a ',
  '  a  aaa  a  aaa',
  ' a a a aaaaaaaaa',
  'a a a a a a a a ',
  '  a  aaa  a  aaa',
  '        a a a a ',
  ' a a a a a a a a',
  '  a  aaa  a  aaa',
  ' a a a aaaaaaaaa',
  ' a a a a a a a a',
  '  a  aaa  a  aaa',
  '        a a a a ',
  'aaaaaaaaaaaaaaaa',
  '  a  aaa  a  aaa',
  ' a a a aaaaaaaaa',
  'aaaaaaaaaaaaaaaa',
}

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniMap)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniMap'), 1)

  -- Highlight groups
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniMapSymbolCount', 'links to Special')
  has_highlight('MiniMapSymbolLine', 'links to Title')
  has_highlight('MiniMapSymbolView', 'links to Delimiter')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniMap.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniMap.config.' .. field), value) end

  -- Check default values
  expect_config('integrations', {})

  expect_config('symbols.encode', vim.NIL)
  expect_config('symbols.scroll_line', '█')
  expect_config('symbols.scroll_view', '┃')

  expect_config('window.side', 'right')
  expect_config('window.show_integration_count', true)
  expect_config('window.width', 10)
  expect_config('window.winblend', 25)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ window = { width = 1 } })
  eq(child.lua_get('MiniMap.config.window.width'), 1)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  local expect_all_encode_symbols_check = function()
    local expect_bad_config = function(err_pattern)
      expect.error(function() child.lua([[MiniMap.setup(_G.bad_config)]]) end, err_pattern)
    end

    child.lua('_G.bad_config = { symbols = { encode = { resolution = { col = 2, row = 2 } } } }')
    for i = 1, 4 do
      expect_bad_config('symbols%.encode%[' .. i .. '%].*string')
      child.lua(string.format('_G.bad_config.symbols.encode[%d] = "%d"', i, i))
    end
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ integrations = 'a' }, 'integrations', 'array')
  expect_config_error({ integrations = { 'a' } }, 'integrations', 'callable')

  expect_config_error({ symbols = 'a' }, 'symbols', 'table')
  expect_config_error({ symbols = { encode = 'a' } }, 'symbols.encode', 'table')

  expect_config_error({ symbols = { encode = { resolution = 'a' } } }, 'symbols.encode.resolution', 'table')
  expect_config_error(
    { symbols = { encode = { resolution = { col = 'a' } } } },
    'symbols.encode.resolution.col',
    'number'
  )
  expect_config_error(
    { symbols = { encode = { resolution = { col = 2, row = 'a' } } } },
    'symbols.encode.resolution.row',
    'number'
  )
  expect_all_encode_symbols_check()

  expect_config_error({ symbols = { scroll_line = 1 } }, 'symbols.scroll_line', 'string')
  expect_config_error({ symbols = { scroll_view = 1 } }, 'symbols.scroll_view', 'string')

  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { side = 1 } }, 'window.side', 'one of')
  expect_config_error({ window = { side = 'a' } }, 'window.side', 'one of')
  expect_config_error({ window = { show_integration_count = 1 } }, 'window.show_integration_count', 'boolean')
  expect_config_error({ window = { width = 'a' } }, 'window.width', 'number')
  expect_config_error({ window = { winblend = 'a' } }, 'window.winblend', 'number')
end

local encode_strings = function(strings, opts)
  local cmd = string.format('MiniMap.encode_strings(%s, %s)', vim.inspect(strings), vim.inspect(opts))
  return child.lua_get(cmd)
end

T['encode_strings()'] = new_set()

T['encode_strings()']['works'] = function() eq(encode_strings({ 'aa', 'aa', 'aa' }), { '█' }) end

T['encode_strings()']['validates `strings` argument'] = function()
  expect.error(encode_strings, 'array', 'a')
  expect.error(encode_strings, 'strings', { 1, 'a' })
end

T['encode_strings()']['respects `strings` argument'] = function() eq(encode_strings({ 'aa' }), { '🬂' }) end

T['encode_strings()']['respects `opts.n_rows`'] = function()
  local strings = tbl_repeat('aa', 3 * 3)
  eq(encode_strings(strings), { '█', '█', '█' })
  eq(encode_strings(strings, { n_rows = 1 }), { '█' })
  -- Very big values are trimmed to minimum necessary needed
  eq(encode_strings(strings, { n_rows = 1000 }), { '█', '█', '█' })

  -- Rescaling should be done via "output is non-empty if at least one cell is
  -- non-empty; empty if all empty"
  eq(encode_strings({ 'a', ' ', ' ', ' ', ' ', 'a', 'a', 'a', ' ', ' ', ' ' }, { n_rows = 2 }), { '🬐', '🬀' })
end

T['encode_strings()']['respects `opts.n_cols`'] = function()
  local strings = tbl_repeat('aaaaaa', 3)
  eq(encode_strings(strings), { '███' })
  eq(encode_strings(strings, { n_cols = 1 }), { '█' })
  -- Very big values are trimmed to minimum necessary needed
  eq(encode_strings(strings, { n_cols = 1000 }), { '███' })

  -- Rescaling should be done via "output is non-empty if at least one cell is
  -- non-empty; empty if all empty"
  eq(encode_strings({ 'a  a  aa' }, { n_cols = 2 }), { '🬂🬁' })
end

T['encode_strings()']['respects `opts.symbols`'] = function()
  local symbols = { '1', '2', '3', '4', resolution = { row = 1, col = 2 } }
  eq(encode_strings({ '  aa', 'a  a' }, { symbols = symbols }), { '14', '23' })
end

T['encode_strings()']['works with empty strings'] =
  function() eq(encode_strings({ 'aaaa', '', 'aaaa', '' }), { '🬰🬰', '  ' }) end

T['encode_strings()']['correctly computes default dimensions'] =
  function() eq(encode_strings({ 'a', 'aa', 'aaa', 'aaaa', 'aaaaa', '' }), { '🬺🬏 ', '🬎🬎🬃' }) end

T['encode_strings()']['does not trim whitespace'] = function()
  eq(encode_strings({ ' ' }), { ' ' })
  eq(encode_strings({ 'aa  ', 'aa  ', 'aa  ' }), { '█ ' })
end

T['encode_strings()']['works with multibyte strings'] = function()
  eq(encode_strings({ 'ыыыыыы', 'ыыыы', 'ыы', 'aaaaaa', 'aaaa', 'aa' }), { '█🬎🬂', '█🬎🬂' })
end

T['encode_strings()']['correctly rescales in edge cases'] = function()
  -- There were cases with more straightforward rescaling when certain middle
  -- output row was not affected by any input row, leaving it empty. This was
  -- because rescaling coefficient was more than 1.
  local strings = tbl_repeat('aa', 37)
  local ref_output = tbl_repeat('█', 12)
  table.insert(ref_output, '🬂')
  eq(encode_strings(strings), ref_output)
end

T['encode_strings()']['can work with input dimensions being not multiple of resolution'] = function()
  eq(encode_strings({ 'a' }), { '🬀' })
  eq(encode_strings({ 'aaa' }), { '🬂🬀' })
  eq(encode_strings({ 'a', 'a' }), { '🬄' })
  eq(encode_strings({ 'a', 'a', 'a', 'a' }), { '▌', '🬀' })
end

T['encode_strings()']['expands tabs'] = function()
  eq(encode_strings({ '\taa' }), { '    🬂' })

  child.o.tabstop = 4
  eq(encode_strings({ '\taa' }), { '  🬂' })
end

T['open()'] = new_set({ hooks = { pre_case = function() child.set_size(30, 30) end } })

T['open()']['works'] = function()
  set_lines(example_lines)
  set_cursor(1, 0)

  open_map()

  child.expect_screenshot()
end

T['open()']['correctly update `MiniMap.current`'] = function()
  open_map()
  local current = get_current()

  eq_keys(current, { 'buf_data', 'opts', 'win_data' })

  eq_keys(current.buf_data, { 'map', 'source' })
  eq(current.buf_data.source, child.api.nvim_get_current_buf())

  eq(current.opts, child.lua_get('MiniMap.config'))

  eq_keys(current.win_data, { child.api.nvim_get_current_tabpage() })
end

T['open()']['correctly computes window config'] = function()
  child.set_size(30, 20)
  open_map()
  local win_id = get_map_win_id()

  eq(child.api.nvim_win_get_config(win_id), {
    anchor = 'NE',
    col = 20,
    external = false,
    focusable = true,
    height = 28,
    relative = 'editor',
    row = 0,
    width = 10,
    zindex = 10,
  })
  eq(child.api.nvim_win_get_option(win_id, 'winblend'), child.lua_get('MiniMap.config.window.winblend'))
end

T['open()']['respects `opts.symbols` argument'] = function()
  set_lines(example_lines)
  child.lua([[MiniMap.open({
    symbols = {
      encode = { '1', '2', '3', '4', resolution = { row = 1, col = 2 } },
      scroll_line = '>',
      scroll_view = '+',
    },
  })]])

  child.expect_screenshot()
end

T['open()']['respects `opts.window` argument'] = function()
  set_lines(example_lines)
  local opts = { window = { side = 'left', show_integration_count = false, width = 15, winblend = 50 } }
  open_map(opts)

  child.expect_screenshot()
  eq(child.api.nvim_win_get_option(get_map_win_id(), 'winblend'), 50)

  -- Updates current data accordingly
  eq(child.lua_get('MiniMap.current.opts.window'), opts.window)
end

T['open()']['respects `MiniMap.config.window`'] = function()
  child.lua('MiniMap.config.window.width = 20')
  open_map()
  eq(child.api.nvim_win_get_width(get_map_win_id()), 20)
  eq(child.lua_get('MiniMap.current.opts.window.width'), 20)
end

T['open()']['respects important options when computing window height'] = function()
  local validate = function(options, row, height)
    local default_opts = { showtabline = 1, laststatus = 2, cmdheight = 1 }
    options = vim.tbl_deep_extend('force', default_opts, options)
    for name, value in pairs(options) do
      child.o[name] = value
    end

    open_map()
    local config = child.api.nvim_win_get_config(get_map_win_id())
    eq(config.row, row)
    eq(config.height, height)
    close_map()

    for name, value in pairs(default_opts) do
      child.o[name] = value
    end
  end

  validate({ showtabline = 0, laststatus = 0, cmdheight = 1 }, 0, 29)

  -- Tabline. Should make space for it if it is actually shown
  validate({ showtabline = 2, laststatus = 0 }, 1, 28)

  validate({ showtabline = 1, laststatus = 0 }, 0, 29)
  child.cmd('tabedit')
  validate({ showtabline = 2, laststatus = 0 }, 1, 28)
  child.cmd('tabclose')

  -- Statusline
  validate({ showtabline = 0, laststatus = 1 }, 0, 28)
  validate({ showtabline = 0, laststatus = 2 }, 0, 28)

  if child.fn.has('nvim-0.8') == 1 then validate({ showtabline = 0, laststatus = 3 }, 0, 28) end

  -- Command line
  validate({ showtabline = 0, laststatus = 0, cmdheight = 4 }, 0, 26)

  if child.fn.has('nvim-0.8') == 1 then validate({ showtabline = 0, laststatus = 0, cmdheight = 0 }, 0, 30) end
end

T['open()']['can be used with already opened window'] = function()
  open_map()
  local current = get_current()
  expect.no_error(open_map)
  eq(current, get_current())
end

T['open()']['can open pure scrollbar'] = function()
  -- child.set_size(15, 30)
  -- set_lines(example_lines)
  -- set_cursor(24, 0)
  -- child.cmd('normal! zz')
  -- open_map({ window = { width = 1 } })
  -- child.expect_screenshot()
end

T['open()']['respects `vim.{g,b}.minimap_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minimap_disable = true

    open_map()
    eq(#child.api.nvim_list_wins(), 1)
  end,
})

T['refresh()'] = new_set()

T['refresh()']['works'] = function() MiniTest.skip() end

T['close()'] = new_set()

T['close()']['works'] = function() MiniTest.skip() end

T['toggle()'] = new_set()

T['toggle()']['works'] = function() MiniTest.skip() end

T['toggle_focus()'] = new_set()

T['toggle_focus()']['works'] = function() MiniTest.skip() end

T['toggle_side()'] = new_set()

T['toggle_side()']['works'] = function() MiniTest.skip() end

local validate_gen_symbols = function(field, id)
  child.lua(string.format([[_G.symbols = MiniMap.gen_encode_symbols['%s']('%s')]], field, id))

  local cmd = string.format(
    [[MiniMap.encode_strings(vim.fn.readfile('%s'), { symbols = _G.symbols })]],
    get_resolution_test_file(id)
  )

  eq(child.lua_get(cmd), child.lua_get('{ table.concat(_G.symbols) }'))
end

T['current'] = new_set()

T['current']['has initial value'] = function()
  local config = child.lua_get('MiniMap.config')
  eq(get_current(), {
    buf_data = {},
    opts = config,
    win_data = {},
  })
end

T['current']['has correct `buf_data`'] = function() MiniTest.skip() end

T['current']['has correct `encode_data`'] = function() MiniTest.skip() end

T['current']['has correct `opts`'] = function() MiniTest.skip() end

T['current']['has correct `scrollbar_data`'] = function() MiniTest.skip() end

T['current']['has correct `win_data`'] = function() MiniTest.skip() end

T['current']['correctly updates'] = function() MiniTest.skip() end

T['gen_encode_symbols'] = new_set()

T['gen_encode_symbols']['block()'] = function()
  validate_gen_symbols('block', '1x2')
  validate_gen_symbols('block', '2x1')
  validate_gen_symbols('block', '2x2')
  validate_gen_symbols('block', '3x2')
end

T['gen_encode_symbols']['dot()'] = function()
  validate_gen_symbols('dot', '3x2')
  validate_gen_symbols('dot', '4x2')
end

T['gen_encode_symbols']['shade()'] = function()
  validate_gen_symbols('shade', '1x2')
  validate_gen_symbols('shade', '2x1')
end

T['gen_integration'] = new_set()

T['gen_integration']['builtin_search()'] = function() MiniTest.skip() end

T['gen_integration']['diagnostics()'] = function() MiniTest.skip() end

T['gen_integration']['gitsigns()'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
T['Window'] = new_set()

T['Window']['works'] = function() MiniTest.skip() end

T['Window']['can be opened in multiple tabpages'] = function() MiniTest.skip() end

T['Window']['implements buffer local mappings'] = function() MiniTest.skip() end

T['Window']['can work as pure scrollbar'] = function() MiniTest.skip() end

T['Scrollbar'] = new_set()

T['Scrollbar']['works'] = function() MiniTest.skip() end

T['Focus'] = new_set()

T['Focus']['works'] = function() MiniTest.skip() end

T['Focus']['moves cursor in source window'] = function() MiniTest.skip() end

T['Integrations'] = new_set()

T['Integrations']['allow extreme lines in output'] = function()
  -- So both less than 1 and more than current number of lines
  MiniTest.skip()
end

T['Integrations'] = new_set()

return T
