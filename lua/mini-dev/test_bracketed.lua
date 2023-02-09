local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('bracketed', config) end
local unload_module = function() child.mini_unload('bracketed') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

-- Helper wrappers for iteration directions
local forward = function(target, ...)
  local command = string.format('MiniBracketed.%s("forward", ...)', target)
  child.lua(command, { ... })
end

local backward = function(target, ...)
  local command = string.format('MiniBracketed.%s("backward", ...)', target)
  child.lua(command, { ... })
end

local first = function(target, ...)
  local command = string.format('MiniBracketed.%s("first", ...)', target)
  child.lua(command, { ... })
end

local last = function(target, ...)
  local command = string.format('MiniBracketed.%s("last", ...)', target)
  child.lua(command, { ... })
end

-- Output test set ============================================================
T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniBracketed)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniBracketed'), 1)
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniBracketed.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniBracketed.config.' .. field), value) end

  expect_config('buffer.suffix', 'b')
  expect_config('buffer.options', {})

  expect_config('comment.suffix', 'c')
  expect_config('comment.options', {})

  expect_config('conflict.suffix', 'x')
  expect_config('conflict.options', {})

  expect_config('diagnostic.suffix', 'd')
  expect_config('diagnostic.options', {})

  expect_config('file.suffix', 'f')
  expect_config('file.options', {})

  expect_config('indent.suffix', 'i')
  expect_config('indent.options', {})

  expect_config('jump.suffix', 'j')
  expect_config('jump.options', {})

  expect_config('location.suffix', 'l')
  expect_config('location.options', {})

  expect_config('oldfile.suffix', 'o')
  expect_config('oldfile.options', {})

  expect_config('quickfix.suffix', 'q')
  expect_config('quickfix.options', {})

  expect_config('window.suffix', 'w')
  expect_config('window.options', {})
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ buffer = { suffix = '' } })
  eq(child.lua_get('MiniBracketed.config.buffer.suffix'), '')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')

  expect_config_error({ buffer = 'a' }, 'buffer', 'table')
  expect_config_error({ buffer = { suffix = 1 } }, 'buffer.suffix', 'string')
  expect_config_error({ buffer = { options = 'a' } }, 'buffer.options', 'table')

  expect_config_error({ comment = 'a' }, 'comment', 'table')
  expect_config_error({ comment = { suffix = 1 } }, 'comment.suffix', 'string')
  expect_config_error({ comment = { options = 'a' } }, 'comment.options', 'table')

  expect_config_error({ conflict = 'a' }, 'conflict', 'table')
  expect_config_error({ conflict = { suffix = 1 } }, 'conflict.suffix', 'string')
  expect_config_error({ conflict = { options = 'a' } }, 'conflict.options', 'table')

  expect_config_error({ diagnostic = 'a' }, 'diagnostic', 'table')
  expect_config_error({ diagnostic = { suffix = 1 } }, 'diagnostic.suffix', 'string')
  expect_config_error({ diagnostic = { options = 'a' } }, 'diagnostic.options', 'table')

  expect_config_error({ file = 'a' }, 'file', 'table')
  expect_config_error({ file = { suffix = 1 } }, 'file.suffix', 'string')
  expect_config_error({ file = { options = 'a' } }, 'file.options', 'table')

  expect_config_error({ indent = 'a' }, 'indent', 'table')
  expect_config_error({ indent = { suffix = 1 } }, 'indent.suffix', 'string')
  expect_config_error({ indent = { options = 'a' } }, 'indent.options', 'table')

  expect_config_error({ jump = 'a' }, 'jump', 'table')
  expect_config_error({ jump = { suffix = 1 } }, 'jump.suffix', 'string')
  expect_config_error({ jump = { options = 'a' } }, 'jump.options', 'table')

  expect_config_error({ location = 'a' }, 'location', 'table')
  expect_config_error({ location = { suffix = 1 } }, 'location.suffix', 'string')
  expect_config_error({ location = { options = 'a' } }, 'location.options', 'table')

  expect_config_error({ oldfile = 'a' }, 'oldfile', 'table')
  expect_config_error({ oldfile = { suffix = 1 } }, 'oldfile.suffix', 'string')
  expect_config_error({ oldfile = { options = 'a' } }, 'oldfile.options', 'table')

  expect_config_error({ quickfix = 'a' }, 'quickfix', 'table')
  expect_config_error({ quickfix = { suffix = 1 } }, 'quickfix.suffix', 'string')
  expect_config_error({ quickfix = { options = 'a' } }, 'quickfix.options', 'table')

  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { suffix = 1 } }, 'window.suffix', 'string')
  expect_config_error({ window = { options = 'a' } }, 'window.options', 'table')
