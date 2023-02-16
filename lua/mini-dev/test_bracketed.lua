local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local path_sep = package.config:sub(1, 1)
local project_root = vim.fn.fnamemodify(vim.fn.getcwd(), ':p')
local dir_bracketed_path = project_root .. 'tests/dir-bracketed/'

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('bracketed', config) end
local unload_module = function() child.mini_unload('bracketed') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local make_path = function(...) return table.concat({...}, path_sep):gsub(path_sep .. path_sep, path_sep) end
local make_testpath = function(...) return make_path(dir_bracketed_path, ...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

local edit_test_file = function(rel_path) child.cmd('edit ' .. make_testpath(rel_path)) end
local get_bufname = function(buf_id) return child.api.nvim_buf_get_name(buf_id or 0) end
local validate_test_file = function(rel_path) eq(get_bufname(), make_testpath(rel_path)) end

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

-- Data =======================================================================
local test_files = { 'file-a', 'file-b', 'file-c', 'file-d', 'file-e' }

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

  expect_config('undo.suffix', 'u')
  expect_config('undo.options', {})

  expect_config('window.suffix', 'w')
  expect_config('window.options', {})

  expect_config('yank.suffix', 'y')
  expect_config('yank.options', {})
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

  expect_config_error({ undo = 'a' }, 'undo', 'table')
  expect_config_error({ undo = { suffix = 1 } }, 'undo.suffix', 'string')
  expect_config_error({ undo = { options = 'a' } }, 'undo.options', 'table')

  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { suffix = 1 } }, 'window.suffix', 'string')
  expect_config_error({ window = { options = 'a' } }, 'window.options', 'table')

  expect_config_error({ yank = 'a' }, 'yank', 'table')
  expect_config_error({ yank = { suffix = 1 } }, 'yank.suffix', 'string')
  expect_config_error({ yank = { options = 'a' } }, 'yank.options', 'table')
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
  local validate = function(id_start, direction, id_ref, opts)
    set_buf(buf_list[id_start])
    child.lua('MiniBracketed.buffer(...)', { direction, opts })
    eq(get_buf(), buf_list[id_ref])
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
  local validate = function(id_start, direction, id_ref, opts)
    set_buf(buf_list[id_start])
    child.lua('MiniBracketed.buffer(...)', { direction, opts })
    eq(get_buf(), buf_list[id_ref])
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
  local validate = function(id_start, direction, id_ref, opts)
    set_buf(buf_list[id_start])
    child.lua('MiniBracketed.buffer(...)', { direction, opts })
    eq(get_buf(), buf_list[id_ref])
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

local validate_comment = function(line_start, direction, line_ref, opts)
  set_cursor(line_start, 0)
  child.lua('MiniBracketed.comment(...)', { direction, opts })
  eq(get_cursor(), { line_ref, 0 })
end

T['comment()']['works'] = function()
  child.o.commentstring = '## %s'
  local lines = { '1', '## 2', '3', '## 4', '5', '## 6', '7', '## 8', '9', '## 10', '11' }
  set_lines(lines)
  local line_ref

  -- Forward
  line_ref = { 2, 4, 4, 6, 6, 8, 8, 10, 10, 2, 2 }
  for i = 1, #lines do
    validate_comment(i, 'forward', line_ref[i])
  end

  -- Backward
  line_ref = { 10, 10, 2, 2, 4, 4, 6, 6, 8, 8, 10 }
  for i = 1, #lines do
    validate_comment(i, 'backward', line_ref[i])
  end

  -- First
  line_ref = { 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 }
  for i = 1, #lines do
    validate_comment(i, 'first', line_ref[i])
  end

  -- Last
  line_ref = { 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10 }
  for i = 1, #lines do
    validate_comment(i, 'last', line_ref[i])
  end
end

T['comment()']['works on first/last lines comments'] = function()
  child.o.commentstring = '## %s'
  local lines = { '## 1', '2', '## 3', '4', '## 5' }
  set_lines(lines)
  local line_ref

  -- Forward
  line_ref = { 3, 3, 5, 5, 1 }
  for i = 1, #lines do
    validate_comment(i, 'forward', line_ref[i])
  end

  -- Backward
  line_ref = { 5, 1, 1, 3, 3 }
  for i = 1, #lines do
    validate_comment(i, 'backward', line_ref[i])
  end

  -- First
  line_ref = { 1, 1, 1, 1, 1 }
  for i = 1, #lines do
    validate_comment(i, 'first', line_ref[i])
  end

  -- Last
  line_ref = { 5, 5, 5, 5, 5 }
  for i = 1, #lines do
    validate_comment(i, 'last', line_ref[i])
  end
end

T['comment()']['works whith one comment or less'] = function()
  child.o.commentstring = '## %s'
  local lines

  -- One comment
  lines = { '1', '## 2', '3' }
  set_lines(lines)

  for i = 1, #lines do
    validate_comment(i, 'forward', 2)
    validate_comment(i, 'backward', 2)
    validate_comment(i, 'first', 2)
    validate_comment(i, 'last', 2)
  end

  -- No comments. Should not move cursor at all
  set_lines({ '11', '22' })

  for _, dir in ipairs({ forward, backward, first, last }) do
    set_cursor(1, 1)
    dir('comment')
    eq(get_cursor(), { 1, 1 })
  end
end

T['comment()']['works when jumping to current line'] = function()
  child.o.commentstring = '## %s'
  local lines = { '1', '## 2', '3', '## 4', '5' }
  set_lines(lines)

  local validate = function(cursor, direction, opts)
    set_cursor(cursor[1], cursor[2])
    child.lua('MiniBracketed.comment(...)', { direction, opts })
    -- Should not move cursor at all
    eq(get_cursor(), cursor)
  end

  validate({ 2, 1 }, 'forward', { n_times = 2 })
  validate({ 2, 1 }, 'backward', { n_times = 2 })
  validate({ 2, 1 }, 'first', { n_times = 3 })
  validate({ 2, 1 }, 'last', { n_times = 2 })
end

T['comment()']['opens just enough folds'] = function()
  child.o.commentstring = '## %s'
  local lines = { '1', '## 2', '## 3', '4', '## 5', '## 6', '7' }
  set_lines(lines)
  set_cursor(1, 0)

  child.cmd('2,3 fold')
  eq({ child.fn.foldclosed(2), child.fn.foldclosed(3) }, { 2, 2 })
  child.cmd('5,6 fold')
  eq({ child.fn.foldclosed(5), child.fn.foldclosed(6) }, { 5, 5 })

  forward('comment')
  eq(get_cursor(), { 2, 0 })

  eq({ child.fn.foldclosed(2), child.fn.foldclosed(3) }, { -1, -1 })
  eq({ child.fn.foldclosed(5), child.fn.foldclosed(6) }, { 5, 5 })
end

T['comment()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.comment(1)') end, 'comment%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.comment('next')]]) end, 'comment%(%).*direction.*one of')
end

T['comment()']['respects `opts.block_side`'] = function()
  child.o.commentstring = '## %s'
  local lines = { '1', '## 2', '## 3', '## 4', '5', '6', '7', '## 8', '## 9', '## 10', '11' }
  set_lines(lines)
  local line_ref

  -- Default ('near')
  line_ref = { 2, 8, 8, 8, 8, 8, 8, 2, 2, 2, 2 }
  for i = 1, #lines do
    validate_comment(i, 'forward', line_ref[i])
    validate_comment(i, 'forward', line_ref[i], { block_side = 'near' })
  end

  line_ref = { 10, 10, 10, 10, 4, 4, 4, 4, 4, 4, 10 }
  for i = 1, #lines do
    validate_comment(i, 'backward', line_ref[i])
    validate_comment(i, 'backward', line_ref[i], { block_side = 'near' })
  end

  -- Start
  line_ref = { 2, 8, 8, 8, 8, 8, 8, 2, 2, 2, 2 }
  for i = 1, #lines do
    validate_comment(i, 'forward', line_ref[i], { block_side = 'start' })
  end

  line_ref = { 8, 8, 2, 2, 2, 2, 2, 2, 8, 8, 8 }
  for i = 1, #lines do
    validate_comment(i, 'backward', line_ref[i], { block_side = 'start' })
  end

  -- End
  line_ref = { 4, 4, 4, 10, 10, 10, 10, 10, 10, 4, 4 }
  for i = 1, #lines do
    validate_comment(i, 'forward', line_ref[i], { block_side = 'end' })
  end

  line_ref = { 10, 10, 10, 10, 4, 4, 4, 4, 4, 4, 10 }
  for i = 1, #lines do
    validate_comment(i, 'backward', line_ref[i], { block_side = 'end' })
  end

  -- Both
  line_ref = { 2, 4, 4, 8, 8, 8, 8, 10, 10, 2, 2 }
  for i = 1, #lines do
    validate_comment(i, 'forward', line_ref[i], { block_side = 'both' })
  end

  line_ref = { 10, 10, 2, 2, 4, 4, 4, 4, 8, 8, 10 }
  for i = 1, #lines do
    validate_comment(i, 'backward', line_ref[i], { block_side = 'both' })
  end
end

T['comment()']['respects `opts.n_times`'] = function()
  child.o.commentstring = '## %s'
  local lines = { '1', '## 2', '3', '## 4', '5', '## 6', '7', '## 8', '9' }
  set_lines(lines)
  local line_ref

  -- Forward
  line_ref = { 4, 6, 6, 8, 8, 2, 2, 4, 4 }
  for i = 1, #lines do
    validate_comment(i, 'forward', line_ref[i], { n_times = 2 })
  end

  -- Backward
  line_ref = { 6, 6, 8, 8, 2, 2, 4, 4, 6 }
  for i = 1, #lines do
    validate_comment(i, 'backward', line_ref[i], { n_times = 2 })
  end

  -- First
  line_ref = { 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4 }
  for i = 1, #lines do
    validate_comment(i, 'first', line_ref[i], { n_times = 2 })
  end

  -- Last
  line_ref = { 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6 }
  for i = 1, #lines do
    validate_comment(i, 'last', line_ref[i], { n_times = 2 })
  end
end

T['comment()']['respects `opts.wrap`'] = function()
  child.o.commentstring = '## %s'
  local lines = { '1', '## 2', '3', '## 4', '5', '## 6', '7', '## 8', '9' }
  set_lines(lines)

  -- Forward
  validate_comment(9, 'forward', 9, { wrap = false })
  validate_comment(8, 'forward', 8, { wrap = false })
  validate_comment(7, 'forward', 8, { n_times = 1000, wrap = false })

  -- Backward
  validate_comment(1, 'backward', 1, { wrap = false })
  validate_comment(2, 'backward', 2, { wrap = false })
  validate_comment(3, 'backward', 2, { n_times = 1000, wrap = false })

  -- First
  validate_comment(1, 'first', 8, { n_times = 1000, wrap = false })
  validate_comment(2, 'first', 8, { n_times = 1000, wrap = false })
  validate_comment(8, 'first', 8, { n_times = 1000, wrap = false })
  validate_comment(9, 'first', 8, { n_times = 1000, wrap = false })

  -- Backward
  validate_comment(1, 'last', 2, { n_times = 1000, wrap = false })
  validate_comment(2, 'last', 2, { n_times = 1000, wrap = false })
  validate_comment(8, 'last', 2, { n_times = 1000, wrap = false })
  validate_comment(9, 'last', 2, { n_times = 1000, wrap = false })
