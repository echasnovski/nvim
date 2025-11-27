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
  expect_config('autocomplete.map_arrows', true)
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
  expect_config_error({ autocomplete = { map_arrows = 1 } }, 'autocomplete.map_arrows', 'boolean')
  expect_config_error({ autocorrect = 1 }, 'autocorrect', 'table')
  expect_config_error({ autocorrect = { enable = 1 } }, 'autocorrect.enable', 'boolean')
  expect_config_error({ autocorrect = { func = 1 } }, 'autocorrect.func', 'function')
  expect_config_error({ preview_range = 1 }, 'preview_range', 'table')
  expect_config_error({ preview_range = { enable = 1 } }, 'preview_range.enable', 'boolean')
end

T['setup()']['sets recommended option values'] = function()
  local check_wildmode = child.fn.has('nvim-0.11') == 1
  load_module()
  eq(child.o.wildoptions, 'pum,fuzzy')
  if check_wildmode then eq(child.o.wildmode, 'noselect,full') end

  -- Should not set if was previously set
  child.o.wildoptions = 'pum'
  if check_wildmode then child.o.wildmode = 'full' end
  load_module()
  eq(child.o.wildoptions, 'pum')
  if check_wildmode then eq(child.o.wildmode, 'full') end

  -- Should only set 'wildmode' if autocomplete is enabled
  if check_wildmode then
    child.restart({ '--noplugin', '-u', 'lua/mini-dev/minimal_init.lua' })
    load_module({ autocomplete = { enable = false } })
    eq(child.o.wildmode, 'full')
  end
end

T['default_autocomplete_predicate()'] = new_set()

T['default_autocomplete_predicate()']['works'] = function()
  load_module()
  eq(child.lua_get('MiniCmdline.default_autocomplete_predicate()'), true)
end

T['default_autocorrect_func()'] = new_set()

T['default_autocorrect_func()']['works'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
T['Autocomplete'] = new_set({
  hooks = {
    pre_case = function() load_module({ autocorrect = { enable = false }, preview_range = { enable = false } }) end,
  },
})

T['Autocomplete']['works'] = function() MiniTest.skip() end

T['Autocomplete']["works with different 'wildchar'"] = function()
  MiniTest.skip()
  child.cmd('set wildchar=<Down>')
  type_keys(':', 'h')
  child.expect_screenshot()
end

T['Autocomplete']['respects `vim.{g,b}.minicmdline_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicmdline_disable = true
    MiniTest.skip()
  end,
})

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
  child.cmd('command Git echo "World"')

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

  -- Should respect "ignore case" matches
  validate('WrItE', 'write')
  validate('W', 'w')
  validate('NNO', 'nno')

  validate('myc', 'MyC')

  -- Should prefer "respect case" abbreviation over "ignore case"
  validate('%g', '%g')

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

T['Autocorrect']['can act after mappings appended text'] = function()
  -- Should act if text increases latest word
  child.cmd('cnoremap <C-x> www')
  type_keys(':', 'XX', '<C-x>')
  validate_cmdline('XXwww')
  type_keys(' ')
  validate_cmdline('below ')
  type_keys('<Esc>')

  -- Should act if text finishes the last word.
  child.cmd('cnoremap <C-y> www<Space>')
  type_keys(':', 'XX', '<C-y>')
  -- Whole new text from the mapping is treated as "separator text" and is not
  -- included into autocorrected word. It might be good to have the new text
  -- also be part of the word to correct (`XXwww` here instead of `XX`), but it
  -- seems too complex to implement (if reasonably possible even).
  validate_cmdline('exwww ')
  type_keys('<Esc>')
end

T['Autocomplete']['works only when appending new word'] = function()
  type_keys(':', 'set ', '<Left>')
  type_keys('<BS>')
  validate_cmdline('se ', 3)
  type_keys('T')
  validate_cmdline('seT ', 4)
  type_keys(' ')
  validate_cmdline('seT  ', 5)
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

T['Autocorrect']['suggests only valid abbreviations'] = function()
  -- Should uniquely identify user commands
  child.cmd('command MyCommandA echo "Hello"')
  child.cmd('command MyCommandB echo "World"')

  type_keys(':', 'MyComman', ' ')
  validate_cmdline('MyCommandA ')
  type_keys('<Esc>')

  -- `:def` is not a valid abbreviation
  type_keys(':', 'def', ' ')
  validate_cmdline('de ')
  type_keys('<Esc>')
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

T['Autocorrect']['uses correct state before final <CR>'] = function()
  child.lua([[
    _G.log = {}
    MiniCmdline.config.autocorrect.func = function(data)
      table.insert(_G.log, vim.deepcopy(data))
      return data.word
    end
  ]])

  -- Changing `type` just before `<CR>`
  type_keys(':', 'cnoremap <C-x> www', '<CR>')
  type_keys(':', 'cn', '<Up>')
  validate_cmdline('cnoremap \24 www')
  child.lua('_G.log = {}')
  type_keys('<CR>')
  local ref_word = child.fn.has('nvim-0.11') == 1 and '\24 www' or 'www'
  eq(child.lua_get('_G.log'), { { word = ref_word, type = 'mapping' } })

  -- Should include `!` in the word (when using `vim.fn.getcmdcomplpat()`)
  if child.fn.has('nvim-0.11') == 0 then return end
  child.cmd('split')
  child.lua('_G.log = {}')
  type_keys(':', 'q!', '<CR>')
  eq(child.lua_get('_G.log'), { { word = 'q!', type = '' } })
end

T['Autocorrect']['respects `vim.{g,b}.minicmdline_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicmdline_disable = true
    type_keys(':', 'seT', ' ')
    validate_cmdline('seT ')
  end,
})

T['Range preview'] = new_set({
  hooks = {
    pre_case = function() load_module({ autocomplete = { enable = false }, preview_range = { enable = false } }) end,
  },
})

T['Range preview']['works'] = function() MiniTest.skip() end

T['Range preview']['respects `vim.{g,b}.minicmdline_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicmdline_disable = true
    MiniTest.skip()
  end,
})

T['Arrow mappings'] = new_set()

T['Arrow mappings']['work'] = function() MiniTest.skip() end

T['Arrow mappings']['respect `config.autocomplete.map_arrows`'] = function() MiniTest.skip() end

return T