end

T['setup()']['properly creates mappings'] = function()
  local has_map = function(lhs, mode) return child.cmd_capture(mode .. 'map ' .. lhs):find('MiniBracketed') ~= nil end
  eq(has_map('[B', 'n'), true)
  eq(has_map('[b', 'n'), true)
  eq(has_map(']b', 'n'), true)
  eq(has_map(']B', 'n'), true)

  unload_module()
  child.api.nvim_del_keymap('n', '[B')
  child.api.nvim_del_keymap('n', '[b')
  child.api.nvim_del_keymap('n', ']b')
  child.api.nvim_del_keymap('n', ']B')

  -- Supplying empty string as suffix should mean "don't create keymaps"
  load_module({ buffer = { suffix = '' } })
  eq(has_map('[B', 'n'), false)
  eq(has_map('[b', 'n'), false)
  eq(has_map(']b', 'n'), false)
  eq(has_map(']B', 'n'), false)
end

T['buffer()'] = new_set()

local get_buf = function() return child.api.nvim_get_current_buf() end
local set_buf = function(x) return child.api.nvim_set_current_buf(x) end

local setup_buffers = function()
  local init_buf = child.api.nvim_get_current_buf()

  local buf_1 = child.api.nvim_create_buf(true, false)

  -- Test when target buffers are not consecutive
  child.api.nvim_create_buf(false, false)

  local buf_2 = child.api.nvim_create_buf(true, false)
  local buf_3 = child.api.nvim_create_buf(true, false)

  -- Should work even in not "normal" buffers
  local buf_4 = child.api.nvim_create_buf(true, false)
  child.bo[buf_4].buftype = 'help'

  local buf_5 = child.api.nvim_create_buf(true, false)

  -- Test if initial buffer is not 1
  child.cmd('bwipeout ' .. init_buf)

  return { buf_1, buf_2, buf_3, buf_4, buf_5 }
end

T['buffer()']['works'] = function()
  local buf_list = setup_buffers()
  local n = #buf_list
  local validate = function(id_start, direction, id_end, opts)
    set_buf(buf_list[id_start])
    child.lua('MiniBracketed.buffer(...)', { direction, opts })
    eq(get_buf(), buf_list[id_end])
  end

  -- Forward
  validate(1, 'forward', 2)
  validate(2, 'forward', 3)
  validate(n - 1, 'forward', n)
  validate(n, 'forward', 1)

  -- Backward
  validate(n, 'backward', n - 1)
  validate(n - 1, 'backward', n - 2)
  validate(2, 'backward', 1)
  validate(1, 'backward', n)

  -- First
  validate(n, 'first', 1)
  validate(2, 'first', 1)
  validate(1, 'first', 1)

  -- Last
  validate(1, 'last', n)
  validate(2, 'last', n)
  validate(n, 'last', n)
end