end

T['comment()']['correctly identifies comment'] = function()
  -- -- Uses 'commentstring'
  child.o.commentstring = '## %s //'
  set_lines({ '1', '## 2', '## 3 //', '4 //' })
  validate_comment(1, 'forward', 3)

  -- Handles empty comment line
  child.o.commentstring = '## %s //'
  set_lines({ '1', '##//', '3', '## //' })
  validate_comment(1, 'forward', 2)
  validate_comment(2, 'forward', 4)

  -- Trims whitespace form comment parts
  child.o.commentstring = '## %s'
  set_lines({ '1', '##2' })
  validate_comment(1, 'forward', 2)

  -- Escapes special characters in comment parts
  child.o.commentstring = '%. %s'
  set_lines({ '1', '%. 2' })
  validate_comment(1, 'forward', 2)
end

T['comment()']['works for indented comments'] = function()
  child.o.commentstring = '## %s'
  local lines = { '1', '  ## 2', '    ## 3', '    4', '    ## 5', '  ## 6', '7' }
  set_lines(lines)

  local validate = function(cur_start, direction, cur_ref, opts)
    set_cursor(cur_start[1], cur_start[2])
    child.lua('MiniBracketed.comment(...)', { direction, opts })
    eq(get_cursor(), cur_ref)
  end

  -- Should put cursor on first non-whitespace character
  validate({ 1, 0 }, 'forward', { 2, 2 })
  validate({ 2, 5 }, 'forward', { 5, 4 })

  validate({ 7, 0 }, 'backward', { 6, 2 })
  validate({ 6, 5 }, 'backward', { 3, 4 })
end

T['comment()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child.o.commentstring = '## %s'
    set_lines({ '1', '# 2' })
    set_cursor(1, 0)

    child[var_type].minibracketed_disable = true
    forward('comment')
    eq(get_cursor(), { 1, 0 })
  end,
})

T['comment()']['respects `vim.b.minibracketed_config`'] = function()
  child.o.commentstring = '## %s'
  set_lines({ '1', '# 2', '3', '# 4', '5' })

  child.b.minibracketed_config = { comment = { options = { wrap = false } } }
  validate_comment(4, 'forward', 4)
end

T['conflict()'] = new_set()

local validate_conflict = function(line_start, direction, line_ref, opts)
  set_cursor(line_start, 0)
  child.lua('MiniBracketed.conflict(...)', { direction, opts })
  eq(get_cursor(), { line_ref, 0 })
end

local conflict_marks = { '<<<<<<< ', '=======', '>>>>>>> ' }

T['conflict()']['works'] = function()
  local m = conflict_marks
  local lines = { '1', m[1], m[2], m[3], '5', m[3], m[2], m[1], '9' }
  set_lines(lines)
  local line_ref

  -- Forward
  line_ref = { 2, 3, 4, 6, 6, 7, 8, 2, 2 }
  for i = 1, #lines do
    validate_conflict(i, 'forward', line_ref[i])
  end

  -- Backward
  line_ref = { 8, 8, 2, 3, 4, 4, 6, 7, 8 }
  for i = 1, #lines do
    validate_conflict(i, 'backward', line_ref[i])
  end

  -- First
  line_ref = { 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 }
  for i = 1, #lines do
    validate_conflict(i, 'first', line_ref[i])
  end

  -- Last
  line_ref = { 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8 }
  for i = 1, #lines do
    validate_conflict(i, 'last', line_ref[i])
  end
end

T['conflict()']['works on first/last lines conflicts'] = function()
  local m = conflict_marks
  local lines = { m[1], m[2], m[3] }
  set_lines(lines)
  local line_ref

  -- Forward
  line_ref = { 2, 3, 1 }
  for i = 1, #lines do
    validate_conflict(i, 'forward', line_ref[i])
  end

  -- Backward
  line_ref = { 3, 1, 2 }
  for i = 1, #lines do
    validate_conflict(i, 'backward', line_ref[i])
  end

  -- First
  line_ref = { 1, 1, 1 }
  for i = 1, #lines do
    validate_conflict(i, 'first', line_ref[i])
  end

  -- Last
  line_ref = { 3, 3, 3 }
  for i = 1, #lines do
    validate_conflict(i, 'last', line_ref[i])
  end
end

T['conflict()']['works whith one conflict or less'] = function()
  local m = conflict_marks
  local lines

  -- One conflict
  lines = { '1', m[1], '3' }
  set_lines(lines)

  for i = 1, #lines do
    validate_conflict(i, 'forward', 2)
    validate_conflict(i, 'backward', 2)
    validate_conflict(i, 'first', 2)
    validate_conflict(i, 'last', 2)
  end

  -- No conflicts. Should not move cursor at all
  set_lines({ '11', '22' })

  for _, dir in ipairs({ forward, backward, first, last }) do
    set_cursor(1, 1)
    dir('conflict')
    eq(get_cursor(), { 1, 1 })
  end
end

T['conflict()']['works when jumping to current line'] = function()
  local m = conflict_marks
  local lines = { '1', m[1], '3', m[2], '5' }
  set_lines(lines)

  local validate = function(cursor, direction, opts)
    set_cursor(cursor[1], cursor[2])
    child.lua('MiniBracketed.conflict(...)', { direction, opts })
    -- Should not move cursor at all
    eq(get_cursor(), cursor)
  end

  validate({ 2, 1 }, 'forward', { n_times = 2 })
  validate({ 2, 1 }, 'backward', { n_times = 2 })
  validate({ 2, 1 }, 'first', { n_times = 3 })
  validate({ 2, 1 }, 'last', { n_times = 2 })
end

T['conflict()']['opens just enough folds'] = function()
  local m = conflict_marks
  local lines = { '1', m[1], m[2], '4', m[3], m[1], '7' }
  set_lines(lines)
  set_cursor(1, 0)

  child.cmd('2,3 fold')
  eq({ child.fn.foldclosed(2), child.fn.foldclosed(3) }, { 2, 2 })
  child.cmd('5,6 fold')
  eq({ child.fn.foldclosed(5), child.fn.foldclosed(6) }, { 5, 5 })

  forward('conflict')
  eq(get_cursor(), { 2, 0 })

  eq({ child.fn.foldclosed(2), child.fn.foldclosed(3) }, { -1, -1 })
  eq({ child.fn.foldclosed(5), child.fn.foldclosed(6) }, { 5, 5 })
end

T['conflict()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.conflict(1)') end, 'conflict%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.conflict('next')]]) end, 'conflict%(%).*direction.*one of')
end

T['conflict()']['respects `opts.n_times`'] = function()
  local m = conflict_marks
  local lines = { '1', m[1], '3', m[2], '5', m[3], '7', m[1], '9' }
  set_lines(lines)
  local line_ref

  -- Forward
  line_ref = { 4, 6, 6, 8, 8, 2, 2, 4, 4 }
  for i = 1, #lines do
    validate_conflict(i, 'forward', line_ref[i], { n_times = 2 })
  end

  -- Backward
  line_ref = { 6, 6, 8, 8, 2, 2, 4, 4, 6 }
  for i = 1, #lines do
    validate_conflict(i, 'backward', line_ref[i], { n_times = 2 })
  end

  -- First
  line_ref = { 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4 }
  for i = 1, #lines do
    validate_conflict(i, 'first', line_ref[i], { n_times = 2 })
  end

  -- Last
  line_ref = { 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6 }
  for i = 1, #lines do
    validate_conflict(i, 'last', line_ref[i], { n_times = 2 })
  end
end

T['conflict()']['respects `opts.wrap`'] = function()
  local m = conflict_marks
  local lines = { '1', m[1], '3', m[2], '5', m[3], '7', m[1], '9' }
  set_lines(lines)

  -- Forward
  validate_conflict(9, 'forward', 9, { wrap = false })
  validate_conflict(8, 'forward', 8, { wrap = false })
  validate_conflict(7, 'forward', 8, { n_times = 1000, wrap = false })

  -- Backward
  validate_conflict(1, 'backward', 1, { wrap = false })
  validate_conflict(2, 'backward', 2, { wrap = false })
  validate_conflict(3, 'backward', 2, { n_times = 1000, wrap = false })

  -- First
  validate_conflict(1, 'first', 8, { n_times = 1000, wrap = false })
  validate_conflict(2, 'first', 8, { n_times = 1000, wrap = false })
  validate_conflict(8, 'first', 8, { n_times = 1000, wrap = false })
  validate_conflict(9, 'first', 8, { n_times = 1000, wrap = false })

  -- Backward
  validate_conflict(1, 'last', 2, { n_times = 1000, wrap = false })
  validate_conflict(2, 'last', 2, { n_times = 1000, wrap = false })
  validate_conflict(8, 'last', 2, { n_times = 1000, wrap = false })
  validate_conflict(9, 'last', 2, { n_times = 1000, wrap = false })
end

T['conflict()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    set_lines({ '1', conflict_marks[1] })
    set_cursor(1, 0)

    child[var_type].minibracketed_disable = true
    forward('conflict')
    eq(get_cursor(), { 1, 0 })
  end,
})

T['conflict()']['respects `vim.b.minibracketed_config`'] = function()
  local m = conflict_marks
  set_lines({ '1', m[1], '3', m[2], '5' })

  child.b.minibracketed_config = { conflict = { options = { wrap = false } } }
  validate_conflict(4, 'forward', 4)
end

T['diagnostic()'] = new_set()

local setup_diagnostic = function()
  local mock_data = dofile(make_testpath('mock/diagnostic.lua'))
  set_lines(mock_data.lines)

  local ns = child.api.nvim_create_namespace('mock-diagnostics')

  child.diagnostic.set(ns, 0, mock_data.diagnostic_arr, {})

  return mock_data.cursor_positions
end

T['diagnostic()']['works'] = function()
  local cur_pos_tbl = setup_diagnostic()
  local all = cur_pos_tbl.all
  local n = #all

  local validate = function(pos_before, direction, id_ref)
    set_cursor(unpack(pos_before))
    child.lua('MiniBracketed.diagnostic(...)', { direction })
    eq(get_cursor(), all[id_ref])
  end

  -- Jumping from diagnostic itself
  for i = 1, n do
    validate(all[i], 'forward', i % n + 1)
    validate(all[i], 'backward', (i - 2) % n + 1)
    validate(all[i], 'first', 1)
    validate(all[i], 'last', n)
  end

  -- Jumping near diagnostic
  local second_pos = all[2]
  validate({ second_pos[1], second_pos[2] - 1 }, 'forward', 2)
  validate({ second_pos[1], second_pos[2] - 1 }, 'backward', 1)
