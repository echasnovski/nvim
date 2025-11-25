local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('cmdline', config) end
local unload_module = function() child.mini_unload('cmdline') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

-- Time constants
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
    n_retry = helpers.get_n_retry(2),
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniCmdline)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  load_module()
  eq(child.lua_get('type(_G.MiniCmdline.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniCmdline.config.' .. field), value) end

  expect_config('autocomplete.enable', true)
  expect_config('autocomplete.delay', 0)
  expect_config('autocomplete.predicate', vim.NIL)
  expect_config('autocorrect.enable', true)
  expect_config('autocorrect.func', vim.NIL)
  expect_config('preview_range.enable', true)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ autocomplete = 1 }, 'autocomplete', 'table')
  expect_config_error({ autocomplete = { enable = 1 } }, 'autocomplete.enable', 'boolean')
  expect_config_error({ autocomplete = { predicate = 1 } }, 'autocomplete.predicate', 'function')
  expect_config_error({ autocorrect = 1 }, 'autocorrect', 'table')
  expect_config_error({ autocorrect = { enable = 1 } }, 'autocorrect.enable', 'boolean')
  expect_config_error({ autocorrect = { func = 1 } }, 'autocorrect.func', 'function')
  expect_config_error({ preview_range = 1 }, 'preview_range', 'table')
  expect_config_error({ preview_range = { enable = 1 } }, 'preview_range.enable', 'boolean')
end

T['default_autocomplete_predicate()'] = new_set()

T['default_autocomplete_predicate()']['works'] = function() MiniTest.skip() end

T['default_autocorrect_func()'] = new_set()