T['buffer()']['works when started in not listed buffer'] = function()
  local buf_list = setup_buffers()
  local buf_nolisted = child.api.nvim_create_buf(false, true)

  -- Forward
  set_buf(buf_nolisted)
  forward('buffer')
  eq(get_buf(), buf_list[1])

  -- Backward
  set_buf(buf_nolisted)
  backward('buffer')
  eq(get_buf(), buf_list[#buf_list])
end

T['buffer()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.buffer(1)') end, 'buffer%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.buffer('next')]]) end, 'buffer%(%).*direction.*one of')
end

T['buffer()']['respects `opts.n_times`'] = function()
  local buf_list = setup_buffers()
  local n = #buf_list
  local validate = function(id_start, direction, id_end, opts)
    set_buf(buf_list[id_start])
    child.lua('MiniBracketed.buffer(...)', { direction, opts })
    eq(get_buf(), buf_list[id_end])
  end

  -- Forward
  validate(1, 'forward', 3, { n_times = 2 })
  validate(n - 2, 'forward', n, { n_times = 2 })
  validate(n - 1, 'forward', 1, { n_times = 2 })

  -- Backward
  validate(n, 'backward', n - 2, { n_times = 2 })
  validate(3, 'backward', 1, { n_times = 2 })
  validate(2, 'backward', n, { n_times = 2 })

  -- First
  validate(n, 'first', 2, { n_times = 2 })
  validate(2, 'first', 2, { n_times = 2 })
  validate(1, 'first', 2, { n_times = 2 })

  -- Last
  validate(1, 'last', n - 1, { n_times = 2 })
  validate(n - 1, 'last', n - 1, { n_times = 2 })
  validate(n, 'last', n - 1, { n_times = 2 })
end

T['buffer()']['respects `opts.wrap`'] = function()
  local buf_list = setup_buffers()
  local n = #buf_list
  local validate = function(id_start, direction, id_end, opts)
    set_buf(buf_list[id_start])
    child.lua('MiniBracketed.buffer(...)', { direction, opts })
    eq(get_buf(), buf_list[id_end])
  end

  -- Forward
  validate(n, 'forward', n, { wrap = false })
  validate(n - 1, 'forward', n, { n_times = 1000, wrap = false })

  -- Backward
  validate(1, 'backward', 1, { wrap = false })
  validate(2, 'backward', 1, { n_times = 1000, wrap = false })

  -- First
  validate(1, 'first', n, { n_times = 1000, wrap = false })
  validate(n, 'first', n, { n_times = 1000, wrap = false })

  -- Last
  validate(n, 'last', 1, { n_times = 1000, wrap = false })
  validate(1, 'last', 1, { n_times = 1000, wrap = false })
end

T['buffer()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    local buf_list = setup_buffers()

    set_buf(buf_list[1])
    child[var_type].minibracketed_disable = true
    forward('buffer')
    eq(get_buf(), buf_list[1])
  end,
})

T['buffer()']['respects `vim.b.minibracketed_config`'] = function()
  local buf_list = setup_buffers()

  set_buf(buf_list[1])
  child.b.minibracketed_config = { buffer = { options = { wrap = false } } }
  backward('buffer')
  eq(get_buf(), buf_list[1])
end

T['comment()'] = new_set()

T['comment()']['works'] = function() MiniTest.skip() end

T['comment()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.comment(1)') end, 'comment%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.comment('next')]]) end, 'comment%(%).*direction.*one of')
end

T['comment()']['respects `opts.block_side`'] = function() MiniTest.skip() end

T['comment()']['respects `opts.n_times`'] = function() MiniTest.skip() end

T['comment()']['respects `opts.wrap`'] = function() MiniTest.skip() end

T['comment()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minibracketed_disable = true
    MiniTest.skip()
  end,
})

T['comment()']['respects `vim.b.minibracketed_config`'] = function()
  child.b.minibracketed_config = { comment = { options = { wrap = false } } }
  MiniTest.skip()
end

T['conflict()'] = new_set()

T['conflict()']['works'] = function() MiniTest.skip() end

T['conflict()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.conflict(1)') end, 'conflict%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.conflict('next')]]) end, 'conflict%(%).*direction.*one of')
end

T['conflict()']['respects `opts.n_times`'] = function() MiniTest.skip() end

T['conflict()']['respects `opts.wrap`'] = function() MiniTest.skip() end

T['conflict()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minibracketed_disable = true
    MiniTest.skip()
  end,
})

T['conflict()']['respects `vim.b.minibracketed_config`'] = function()
  child.b.minibracketed_config = { conflict = { options = { wrap = false } } }
  MiniTest.skip()
end

T['diagnostic()'] = new_set()

T['diagnostic()']['works'] = function() MiniTest.skip() end

T['diagnostic()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.diagnostic(1)') end, 'diagnostic%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.diagnostic('next')]]) end, 'diagnostic%(%).*direction.*one of')
end

T['diagnostic()']['respects `opts.n_times`'] = function() MiniTest.skip() end

T['diagnostic()']['respects `opts.wrap`'] = function() MiniTest.skip() end

T['diagnostic()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minibracketed_disable = true
    MiniTest.skip()
  end,
})

T['diagnostic()']['respects `vim.b.minibracketed_config`'] = function()
  child.b.minibracketed_config = { diagnostic = { options = { wrap = false } } }
  MiniTest.skip()
end

