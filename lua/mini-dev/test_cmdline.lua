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

local test_dir = 'tests/dir-cmdline'

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local validate_cmdline = function(line, pos)
  eq(child.fn.mode(), 'c')
  eq(child.fn.getcmdline(), line)
  eq(child.fn.getcmdpos(), pos or line:len() + 1)
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

  -- Autocommand group
  eq(child.fn.exists('#MiniCmdline'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniCmdlinePreviewBorder', 'links to FloatBorder')
  has_highlight('MiniCmdlinePreviewNormal', 'links to NormalFloat')
  has_highlight('MiniCmdlinePreviewTitle', 'links to FloatTitle')
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
  expect_config('preview_range.window', { config = {}, winblend = 25 })
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
  expect_config_error({ preview_range = { window = 1 } }, 'preview_range.window', 'table')
  expect_config_error({ preview_range = { window = { config = 1 } } }, 'preview_range.window.config', 'table or callab')
  expect_config_error({ preview_range = { window = { winblend = 'a' } } }, 'preview_range.window.winblend', 'number')
end

T['setup()']['ensures colors'] = function()
  load_module()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniCmdlinePreviewBorder'), 'links to FloatBorder')
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

local default_autocomplete_predicate = forward_lua('MiniCmdline.default_autocomplete_predicate')

T['default_autocomplete_predicate()']['works'] = function()
  load_module({ autocorrect = { enable = false }, preview_range = { enable = false } })
  local validate = function(key, ref)
    type_keys(key)
    eq(default_autocomplete_predicate(), ref)
  end

  type_keys(':')
  eq(default_autocomplete_predicate(), false)
  validate('1', false)
  validate(',', false)
  validate('2', false)
  validate(' ', false)
  validate('h', true)
  validate(' ', true)
  validate("'", true)
  type_keys('<Esc>')

  type_keys(':')
  validate(' ', false)
  validate('h', true)
  validate(' ', true)
  validate("'", true)
  type_keys('<Esc>')

  -- Should work outside of Command-line mode
  type_keys('<Esc>')
  eq(default_autocomplete_predicate(), false)
end

T['default_autocorrect_func()'] = new_set({ hooks = { pre_case = load_module } })

local default_autocorrect_func = forward_lua('MiniCmdline.default_autocorrect_func')

T['default_autocorrect_func()']['works'] = function()
  -- Most of the testing is done in 'Autocorrect' test case
  local validate = function(data, ref) eq(default_autocorrect_func(data), ref) end

  -- General
  validate({ word = 'ste', type = 'command' }, 'set')
  validate({ word = 'set', type = 'command' }, 'set')

  -- Strict type
  validate({ word = 'rndomhue', type = 'color' }, 'randomhue')

  -- Not strict type
  validate({ word = 'MniCmdline', type = 'augroup' }, 'MniCmdline')

  -- Empty string
  validate({ word = 'xxx', type = '' }, 'xxx')
  validate({ word = '', type = 'command' }, '')
  validate({ word = '', type = '' }, '')
end

T['default_autocorrect_func()']['respects `opts.strict_type`'] = function()
  local validate = function(data, ref) eq(default_autocorrect_func(data, { strict_type = false }), ref) end
  validate({ word = 'MniCmdline', type = 'augroup' }, 'MiniCmdline')
  validate({ word = 'Nrmal', type = 'highlight' }, 'Normal')
end

T['default_autocorrect_func()']['respects `opts.get_candidates`'] = function()
  local out = child.lua([[
    _G.log = {}
    local get_cand = function(...) table.insert(_G.log, { ... }); return { 'xxx' } end
    return MiniCmdline.default_autocorrect_func({ word = 'ste', type = 'color' }, { get_candidates = get_cand })
  ]])
  eq(out, 'xxx')
  eq(child.lua_get('_G.log'), { { { type = 'color', word = 'ste' } } })
end

T['default_autocorrect_func()']['validates arguments'] = function()
  expect.error(function() default_autocorrect_func(1) end, '`data`.*table')
  expect.error(function() default_autocorrect_func({ word = 1, type = 'command' }) end, '`data.word`.*string')
  expect.error(function() default_autocorrect_func({ word = 'ste', type = 1 }) end, '`data.type`.*string')
end

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

T['Autocomplete']['does not throw errors'] = function()
  type_keys(':tag')
  -- NOTE: Use `nvim_input` instead of `type_keys()` because the latter checks
  -- `v:errmsg` to propagate the error. However, here on Neovim>=0.12 usage of
  -- `vim.fn.wildtrigger()` *does* set `errmsg` but no error is actuall shown.
  child.api.nvim_input(' ')
  -- What actually should be tested is that there is no errors *shown*, but it
  -- doesn't look easy, as behavior in child process and manual testing differ.
  eq(child.cmd('messages'), '')
  expect.no_match(child.v.errmsg, 'cmdline%.lua')
end

T['Autocomplete']['is not triggered when wildmenu is visible'] = function()
  -- Regular test

  -- In combination with autocorrection
  MiniTest.skip('Currently does not work on Neovim<0.12')
  child.lua('MiniCmdline.config.autocorrect.enable = true')
  child.fn.chdir(test_dir)
  child.cmd('argadd fileA fileB')
  type_keys(':', 'argdel fla', ' ')
  validate_cmdline('argdel fileA ')
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

T['Autocorrect']['works for commands'] = function()
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

  -- Should not correct `:=` command
  -- validate('=123', '=123')
  validate('=_G', '=_G')
end

T['Autocorrect']['works for options'] = function()
  local validate_option = function(input, ref)
    -- In progress
    type_keys(':', input, ' ')
    validate_cmdline(ref .. ' ')
    type_keys('<Esc>')

    -- Final
    type_keys(':', input, '<CR>')
    eq(child.fn.histget('cmd', -1), ref)
  end

  -- NOTE: Need to emulate `n-o-...` and `i-n-v-...` as separate keys as these
  -- case detection relies on user interactively typing keys
  validate_option('set expndtb', 'set expandtab')
  validate_option({ 'set ', 'n', 'o', 'expndtb' }, 'set noexpandtab')
  validate_option({ 'set ', 'i', 'n', 'v', 'expndtb' }, 'set invexpandtab')
  validate_option('set ET', 'set et')
  validate_option({ 'set ', 'n', 'o', 'ET' }, 'set noet')
  validate_option({ 'set ', 'i', 'n', 'v', 'ET' }, 'set invet')

  validate_option('setlocal expndtb', 'setlocal expandtab')

  -- Should work multiple times
  type_keys(':', 'set ET', ' ', 'inorecase', ' ', 'nowrp', ' ', 'invmgic', ' ')
  validate_cmdline('set et ignorecase nowrap invmagic ')
  type_keys('<Esc>')

  -- Correction when option is followed by not space
  local validate_option_char = function(char)
    -- Similarly to `n-o-...` case, need to emulate key before tested character
    type_keys(':', 'set lstchar', 's', char)
    validate_cmdline('set listchars' .. char)
    type_keys('<Esc>')

    type_keys(':', 'set LC', 'S', char)
    validate_cmdline('set lcs' .. char)
    type_keys('<Esc>')
  end

  validate_option_char('=')
  validate_option_char('?')
  validate_option_char('!')
  validate_option_char('&')
  validate_option_char('^')
  validate_option_char('+')
  validate_option_char('-')
end

T['Autocorrect']['works for other types'] = function()
  local validate_inprogress = function(input, ref)
    type_keys(':', input, ' ')
    validate_cmdline(ref .. ' ')
    type_keys('<Esc>')
  end
  local validate_final = function(input, ref)
    type_keys(':', input, '<CR>')
    eq(child.fn.histget('cmd', -1), ref)
  end

  child.fn.chdir(test_dir)
  child.cmd([[let &runtimepath.=','.getcwd()]])
  child.cmd([[let &packpath.=','.getcwd()]])

  -- arglist
  child.cmd('argadd fileA fileB')
  validate_inprogress('argdel fla', 'argdel fileA')
  validate_final('argdel flb', 'argdel fileB')

  -- buffer
  child.cmd('edit fileA')
  child.cmd('edit fileB')
  -- - No in-progress check since `:buffer` expects single argument
  validate_final('buffer flB', 'buffer fileB')

  -- color
  -- - No in-progress check since `:colorscheme` expects single argument
  validate_final('colorscheme dfault', 'colorscheme default')

  -- compiler
  -- - No in-progress check since `:compiler` expects single argument
  validate_final('compiler tstcompiler', 'compiler testcompiler')

  -- diff_buffer
  child.cmd('edit fileA')
  child.cmd('diffsplit fileB')
  -- - No in-progress check since `:diffput` expects single argument
  validate_final('diffput flA', 'diffput fileA')

  child.cmd('%bwipeout')
  child.cmd('only')

  -- event
  validate_inprogress('au Cmdlinelve', 'au CmdlineLeave')
  validate_final('au BfEnter', 'au BufEnter')
  type_keys('<C-c>')

  -- filetype
  -- - No in-progress check since `:setfiletype` expects single argument
  validate_final('setfiletype pthon', 'setfiletype python')

  -- history
  -- - No in-progress check since `:history` expects single argument
  validate_final('history srch', 'history search')

  -- keymap
  -- Neovim<0.10 has no 'keymap' `:h :command-complete` value
  if child.fn.has('nvim-0.10') == 1 then
    validate_inprogress('set keymap=tstkeymap', 'set keymap=testkeymap')
    validate_final('set keymap=tstkeymap', 'set keymap=testkeymap')
  end

  -- locale
  -- - No in-progress check since `:language time` expects single argument
  -- No easy way to test locales on non-Linux
  if child.fn.has('linux') == 1 then validate_final('language time PSX', 'language time POSIX') end

  -- mapclear
  -- Neovim<0.11 has wrong `complpat` computation in this case
  if child.fn.has('nvim-0.11') == 1 then
    -- - No in-progress check since `:mapclear` expects single argument
    validate_final({ 'mapclear ', '<', 'bfr', '>' }, 'mapclear <buffer>')
  end

  -- messages
  -- - No in-progress check since `:messages` expects single argument
  validate_final('messages clr', 'messages clear')

  -- packadd
  -- - No in-progress check since `:packadd` expects single argument
  validate_final('packadd tstplugin', 'packadd testplugin')

  -- sign
  validate_inprogress('sign dfine', 'sign define')
  validate_final('sign lst', 'sign list')

  -- syntax
  -- Neovim<0.10 does not set `compltype=syntax` in this case
  if child.fn.has('nvim-0.10') == 1 then
    validate_inprogress('set syntax=LUA', 'set syntax=lua')
    validate_final('set syntax=LUA', 'set syntax=lua')
  end

  -- syntime
  -- - No in-progress check since `:syntime` expects single argument
  validate_final('syntime clr', 'syntime clear')

  MiniTest.skip('Finish `option` type')
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

T['Autocorrect']['respects mappings'] = function()
  -- Should not work if Command-line mode is both entered and exited
  child.cmd('nnoremap <C-x> :ehco<CR>')
  local ok, err = pcall(type_keys, '<C-x>')
  eq(ok, false)
  eq(err, 'E492: Not an editor command: ehco')

  -- Should work if Command-line mode is only entered
  child.cmd('nnoremap <C-y> :ehco')
  type_keys('<C-y>', '<CR>')
  eq(child.fn.histget('cmd', -1), 'echo')
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

  -- Handles improper output
  child.lua([[
    _G.notify_log = {}
    vim.notify = function(...) table.insert(_G.notify_log, { ... }) end
    MiniCmdline.config.autocorrect.func = function() return 1 end
  ]])
  type_keys(':', 'srot', ' ')
  validate_cmdline('srot ')
  local warn_level = child.lua_get('vim.log.levels.WARN')
  eq(child.lua_get('_G.notify_log'), { { '(mini.cmdline) Can not autocorrect for "srot"', warn_level } })
end

T['Autocorrect']['works just before final <CR>'] = function()
  local validate = function(bad_word, ref_word)
    type_keys(':', bad_word, '<CR>')
    eq(child.fn.histget('cmd', -1), ref_word)
    eq(child.fn.mode(), 'n')
  end

  local buf_id_other = child.api.nvim_create_buf(true, false)
  validate('bnxxt', 'bnext')
  eq(child.api.nvim_get_current_buf(), buf_id_other)
  type_keys('<Esc>')

  -- Should work with `!`
  child.cmd('vsplit')
  local win_id = child.api.nvim_get_current_win()
  validate({ 'Q', '!' }, 'q!')
  eq(child.api.nvim_win_is_valid(win_id), false)
end

T['Autocorrect']['is not applied when abandoning command line'] = function()
  local validate = function(key)
    type_keys(':', 'xxxx', key)
    eq(child.fn.histget('cmd', -1), 'xxxx')
  end
  validate('<Esc>')
  validate('<C-c>')
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

T['Range preview']['works after deleting text'] = function()
  -- With <BS>

  -- With <C-w>

  -- With <C-u>

  MiniTest.skip()
end

T['Range preview']['is not shown after visual selection'] = function()
  -- Otherwise it hides visual selection, which itself is kind of range preview
  MiniTest.skip()
end

T['Range preview']['can be hidden and opened within same session'] = function() MiniTest.skip() end

T['Range preview']['works if range is present immediately'] = function()
  child.cmd('nnoremap <C-x> :2,3')
  MiniTest.skip()
end

T['Range preview']['works with out-of-bounds values'] = function()
  -- Both `from` and `to`
  MiniTest.skip()
end

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