end

T['diagnostic()']['works on first/last diagnostic'] = function()
  set_lines('E   E')
  local sev_err = vim.diagnostic.severity.ERROR
  local diagnostic_arr = {
    { lnum = 0, end_lnum = 0, col = 0, end_col = 1, message = 'Error 1', severity = sev_err },
    { lnum = 0, end_lnum = 0, col = 4, end_col = 5, message = 'Error 2', severity = sev_err },
  }
  local ns = child.api.nvim_create_namespace('mock-edge-diagnostics')
  child.diagnostic.set(ns, 0, diagnostic_arr, {})

  local positions = { { 1, 0 }, { 1, 4 } }

  local validate = function(pos_before, direction, id_ref, opts)
    set_cursor(unpack(pos_before))
    child.lua('MiniBracketed.diagnostic(...)', { direction, opts })
    eq(get_cursor(), positions[id_ref])
  end

  validate({ 1, 2 }, 'forward', 2)
  validate({ 1, 2 }, 'forward', 1, { n_times = 2 })

  validate({ 1, 2 }, 'backward', 1)
  validate({ 1, 2 }, 'backward', 2, { n_times = 2 })

  validate({ 1, 2 }, 'first', 1)
  validate({ 1, 2 }, 'first', 2, { n_times = 2 })

  validate({ 1, 2 }, 'last', 2)
  validate({ 1, 2 }, 'last', 1, { n_times = 2 })
end

T['diagnostic()']['works whith one diagnostic or less'] = function()
  -- No diagnostic. Should not move cursor.
  set_lines({ 'aaa', 'Error', 'aaa' })

  for _, dir in ipairs({ forward, backward, first, last }) do
    set_cursor(1, 2)
    dir('diagnostic')
    eq(get_cursor(), { 1, 2 })
  end

  -- One diagnostic
  local sev_err = vim.diagnostic.severity.ERROR
  local diagnostic_arr = {
    { lnum = 1, end_lnum = 1, col = 0, end_col = 5, message = 'Error 1', severity = sev_err },
  }
  local ns = child.api.nvim_create_namespace('mock-single-diagnostics')
  child.diagnostic.set(ns, 0, diagnostic_arr, {})

  for _, dir in ipairs({ forward, backward, first, last }) do
    set_cursor(1, 2)
    dir('diagnostic')
    eq(get_cursor(), { 2, 0 })
  end
end