T['file()'] = new_set()

T['file()']['works'] = function() MiniTest.skip() end

T['file()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.file(1)') end, 'file%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.file('next')]]) end, 'file%(%).*direction.*one of')
end

T['file()']['respects `opts.n_times`'] = function() MiniTest.skip() end

T['file()']['respects `opts.wrap`'] = function() MiniTest.skip() end

T['file()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minibracketed_disable = true
    MiniTest.skip()
  end,
})

T['file()']['respects `vim.b.minibracketed_config`'] = function()
  child.b.minibracketed_config = { file = { options = { wrap = false } } }
  MiniTest.skip()
end

T['indent()'] = new_set()

T['indent()']['works'] = function() MiniTest.skip() end

T['indent()']['respects `opts.change_type`'] = function() MiniTest.skip() end

T['indent()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.indent(1)') end, 'indent%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.indent('next')]]) end, 'indent%(%).*direction.*one of')
end

T['indent()']['respects `opts.n_times`'] = function() MiniTest.skip() end

T['indent()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minibracketed_disable = true
    MiniTest.skip()
  end,
})

T['indent()']['respects `vim.b.minibracketed_config`'] = function()
  child.b.minibracketed_config = { indent = { options = { wrap = false } } }
  MiniTest.skip()
end

T['jump()'] = new_set()

local get_jump = function() return child.fn.getjumplist()[2] end
-- local set_jump = function(x) child.cmd('silent ll ' .. x) end

T['jump()']['works'] = function() MiniTest.skip() end

T['jump()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.jump(1)') end, 'jump%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.jump('next')]]) end, 'jump%(%).*direction.*one of')
end

T['jump()']['respects `opts.n_times`'] = function() MiniTest.skip() end

T['jump()']['respects `opts.wrap`'] = function() MiniTest.skip() end

T['jump()']['opens just enough folds'] = function() MiniTest.skip() end

T['jump()']['can jump to current entry'] = function() MiniTest.skip() end

T['jump()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minibracketed_disable = true
    MiniTest.skip()
  end,
})

T['jump()']['respects `vim.b.minibracketed_config`'] = function()
  child.b.minibracketed_config = { jump = { options = { wrap = false } } }
  MiniTest.skip()
end

T['location()'] = new_set()

local get_location = function() return child.fn.getloclist(0, { idx = 0 }).idx end
local set_location = function(x) child.cmd('silent ll ' .. x) end

local setup_location = function()
  set_lines({ 'aaaaa', 'bbbbb', 'ccccc', 'ddddd', 'eeeee' })
  local buf_id = child.api.nvim_get_current_buf()

  child.fn.setloclist(0, {
    { bufnr = buf_id, lnum = 1, col = 1 },
    { bufnr = buf_id, lnum = 2, col = 2 },
    { bufnr = buf_id, lnum = 3, col = 3 },
    { bufnr = buf_id, lnum = 4, col = 4 },
    { bufnr = buf_id, lnum = 5, col = 5 },
  })

  return child.fn.getloclist(0)
end

T['location()']['works'] = function()
  local qf_list = setup_location()
  local n = #qf_list
  local validate = function(id_start, direction, id_end, opts)
    set_location(id_start)
    child.lua('MiniBracketed.location(...)', { direction, opts })
    eq(get_location(), id_end)
    eq(get_cursor(), { qf_list[id_end].lnum, qf_list[id_end].col - 1 })
  end

  -- Forward
  validate(1, 'forward', 2)
  validate(2, 'forward', 3)
  validate(n - 1, 'forward', n)
  validate(n, 'forward', 1)

  -- Backward
  validate(n, 'backward', n - 1)
  validate(n - 1, 'backward', n - 2)
  validate(2, 'backward', 1)
  validate(1, 'backward', n)

  -- First
  validate(n, 'first', 1)
  validate(2, 'first', 1)
  validate(1, 'first', 1)

  -- Last
  validate(1, 'last', n)
  validate(2, 'last', n)
  validate(n, 'last', n)
end

T['location()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.location(1)') end, 'location%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.location('next')]]) end, 'location%(%).*direction.*one of')
end