T['default_autocorrect_func()']['works'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
T['Autocomplete'] = new_set({
  hooks = {
    pre_case = function() load_module({ autocorrect = { enable = false }, preview_range = { enable = false } }) end,
  },
})

T['Autocomplete']['works'] = function() MiniTest.skip() end

T['Autocorrect'] = new_set({
  hooks = {
    pre_case = function() load_module({ autocomplete = { enable = false }, preview_range = { enable = false } }) end,
  },
})

local validate_cmdline = function(line, pos)
  eq(child.fn.mode(), 'c')
  eq(child.fn.getcmdline(), line)
  eq(child.fn.getcmdpos(), pos or line:len() + 1)
end

T['Autocorrect']['works'] = function()
  local validate = function(bad_word, ref_word)
    type_keys(':', bad_word, ' ')
    validate_cmdline(ref_word .. ' ')
    type_keys('<Esc>')
  end

  child.cmd('command MyCommand echo "Hello"')

  -- Should correct for common edit types
  validate('bbuffer', 'buffer') -- Deletion
  validate('uffer', 'buffer') -- Insertion
  validate('xuffer', 'buffer') -- Substitution
  validate('ste', 'set') -- Transposition

  -- Should respect abbreviations, even for user commands
  validate('nmor', 'nnor')
  validate('nmore', 'nnore')

  validate('MxC', 'MyC')

  validate('W', 'w')
  validate('Q', 'q')

  -- Should prefer "ignore case" matches
  validate('WrItE', 'write')
  validate('W', 'w')
  validate('NNO', 'nno')

  validate('myc', 'MyC')

  -- Should prefer transposition
  validate('ua', 'au')

  -- Should work with bang
  type_keys(':', 'Q', '!')
  validate_cmdline('q!')
  type_keys('<Esc>')

  -- Should work with range
  type_keys(':', "'a")
  validate_cmdline("'a")
  type_keys(',')
  validate_cmdline("'a,")
  type_keys("'b")
  validate_cmdline("'a,'b")
  type_keys('<Esc>')

  -- Should work with command modifiers
  validate('abvelfet', 'aboveleft')
end

T['Autocorrect']['works multiple times'] = function()
  type_keys(':', 'srot', ' ')
  validate_cmdline('sort ')

  -- After delete
  type_keys('<C-u>', 'abvoelfet', ' ')
  validate_cmdline('aboveleft ')

  -- After another typed autocorrection
  type_keys('noutocmd', ' ')
  validate_cmdline('aboveleft noautocmd ')

  type_keys('sort', ' ')
  validate_cmdline('aboveleft noautocmd sort ')
end

T['Autocorrect']['does not work in mappings'] = function()
  child.cmd('nnoremap <C-x> :ehco<CR>')
  local ok, err = pcall(type_keys, '<C-x>')
  eq(ok, false)
  eq(err, 'E492: Not an editor command: ehco')
end

T['Autocomplete']['works only when typing new word'] = function()
  type_keys(':', 'set tw', '<Left><Left>')
  type_keys('<BS>')
  validate_cmdline('settw', 4)
  type_keys('<BS>')
  validate_cmdline('setw', 3)
  MiniTest.skip()
end

T['Autocorrect']['correctly computes word to autocorrect'] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip('Requires `getcmdcomplpat()`, present in Neovim>=0.11') end

  local validate = function(text, final_key, ref)
    type_keys(':', text, final_key)
    validate_cmdline(ref)
    type_keys('<Esc>')
  end

  validate("'a,'bsrot", ' ', "'a,'bsort ")
  validate("'a,'bsrot", '!', "'a,'bsort!")
  validate("'a,''srot", ' ', "'a,''sort ")
end

T['Autocorrect']['works when correcting not at end of line'] = function()
  MiniTest.skip('Currently does not work')

  type_keys(':', 'set tw', '<Left><Left>')
  type_keys('<BS><BS>', 'T')
  validate_cmdline('set tw')
end

T['Autocorrect']['works just before final <CR>'] = function()
  MiniTest.skip('Currently does not work')

  local validate = function(bad_word, ref_word)
    type_keys(':', bad_word, '<CR>')
    eq(child.fn.histget('cmd', -1), ref_word)
    eq(child.fn.mode(), 'n')
  end

  local buf_id = child.api.nvim_get_current_buf()
  set_lines({ '1', '2' })
  set_cursor(1, 0)

  local buf_id_other = child.api.nvim_create_buf(true, false)
  validate('bnxxt', 'bnext')
  eq(child.api.nvim_get_current_buf(), buf_id_other)
  type_keys('<Esc>')

  -- Should work not at end of line
  type_keys(':', 'bnext +2', '<Left><Left><Left>', '<BS>x')
  validate_cmdline('bnexx +2', 6)
  type_keys('<CR>')
  eq(child.api.nvim_get_current_buf(), buf_id)
  eq(get_cursor(), { 2, 0 })

  -- Should work with `!`
  child.cmd('vsplit')
  local win_id = child.api.nvim_get_current_win()
  validate({ 'Q', '!' }, 'q!')
  eq(child.api.nvim_win_is_valid(win_id), false)
end

T['Autocorrect']['does not correct valid words'] = function()
  child.cmd('au CmdlineChanged * lua _G.n = (_G.n or 0) + 1')

  local validate = function(word)
    type_keys(':', word)
    child.lua('_G.n = 0')
    type_keys(' ')
    validate_cmdline(word .. ' ')
    eq(child.lua_get('_G.n'), 1)

    type_keys('<Esc>')
  end

  validate('cnoremap')
  validate('cnor')

  child.cmd('command MyCommand echo "Hello"')
  validate('MyCommand')
  validate('MyC')

  child.cmd('vsplit')
  local win_id = child.api.nvim_get_current_win()
  type_keys(':', 'q', '!', '<CR>')
  eq(child.api.nvim_win_is_valid(win_id), false)
end

T['Autocorrect']['respects `config.autocorrect.func`'] = function()
  child.lua([[
    _G.log = {}
    MiniCmdline.config.autocorrect.func = function(data)
      table.insert(_G.log, vim.deepcopy(data))
      return _G.correction
    end
  ]])

  child.lua('_G.correction = "xxxx"')
  type_keys(':', 'srot')
  eq(child.lua_get('_G.log'), {})
  type_keys(' ')
  -- NOTE: Should not autocorrect output
  validate_cmdline('xxxx ')
  eq(child.lua_get('_G.log'), { { word = 'srot', type = 'command' } })
  child.lua('_G.log = {}')
  type_keys('<Esc>')

  -- Should not change command line if output is same word or `nil`
  child.cmd('au CmdlineChanged * lua _G.n = (_G.n or 0) + 1')
  local validate_no_change = function(correction)
    child.lua('_G.correction = ' .. vim.inspect(correction))
    type_keys(':', 'srot')
    child.lua('_G.n = 0')

    type_keys(' ')
    validate_cmdline('srot ')
    eq(child.lua_get('_G.n'), 1)

    type_keys('<Esc>')
  end

  validate_no_change('srot')
  validate_no_change(nil)
end

T['Range preview'] = new_set({
  hooks = {
    pre_case = function() load_module({ autocomplete = { enable = false }, preview_range = { enable = false } }) end,
  },
})

T['Range preview']['works'] = function() MiniTest.skip() end

T['Mappings'] = new_set()

T['Mappings']['work'] = function() MiniTest.skip() end

return T