T['diagnostic()']['opens just enough folds'] = function()
  local cur_pos_tbl = setup_diagnostic()
  local all = cur_pos_tbl.all

  set_cursor(3, 0)
  child.cmd('1,2 fold')
  eq({ child.fn.foldclosed(1), child.fn.foldclosed(2) }, { 1, 1 })
  child.cmd('5,6 fold')
  eq({ child.fn.foldclosed(5), child.fn.foldclosed(6) }, { 5, 5 })

  last('diagnostic')
  eq(get_cursor(), all[#all])

  eq({ child.fn.foldclosed(1), child.fn.foldclosed(2) }, { 1, 1 })
  eq({ child.fn.foldclosed(5), child.fn.foldclosed(6) }, { -1, -1 })
end

T['diagnostic()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.diagnostic(1)') end, 'diagnostic%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.diagnostic('next')]]) end, 'diagnostic%(%).*direction.*one of')
end

T['diagnostic()']['respects `opts.n_times`'] = function()
  local cur_pos_tbl = setup_diagnostic()
  local all = cur_pos_tbl.all
  local n = #all

  local validate = function(id_before, direction, id_ref, opts)
    set_cursor(unpack(all[id_before]))
    child.lua('MiniBracketed.diagnostic(...)', { direction, opts })
    eq(get_cursor(), all[id_ref])
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

local severity_tbl = vim.diagnostic.severity

T['diagnostic()']['respects `opts.severity`'] = new_set({
  parametrize = {
    { 'error', severity_tbl.ERROR },
    { 'warning', severity_tbl.WARN },
    { 'info', severity_tbl.INFO },
    { 'hint', severity_tbl.HINT },
    { 'error_warning', { min = severity_tbl.WARN } },
  },
}, {
  test = function(position_key, severity)
    local cur_pos_tbl = setup_diagnostic()
    local positions = cur_pos_tbl[position_key]
    local n = #positions

    local validate = function(id_before, direction, id_ref)
      set_cursor(unpack(positions[id_before]))
      child.lua('MiniBracketed.diagnostic(...)', { direction, { severity = severity } })
      eq(get_cursor(), positions[id_ref])
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
  end,
})

T['diagnostic()']['respects `opts.wrap`'] = function()
  local cur_pos_tbl = setup_diagnostic()
  local all = cur_pos_tbl.all
  local n = #all

  local validate = function(id_before, direction, id_ref, opts)
    set_cursor(unpack(all[id_before]))
    child.lua('MiniBracketed.diagnostic(...)', { direction, opts })
    eq(get_cursor(), all[id_ref])
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

T['diagnostic()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    setup_diagnostic()
    set_cursor(2, 0)

    child[var_type].minibracketed_disable = true
    forward('diagnostic')
    eq(get_cursor(), { 2, 0 })
  end,
})

T['diagnostic()']['respects `vim.b.minibracketed_config`'] = function()
  setup_diagnostic()
  set_cursor(1, 0)

  child.b.minibracketed_config = { diagnostic = { options = { wrap = false } } }
  backward('diagnostic')
  eq(get_cursor(), { 1, 0 })
end

T['file()'] = new_set()

local validate_file = function(id_start, direction, id_ref, opts)
  edit_test_file(test_files[id_start])
  child.lua('MiniBracketed.file(...)', { direction, opts })
  validate_test_file(test_files[id_ref])
end

T['file()']['works'] = function()
  eq(child.fn.getcwd() .. '/', project_root)

  -- Should traverse files alphabetically in directory of currently opened file
  local n = #test_files

  -- Forward
  validate_file(1, 'forward', 2)
  validate_file(2, 'forward', 3)
  validate_file(n - 1, 'forward', n)
  validate_file(n, 'forward', 1)

  -- Backward
  validate_file(n, 'backward', n - 1)
  validate_file(n - 1, 'backward', n - 2)
  validate_file(2, 'backward', 1)
  validate_file(1, 'backward', n)

  -- First
  validate_file(n, 'first', 1)
  validate_file(2, 'first', 1)
  validate_file(1, 'first', 1)

  -- Last
  validate_file(1, 'last', n)
  validate_file(2, 'last', n)
  validate_file(n, 'last', n)
end

T['file()']['reuses buffer if file is already opened'] = function()
  edit_test_file('file-a')
  local buf_a = child.api.nvim_get_current_buf()
  edit_test_file('file-b')
  eq(#child.api.nvim_list_bufs(), 2)

  backward('file')
  validate_test_file('file-a')
  eq(child.api.nvim_get_current_buf(), buf_a)
end

T['file()']['works with non-file current buffer'] = function()
  -- Should select first (for 'forward') or last (for 'backward') file in
  -- current working directory
  child.fn.chdir(dir_bracketed_path)

  local buf_id_nonfile = child.api.nvim_get_current_buf()
  eq(child.api.nvim_buf_get_name(0), '')

  forward('file')
  validate_test_file('file-a')

  child.api.nvim_set_current_buf(buf_id_nonfile)
  backward('file')
  validate_test_file('file-e')
end

T['file()']['does not traverses subdirectories'] = function()
  edit_test_file('file-a')
  validate_test_file('file-a')

  forward('file')
  validate_test_file('file-b')

  forward('file')
  validate_test_file('file-c')

  forward('file')
  validate_test_file('file-d')

  forward('file')
  validate_test_file('file-e')

  forward('file')
  validate_test_file('file-a')
end

T['file()']['works for empty directory'] = function()
  local empty_dir_path = make_testpath('dir-empty')
  child.fn.mkdir(empty_dir_path, 'p')
  MiniTest.finally(function() child.fn.delete(empty_dir_path, 'rf') end)

  child.fn.chdir(empty_dir_path)

  local buf_id = child.api.nvim_get_current_buf()
  eq(child.api.nvim_buf_get_name(buf_id), '')

  forward('file')
  eq(child.api.nvim_get_current_buf(), buf_id)
  eq(child.api.nvim_buf_get_name(buf_id), '')
end

T['file()']['works when jumping to current file'] = function()
  local n = #test_files

  edit_test_file('file-a')
  set_lines('This is unsaved change making buffer modified.')
  eq(child.bo.modified, true)

  -- Should not call `:edit`, as it causes flicker
  forward('file', { n_times = n })
  validate_test_file('file-a')
  -- If it called `:edit`, there would be an error message
  eq(child.cmd_capture('1messages'), '')
end

T['file()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.file(1)') end, 'file%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.file('next')]]) end, 'file%(%).*direction.*one of')
end

T['file()']['respects `opts.n_times`'] = function()
  local n = #test_files

  -- Forward
  validate_file(1, 'forward', 3, { n_times = 2 })
  validate_file(n - 2, 'forward', n, { n_times = 2 })
  validate_file(n - 1, 'forward', 1, { n_times = 2 })

  -- Backward
  validate_file(n, 'backward', n - 2, { n_times = 2 })
  validate_file(3, 'backward', 1, { n_times = 2 })
  validate_file(2, 'backward', n, { n_times = 2 })

  -- First
  validate_file(n, 'first', 2, { n_times = 2 })
  validate_file(2, 'first', 2, { n_times = 2 })
  validate_file(1, 'first', 2, { n_times = 2 })

  -- Last
  validate_file(1, 'last', n - 1, { n_times = 2 })
  validate_file(n - 1, 'last', n - 1, { n_times = 2 })
  validate_file(n, 'last', n - 1, { n_times = 2 })
end

T['file()']['respects `opts.wrap`'] = function()
  local n = #test_files

  -- Forward
  validate_file(n, 'forward', n, { wrap = false })
  validate_file(n - 1, 'forward', n, { n_times = 1000, wrap = false })

  -- Backward
  validate_file(1, 'backward', 1, { wrap = false })
  validate_file(2, 'backward', 1, { n_times = 1000, wrap = false })

  -- First
  validate_file(1, 'first', n, { n_times = 1000, wrap = false })
  validate_file(n, 'first', n, { n_times = 1000, wrap = false })

  -- Last
  validate_file(n, 'last', 1, { n_times = 1000, wrap = false })
  validate_file(1, 'last', 1, { n_times = 1000, wrap = false })
end

T['file()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    edit_test_file('file-a')

    child[var_type].minibracketed_disable = true
    forward('file')
    validate_test_file('file-a')
  end,
})

T['file()']['respects `vim.b.minibracketed_config`'] = function()
  edit_test_file('file-a')

  child.b.minibracketed_config = { file = { options = { wrap = false } } }
  backward('file')
  validate_test_file('file-a')
end

T['indent()'] = new_set()

local validate_indent = function(line_start, direction, line_ref, opts)
  local col_start = math.max(child.fn.getline(line_start):len() - 1, 0)
  set_cursor(line_start, col_start)
  child.lua('MiniBracketed.indent(...)', { direction, opts })

  -- Should put cursor on first non-blank character
  eq(get_cursor(), { line_ref, child.fn.indent(line_ref) })
end

T['indent()']['works'] = function()
  local lines = { '1', ' 2', '3', ' 4', '  5', ' 6', '7', ' 8', '9' }
  set_lines(lines)
  local line_ref

  -- Forward. By default moves to next line with strictly less indent.
  line_ref = { 1, 3, 3, 7, 6, 7, 7, 9, 9 }
  for i = 1, #lines do
    validate_indent(i, 'forward', line_ref[i])
  end

  -- Backward. By default moves to previous line with strictly less indent.
  line_ref = { 1, 1, 3, 3, 4, 3, 7, 7, 9 }
  for i = 1, #lines do
    validate_indent(i, 'backward', line_ref[i])
  end

  -- First. By default moves to a nearest line above with the smallest indent.
  line_ref = { 1, 1, 3, 3, 3, 3, 7, 7, 9 }
  for i = 1, #lines do
    validate_indent(i, 'first', line_ref[i])
  end

  -- Last. By default moves to a nearest line below with the smallest indent.
  line_ref = { 1, 3, 3, 7, 7, 7, 7, 9, 9 }
  for i = 1, #lines do
    validate_indent(i, 'last', line_ref[i])
  end
end

T['indent()']['works with minimum indent more than 1'] = function()
  set_lines({ ' 1', ' 2', '  3', '4' })
  validate_indent(3, 'first', 2)

  set_lines({ '1', '  2', ' 3', ' 4' })
  validate_indent(2, 'last', 3)
end

T['indent()']['ignores blank/empty lines'] = function()
  local lines = { '1', ' 2', '', ' ', '  5', ' ', '', ' 8', '9' }
  set_lines(lines)

  validate_indent(5, 'forward', 8)
  validate_indent(5, 'backward', 2)
  validate_indent(5, 'first', 1)
  validate_indent(5, 'last', 9)
end

T['indent()']['works when no jump target found'] = function()
  local lines = { '11', ' 22', '33', ' 44', '55' }
  set_lines(lines)

  local validate = function(cursor, direction, opts)
    set_cursor(cursor[1], cursor[2])
    child.lua('MiniBracketed.indent(...)', { direction, opts })
    -- Should not move cursor at all
    eq(get_cursor(), cursor)
  end

  validate({ 3, 1 }, 'forward')
  validate({ 3, 1 }, 'backward')
  validate({ 3, 1 }, 'first')
  validate({ 3, 1 }, 'last')

  validate({ 2, 2 }, 'forward', { change_type = 'more' })
  validate({ 2, 2 }, 'backward', { change_type = 'more' })
  validate({ 2, 2 }, 'first', { change_type = 'more' })
  validate({ 2, 2 }, 'last', { change_type = 'more' })

  validate({ 5, 1 }, 'forward', { change_type = 'diff' })
  validate({ 1, 1 }, 'backward', { change_type = 'diff' })
  validate({ 1, 1 }, 'first', { change_type = 'diff' })
  validate({ 5, 1 }, 'last', { change_type = 'diff' })
end

T['indent()']['opens just enough folds'] = function()
  local lines = { '1', ' 2', '3', '4', ' 5', '6', '7' }
  set_lines(lines)
  set_cursor(2, 0)

  child.cmd('3,4 fold')
  eq({ child.fn.foldclosed(3), child.fn.foldclosed(4) }, { 3, 3 })
  child.cmd('6,7 fold')
  eq({ child.fn.foldclosed(6), child.fn.foldclosed(7) }, { 6, 6 })

  forward('indent')
  eq(get_cursor(), { 3, 0 })

  eq({ child.fn.foldclosed(3), child.fn.foldclosed(4) }, { -1, -1 })
  eq({ child.fn.foldclosed(6), child.fn.foldclosed(7) }, { 6, 6 })
end

T['indent()']['works in edge cases'] = function()
  -- All lines are empty/blank
  set_lines({ '', ' ', '  ', '', '\t\t' })

  local validate = function(cursor, direction, opts)
    set_cursor(cursor[1], cursor[2])
    child.lua('MiniBracketed.indent(...)', { direction, opts })
    -- Should not move cursor at all
    eq(get_cursor(), cursor)
  end

  validate({ 3, 1 }, 'forward')
  validate({ 3, 1 }, 'backward')
  validate({ 3, 1 }, 'first')
  validate({ 3, 1 }, 'last')
end

T['indent()']['works when starting in empty/blank line'] = new_set({ parametrize = { { '' }, { ' ' } } }, {
  test = function(init_line)
    -- Should take indent from line in a search direction
    set_lines({ ' 1', init_line, '   3', '  2', '5' })
    validate_indent(3, 'forward', 4)

    set_lines({ '1', '  2', '   3', init_line, ' 5' })
    validate_indent(3, 'backward', 2)

    set_lines({ '1', ' 2', init_line, ' 4', '5' })
    validate_indent(3, 'first', 1)
    validate_indent(3, 'last', 5)
  end,
})

T['indent()']['does not depend on cursor position when computing indent'] = function()
  local validate = function(pos_start, direction, pos_ref, opts)
    set_cursor(pos_start[1], pos_start[2])
    child.lua('MiniBracketed.indent(...)', { direction, opts })
    eq(get_cursor(), pos_ref)
  end

  set_lines({ '1', ' 2', '  3', ' 4', '5' })

  for col = 0, 2 do
    validate({ 3, col }, 'forward', { 4, 1 })
    validate({ 3, col }, 'backward', { 2, 1 })
    validate({ 3, col }, 'first', { 1, 0 })
    validate({ 3, col }, 'last', { 5, 0 })
  end
end

T['indent()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.indent(1)') end, 'indent%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.indent('next')]]) end, 'indent%(%).*direction.*one of')
end

T['indent()']['respects `opts.change_type`'] = function()
  local lines, line_ref

  -- 'more'
  lines = { '1', ' 2', '3', ' 4', '  5', ' 6', '7', ' 8', '9' }
  set_lines(lines)

  -- - Forward
  line_ref = { 2, 5, 4, 5, 5, 6, 8, 8, 9 }
  for i = 1, #lines do
    validate_indent(i, 'forward', line_ref[i], { change_type = 'more' })
  end

  -- - Backward
  line_ref = { 1, 2, 2, 4, 5, 5, 6, 5, 8 }
  for i = 1, #lines do
    validate_indent(i, 'backward', line_ref[i], { change_type = 'more' })
  end

  -- - First (nearest biggest indent above)
  line_ref = { 1, 2, 2, 4, 5, 5, 5, 5, 5 }
  for i = 1, #lines do
    validate_indent(i, 'first', line_ref[i], { change_type = 'more' })
  end

  -- - Last (nearest biggest indent below)
  line_ref = { 5, 5, 5, 5, 5, 6, 8, 8, 9 }
  for i = 1, #lines do
    validate_indent(i, 'last', line_ref[i], { change_type = 'more' })
  end

  -- 'diff'
  lines = { '1', '2', '3', ' 4', ' 5', ' 6', '  7', '8', '9' }
  set_lines(lines)

  -- - Forward
  line_ref = { 4, 4, 4, 7, 7, 7, 8, 8, 9 }
  for i = 1, #lines do
    validate_indent(i, 'forward', line_ref[i], { change_type = 'diff' })
  end

  -- - Backward
  line_ref = { 1, 2, 3, 3, 3, 3, 6, 7, 7 }
  for i = 1, #lines do
    validate_indent(i, 'backward', line_ref[i], { change_type = 'diff' })
  end

  -- - First (last change above)
  line_ref = { 1, 2, 3, 3, 3, 3, 3, 3, 3 }
  for i = 1, #lines do
    validate_indent(i, 'first', line_ref[i], { change_type = 'diff' })
  end

  -- - Last (last change below)
  line_ref = { 8, 8, 8, 8, 8, 8, 8, 8, 9 }
  for i = 1, #lines do
    validate_indent(i, 'last', line_ref[i], { change_type = 'diff' })
  end
end

T['indent()']['respects `opts.n_times`'] = function()
  set_lines({ '1', '2', ' 3', '  4', ' 5', '6', '7' })

  -- Change type 'less' (default)
  validate_indent(4, 'forward', 6, { n_times = 2 })
  validate_indent(4, 'backward', 2, { n_times = 2 })
  -- - Ideally, it should be 3 and 5 (as if counting from first forward and
  --   last backward), but it would mean worse performance, because first and
  --   last indents should have been precomputed.
  validate_indent(4, 'first', 2, { n_times = 2 })
  validate_indent(4, 'last', 6, { n_times = 2 })

  -- Change type 'more'
  validate_indent(2, 'forward', 4, { change_type = 'more', n_times = 2 })
  validate_indent(6, 'backward', 4, { change_type = 'more', n_times = 2 })
  -- - Again, should have been 5 and 3
  validate_indent(6, 'first', 4, { change_type = 'more', n_times = 2 })
  validate_indent(2, 'last', 4, { change_type = 'more', n_times = 2 })

  -- Change type 'diff'
  validate_indent(3, 'forward', 5, { change_type = 'diff', n_times = 2 })
  validate_indent(5, 'backward', 3, { change_type = 'diff', n_times = 2 })
  -- - Again, should have been 3 and 5
  validate_indent(6, 'first', 2, { change_type = 'diff', n_times = 2 })
  validate_indent(2, 'last', 6, { change_type = 'diff', n_times = 2 })

  -- Allows "early stop" with very big `n_times`
  validate_indent(4, 'forward', 6, { n_times = 100 })
  validate_indent(4, 'backward', 2, { n_times = 100 })
  validate_indent(4, 'first', 2, { n_times = 100 })
  validate_indent(4, 'last', 6, { n_times = 100 })
end

T['indent()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    set_lines({ '1', ' 2', '3' })
    set_cursor(2, 1)

    child[var_type].minibracketed_disable = true
    forward('indent')
    eq(get_cursor(), { 2, 1 })
  end,
})

T['indent()']['respects `vim.b.minibracketed_config`'] = function()
  set_lines({ ' 1', '  2', '3' })
  set_cursor(1, 1)

  child.b.minibracketed_config = { indent = { options = { change_type = 'more' } } }
  forward('indent')
  eq(get_cursor(), { 2, 2 })
end