T['location()']['respects `opts.n_times`'] = function()
  local qf_list = setup_location()
  local n = #qf_list
  local validate = function(id_start, direction, id_end, opts)
    set_location(id_start)
    child.lua('MiniBracketed.location(...)', { direction, opts })
    eq(get_location(), id_end)
    eq(get_cursor(), { qf_list[id_end].lnum, qf_list[id_end].col - 1 })
  end

  -- Forward
  validate(1, 'forward', 3, { n_times = 2 })
  validate(n - 2, 'forward', n, { n_times = 2 })
  validate(n - 1, 'forward', 1, { n_times = 2 })

  -- Backward
  validate(n, 'backward', n - 2, { n_times = 2 })
  validate(3, 'backward', 1, { n_times = 2 })
  validate(2, 'backward', n, { n_times = 2 })

  -- First
  validate(n, 'first', 2, { n_times = 2 })
  validate(2, 'first', 2, { n_times = 2 })
  validate(1, 'first', 2, { n_times = 2 })

  -- Last
  validate(1, 'last', n - 1, { n_times = 2 })
  validate(n - 1, 'last', n - 1, { n_times = 2 })
  validate(n, 'last', n - 1, { n_times = 2 })
end

T['location()']['respects `opts.wrap`'] = function()
  local qf_list = setup_location()
  local n = #qf_list
  local validate = function(id_start, direction, id_end, opts)
    set_location(id_start)
    child.lua('MiniBracketed.location(...)', { direction, opts })
    eq(get_location(), id_end)
    eq(get_cursor(), { qf_list[id_end].lnum, qf_list[id_end].col - 1 })
  end

  -- Forward
  validate(n, 'forward', n, { wrap = false })
  validate(n - 1, 'forward', n, { n_times = 1000, wrap = false })

  -- Backward
  validate(1, 'backward', 1, { wrap = false })
  validate(2, 'backward', 1, { n_times = 1000, wrap = false })

  -- First
  validate(1, 'first', n, { n_times = 1000, wrap = false })
  validate(n, 'first', n, { n_times = 1000, wrap = false })

  -- Last
  validate(n, 'last', 1, { n_times = 1000, wrap = false })
  validate(1, 'last', 1, { n_times = 1000, wrap = false })
end

T['location()']['opens just enough folds and centers window'] = function()
  local qf_list = setup_location()
  set_location(3)

  child.set_size(5, 12)
  set_cursor(1, 0)
  type_keys('zt')

  eq(child.fn.line('w0'), 1)
  child.cmd('1,2 fold')
  eq({ child.fn.foldclosed(1), child.fn.foldclosed(2) }, { 1, 1 })
  child.cmd('4,5 fold')
  eq({ child.fn.foldclosed(4), child.fn.foldclosed(5) }, { 4, 4 })

  child.cmd([[silent lua MiniBracketed.location('forward')]])
  eq(get_location(), 4)
  eq(get_cursor(), { qf_list[4].lnum, qf_list[4].col - 1 })

  eq(child.fn.line('w0'), 3)
  eq({ child.fn.foldclosed(1), child.fn.foldclosed(2) }, { 1, 1 })
  eq({ child.fn.foldclosed(4), child.fn.foldclosed(5) }, { -1, -1 })
end

T['location()']['can jump to current entry'] = function()
  local qf_list = setup_location()
  set_location(3)
  set_cursor(1, 0)

  forward('location', { n_times = #qf_list })
  eq(get_location(), 3)
  eq(get_cursor(), { qf_list[3].lnum, qf_list[3].col - 1 })
end

T['location()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    setup_location()
    set_location(1)
    local cur_pos = get_cursor()

    child[var_type].minibracketed_disable = true
    forward('location')
    eq(get_location(), 1)
    eq(get_cursor(), cur_pos)
  end,
})

T['location()']['respects `vim.b.minibracketed_config`'] = function()
  setup_location()
  set_location(1)
  local cur_pos = get_cursor()

  child.b.minibracketed_config = { location = { options = { wrap = false } } }
  backward('location')
  eq(get_location(), 1)
  eq(get_cursor(), cur_pos)
end

T['oldfile()'] = new_set()

T['oldfile()']['works'] = function() MiniTest.skip() end

T['oldfile()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.oldfile(1)') end, 'oldfile%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.oldfile('next')]]) end, 'oldfile%(%).*direction.*one of')
end

T['oldfile()']['respects `opts.n_times`'] = function() MiniTest.skip() end

T['oldfile()']['respects `opts.wrap`'] = function() MiniTest.skip() end

T['oldfile()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minibracketed_disable = true
    MiniTest.skip()
  end,
})

T['oldfile()']['respects `vim.b.minibracketed_config`'] = function()
  child.b.minibracketed_config = { oldfile = { options = { wrap = false } } }
  MiniTest.skip()
end

T['quickfix()'] = new_set()

local get_quickfix = function() return child.fn.getqflist({ idx = 0 }).idx end
local set_quickfix = function(x) child.cmd('silent cc ' .. x) end

local setup_quickfix = function()
  set_lines({ 'aaaaa', 'bbbbb', 'ccccc', 'ddddd', 'eeeee' })
  local buf_id = child.api.nvim_get_current_buf()

  child.fn.setqflist({
    { bufnr = buf_id, lnum = 1, col = 1 },
    { bufnr = buf_id, lnum = 2, col = 2 },
    { bufnr = buf_id, lnum = 3, col = 3 },
    { bufnr = buf_id, lnum = 4, col = 4 },
    { bufnr = buf_id, lnum = 5, col = 5 },
  })

  return child.fn.getqflist()
end

T['quickfix()']['works'] = function()
  local qf_list = setup_quickfix()
  local n = #qf_list
  local validate = function(id_start, direction, id_end, opts)
    set_quickfix(id_start)
    child.lua('MiniBracketed.quickfix(...)', { direction, opts })
    eq(get_quickfix(), id_end)
    eq(get_cursor(), { qf_list[id_end].lnum, qf_list[id_end].col - 1 })
  end

  -- Forward
  validate(1, 'forward', 2)
  validate(2, 'forward', 3)
  validate(n - 1, 'forward', n)
  validate(n, 'forward', 1)

  -- Backward
  validate(n, 'backward', n - 1)
  validate(n - 1, 'backward', n - 2)
  validate(2, 'backward', 1)
  validate(1, 'backward', n)

  -- First
  validate(n, 'first', 1)
  validate(2, 'first', 1)
  validate(1, 'first', 1)

  -- Last
  validate(1, 'last', n)
  validate(2, 'last', n)
  validate(n, 'last', n)
end

T['quickfix()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.quickfix(1)') end, 'quickfix%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.quickfix('next')]]) end, 'quickfix%(%).*direction.*one of')
end

T['quickfix()']['respects `opts.n_times`'] = function()
  local qf_list = setup_quickfix()
  local n = #qf_list
  local validate = function(id_start, direction, id_end, opts)
    set_quickfix(id_start)
    child.lua('MiniBracketed.quickfix(...)', { direction, opts })
    eq(get_quickfix(), id_end)
    eq(get_cursor(), { qf_list[id_end].lnum, qf_list[id_end].col - 1 })
  end

  -- Forward
  validate(1, 'forward', 3, { n_times = 2 })
  validate(n - 2, 'forward', n, { n_times = 2 })
  validate(n - 1, 'forward', 1, { n_times = 2 })

  -- Backward
  validate(n, 'backward', n - 2, { n_times = 2 })
  validate(3, 'backward', 1, { n_times = 2 })
  validate(2, 'backward', n, { n_times = 2 })

  -- First
  validate(n, 'first', 2, { n_times = 2 })
  validate(2, 'first', 2, { n_times = 2 })
  validate(1, 'first', 2, { n_times = 2 })

  -- Last
  validate(1, 'last', n - 1, { n_times = 2 })
  validate(n - 1, 'last', n - 1, { n_times = 2 })
  validate(n, 'last', n - 1, { n_times = 2 })
end

T['quickfix()']['respects `opts.wrap`'] = function()
  local qf_list = setup_quickfix()
  local n = #qf_list
  local validate = function(id_start, direction, id_end, opts)
    set_quickfix(id_start)
    child.lua('MiniBracketed.quickfix(...)', { direction, opts })
    eq(get_quickfix(), id_end)
    eq(get_cursor(), { qf_list[id_end].lnum, qf_list[id_end].col - 1 })
  end

  -- Forward
  validate(n, 'forward', n, { wrap = false })
  validate(n - 1, 'forward', n, { n_times = 1000, wrap = false })

  -- Backward
  validate(1, 'backward', 1, { wrap = false })
  validate(2, 'backward', 1, { n_times = 1000, wrap = false })

  -- First
  validate(1, 'first', n, { n_times = 1000, wrap = false })
  validate(n, 'first', n, { n_times = 1000, wrap = false })

  -- Last
  validate(n, 'last', 1, { n_times = 1000, wrap = false })
  validate(1, 'last', 1, { n_times = 1000, wrap = false })