T['jump()'] = new_set()

local get_jump_num = function() return child.fn.getjumplist()[2] + 1 end
local set_jump_num = function(x)
  local jump_list, cur_jump_num = unpack(child.fn.getjumplist())
  cur_jump_num = cur_jump_num + 1

  local num_diff = x - cur_jump_num
  if num_diff == 0 then
    local jump_entry = jump_list[x]
    pcall(child.fn.cursor, { jump_entry.lnum, jump_entry.col + 1, jump_entry.coladd })
  else
    -- Use builtin mappings to also update current jump entry
    local key = num_diff > 0 and '<C-i>' or '<C-o>'
    type_keys(math.abs(num_diff) .. key)
  end
end

local setup_jumplist = function()
  -- Set up buffers with text
  local buf_1 = child.api.nvim_get_current_buf()
  child.api.nvim_buf_set_lines(buf_1, 0, -1, true, { 'aa', '1aa', 'a2a', 'aa3', 'a4a', '5aa' })

  local buf_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_2, 0, -1, true, { 'aa', '1aa', 'a2a' })

  -- Creat jump list for two buffers
  child.cmd('clearjumps')
  child.fn.setreg('/', [[\d\+]])
  -- - Start with last wanted jump location. It will be added as first jumplist
  --   entry. At the end, put cursor on it again, move back in jumplist in
  --   order to add it to end of jump list (thus removing from first entry).
  set_cursor(6, 0)
  type_keys('n', 'n', 'n')

  child.api.nvim_set_current_buf(buf_2)
  type_keys('n')

  child.api.nvim_set_current_buf(buf_1)
  type_keys('n')

  child.api.nvim_set_current_buf(buf_2)
  type_keys('n')

  child.api.nvim_set_current_buf(buf_1)
  type_keys('n')

  -- - Add current cursor position to the end of jumplist
  eq(get_cursor(), { 6, 0 })
  type_keys('<C-o>')
  type_keys('<C-i>')

  -- Create separate reference jumplist indexes for two buffers
  local jump_list = child.fn.getjumplist()[1]
  local buf_1_list, buf_2_list = {}, {}
  for i, entry in ipairs(jump_list) do
    local list = entry.bufnr == buf_1 and buf_1_list or buf_2_list
    table.insert(list, i)
  end

  return jump_list, { cur = buf_1_list, other = buf_2_list }
end

T['jump()']['works'] = function()
  local jump_list, jump_num_per_buf = setup_jumplist()
  local cur_jump_inds = jump_num_per_buf.cur
  local n = #cur_jump_inds

  -- Should jump only inside current buffer. This is checked with by using jump
  -- numbers referring only to current buffer.
  local validate = function(id_start, direction, id_ref, opts)
    local s, e = cur_jump_inds[id_start], cur_jump_inds[id_ref]

    set_jump_num(s)
    child.lua('MiniBracketed.jump(...)', { direction, opts })
    eq(get_jump_num(), e)
    eq(get_cursor(), { jump_list[e].lnum, jump_list[e].col })
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

T['jump()']['works when currently moved after latest jump'] = function()
  local jump_list, jump_num_per_buf = setup_jumplist()
  local cur_jump_inds = jump_num_per_buf.cur
  local n = #cur_jump_inds

  set_cursor(1, 0)
  last('jump')
  eq(get_jump_num(), cur_jump_inds[n])
  local last_entry = jump_list[cur_jump_inds[n]]
  eq(get_cursor(), { last_entry.lnum, last_entry.col })
end

T['jump()']['works when current jump number is outside of jumplist'] = function()
  local jump_list, jump_num_per_buf = setup_jumplist()
  local cur_jump_inds = jump_num_per_buf.cur
  local n = #cur_jump_inds

  -- This should increase current jump number by one but not affect jumplist
  -- yet (empty line with `>` when execute `:jumps`). After next jump or
  -- `<C-o>`/`<C-i>` current position will be added to the end. Because it is
  -- not yet in jumplist, the rest of jumplist should not be affected.
  -- See `:h jumplist`.
  type_keys('gg')
  backward('jump')
  eq(get_jump_num(), cur_jump_inds[n])
  local last_entry = jump_list[cur_jump_inds[n]]
  eq(get_cursor(), { last_entry.lnum, last_entry.col })
end

T['jump()']['can jump to current entry'] = function()
  local jump_list, jump_num_per_buf = setup_jumplist()
  local cur_jump_inds = jump_num_per_buf.cur
  local n = #cur_jump_inds

  set_cursor(1, 0)
  forward('jump', { n_times = n })
  eq(get_jump_num(), cur_jump_inds[n])
  local last_entry = jump_list[cur_jump_inds[n]]
  eq(get_cursor(), { last_entry.lnum, last_entry.col })
end

T['jump()']['opens just enough folds'] = function()
  setup_jumplist()

  child.cmd('1,2 fold')
  eq({ child.fn.foldclosed(1), child.fn.foldclosed(2) }, { 1, 1 })
  child.cmd('4,5 fold')
  eq({ child.fn.foldclosed(4), child.fn.foldclosed(5) }, { 4, 4 })

  backward('jump')
  eq(get_cursor(), { 5, 1 })

  eq({ child.fn.foldclosed(1), child.fn.foldclosed(2) }, { 1, 1 })
  eq({ child.fn.foldclosed(4), child.fn.foldclosed(5) }, { -1, -1 })
end

T['jump()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.jump(1)') end, 'jump%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.jump('next')]]) end, 'jump%(%).*direction.*one of')
end

T['jump()']['respects `opts.n_times`'] = function()
  local jump_list, jump_num_per_buf = setup_jumplist()
  local cur_jump_inds = jump_num_per_buf.cur
  local n = #cur_jump_inds

  local validate = function(id_start, direction, id_ref, opts)
    local s, e = cur_jump_inds[id_start], cur_jump_inds[id_ref]

    set_jump_num(s)
    child.lua('MiniBracketed.jump(...)', { direction, opts })
    eq(get_jump_num(), e)
    eq(get_cursor(), { jump_list[e].lnum, jump_list[e].col })
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

T['jump()']['respects `opts.wrap`'] = function()
  local jump_list, jump_num_per_buf = setup_jumplist()
  local cur_jump_inds = jump_num_per_buf.cur
  local n = #cur_jump_inds

  local validate = function(id_start, direction, id_ref, opts)
    local s, e = cur_jump_inds[id_start], cur_jump_inds[id_ref]

    set_jump_num(s)
    child.lua('MiniBracketed.jump(...)', { direction, opts })
    eq(get_jump_num(), e)
    eq(get_cursor(), { jump_list[e].lnum, jump_list[e].col })
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

T['jump()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    setup_jumplist()

    child[var_type].minibracketed_disable = true
    local cur_pos = get_cursor()
    backward('jump')
    eq(get_cursor(), cur_pos)
  end,
})

T['jump()']['respects `vim.b.minibracketed_config`'] = function()
  setup_jumplist()

  child.b.minibracketed_config = { jump = { options = { wrap = false } } }
  local cur_pos = get_cursor()
  forward('jump')
  eq(get_cursor(), cur_pos)
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
  local validate = function(id_start, direction, id_ref, opts)
    set_location(id_start)
    child.lua('MiniBracketed.location(...)', { direction, opts })
    eq(get_location(), id_ref)
    eq(get_cursor(), { qf_list[id_ref].lnum, qf_list[id_ref].col - 1 })
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
  local validate = function(id_start, direction, id_ref, opts)
    set_location(id_start)
    child.lua('MiniBracketed.location(...)', { direction, opts })
    eq(get_location(), id_ref)
    eq(get_cursor(), { qf_list[id_ref].lnum, qf_list[id_ref].col - 1 })
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
  local validate = function(id_start, direction, id_ref, opts)
    set_location(id_start)
    child.lua('MiniBracketed.location(...)', { direction, opts })
    eq(get_location(), id_ref)
    eq(get_cursor(), { qf_list[id_ref].lnum, qf_list[id_ref].col - 1 })
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

local setup_oldfile = function()
  local file_arr = { 'file-a', 'file-e', 'file-b', 'file-d', 'file-c' }
  for _, file in ipairs(file_arr) do
    edit_test_file(file)
  end
  return file_arr
end

T['oldfile()']['works'] = function()
  local files = setup_oldfile()
  local n = #files

  local validate = function(direction, id_ref)
    child.lua('MiniBracketed.oldfile(...)', { direction })
    validate_test_file(files[id_ref])
  end

  -- Forward
  for i = 1, n do
    validate('forward', i)
  end

  -- Backward
  for i = n - 1, 1, -1 do
    validate('backward', i)
  end
  validate('backward', n)

  -- First
  validate('first', 1)

  -- Last
  validate('last', n)
end

T['oldfile()']['works in not appropriate buffers'] = function()
  local files = setup_oldfile()
  local n = #files

  -- When in buffer without name should still go recent buffers
  local buf_id_normal_nonfile = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(buf_id_normal_nonfile)
  eq(get_bufname(), '')
  eq(child.bo.buftype, '')

  backward('oldfile')
  validate_test_file(files[n])

  child.api.nvim_set_current_buf(buf_id_normal_nonfile)
  forward('oldfile')
  validate_test_file(files[1])

  -- Same with non-normal buffers with name
  local buf_id_nonnormal = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(buf_id_nonnormal)
  child.api.nvim_buf_set_name(buf_id_nonnormal, 'tmp')
  eq(vim.fn.fnamemodify(get_bufname(), ':t'), 'tmp')
  eq(child.bo.buftype, 'nofile')

  backward('oldfile')
  validate_test_file(files[n])

  child.api.nvim_set_current_buf(buf_id_nonnormal)
  forward('oldfile')
  validate_test_file(files[1])
end

T['oldfile()']['is initialized with `v:oldfiles`'] = function()
  -- Enable shada
  local shada_path = make_testpath('oldfile.shada')
  child.o.shadafile = ''
  MiniTest.finally(function() child.fn.delete(shada_path) end)

  -- Set up `v:oldfiles`
  setup_oldfile()
  child.cmd('wshada! ' .. shada_path)

  child.restart()
  load_module()
  child.o.shadafile = ''
  child.cmd('rshada! ' .. shada_path)

  -- Notes:
  -- - It is ordered from most recent to oldest.
  -- - It doesn't seem to preserve order from `setup_oldfile()` in this test.
  local files = {}
  for _, f in ipairs(child.v.oldfiles) do
    table.insert(files, 1, f)
  end
  local n = #files

  child.cmd('edit ' .. files[n])

  forward('oldfile')
  eq(get_bufname(), files[1])

  backward('oldfile', { n_times = 2 })
  eq(get_bufname(), files[n - 1])
end

T['oldfile()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.oldfile(1)') end, 'oldfile%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.oldfile('next')]]) end, 'oldfile%(%).*direction.*one of')
end