end

T['quickfix()']['opens just enough folds and centers window'] = function()
  local qf_list = setup_quickfix()
  set_quickfix(3)

  child.set_size(5, 12)
  set_cursor(1, 0)
  type_keys('zt')

  eq(child.fn.line('w0'), 1)
  child.cmd('1,2 fold')
  eq({ child.fn.foldclosed(1), child.fn.foldclosed(2) }, { 1, 1 })
  child.cmd('4,5 fold')
  eq({ child.fn.foldclosed(4), child.fn.foldclosed(5) }, { 4, 4 })

  child.cmd([[silent lua MiniBracketed.quickfix('forward')]])
  eq(get_quickfix(), 4)
  eq(get_cursor(), { qf_list[4].lnum, qf_list[4].col - 1 })

  eq(child.fn.line('w0'), 3)
  eq({ child.fn.foldclosed(1), child.fn.foldclosed(2) }, { 1, 1 })
  eq({ child.fn.foldclosed(4), child.fn.foldclosed(5) }, { -1, -1 })
end

T['quickfix()']['can jump to current entry'] = function()
  local qf_list = setup_quickfix()
  set_quickfix(3)
  set_cursor(1, 0)

  forward('quickfix', { n_times = #qf_list })
  eq(get_quickfix(), 3)
  eq(get_cursor(), { qf_list[3].lnum, qf_list[3].col - 1 })
end

T['quickfix()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    setup_quickfix()
    set_quickfix(1)
    local cur_pos = get_cursor()

    child[var_type].minibracketed_disable = true
    forward('quickfix')
    eq(get_quickfix(), 1)
    eq(get_cursor(), cur_pos)
  end,
})

T['quickfix()']['respects `vim.b.minibracketed_config`'] = function()
  setup_quickfix()
  set_quickfix(1)
  local cur_pos = get_cursor()

  child.b.minibracketed_config = { quickfix = { options = { wrap = false } } }
  backward('quickfix')
  eq(get_quickfix(), 1)
  eq(get_cursor(), cur_pos)
end

T['window()'] = new_set()

local get_winnr = function() return child.fn.winnr() end
local set_winnr = function(x) return child.api.nvim_set_current_win(child.fn.win_getid(x)) end

local setup_windows = function()
  child.cmd('rightbelow vertical split')
  child.cmd('rightbelow split')
  child.cmd('rightbelow vertical split')
  child.cmd('rightbelow split')
  child.cmd('rightbelow split')

  -- Should traverse windows in order of their number (which is position
  -- specific, unlike id)
  local win_list = {}
  for i = 1, child.fn.winnr('$') do
    table.insert(win_list, i)
  end

  -- Should not matter what buffer is shown in window
  local win_2 = child.fn.win_getid(2)
  local buf_scratch = child.api.nvim_create_buf(false, true)
  child.api.nvim_win_set_buf(win_2, buf_scratch)

  -- Should ignore floating windows
  local buf_float = child.api.nvim_create_buf(true, false)
  child.api.nvim_open_win(buf_float, false, { relative = 'editor', width = 2, height = 2, row = 2, col = 2 })

  return win_list
end

T['window()']['works'] = function()
  local winnr_list = setup_windows()
  local n = #winnr_list
  local validate = function(id_start, direction, id_end, opts)
    set_winnr(winnr_list[id_start])
    child.lua('MiniBracketed.window(...)', { direction, opts })
    eq(get_winnr(), winnr_list[id_end])
  end

  -- Forward
  validate(1, 'forward', 2)
  validate(2, 'forward', 3)
  validate(n - 1, 'forward', n)
  validate(n, 'forward', 1)

  -- Backward
  validate(n, 'backward', n - 1)
  validate(n - 1, 'backward', n - 2)
  validate(2, 'backward', 1)
  validate(1, 'backward', n)

  -- First
  validate(n, 'first', 1)
  validate(2, 'first', 1)
  validate(1, 'first', 1)

  -- Last
  validate(1, 'last', n)
  validate(2, 'last', n)
  validate(n, 'last', n)
end

T['window()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.window(1)') end, 'window%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.window('next')]]) end, 'window%(%).*direction.*one of')
end

T['window()']['respects `opts.n_times`'] = function()
  local winnr_list = setup_windows()
  local n = #winnr_list
  local validate = function(id_start, direction, id_end, opts)
    set_winnr(winnr_list[id_start])
    child.lua('MiniBracketed.window(...)', { direction, opts })
    eq(get_winnr(), winnr_list[id_end])
  end

  -- Forward
  validate(1, 'forward', 3, { n_times = 2 })
  validate(n - 2, 'forward', n, { n_times = 2 })
  validate(n - 1, 'forward', 1, { n_times = 2 })

  -- Backward
  validate(n, 'backward', n - 2, { n_times = 2 })
  validate(3, 'backward', 1, { n_times = 2 })
  validate(2, 'backward', n, { n_times = 2 })

  -- First
  validate(n, 'first', 2, { n_times = 2 })
  validate(2, 'first', 2, { n_times = 2 })
  validate(1, 'first', 2, { n_times = 2 })

  -- Last
  validate(1, 'last', n - 1, { n_times = 2 })
  validate(n - 1, 'last', n - 1, { n_times = 2 })
  validate(n, 'last', n - 1, { n_times = 2 })
end

T['window()']['respects `opts.wrap`'] = function()
  local winnr_list = setup_windows()
  local n = #winnr_list
  local validate = function(id_start, direction, id_end, opts)
    set_winnr(winnr_list[id_start])
    child.lua('MiniBracketed.window(...)', { direction, opts })
    eq(get_winnr(), winnr_list[id_end])
  end

  -- Forward
  validate(n, 'forward', n, { wrap = false })
  validate(n - 1, 'forward', n, { n_times = 1000, wrap = false })

  -- Backward
  validate(1, 'backward', 1, { wrap = false })
  validate(2, 'backward', 1, { n_times = 1000, wrap = false })

  -- First
  validate(1, 'first', n, { n_times = 1000, wrap = false })
  validate(n, 'first', n, { n_times = 1000, wrap = false })

  -- Last
  validate(n, 'last', 1, { n_times = 1000, wrap = false })
  validate(1, 'last', 1, { n_times = 1000, wrap = false })
end

T['window()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    local winnr_list = setup_windows()

    set_winnr(winnr_list[1])
    child[var_type].minibracketed_disable = true
    forward('window')
    eq(get_winnr(), winnr_list[1])
  end,
})

T['window()']['respects `vim.b.minibracketed_config`'] = function()
  local winnr_list = setup_windows()

  set_winnr(winnr_list[1])
  child.b.minibracketed_config = { window = { options = { wrap = false } } }
  backward('window')
  eq(get_winnr(), winnr_list[1])
end

T['advance()'] = new_set()

T['advance()']['works'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
T['Mappings'] = new_set()

T['Mappings']['Buffer'] = new_set()

-- Should also test with `[count]`
T['Mappings']['Buffer']['works'] = function() MiniTest.skip() end

T['Mappings']['comment'] = new_set()

T['Mappings']['comment']['works'] = function() MiniTest.skip() end

T['Mappings']['conflict'] = new_set()

T['Mappings']['conflict']['works'] = function() MiniTest.skip() end

T['Mappings']['diagnostic'] = new_set()

T['Mappings']['diagnostic']['works'] = function() MiniTest.skip() end

T['Mappings']['file'] = new_set()

T['Mappings']['file']['works'] = function() MiniTest.skip() end

T['Mappings']['indent'] = new_set()

T['Mappings']['indent']['works'] = function() MiniTest.skip() end

T['Mappings']['jump'] = new_set()

T['Mappings']['jump']['works'] = function() MiniTest.skip() end

T['Mappings']['location'] = new_set()

T['Mappings']['location']['works'] = function() MiniTest.skip() end

T['Mappings']['oldfile'] = new_set()

T['Mappings']['oldfile']['works'] = function() MiniTest.skip() end

T['Mappings']['quickfix'] = new_set()

T['Mappings']['quickfix']['works'] = function() MiniTest.skip() end

T['Mappings']['window'] = new_set()

T['Mappings']['window']['works'] = function() MiniTest.skip() end

return T