T['oldfile()']['respects `opts.n_times`'] = function()
  local files = setup_oldfile()
  local n = #files

  local validate = function(direction, id_ref, opts)
    child.lua('MiniBracketed.oldfile(...)', { direction, opts })
    validate_test_file(files[id_ref])
  end

  -- Forward
  validate_test_file(files[n])
  for i = 1, n do
    validate('forward', (2 * i - 1) % n + 1, { n_times = 2 })
  end

  -- Backward
  validate_test_file(files[n])
  for i = 1, n do
    validate('backward', (n - 2 * i - 1) % n + 1, { n_times = 2 })
  end

  -- First
  validate('first', 2, { n_times = 2 })

  -- Last
  validate('last', n - 1, { n_times = 2 })
end

T['oldfile()']['respects `opts.wrap`'] = function()
  local files = setup_oldfile()
  local n = #files

  local validate = function(direction, id_ref, opts)
    child.lua('MiniBracketed.oldfile(...)', { direction, opts })
    validate_test_file(files[id_ref])
  end

  -- Forward
  validate_test_file(files[n])
  validate('forward', n, { wrap = false })

  backward('oldfile')
  validate_test_file(files[n - 1])
  validate('forward', n, { n_times = 1000, wrap = false })

  -- Backward
  first('oldfile')
  validate_test_file(files[1])
  validate('backward', 1, { wrap = false })

  forward('oldfile')
  validate_test_file(files[2])
  validate('backward', 1, { n_times = 1000, wrap = false })

  -- First
  first('oldfile')
  validate_test_file(files[1])
  validate('first', n, { n_times = 1000, wrap = false })

  last('oldfile')
  validate_test_file(files[n])
  validate('first', n, { n_times = 1000, wrap = false })

  -- Last
  last('oldfile')
  validate_test_file(files[n])
  validate('last', 1, { n_times = 1000, wrap = false })

  first('oldfile')
  validate_test_file(files[1])
  validate('last', 1, { n_times = 1000, wrap = false })
end

T['oldfile()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    local files = setup_oldfile()
    local n = #files

    -- `oldfile()` itself shouldn't work
    child[var_type].minibracketed_disable = true
    backward('oldfile')
    validate_test_file(files[n])

    -- Tracking recent files shouldn't work
    edit_test_file(files[2])
    edit_test_file(files[n])
    child[var_type].minibracketed_disable = false
    backward('oldfile')
    validate_test_file(files[n - 1])
  end,
})

T['oldfile()']['respects `vim.b.minibracketed_config`'] = function()
  local files = setup_oldfile()

  local cur_bufname = files[#files]
  child.b.minibracketed_config = { oldfile = { options = { wrap = false } } }
  forward('oldfile')
  validate_test_file(cur_bufname)
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
  local validate = function(id_start, direction, id_ref, opts)
    set_quickfix(id_start)
    child.lua('MiniBracketed.quickfix(...)', { direction, opts })
    eq(get_quickfix(), id_ref)
    eq(get_cursor(), { qf_list[id_ref].lnum, qf_list[id_ref].col - 1 })
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
  local validate = function(id_start, direction, id_ref, opts)
    set_quickfix(id_start)
    child.lua('MiniBracketed.quickfix(...)', { direction, opts })
    eq(get_quickfix(), id_ref)
    eq(get_cursor(), { qf_list[id_ref].lnum, qf_list[id_ref].col - 1 })
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
  local validate = function(id_start, direction, id_ref, opts)
    set_quickfix(id_start)
    child.lua('MiniBracketed.quickfix(...)', { direction, opts })
    eq(get_quickfix(), id_ref)
    eq(get_cursor(), { qf_list[id_ref].lnum, qf_list[id_ref].col - 1 })
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

T['undo()'] = new_set()

T['undo()']['works'] = function() MiniTest.skip() end

T['undo()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.undo(1)') end, 'undo%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.undo('next')]]) end, 'undo%(%).*direction.*one of')
end

T['undo()']['respects `opts.n_times`'] = function() MiniTest.skip() end

T['undo()']['respects `opts.wrap`'] = function() MiniTest.skip() end

T['undo()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minibracketed_disable = true
    MiniTest.skip()
  end,
})

T['undo()']['respects `vim.b.minibracketed_config`'] = function()
  child.b.minibracketed_config = { undo = { options = { wrap = false } } }
  MiniTest.skip()
end

T['register_undo_state()'] = new_set()

T['register_undo_state()']['works'] = function() MiniTest.skip() end

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
  local validate = function(id_start, direction, id_ref, opts)
    set_winnr(winnr_list[id_start])
    child.lua('MiniBracketed.window(...)', { direction, opts })
    eq(get_winnr(), winnr_list[id_ref])
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
  local validate = function(id_start, direction, id_ref, opts)
    set_winnr(winnr_list[id_start])
    child.lua('MiniBracketed.window(...)', { direction, opts })
    eq(get_winnr(), winnr_list[id_ref])
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
  local validate = function(id_start, direction, id_ref, opts)
    set_winnr(winnr_list[id_start])
    child.lua('MiniBracketed.window(...)', { direction, opts })
    eq(get_winnr(), winnr_list[id_ref])
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

T['yank()'] = new_set()

-- local get_yank = function() return end
-- local set_yank = function(x) end

---@param ... any Yank entries to populate yank history.
---   Each element is one of:
---   - String. Will be yanked in charwise mode.
---   - Table. First element is array of lines, second - keys used to yank them
---     (assuming Normal mode and cursor being {1, 0}).
---@return table Array of arrays with yank history lines.
---@private
local setup_yank = function(...)
  local yank_entries = vim.tbl_map(function(x)
    -- If entry is string, yank it whole in charwise mode
    if type(x) == 'string' then return { { x }, '0v$hy' } end
    return x
  end, { ... })

  for _, entry in ipairs(yank_entries) do
    child.ensure_normal_mode()
    set_lines(entry[1])
    set_cursor(1, 0)
    type_keys(entry[2])
  end

  child.ensure_normal_mode()
  set_lines({})
  return vim.tbl_map(function(x) return x[1] end, yank_entries)
end

T['yank()']['works'] = function()
  local yanks = setup_yank('one', 'two', 'three', 'four', 'five')
  local n = #yanks
  type_keys('p')
  eq(get_lines(), yanks[n])

  local validate = function(direction, id_ref)
    child.lua('MiniBracketed.yank(...)', { direction })
    eq(get_lines(), yanks[id_ref])
  end

  -- Forward
  for i = 1, n do
    validate('forward', i)
  end

  -- Backward
  for i = n - 1, 1, -1 do
    validate('backward', i)
  end
  validate('backward', n)

  -- First
  validate('first', 1)

  -- Last
  validate('last', n)
end

T['yank()']['works advancing charwise<->charwise'] = function()
  setup_yank('one', 'two')

  set_lines({ '____' })
  set_cursor(1, 2)
  type_keys('yl', 'P')
  eq(get_lines(), { '_____' })

  backward('yank')
  eq(get_lines(), { '__two__' })

  backward('yank')
  eq(get_lines(), { '__one__' })

  last('yank')
  eq(get_lines(), { '_____' })
end

T['yank()']['works advancing charwise<->linewise'] = function()
  setup_yank({ { 'line' }, 'yy' })

  set_lines({ '_', '____', '_' })
  set_cursor(2, 2)
  type_keys('yl', 'P')
  eq(get_lines(), { '_', '_____', '_' })

  backward('yank')
  eq(get_lines(), { '_', 'line', '____', '_' })

  backward('yank')
  eq(get_lines(), { '_', '_____', '_' })
end

T['yank()']['works advancing charwise<->blockwise'] = function()
  setup_yank({ { 'bl', 'ock' }, '<C-v>j2ly' })

  set_lines({ '_', '____', '_' })
  set_cursor(2, 2)
  type_keys('yl', 'P')
  eq(get_lines(), { '_', '_____', '_' })

  backward('yank')
  eq(get_lines(), { '_', '__bl __', '_ ock' })

  backward('yank')
  eq(get_lines(), { '_', '_____', '_ ' })
end

T['yank()']['works with multiline charwise yank entry'] = function()
  setup_yank({ { 'one', 'aaaa' }, 'v$jy' })

  set_lines({ '_', '____', '_' })
  set_cursor(2, 2)
  type_keys('yl', 'P')
  eq(get_lines(), { '_', '_____', '_' })

  backward('yank')
  eq(get_lines(), { '_', '__one', 'aaaa__', '_' })

  backward('yank')
  eq(get_lines(), { '_', '_____', '_' })
end

T['yank()']['works pasting charwise on last column'] = function()
  setup_yank('one')

  -- Past last column
  set_lines({ 'xyz' })
  set_cursor(1, 1)
  type_keys('vy', '$', 'p')
  eq(get_lines(), { 'xyzy' })

  backward('yank')
  eq(get_lines(), { 'xyzone' })

  backward('yank')
  eq(get_lines(), { 'xyzy' })

  -- Just before last column
  set_lines({ 'xyz' })
  set_cursor(1, 2)
  type_keys('P')
  eq(get_lines(), { 'xyyz' })

  backward('yank')
  eq(get_lines(), { 'xyonez' })

  backward('yank')
  eq(get_lines(), { 'xyyz' })

  -- Replacing linewise region on last line
  type_keys('yy', 'p')
  eq(get_lines(), { 'xyyz', 'xyyz' })

  backward('yank')
  eq(get_lines(), { 'yxyyz' })
end

T['yank()']['works advancing linewise<->linewise'] = function()
  setup_yank({ { 'line1' }, 'yy' }, { { 'line2' }, 'yy' })

  set_lines({ '_', '_' })
  set_cursor(1, 0)
  type_keys('yy', 'p')
  eq(get_lines(), { '_', '_', '_' })

  backward('yank')
  eq(get_lines(), { '_', 'line2', '_' })

  backward('yank')
  eq(get_lines(), { '_', 'line1', '_' })

  backward('yank')
  eq(get_lines(), { '_', '_', '_' })
end

T['yank()']['works advancing linewise<->blockwise'] = function()
  setup_yank({ { 'bl', 'ock' }, '<C-v>j2ly' })

  set_lines({ '_', '_' })
  set_cursor(1, 0)
  type_keys('yy', 'p')
  eq(get_lines(), { '_', '_', '_' })

  backward('yank')
  eq(get_lines(), { '_', 'bl _', 'ock' })

  backward('yank')
  eq(get_lines(), { '_', '_', '_', '' })
end

T['yank()']['works with multiline linewise yank entry'] = function()
  setup_yank({ { 'line1', 'line2' }, 'y2_' })

  set_lines({ '_', '_' })
  set_cursor(1, 0)
  type_keys('yy', 'p')
  eq(get_lines(), { '_', '_', '_' })

  backward('yank')
  eq(get_lines(), { '_', 'line1', 'line2', '_' })

  backward('yank')
  eq(get_lines(), { '_', '_', '_' })
end

T['yank()']['works pasting linewise on last line'] = function()
  setup_yank({ { 'line' }, 'yy' })

  -- Past last line
  set_lines({ 'xxx', '___' })
  set_cursor(1, 0)
  type_keys('yy', 'j', 'p')
  eq(get_lines(), { 'xxx', '___', 'xxx' })

  backward('yank')
  eq(get_lines(), { 'xxx', '___', 'line' })

  backward('yank')
  eq(get_lines(), { 'xxx', '___', 'xxx' })

  -- Just before of last line
  set_lines({ 'yyy', '___' })
  set_cursor(2, 0)
  type_keys('P')
  eq(get_lines(), { 'yyy', 'xxx', '___' })

  backward('yank')
  eq(get_lines(), { 'yyy', 'line', '___' })

  backward('yank')
  eq(get_lines(), { 'yyy', 'xxx', '___' })

  -- Replacing non-linewise region on last column
  set_lines({ 'yyy', '___' })
  set_cursor(1, 2)
  type_keys('yl', 'p')
  eq(get_lines(), { 'yyyy', '___' })

  backward('yank')
  eq(get_lines(), { 'xxx', 'yyy', '___' })
end

T['yank()']['works advancing blockwise<->blockwise'] = function()
  setup_yank({ { 'bl', 'ock1' }, '<C-v>j3ly' }, { { 'block2' }, '<C-v>5ly' })

  set_lines({ '___', '___' })
  set_cursor(1, 1)
  type_keys('<C-v>y', 'P')
  eq(get_lines(), { '____', '___' })

  backward('yank')
  eq(get_lines(), { '_block2__', '___' })

  backward('yank')
  eq(get_lines(), { '_bl  __', '_ock1__' })

  backward('yank')
  eq(get_lines(), { '____', '___' })
end

T['yank()']['works pasting blockwise on last column'] = function()
  setup_yank({ { 'bl', 'ock' }, '<C-v>j2ly' })

  -- Past last column
  set_lines({ 'x__', 'x__' })
  set_cursor(1, 0)
  type_keys('<C-v>jy', '$', 'p')
  eq(get_lines(), { 'x__x', 'x__x' })

  backward('yank')
  eq(get_lines(), { 'x__bl', 'x__ock' })

  backward('yank')
  eq(get_lines(), { 'x__x', 'x__x' })

  -- Just before last column
  set_lines({ '___', '___' })
  set_cursor(1, 2)
  type_keys('P')
  eq(get_lines(), { '__x_', '__x_' })

  backward('yank')
  eq(get_lines(), { '__bl _', '__ock_' })

  backward('yank')
  eq(get_lines(), { '__x_', '__x_' })

  -- Replacing linewise region on last line
  set_lines({ 'aaa' })
  type_keys('yy', 'p')
  eq(get_lines(), { 'aaa', 'aaa' })

  backward('yank')
  eq(get_lines(), { 'xaaa', 'x' })
end

T['yank()']['works with one yank entry or less'] = function()
  -- No yank history
  for _, dir in ipairs({ forward, backward, first, last }) do
    set_lines({ 'aaa' })
    set_cursor(1, 0)
    dir('yank')
    eq(get_lines(), { 'aaa' })
    eq(get_cursor(), { 1, 0 })
  end

  -- Single-entry yank history
  set_lines({ 'x__' })
  set_cursor(1, 0)
  type_keys('ylp')
  eq(get_lines(), { 'xx__' })
  eq(get_cursor(), { 1, 1 })

  for _, dir in ipairs({ forward, backward, first, last }) do
    dir('yank')
    eq(get_lines(), { 'xx__' })
    eq(get_cursor(), { 1, 1 })
  end

  -- No yank entry with proper operator
  for _, dir in ipairs({ forward, backward, first, last }) do
    dir('yank', { operators = { 'c' } })
    eq(get_lines(), { 'xx__' })
    eq(get_cursor(), { 1, 1 })
  end
end

T['yank()']['does not depend on cursor position'] = function()
  setup_yank('one')

  set_lines({ '___', '___' })
  set_cursor(1, 0)
  type_keys('yl', 'p')
  eq(get_lines(), { '____', '___' })

  set_cursor(2, 2)
  backward('yank')
  eq(get_lines(), { '_one__', '___' })
  eq(get_cursor(), { 1, 3 })
end

T['yank()']['places cursor at region start during replacement'] = function()
  setup_yank('x', { { 'xxx' }, 'yy' })

  set_lines({ '___' })
  type_keys('p')
  eq(get_lines(), { '___', 'xxx' })

  set_cursor(2, 2)
  backward('yank')
  eq(get_lines(), { 'x___' })
end

T['yank()']['tracks all `TextYankPost` events'] = function()
  setup_yank({ { 'one' }, '"ayiw' }, { { 'two' }, 'diw' }, { { 'three' }, 'ciw<Esc>' })

  set_lines({ '___' })
  set_cursor(1, 0)
  type_keys('yl', 'p')
  eq(get_lines(), { '____' })

  backward('yank')
  eq(get_lines(), { '_three__' })

  backward('yank')
  eq(get_lines(), { '_two__' })

  backward('yank')
  eq(get_lines(), { '_one__' })

  backward('yank')
  eq(get_lines(), { '____' })
end

T['yank()']['tracks yanking right after advancing'] = function()
  setup_yank('one', 'two')

  set_lines({ '', 'three' })
  set_cursor(1, 0)
  type_keys('p')
  eq(get_lines(), { 'two', 'three' })

  backward('yank')
  eq(get_lines(), { 'one', 'three' })

  -- It should reset advancing after adding another entry to yank history
  set_cursor(2, 0)
  type_keys('yiw', 'P')
  eq(get_lines(), { 'one', 'threethree' })

  backward('yank')
  eq(get_lines(), { 'one', 'twothree' })
end

T['yank()']['does not detect correct region mode when pasted with register'] = function()
  -- It would be **great** to make it work but seems imposible right now
  -- See https://github.com/vim/vim/issues/12003
  setup_yank({ { 'a', 'b' }, '<C-v>j"ay' }, { { 'aaa' }, 'yy' })

  set_lines({ 'xxx', 'yyy' })
  set_cursor(1, 0)
  type_keys('"aP')
  eq(get_lines(), { 'axxx', 'byyy' })

  backward('yank')
  -- It thinks that region is linewise but it is not. Also at this point yank
  -- history is { {'a', 'b'}, {'aaa'} } so backward chooses second to last.
  eq(get_lines(), { 'a', 'b' })

  backward('yank')
  eq(get_lines(), { 'aaa', '', '' })
end

T['yank()']['does not have side effects'] = function()
  setup_yank('one', 'two')

  set_lines({ 'x__' })
  set_cursor(1, 0)
  type_keys('"zyl', 'l', 'yl')
  type_keys('P')
  eq(get_lines(), { 'x___' })
  eq(child.fn.getreg('z'), 'x')
  eq(child.fn.getreg('"'), '_')

  backward('yank')
  eq(get_lines(), { 'xx__' })

  backward('yank')
  eq(get_lines(), { 'xtwo__' })

  eq(child.fn.getreg('z'), 'x')
  eq(child.fn.getreg('"'), '_')
end

T['yank()']['undos all advances at once'] = function()
  setup_yank('one', 'two', 'three', 'four')

  type_keys('p')
  eq(get_lines(), { 'four' })

  backward('yank')
  eq(get_lines(), { 'three' })
  backward('yank')
  eq(get_lines(), { 'two' })
  backward('yank')
  eq(get_lines(), { 'one' })

  type_keys('u')
  eq(get_lines(), { 'four' })
  type_keys('u')
  eq(get_lines(), { '' })
end

T['yank()']['replaces region based on `[` marks `]`'] = function()
  -- Should replace not only latest put region, but also yanked or changed
  -- Region from change operation
  setup_yank('one')

  set_lines({ '____' })
  set_cursor(1, 1)
  type_keys('cl<Esc>')
  eq(get_lines(), { '___' })

  backward('yank')
  -- - As `_` is now the last entry in history, going backward selects `two`
  eq(get_lines(), { '_one_' })

  -- Region from yank operation
  setup_yank('two')

  set_lines({ '____' })
  set_cursor(1, 1)
  type_keys('yl')

  backward('yank')
  eq(get_lines(), { '_two_' })
end

T['yank()']['respects `register_put_region()` to determine region boundaries'] = function()
  -- Should take into account only regions coming from the helper; not from
  -- yank or change operations.
  set_lines({ 'xaa', 'bbb', 'ccc' })

  set_cursor(1, 0)
  type_keys('yl', '$', 'P')

  child.lua('MiniBracketed.register_put_region()')

  set_cursor(2, 0)
  type_keys('ciw', '<Esc>')

  set_cursor(3, 0)
  type_keys('yiw')

  eq(get_lines(), { 'xaxa', '', 'ccc' })
  backward('yank')
  -- - At this moment yank history is `{ 'x', 'bbb', 'ccc' }` with current
  --   entry being the last one.
  eq(get_lines(), { 'xabbba', '', 'ccc' })
end

T['yank()']['respects `register_put_region()` to determine region mode'] = function()
  -- Currently this is only possible with remapping
  child.api.nvim_set_keymap('n', 'P', 'v:lua.MiniBracketed.register_put_region("P")', { expr = true })

  setup_yank({ { 'a', 'b' }, '<C-v>j"ay' }, { { 'aaa' }, 'yy' })

  set_lines({ 'xxx', 'yyy' })
  set_cursor(1, 0)
  type_keys('"aP')
  eq(get_lines(), { 'axxx', 'byyy' })

  backward('yank')
  -- At this point yank history is { { 'a', 'b' }, { 'aaa' } } so backward
  -- chooses second to last.
  eq(get_lines(), { 'axxx', 'byyy' })
  backward('yank')
  eq(get_lines(), { 'aaa', 'xxx', 'yyy' })
end

T['yank()']['should reset advancing on buffer change'] = function()
  local buf_id_new = child.api.nvim_create_buf(true, false)
  setup_yank('one', 'two', 'three', 'four')

  type_keys('P')
  eq(get_lines(), { 'four' })

  backward('yank')
  eq(get_lines(), { 'three' })
  backward('yank')
  eq(get_lines(), { 'two' })

  child.api.nvim_set_current_buf(buf_id_new)
  type_keys('P')
  eq(get_lines(), { 'four' })
  backward('yank')
  eq(get_lines(), { 'three' })
end

T['yank()']['validates `direction`'] = function()
  expect.error(function() child.lua('MiniBracketed.yank(1)') end, 'yank%(%).*direction.*one of')
  expect.error(function() child.lua([[MiniBracketed.yank('next')]]) end, 'yank%(%).*direction.*one of')
end

T['yank()']['respects `opts.n_times`'] = function()
  local yanks = setup_yank('one', 'two', 'three', 'four', 'five')
  local n = #yanks
  type_keys('p')
  eq(get_lines(), yanks[n])

  local validate = function(direction, id_ref, opts)
    child.lua('MiniBracketed.yank(...)', { direction, opts })
    eq(get_lines(), yanks[id_ref])
  end

  -- Forward
  eq(get_lines(), yanks[n])
  for i = 1, n do
    validate('forward', (2 * i - 1) % n + 1, { n_times = 2 })
  end

  -- Backward
  eq(get_lines(), yanks[n])
  for i = 1, n do
    validate('backward', (n - 2 * i - 1) % n + 1, { n_times = 2 })
  end

  -- First
  validate('first', 2, { n_times = 2 })

  -- Last
  validate('last', n - 1, { n_times = 2 })
end

T['yank()']['respects `opts.operators`'] = function()
  setup_yank({ { 'one' }, '"ayiw' }, { { 'two' }, 'diw' }, { { 'three' }, 'ciw<Esc>' })

  set_lines({ '___' })
  set_cursor(1, 0)
  type_keys('yl', 'p')
  eq(get_lines(), { '____' })

  backward('yank', { operators = { 'y' } })
  eq(get_lines(), { '_one__' })

  backward('yank', { operators = { 'd' } })
  eq(get_lines(), { '_two__' })

  backward('yank', { operators = { 'c' } })
  eq(get_lines(), { '_three__' })

  backward('yank', { operators = { 'y', 'd' } })
  eq(get_lines(), { '_two__' })
end

T['yank()']['respects `opts.wrap`'] = function()
  local yanks = setup_yank('one', 'two', 'three', 'four', 'five')
  local n = #yanks
  type_keys('p')
  eq(get_lines(), yanks[n])

  local validate = function(direction, id_ref, opts)
    child.lua('MiniBracketed.yank(...)', { direction, opts })
    eq(get_lines(), yanks[id_ref])
  end

  -- Forward
  eq(get_lines(), yanks[n])
  validate('forward', n, { wrap = false })

  backward('yank')
  eq(get_lines(), yanks[n - 1])
  validate('forward', n, { n_times = 1000, wrap = false })

  -- Backward
  first('yank')
  eq(get_lines(), yanks[1])
  validate('backward', 1, { wrap = false })

  forward('yank')
  eq(get_lines(), yanks[2])
  validate('backward', 1, { n_times = 1000, wrap = false })

  -- First
  first('yank')
  eq(get_lines(), yanks[1])
  validate('first', n, { n_times = 1000, wrap = false })

  last('yank')
  eq(get_lines(), yanks[n])
  validate('first', n, { n_times = 1000, wrap = false })

  -- Last
  last('yank')
  eq(get_lines(), yanks[n])
  validate('last', 1, { n_times = 1000, wrap = false })

  first('yank')
  eq(get_lines(), yanks[1])
  validate('last', 1, { n_times = 1000, wrap = false })
end

T['yank()']['respects `vim.{g,b}.minibracketed_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    setup_yank('one', 'two')
    type_keys('p')
    eq(get_lines(), { 'two' })

    -- `yank()` itself shouldn't work
    child[var_type].minibracketed_disable = true
    backward('yank')
    eq(get_lines(), { 'two' })

    -- Tracking yank history shouldn't work
    set_cursor(1, 0)
    type_keys('yl')

    set_cursor(1, 1)
    type_keys('yl', 'P')
    eq(get_lines(), { 'twwo' })

    child[var_type].minibracketed_disable = false
    -- Yank history should still be { 'one', 'two' } (without 't' and 'w').
    -- Going backward select second to last entry.
    backward('yank')
    eq(get_lines(), { 'tonewo' })
  end,
})

T['yank()']['respects `vim.b.minibracketed_config`'] = function()
  setup_yank('one', 'two')
  type_keys('p')
  eq(get_lines(), { 'two' })

  child.b.minibracketed_config = { yank = { options = { wrap = false } } }
  forward('yank')
  eq(get_lines(), { 'two' })
end

-- Main tests are in `yank()`
T['register_put_region()'] = new_set()

T['register_put_region()']['is present'] =
  function() eq(child.lua_get('type(MiniBracketed.register_put_region)'), 'function') end

T['register_put_region()']['uses `[` and `]` marks'] = function()
  set_lines({ 'xaa', 'bbb', 'ccc' })

  set_cursor(1, 0)
  type_keys('yl', '$', 'P')

  -- Should be possible to use it not only on region from put operation
  -- - Change
  set_cursor(2, 0)
  type_keys('ciw', '<Esc>')
  child.lua('MiniBracketed.register_put_region()')

  eq(get_lines(), { 'xaxa', '', 'ccc' })
  -- - Yank history at this point: { 'x', 'bbb' }
  backward('yank')
  eq(get_lines(), { 'xaxa', 'x', 'ccc' })

  -- - Yank
  set_cursor(3, 0)
  type_keys('yiw')
  child.lua('MiniBracketed.register_put_region()')

  eq(get_lines(), { 'xaxa', 'x', 'ccc' })
  -- - Yank history at this point: { 'x', 'bbb', 'ccc' }
  backward('yank')
  eq(get_lines(), { 'xaxa', 'x', 'bbb' })
end

T['advance()'] = new_set()

local make_iterator = function(init_state)
  child.lua([[
    _G.iterator = {}

    _G.iterator.next = function(id)
      if id == nil then return -1 end
      if 5 <= id then return end
      return id + 1
    end

    _G.iterator.prev = function(id)
      if id == nil then return -2 end
      if id <= 1 then return end
      return id - 1
    end

    _G.iterator.start_edge = 0
    _G.iterator.end_edge = 6
  ]])
  child.lua('_G.iterator.state = ' .. tostring(init_state))
end

local advance =
  function(direction, opts) return child.lua_get('MiniBracketed.advance(iterator, ...)', { direction, opts }) end

T['advance()']['works'] = function()
  make_iterator(3)

  -- Should only return new state without changing current one
  local res_id = advance('forward')
  eq(res_id, 4)
  eq(child.lua_get('_G.iterator.state'), 3)
end

T['advance()']['respects `direction` argument'] = function()
  local n = 5

  for i = 1, n do
    make_iterator(i)

    eq(advance('forward'), i % n + 1)
    eq(advance('backward'), (i - 2) % n + 1)
    eq(advance('first'), 1)
    eq(advance('last'), n)
  end
end

T['advance()']['respects `opts.n_times`'] = function()
  local n = 5

  for i = 1, n do
    make_iterator(i)

    eq(advance('forward', { n_times = 2 }), (i + 1) % n + 1)
    eq(advance('backward', { n_times = 2 }), (i - 3) % n + 1)
    eq(advance('first', { n_times = 2 }), 2)
    eq(advance('last', { n_times = 2 }), n - 1)
  end
end

T['advance()']['respects `opts.wrap`'] = function()
  local n = 5

  local validate = function(id_before, direction, id_ref, opts)
    make_iterator(id_before)
    eq(advance(direction, opts), id_ref)
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

T['advance()']['handles `nil` states'] = function()
  local n = 5

  -- `state = nil`
  make_iterator(3)
  child.lua('_G.iterator.state = nil')

  eq(advance('forward'), -1)
  eq(advance('backward'), -2)
  eq(advance('first'), 1)
  eq(advance('last'), n)

  -- `start_edge = nil`
  make_iterator(3)
  child.lua('_G.iterator.start_edge = nil')

  eq(advance('forward'), 4)
  eq(advance('backward'), 2)
  eq(advance('first'), -1)
  eq(advance('last'), n)

  -- `end_edge = nil`
  make_iterator(3)
  child.lua('_G.iterator.end_edge = nil')

  eq(advance('forward'), 4)
  eq(advance('backward'), 2)
  eq(advance('first'), 1)
  eq(advance('last'), -2)
end

-- Integration tests ==========================================================
T['Mappings'] = new_set()

T['Mappings']['buffer'] = new_set()

-- Should also test with `[count]`
T['Mappings']['buffer']['works'] = function() MiniTest.skip() end

T['Mappings']['buffer']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['comment'] = new_set()

T['Mappings']['comment']['works in Normal mode'] = function() MiniTest.skip() end

T['Mappings']['comment']['works in Visual mode'] = function() MiniTest.skip() end

T['Mappings']['comment']['works in Operator-pending mode'] = function()
  -- Should also respect dot-repeat
  MiniTest.skip()
end

T['Mappings']['comment']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['conflict'] = new_set()

T['Mappings']['conflict']['works in Normal mode'] = function() MiniTest.skip() end

T['Mappings']['conflict']['works in Visual mode'] = function() MiniTest.skip() end

T['Mappings']['conflict']['works in Operator-pending mode'] = function() MiniTest.skip() end

T['Mappings']['conflict']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['diagnostic'] = new_set()

T['Mappings']['diagnostic']['works in Normal mode'] = function() MiniTest.skip() end

T['Mappings']['diagnostic']['works in Visual mode'] = function() MiniTest.skip() end

T['Mappings']['diagnostic']['works in Operator-pending mode'] = function() MiniTest.skip() end

T['Mappings']['diagnostic']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['file'] = new_set()

T['Mappings']['file']['works'] = function() MiniTest.skip() end

T['Mappings']['file']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['indent'] = new_set()

T['Mappings']['indent']['works in Normal mode'] = function() MiniTest.skip() end

T['Mappings']['indent']['works in Visual mode'] = function() MiniTest.skip() end

T['Mappings']['indent']['works in Operator-pending mode'] = function() MiniTest.skip() end

T['Mappings']['indent']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['jump'] = new_set()

T['Mappings']['jump']['works in Normal mode'] = function() MiniTest.skip() end

T['Mappings']['jump']['works in Visual mode'] = function() MiniTest.skip() end

T['Mappings']['jump']['works in Operator-pending mode'] = function() MiniTest.skip() end

T['Mappings']['jump']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['location'] = new_set()

T['Mappings']['location']['works'] = function() MiniTest.skip() end

T['Mappings']['location']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['oldfile'] = new_set()

T['Mappings']['oldfile']['works'] = function() MiniTest.skip() end

T['Mappings']['oldfile']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['quickfix'] = new_set()

T['Mappings']['quickfix']['works'] = function() MiniTest.skip() end

T['Mappings']['quickfix']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['undo'] = new_set()

T['Mappings']['undo']['works'] = function() MiniTest.skip() end

T['Mappings']['undo']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['window'] = new_set()

T['Mappings']['window']['works'] = function() MiniTest.skip() end

T['Mappings']['window']['allows non-letter suffix'] = function() MiniTest.skip() end

T['Mappings']['yank'] = new_set()

T['Mappings']['yank']['works'] = function() MiniTest.skip() end

T['Mappings']['yank']['allows non-letter suffix'] = function() MiniTest.skip() end

return T
