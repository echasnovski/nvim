local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq, no_eq = helpers.expect, helpers.expect.equality, helpers.expect.no_equality
local eq_partial_tbl = helpers.expect.equality_partial_tbl
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('snippets', config) end
local unload_module = function() child.mini_unload('snippets') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
local new_buf = function() return child.api.nvim_create_buf(true, false) end
local new_scratch_buf = function() return child.api.nvim_create_buf(false, true) end
local get_buf = function() return child.api.nvim_get_current_buf() end
local set_buf = function(buf_id) child.api.nvim_set_current_buf(buf_id) end
--stylua: ignore end

local test_dir = 'tests/dir-snippets'
local test_dir_absolute = vim.fn.fnamemodify(test_dir, ':p'):gsub('\\', '/'):gsub('(.)/$', '%1')

-- Time constants
local small_time = helpers.get_time_const(10)

-- Tweak `expect_screenshot()` to test only on Neovim>=0.10 (as it has inline
-- extmarks support). Use `child.expect_screenshot_orig()` for original testing.
child.expect_screenshot_orig = child.expect_screenshot
child.expect_screenshot = function(opts)
  if child.fn.has('nvim-0.10') == 0 then return end
  child.expect_screenshot_orig(opts)
end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local get = forward_lua('MiniSnippets.session.get')
local get_all = function() return get(true) end
local jump = forward_lua('MiniSnippets.session.jump')
local stop = forward_lua('MiniSnippets.session.stop')

-- Common helpers
local get_cur_tabstop = function() return (get() or {}).cur_tabstop end

local validate_active_session = function() eq(child.lua_get('MiniSnippets.session.get() ~= nil'), true) end
local validate_no_active_session = function() eq(child.lua_get('MiniSnippets.session.get() ~= nil'), false) end
local validate_n_sessions = function(n) eq(child.lua_get('#MiniSnippets.session.get(true)'), n) end

local validate_pumvisible = function() eq(child.fn.pumvisible(), 1) end
local validate_no_pumvisible = function() eq(child.fn.pumvisible(), 0) end
local validate_pumitems = function(ref)
  eq(vim.tbl_map(function(t) return t.word end, child.fn.complete_info().items), ref)
end

local validate_state = function(mode, lines, cursor)
  if mode ~= nil then eq(child.fn.mode(), mode) end
  if lines ~= nil then eq(get_lines(), lines) end
  if cursor ~= nil then eq(get_cursor(), cursor) end
end

local setup_event_log = function()
  child.lua([[
    local suffixes = { 'Start', 'Stop', 'Suspend', 'Resume', 'JumpPre', 'Jump' }
    local au_events = vim.tbl_map(function(s) return 'MiniSnippetsSession' .. s end, suffixes)
    _G.au_log = {}
    local log_event = function(args)
      table.insert(au_log, { buf_id = args.buf, event = args.match, data = args.data })
    end
    vim.api.nvim_create_autocmd('User', { pattern = au_events, callback = log_event })
  ]])
end

local get_au_log = function() return child.lua_get('_G.au_log') end

local clean_au_log = function() return child.lua('_G.au_log = {}') end

local get_snippet_body = function(session) return (session or get()).insert_args.snippet.body end
local make_snippet_body = function(body) return { insert_args = { snippet = body } } end

local make_get_extmark = function(session)
  local buf_id, ns_id = session.buf_id, session.ns_id
  return function(extmark_id)
    local data = child.api.nvim_buf_get_extmark_by_id(buf_id, ns_id, extmark_id, { details = true })
    data[3].row, data[3].col = data[1], data[2]
    return data[3]
  end
end

local validate_session_nodes_partial = function(session, ref_nodes)
  local get_extmark = make_get_extmark(session)
  local nodes = vim.deepcopy(session.nodes)
  -- Replace `extmark_id` (should be present in every node) with extmark data
  local replace_extmarks
  replace_extmarks = function(n_arr)
    for _, n in ipairs(n_arr) do
      n.extmark = get_extmark(n.extmark_id)
      n.extmark_id = nil
      if n.placeholder ~= nil then replace_extmarks(n.placeholder) end
    end
  end
  replace_extmarks(nodes)

  eq_partial_tbl(nodes, ref_nodes)
end

local ensure_clean_state = function()
  child.lua([[while MiniSnippets.session.get() do MiniSnippets.session.stop() end]])
  -- while get() do stop() end
  child.ensure_normal_mode()
  set_lines({})
  clean_au_log()
end

local edit = function(path)
  child.cmd('edit ' .. child.fn.fnameescape(path))
  -- Slow context needs a small delay to get things up to date
  if helpers.is_slow() then sleep(small_time) end
end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.set_size(8, 40)
      set_buf(new_buf())

      load_module()
    end,
    post_once = child.stop,
    n_retry = helpers.get_n_retry(2),
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniSnippets)'), 'table')

  -- Highlight groups
  child.cmd('hi clear')
  child.cmd('hi DiagnosticUnderlineError guisp=#ff0000 gui=underline cterm=underline')
  child.cmd('hi DiagnosticUnderlineWarn guisp=#ffff00 gui=undercurl cterm=undercurl')
  child.cmd('hi DiagnosticUnderlineInfo guisp=#0000ff gui=underdotted cterm=underline')
  child.cmd('hi DiagnosticUnderlineHint guisp=#00ffff gui=underdashed cterm=underdashed')
  child.cmd('hi DiagnosticUnderlineOk guifg=#00ff00 guibg=#000000')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniSnippetsCurrent', 'gui=underdouble guisp=#ffff00')
  has_highlight('MiniSnippetsCurrentReplace', 'gui=underdouble guisp=#ff0000')
  has_highlight('MiniSnippetsFinal', 'gui=underdouble')
  has_highlight('MiniSnippetsUnvisited', 'gui=underdouble guisp=#00ffff')
  has_highlight('MiniSnippetsVisited', 'gui=underdouble guisp=#0000ff')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniSnippets.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniSnippets.config.' .. field), value) end

  expect_config('snippets', {})
  expect_config('mappings.expand', '<C-j>')
  expect_config('mappings.jump_next', '<C-l>')
  expect_config('mappings.jump_prev', '<C-h>')
  expect_config('mappings.stop', '<C-c>')
  expect_config('expand', { match = nil, select = nil, insert = nil })
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ snippets = { { prefix = 'a', body = 'axa' } } })
  eq(child.lua_get('MiniSnippets.config.snippets'), { { prefix = 'a', body = 'axa' } })
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ snippets = 1 }, 'snippets', 'table')
  expect_config_error({ mappings = 1 }, 'mappings', 'table')
  expect_config_error({ mappings = { expand = 1 } }, 'mappings.expand', 'string')
  expect_config_error({ mappings = { jump_next = 1 } }, 'mappings.jump_next', 'string')
  expect_config_error({ mappings = { jump_prev = 1 } }, 'mappings.jump_prev', 'string')
  expect_config_error({ mappings = { stop = 1 } }, 'mappings.stop', 'string')
  expect_config_error({ expand = 1 }, 'expand', 'table')
  expect_config_error({ expand = { match = 1 } }, 'expand.match', 'function')
  expect_config_error({ expand = { select = 1 } }, 'expand.select', 'function')
  expect_config_error({ expand = { insert = 1 } }, 'expand.insert', 'function')
end

T['expand()'] = new_set()

local expand = forward_lua('MiniSnippets.expand')

T['expand()']['works'] = function() MiniTest.skip() end

T['gen_loader.from_lang()'] = new_set()

T['gen_loader.from_lang()']['works'] = function() MiniTest.skip() end

T['gen_loader.from_runtime()'] = new_set()

T['gen_loader.from_runtime()']['works'] = function() MiniTest.skip() end

T['gen_loader.from_file()'] = new_set()

T['gen_loader.from_file()']['works'] = function() MiniTest.skip() end

T['read_file()'] = new_set()

local read_file = forward_lua('MiniSnippets.read_file')

T['read_file()']['works'] = function() MiniTest.skip() end

T['default_match()'] = new_set()

local default_match = forward_lua('MiniSnippets.default_match')

T['default_match()']['works'] = function() MiniTest.skip() end

T['default_select()'] = new_set()

local default_select = forward_lua('MiniSnippets.default_select')

T['default_select()']['works'] = function() MiniTest.skip() end

T['default_insert()'] = new_set()

local default_insert = forward_lua('MiniSnippets.default_insert')

T['default_insert()']['works'] = function()
  -- Just text
  child.cmd('startinsert')
  default_insert({ body = 'Text' })
  validate_state('i', { 'Text' }, { 1, 4 })
  validate_no_active_session()
  ensure_clean_state()

  -- With tabstops (should start active session)
  child.cmd('startinsert')
  default_insert({ body = 'T1=$1 T2=$2' })
  validate_state('i', { 'T1= T2=' }, { 1, 3 })
  validate_active_session()
  jump('next')
  validate_state('i', { 'T1= T2=' }, { 1, 7 })
  ensure_clean_state()

  -- Should allow array of strings as body
  child.cmd('startinsert')
  default_insert({ body = { 'T1=$1', 'T0=$0' } })
  validate_state('i', { 'T1=', 'T0=' }, { 1, 3 })
end

T['default_insert()']['ensures Insert mode in current buffer'] = function()
  -- Normal mode
  default_insert({ body = 'Text' })
  validate_state('i', { 'Text' }, { 1, 4 })
  ensure_clean_state()

  default_insert({ body = 'T1=$1' })
  validate_state('i', { 'T1=' }, { 1, 3 })
  validate_active_session()
  ensure_clean_state()

  -- Visual mode
  type_keys('v')
  eq(child.fn.mode(), 'v')
  default_insert({ body = 'T1=$1 T2=$2' })
  validate_state('i', { 'T1= T2=' }, { 1, 3 })
  ensure_clean_state()

  -- Command-line mode
  type_keys(':')
  eq(child.fn.mode(), 'c')
  default_insert({ body = 'T1=$1' })
  validate_state('i', { 'T1=' }, { 1, 3 })
end

T['default_insert()']['deletes snippet region'] = function()
  set_lines({ 'abcd' })
  local region = { from = { line = 1, col = 2 }, to = { line = 1, col = 3 } }
  default_insert({ body = 'T1=$1', region = region })
  validate_state('i', { 'aT1=d' }, { 1, 4 })
end

T['default_insert()']['can be used to create nested session'] = function()
  default_insert({ body = 'T1=$1' })
  validate_n_sessions(1)
  validate_state('i', { 'T1=' }, { 1, 3 })

  default_insert({ body = 'T2=$2' })
  validate_n_sessions(2)
  validate_state('i', { 'T1=T2=' }, { 1, 6 })
end

T['default_insert()']['indent'] = new_set()

T['default_insert()']['indent']['is added on every new line'] = function()
  type_keys('i', ' \t')
  default_insert({ body = 'multi\n  line\n\ttext\n' })
  validate_state('i', { ' \tmulti', ' \t  line', ' \t\ttext', ' \t' }, { 4, 2 })
  ensure_clean_state()

  type_keys('i', ' ')
  default_insert({ body = 'T1=$1\nT0=$0' })
  validate_state('i', { ' T1=', ' T0=' }, { 1, 4 })
  ensure_clean_state()

  -- Should use line's indent (even if inserted not next to whitespace)
  type_keys('i', ' \txxx \t')
  default_insert({ body = 'multi\nline\n' })
  validate_state('i', { ' \txxx \tmulti', ' \tline', ' \t' }, { 3, 2 })
  ensure_clean_state()

  -- Inserting in Normal mode is the same as pressing `i` beforehand
  type_keys('i', '   ', '<Esc>')
  default_insert({ body = 'multi\nline' })
  validate_state('i', { '  multi', '  line ' }, { 2, 6 })
end

--stylua: ignore
T['default_insert()']['indent']['works inside comments'] = function()
  local validate = function(cur_line, lines_after)
    set_lines({ cur_line })
    type_keys('A')
    default_insert({ body = 'multi\nline\n text\n' })
    eq(get_lines(), lines_after)
    ensure_clean_state()
  end

  -- Indent with comment under 'commentstring'
  child.o.commentstring = '# %s'

  validate('#',     { '#multi',     '#line',     '# text',     '#' })
  validate('# ',    { '# multi',    '# line',    '#  text',    '# ' })
  validate('#\t',   { '#\tmulti',   '#\tline',   '#\t text',   '#\t' })
  validate(' # ',   { ' # multi',   ' # line',   ' #  text',   ' # ' })
  validate('\t# ',  { '\t# multi',  '\t# line',  '\t#  text',  '\t# ' })
  validate('\t#\t', { '\t#\tmulti', '\t#\tline', '\t#\t text', '\t#\t' })

  validate('#xx',      { '#xxmulti',      '#line',     '# text',     '#' })
  validate(' # xx ',   { ' # xx multi',   ' # line',   ' #  text',   ' # ' })
  validate('\t#\txx ', { '\t#\txx multi', '\t#\tline', '\t#\t text', '\t#\t' })

  -- Indent with comment under 'comments' parts
  child.bo.comments = ':---,:--'

  validate('--',     { '--multi',     '--line',     '-- text',     '--' })
  validate('-- ',    { '-- multi',    '-- line',    '--  text',    '-- ' })
  validate('--\t',   { '--\tmulti',   '--\tline',   '--\t text',   '--\t' })
  validate(' -- ',   { ' -- multi',   ' -- line',   ' --  text',   ' -- ' })
  validate('\t-- ',  { '\t-- multi',  '\t-- line',  '\t--  text',  '\t-- ' })
  validate('\t--\t', { '\t--\tmulti', '\t--\tline', '\t--\t text', '\t--\t' })

  validate('--xx',     { '--xxmulti',     '--line',     '-- text',     '--' })
  validate(' -- xx',   { ' -- xxmulti',   ' -- line',   ' --  text',   ' -- ' })
  validate('\t--\txx', { '\t--\txxmulti', '\t--\tline', '\t--\t text', '\t--\t' })

  -- Should respect `b` flag (leader should be followed by space/tab/EOL)
  child.bo.comments = 'b:*'
  validate('*',   { '*multi',   'line',   ' text',   '' })
  validate(' *',  { ' *multi',  ' line',  '  text',  ' ' })
  validate('\t*', { '\t*multi', '\tline', '\t text', '\t' })

  validate('* ',    { '* multi',    '* line',    '*  text',    '* ' })
  validate('*\t',   { '*\tmulti',   '*\tline',   '*\t text',   '*\t' })
  validate(' * ',   { ' * multi',   ' * line',   ' *  text',   ' * ' })
  validate('\t*\t', { '\t*\tmulti', '\t*\tline', '\t*\t text', '\t*\t' })

  validate('* xx',  { '* xxmulti',  '* line',  '*  text',  '* ' })
  validate('*\txx', { '*\txxmulti', '*\tline', '*\t text', '*\t' })

  -- Should respect `f` flag (only first line should have it)
  child.bo.comments = 'f:-'
  validate('-',   { '-multi',   'line',   ' text',   '' })
  validate(' -',  { ' -multi',  ' line',  '  text',  ' ' })
  validate('\t-', { '\t-multi', '\tline', '\t text', '\t' })

  validate(' - ',   { ' - multi',   ' line',  '  text',  ' ' })
  validate('\t-\t', { '\t-\tmulti', '\tline', '\t text', '\t' })
end

T['default_insert()']['indent']['computes "indent at cursor"'] = function()
  type_keys('i', '   ', '<Left>')
  eq(get_cursor(), { 1, 2 })
  default_insert({ body = 'multi\nline' })
  validate_state('i', { '  multi', '  line ' }, { 2, 6 })
  ensure_clean_state()

  child.o.commentstring = '--%s'
  type_keys('i', ' --', '<Left>')
  eq(get_cursor(), { 1, 2 })
  default_insert({ body = 'multi\nline' })
  -- `--` is not treated as part of indent because cursor is inside of it
  validate_state('i', { ' -multi', ' line-' }, { 2, 5 })
end

T['default_insert()']['indent']['respects manual lookup entries'] = function()
  type_keys('i', ' \t')
  local lookup = { ['1'] = 'tab\nstop', AAA = 'aaa\nbbb' }
  default_insert({ body = 'T1=$1\nAAA=$AAA' }, { lookup = lookup })
  validate_state('i', { ' \tT1=tab', ' \tstop', ' \tAAA=aaa', ' \tbbb' }, { 2, 6 })
end

T['default_insert()']['triggers start/stop events'] = function()
  local make_ref_data = function(snippet_body)
    return { session = { insert_args = { snippet = { body = snippet_body } } } }
  end
  setup_event_log()
  local body, cur_buf = 'T1=$1 T0=0', get_buf()

  default_insert({ body = body })
  eq_partial_tbl(get_au_log(), { { event = 'MiniSnippetsSessionStart', data = make_ref_data(body), buf_id = cur_buf } })
  clean_au_log()

  stop()
  eq_partial_tbl(get_au_log(), { { event = 'MiniSnippetsSessionStop', data = make_ref_data(body), buf_id = cur_buf } })
end

T['default_insert()']['respects tab-related options'] = function()
  child.bo.expandtab = true
  child.bo.shiftwidth = 3
  default_insert({ body = '\tT1=$1\n\t\tT0=$0' })
  validate_state('i', { '   T1=', '      T0=' }, { 1, 6 })
  ensure_clean_state()

  child.bo.shiftwidth, child.bo.tabstop = 0, 2
  default_insert({ body = '\ttext\t\t' })
  validate_state('i', { '  text    ' }, { 1, 10 })
  ensure_clean_state()

  child.bo.expandtab = false
  default_insert({ body = '\tT1=$1\n\t\tT0=$0' })
  validate_state('i', { '\tT1=', '\t\tT0=' }, { 1, 4 })
  ensure_clean_state()

  default_insert({ body = '\ttext\t\t' })
  validate_state('i', { '\ttext\t\t' }, { 1, 7 })
end

T['default_insert()']['shows tabstop choices after start'] = function()
  -- Called in Insert mode
  type_keys('i')
  default_insert({ body = 'T1=${1|aa,bb|}' })
  validate_pumitems({ 'aa', 'bb' })
  ensure_clean_state()

  -- Called in Normal mode
  default_insert({ body = 'T1=${1|aa,bb|}' })
  validate_pumitems({ 'aa', 'bb' })
  -- - Should not be side effects
  eq(child.cmd_capture('au ModeChanged'):find('Show popup') == nil, true)
end

T['default_insert()']['direct call removes placeholder'] = function()
  default_insert({ body = 'T1=${1:<xxx>}' })
  -- This can happen if `<C-g><C-j>` (i.e. insert snippet without typing prefix
  -- to match) after jumping to tabstop with placeholder
  default_insert({ body = 'U1=$1' })
  validate_state('i', { 'T1=U1=' }, { 1, 6 })
end

T['default_insert()']['respects `opts.empty_tabstop` and `opts.empty_tabstop_final`'] = function()
  default_insert({ body = 'T1=$1 T2=$2 T0=$0' }, { empty_tabstop = '!', empty_tabstop_final = '?' })
  child.expect_screenshot()
end

T['default_insert()']['respects `opts.lookup`'] = function()
  local lookup = { AAA = 'aaa', TM_SELECTED_TEXT = 'xxx', ['1'] = 'tabstop' }
  default_insert({ body = '$AAA $TM_SELECTED_TEXT $1 $1 $2' }, { lookup = lookup })
  child.expect_screenshot()
  -- Looked up tabstop text should be treated as if user typed it (i.e. proper
  -- cursor position and no placeholder)
  eq(get_cursor(), { 1, 15 })
  eq(get().nodes[5].text, 'tabstop')
end

T['default_insert()']['validates input'] = function()
  expect.error(function() default_insert('Text') end, '`snippet`.*snippet table')
  expect.error(function() default_insert({ body = 'Text' }, { empty_tabstop = 1 }) end, '`empty_tabstop`.*string')
  expect.error(
    function() default_insert({ body = 'Text' }, { empty_tabstop_final = 1 }) end,
    '`empty_tabstop_final`.*string'
  )
  expect.error(function() default_insert({ body = 'Text' }, { lookup = 1 }) end, '`lookup`.*table')
end

T['session.get()'] = new_set()

T['session.get()']['works'] = function()
  -- Should work without active session
  eq(get(), vim.NIL)

  default_insert({ body = 'T1=${1:<$2>}' }, { empty_tabstop = '$' })
  local session = get()

  -- Should return correct data structure
  local fields = vim.tbl_keys(session)
  table.sort(fields)
  eq(fields, { 'buf_id', 'cur_tabstop', 'extmark_id', 'insert_args', 'nodes', 'ns_id', 'tabstops' })

  local cur_buf = get_buf()
  local ref_partial_session = {
    buf_id = cur_buf,
    cur_tabstop = '1',
    insert_args = {
      snippet = { body = 'T1=${1:<$2>}' },
      opts = { empty_tabstop = '$', empty_tabstop_final = '∎', lookup = {} },
    },
    tabstops = {
      ['0'] = { is_visited = false, prev = '2', next = '1' },
      ['1'] = { is_visited = true, prev = '0', next = '2' },
      ['2'] = { is_visited = false, prev = '1', next = '0' },
    },
  }
  eq_partial_tbl(session, ref_partial_session)

  -- Should return valid namespace for present extmarks
  local ns_id, is_valid_ns_id = session.ns_id, false
  for _, id in pairs(child.api.nvim_get_namespaces()) do
    is_valid_ns_id = is_valid_ns_id or id == ns_id
  end
  eq(is_valid_ns_id, true)

  -- Should have correct session extmark
  local get_extmark = make_get_extmark(session)
  local ref_extmark = { row = 0, col = 0, end_row = 0, end_col = 5, right_gravity = false, end_right_gravity = true }
  eq_partial_tbl(get_extmark(session.extmark_id), ref_extmark)

  -- Should have proper node structure with correct extmarks attached to nodes
  local has_inline_extmarks = child.fn.has('nvim-0.10') == 1
  --stylua: ignore
  local ref_nodes = {
    { text = 'T1=', extmark = { row = 0, col = 0, end_row = 0, end_col = 3 } },
    {
      tabstop = '1',
      extmark = { row = 0, col = 3, end_row = 0, end_col = 5, right_gravity = false, end_right_gravity = true },
      placeholder = {
        { text = '<', extmark = { row = 0, col = 3, end_row = 0, end_col = 4 } },
        {
          tabstop = '2',
          extmark = {
            row = 0, col = 4, end_row = 0, end_col = 4,
            virt_text = has_inline_extmarks and { { '$', 'MiniSnippetsCurrentReplace' } } or nil,
            virt_text_pos = has_inline_extmarks and 'inline' or nil,
          },
          placeholder = {
            { text = '', extmark = { row = 0, col = 4, end_row = 0, end_col = 4 } }
          },
        },
        { text = '>', extmark = { row = 0, col = 4, end_row = 0, end_col = 5 } },
      }
    },
    {
      tabstop = '0',
      text = '',
      extmark = {
        row = 0, col = 5, end_row = 0, end_col = 5,
        virt_text = has_inline_extmarks and { { '∎', 'MiniSnippetsFinal' } } or nil,
        virt_text_pos = has_inline_extmarks and 'inline' or nil,
      }
    }
  }
  validate_session_nodes_partial(session, ref_nodes)

  -- Should update nodes immediately if they are removed
  type_keys('x')
  session = get()
  ref_nodes = {
    { text = 'T1=', extmark = { row = 0, col = 0, end_row = 0, end_col = 3 } },
    { tabstop = '1', text = 'x', extmark = { row = 0, col = 3, end_row = 0, end_col = 4 } },
    { tabstop = '0', text = '', extmark = { row = 0, col = 4, end_row = 0, end_col = 4 } },
  }
  validate_session_nodes_partial(session, ref_nodes)

  -- Session's tabstop can be used to track session's total region
  get_extmark = make_get_extmark(session)
  eq_partial_tbl(get_extmark(session.extmark_id), { row = 0, col = 0, end_row = 0, end_col = 4 })

  -- Should return copy of the session data
  local is_copy = child.lua([[
    local session = MiniSnippets.session.get()
    local ref_cur_tabstop = session.cur_tabstop
    session.cur_tabstop = -1
    return MiniSnippets.session.get().cur_tabstop == ref_cur_tabstop
  ]])
  eq(is_copy, true)
end

T['session.get()']['reflects up to date tabstop data after jumps'] = function()
  local validate_tabstops = function(ref_cur_tabstop, ref_visited)
    local session = get()
    eq(session.cur_tabstop, ref_cur_tabstop)
    local out_visited = {}
    for id, data in pairs(get().tabstops) do
      out_visited[id] = data.is_visited
    end
    eq(out_visited, ref_visited)
  end

  default_insert({ body = 'T1=$1 T2=$2 T0=$0' })
  validate_tabstops('1', { ['1'] = true, ['2'] = false, ['0'] = false })
  jump('next')
  validate_tabstops('2', { ['1'] = true, ['2'] = true, ['0'] = false })
  -- Already visited should keep returning `true`
  jump('prev')
  validate_tabstops('1', { ['1'] = true, ['2'] = true, ['0'] = false })
  jump('prev')
  validate_tabstops('0', { ['1'] = true, ['2'] = true, ['0'] = true })
end

T['session.get()']['respects `all` argument'] = function()
  default_insert({ body = 'T1=$1 T0=$0' })
  default_insert({ body = 'U1=$1 U0=$0' })
  local sessions = get(true)
  eq(#sessions, 2)

  local cur_buf = get_buf()
  eq_partial_tbl(sessions, {
    { buf_id = cur_buf, cur_tabstop = '1', insert_args = { snippet = { body = 'T1=$1 T0=$0' } } },
    { buf_id = cur_buf, cur_tabstop = '1', insert_args = { snippet = { body = 'U1=$1 U0=$0' } } },
  })

  -- Previous session's extmarks should still be tracking
  eq_partial_tbl(make_get_extmark(sessions[1])(sessions[1].extmark_id), { row = 0, col = 0, end_row = 0, end_col = 14 })
  type_keys('x')
  eq_partial_tbl(make_get_extmark(sessions[1])(sessions[1].extmark_id), { row = 0, col = 0, end_row = 0, end_col = 15 })
end

T['session.jump()'] = new_set()

local validate_jumps = function(jump_data_arr)
  for _, data in ipairs(jump_data_arr) do
    jump(data[1])
    eq(get_cur_tabstop(), data[2])
    if data[3] ~= nil then eq(get_cursor(), data[3]) end
  end
end

T['session.jump()']['works'] = function()
  default_insert({ body = 'T1=$1 T0=$0' })
  -- Jumping to tabstop with placeholder should put cursor at placeholder start
  -- Also should wrap tabstops around the end
  validate_jumps({ { 'next', '0', { 1, 7 } }, { 'next', '1', { 1, 3 } } })
  validate_jumps({ { 'prev', '0', { 1, 7 } }, { 'prev', '1', { 1, 3 } } })

  -- Should not error without active session
  stop()
  eq(jump('next'), vim.NIL)
  eq(jump('prev'), vim.NIL)
end

T['session.jump()']['does not lead to replacing already edited tabstop'] = function()
  default_insert({ body = 'T1=${1:<xxx>}\nT0=$0' })
  type_keys('yyy')
  validate_state('i', { 'T1=yyy', 'T0=' }, { 1, 6 })

  jump('next')
  jump('prev')
  eq(get_cursor(), { 1, 6 })
  type_keys('!')
  validate_state('i', { 'T1=yyy!', 'T0=' }, { 1, 7 })

  -- Should not matter where cursor was when target tabstop was current
  type_keys('<Down>')
  eq(get_cursor(), { 2, 3 })
  jump('prev')
  jump('next')
  eq(get_cursor(), { 1, 7 })
end

T['session.jump()']['works with several linked tabstops'] = function()
  default_insert({ body = 'T1=${1:<$0>} T1=$1 T0=$0' })

  -- Should jump only to the first node of target tabstop
  validate_jumps({ { 'next', '0', { 1, 4 } }, { 'next', '1', { 1, 3 } } })
  validate_jumps({ { 'prev', '0', { 1, 4 } }, { 'prev', '1', { 1, 3 } } })

  -- Even if it changes
  type_keys('x')
  validate_state('i', { 'T1=x T1=x T0=' }, { 1, 4 })
  validate_jumps({ { 'next', '0', { 1, 13 } }, { 'next', '1', { 1, 4 } } })
end

T['session.jump()']['jumps in proper order'] = function()
  default_insert({ body = 'T2=$2 T0=$0 T1=$1' })
  validate_jumps({ { 'next', '2', { 1, 3 } }, { 'next', '0', { 1, 7 } }, { 'next', '1', { 1, 11 } } })
  validate_jumps({ { 'prev', '0', { 1, 7 } }, { 'prev', '2', { 1, 3 } }, { 'prev', '1', { 1, 11 } } })
end

T['session.jump()']['ensures session buffer is current'] = function()
  default_insert({ body = 'T1=$1 T0=$0' })
  type_keys('<Esc>')

  -- Prepare separate buffers and windows
  local buf_id_1, buf_id_2 = get_buf(), new_buf()
  local win_1 = child.api.nvim_get_current_win()
  child.cmd('vertical split')
  local win_2 = child.api.nvim_get_current_win()
  no_eq(win_1, win_2)
  child.api.nvim_win_set_buf(win_2, buf_id_2)

  -- Should reuse visible window
  eq(child.api.nvim_get_current_win(), win_2)
  eq(child.fn.mode(), 'n')
  jump('next')
  eq(child.api.nvim_get_current_win(), win_1)
  eq(child.api.nvim_win_is_valid(win_2), true)
  -- Should ensure Insert mode
  validate_state('i', { 'T1= T0=' }, { 1, 7 })
  eq(get_cur_tabstop(), '0')

  -- Should show target buffer in current window if not visible
  child.api.nvim_win_set_buf(0, buf_id_2)
  eq(child.fn.win_findbuf(buf_id_1), {})
  jump('prev')
  eq(get_buf(), buf_id_1)
  validate_state('i', { 'T1= T0=' }, { 1, 3 })
  eq(get_cur_tabstop(), '1')
end

T['session.jump()']['shows completion for tabstop with choices'] = function()
  child.o.completeopt = 'menuone,noselect'
  default_insert({ body = 'T1=${1|aa,bb|} T2=${2|cc,dd|}' })
  validate_pumitems({ 'aa', 'bb' })
  jump('next')
  validate_pumitems({ 'cc', 'dd' })
  jump('prev')
  validate_pumitems({ 'aa', 'bb' })
end

T['session.jump()']['handles when tabstop becomes absent'] = function()
  default_insert({ body = '${1:$2} ${3:$0}' })
  type_keys('x')
  validate_jumps({ { 'next', '3' }, { 'next', '0' }, { 'next', '1' } })
  validate_jumps({ { 'prev', '0' }, { 'prev', '3' }, { 'prev', '1' } })

  jump('next')
  type_keys('y')
  validate_jumps({ { 'next', '1' }, { 'next', '3' } })
  validate_jumps({ { 'prev', '1' }, { 'prev', '3' } })
end

T['session.jump()']['validates input'] = function()
  expect.error(function() jump(1) end, '`direction`.*one of')
end

--stylua: ignore
T['session.jump()']['triggers events'] = function()
  child.lua([[
    local events = { 'MiniSnippetsSessionJumpPre', 'MiniSnippetsSessionJump' }
    _G.au_log = {}
    local track = function(args)
      local entry = {
        event = args.match,
        buf_id = args.buf,
        data = args.data,
        cur_tabstop = MiniSnippets.session.get().cur_tabstop,
      }
      table.insert(_G.au_log, entry)
    end
    vim.api.nvim_create_autocmd('User', { pattern = events, callback = track })
  ]])

  local cur_buf = get_buf()
  default_insert({ body = 'T1=$1 T0=$0' })
  -- Should not trigger during initial insert
  eq(get_au_log(), {})

  jump('next')
  local ref_au_log = {
    -- `*Pre` should be called *before* changing current tabstop
    { event = 'MiniSnippetsSessionJumpPre', cur_tabstop = '1', data = { tabstop_from = '1', tabstop_to = '0' }, buf_id = cur_buf },
    { event = 'MiniSnippetsSessionJump',    cur_tabstop = '0', data = { tabstop_from = '1', tabstop_to = '0' }, buf_id = cur_buf },
  }
  eq(get_au_log(), ref_au_log)

  jump('next')
  vim.list_extend(ref_au_log, {
    { event = 'MiniSnippetsSessionJumpPre', cur_tabstop = '0', data = { tabstop_from = '0', tabstop_to = '1' }, buf_id = cur_buf },
    { event = 'MiniSnippetsSessionJump',    cur_tabstop = '1', data = { tabstop_from = '0', tabstop_to = '1' }, buf_id = cur_buf },
  })
  eq(get_au_log(), ref_au_log)

  stop()
  clean_au_log()

  -- Should still trigger events if there is only a single tabstop left
  default_insert({ body = 'T1=${1:$0}' })
  type_keys('x')
  jump('next')
  ref_au_log = {
    { event = 'MiniSnippetsSessionJumpPre', cur_tabstop = '1', data = { tabstop_from = '1', tabstop_to = '1' }, buf_id = cur_buf },
    { event = 'MiniSnippetsSessionJump',    cur_tabstop = '1', data = { tabstop_from = '1', tabstop_to = '1' }, buf_id = cur_buf },
  }
  eq(get_au_log(), ref_au_log)
end

T['session.stop()'] = new_set()

T['session.stop()']['works'] = function()
  -- Should work without active session
  expect.no_error(stop)

  default_insert({ body = 'T1=$1 T0=$0' })
  default_insert({ body = 'U1=$1 U0=$0' })
  validate_state('i', { 'T1=U1= U0= T0=' }, { 1, 6 })
  validate_n_sessions(2)
  child.expect_screenshot()

  -- Should stop active session (no change mode/cursor) and resume previous
  stop()
  validate_state('i', { 'T1=U1= U0= T0=' }, { 1, 6 })
  validate_n_sessions(1)
  child.expect_screenshot()

  stop()
  validate_state('i', { 'T1=U1= U0= T0=' }, { 1, 6 })
  validate_n_sessions(0)
  child.expect_screenshot()

  -- Should clean all side effects
  expect.error(function() child.cmd('au MiniSnippetsTrack') end, 'No such group')
  expect.match(child.cmd_capture('imap <C-h>'), 'No mapping')
  expect.match(child.cmd_capture('imap <C-l>'), 'No mapping')
  expect.match(child.cmd_capture('imap <C-c>'), 'No mapping')
end

T['session.stop()']['hides completion popup'] = function()
  default_insert({ body = 'T1=$1 T0=$0' })
  type_keys('<C-n>')
  validate_pumvisible()
  stop()
  validate_no_pumvisible()
  eq(child.fn.mode(), 'i')
end

T['parse()'] = new_set()

local parse = forward_lua('MiniSnippets.parse')

T['parse()']['works'] = function()
  --stylua: ignore
  eq(
    parse('hello ${1:xx} $var world$0'),
    {
      { text = 'hello ' }, { tabstop = '1', placeholder = { { text = 'xx' } } }, { text = ' ' },
      { var = 'var' }, { text = ' world' }, { tabstop = '0' },
    }
  )
  -- Should allow array of strings
  eq(parse({ 'aa', '$1', '$var' }), { { text = 'aa\n' }, { tabstop = '1' }, { text = '\n' }, { var = 'var' } })
end

--stylua: ignore
T['parse()']['text'] = function()
  -- Common
  eq(parse('aa'),      { { text = 'aa' } })
  eq(parse('ыыы ффф'), { { text = 'ыыы ффф' } })

  -- Simple
  eq(parse(''),    { { text = '' } })
  eq(parse('$'),   { { text = '$' } })
  eq(parse('{'),   { { text = '{' } })
  eq(parse('}'),   { { text = '}' } })
  eq(parse([[\]]), { { text = [[\]] } })

  -- Escaped (should ignore `\` before `$}\`)
  eq(parse([[aa\$bb\}cc\\dd]]), { { text = [[aa$bb}cc\dd]] } })
  eq(parse([[aa\$]]),           { { text = 'aa$' } })
  eq(parse([[aa\${}]]),         { { text = 'aa${}' } })
  eq(parse([[\}]]),             { { text = '}' } })
  eq(parse([[aa \\\$]]),        { { text = [[aa \$]] } })
  eq(parse([[\${1|aa,bb|}]]),   { { text = '${1|aa,bb|}' } })

  -- Not spec: allow unescaped backslash
  eq(parse([[aa\bb]]), { { text = [[aa\bb]] } })

  -- Not spec: allow unescaped $ when can not be mistaken for tabstop or var
  eq(parse('aa$ bb'), { { text = 'aa$ bb' } })

  -- Allow '$' at the end of the snippet
  eq(parse('aa$'), { { text = 'aa' }, { text = '$' } })

  -- Not spec: allow unescaped `}` in top-level text
  eq(parse('{ aa }'),         { { text = '{ aa }' } })
  eq(parse('{\n\taa\n}'),     { { text = '{\n\taa\n}' } })
  eq(parse('aa{1}'),          { { text = 'aa{1}' } })
  eq(parse('aa{1:bb}'),       { { text = 'aa{1:bb}' } })
  eq(parse('aa{1:{2:cc}}'),   { { text = 'aa{1:{2:cc}}' } })
  eq(parse('aa{var:{1:bb}}'), { { text = 'aa{var:{1:bb}}' } })
end

--stylua: ignore
T['parse()']['tabstop'] = function()
  -- Common
  eq(parse('$1'),          { { tabstop = '1' } })
  eq(parse('aa $1'),       { { text = 'aa ' },    { tabstop = '1' } })
  eq(parse('aa $1 bb'),    { { text = 'aa ' },    { tabstop = '1' }, { text = ' bb' } })
  eq(parse('aa$1bb'),      { { text = 'aa' },     { tabstop = '1' }, { text = 'bb' } })
  eq(parse('hello_$1_bb'), { { text = 'hello_' }, { tabstop = '1' }, { text = '_bb' } })
  eq(parse('ыыы $1 ффф'),  { { text = 'ыыы ' },   { tabstop = '1' }, { text = ' ффф' } })

  eq(parse('${1}'),          { { tabstop = '1' } })
  eq(parse('aa ${1}'),       { { text = 'aa ' },    { tabstop = '1' } })
  eq(parse('aa ${1} bb'),    { { text = 'aa ' },    { tabstop = '1' }, { text = ' bb' } })
  eq(parse('aa${1}bb'),      { { text = 'aa' },     { tabstop = '1' }, { text = 'bb' } })
  eq(parse('hello_${1}_bb'), { { text = 'hello_' }, { tabstop = '1' }, { text = '_bb' } })
  eq(parse('ыыы ${1} ффф'),  { { text = 'ыыы ' },   { tabstop = '1' }, { text = ' ффф' } })

  eq(parse('$0'),    { { tabstop = '0' } })
  eq(parse('$1 $0'), { { tabstop = '1' }, { text = ' ' }, { tabstop = '0' } })

  eq(parse([[aa\\$1]]), { { text = [[aa\]] }, { tabstop = '1' } })

  -- Adjacent tabstops
  eq(parse('aa$1$2'),   { { text = 'aa' },   { tabstop = '1' }, { tabstop = '2' } })
  eq(parse('aa$1$0'),   { { text = 'aa' },   { tabstop = '1' }, { tabstop = '0' } })
  eq(parse('$1$2'),     { { tabstop = '1' }, { tabstop = '2' } })
  eq(parse('${1}${2}'), { { tabstop = '1' }, { tabstop = '2' } })
  eq(parse('$1${2}'),   { { tabstop = '1' }, { tabstop = '2' } })
  eq(parse('${1}$2'),   { { tabstop = '1' }, { tabstop = '2' } })

  -- Can be any digit sequence in any order
  eq(parse('$2'),       { { tabstop = '2' } })
  eq(parse('$3 $10'),   { { tabstop = '3' }, { text = ' ' }, { tabstop = '10' } })
  eq(parse('$3 $2 $0'), { { tabstop = '3' }, { text = ' ' }, { tabstop = '2' }, { text = ' ' }, { tabstop = '0' } })
  eq(parse('$3 $0 $2'), { { tabstop = '3' }, { text = ' ' }, { tabstop = '0' }, { text = ' ' }, { tabstop = '2' } })
  eq(parse('$1 $01'),   { { tabstop = '1' }, { text = ' ' }, { tabstop = '01' } })

  -- Tricky
  eq(parse('$1$a'), { { tabstop = '1' }, { var = 'a' } })
  eq(parse('$1$-'), { { tabstop = '1' }, { text = '$-' } })
  eq(parse('$a$1'), { { var = 'a' },     { tabstop = '1' } })
  eq(parse('$-$1'), { { text = '$-' },   { tabstop = '1' } })
  eq(parse('$$1'),  { { text = '$' },    { tabstop = '1' } })
  eq(parse('$1$'),  { { tabstop = '1' }, { text = '$' } })
end

--stylua: ignore
T['parse()']['choice'] = function()
  -- Common
  eq(parse('${1|aa|}'),    { { tabstop = '1', choices = { 'aa' } } })
  eq(parse('${2|aa|}'),    { { tabstop = '2', choices = { 'aa' } } })
  eq(parse('${1|aa,bb|}'), { { tabstop = '1', choices = { 'aa', 'bb' } } })

  -- Escape (should ignore `\` before `,|\` and treat as text)
  eq(parse([[${1|},$,\,,\|,\\|}]]), { { tabstop = '1', choices = { '}', '$', ',', '|', [[\]] } } })
  eq(parse([[${1|aa\,bb|}]]),       { { tabstop = '1', choices = { 'aa,bb' } } })

  -- Empty choices
  eq(parse('${1|,|}'),       { { tabstop = '1', choices = { '', '' } } })
  eq(parse('${1|aa,|}'),     { { tabstop = '1', choices = { 'aa', '' } } })
  eq(parse('${1|,aa|}'),     { { tabstop = '1', choices = { '', 'aa' } } })
  eq(parse('${1|aa,,bb|}'),  { { tabstop = '1', choices = { 'aa', '', 'bb' } } })
  eq(parse('${1|aa,,,bb|}'), { { tabstop = '1', choices = { 'aa', '', '', 'bb' } } })

  -- Not spec: allow unescaped backslash
  eq(parse([[${1|aa\bb,cc|}]]), { { tabstop = '1', choices = { [[aa\bb]], 'cc' } } })

  -- Should not be ignored in `$0`
  eq(parse('${0|aa|}'),    { { tabstop = '0', choices = { 'aa' } } })
  eq(parse('${0|aa,bb|}'), { { tabstop = '0', choices = { 'aa', 'bb' } } })
end

--stylua: ignore
T['parse()']['var'] = function()
  -- Common
  eq(parse('$aa'),    { { var = 'aa' } })
  eq(parse('$a_b'),   { { var = 'a_b' } })
  eq(parse('$_a'),    { { var = '_a' } })
  eq(parse('$a1'),    { { var = 'a1' } })
  eq(parse('${aa}'),  { { var = 'aa' } })
  eq(parse('${a_b}'), { { var = 'a_b' } })
  eq(parse('${_a}'),  { { var = '_a' } })
  eq(parse('${a1}'),  { { var = 'a1' } })

  eq(parse([[aa\\$bb]]), { { text = [[aa\]] }, { var = 'bb' } })
  eq(parse('$$aa'),      { { text = '$' },     { var = 'aa' } })
  eq(parse('$aa$'),      { { var = 'aa' },     { text = '$' } })

  -- Should recognize only [_a-zA-Z] [_a-zA-Z0-9]*
  eq(parse('$aa-bb'),     { { var = 'aa' },  { text = '-bb' } })
  eq(parse('$aa bb'),     { { var = 'aa' },  { text = ' bb' } })
  eq(parse('aa$bb cc'),   { { text = 'aa' }, { var = 'bb' }, { text = ' cc' } })
  eq(parse('aa${bb} cc'), { { text = 'aa' }, { var = 'bb' }, { text = ' cc' } })
end

--stylua: ignore
T['parse()']['placeholder'] = function()
  -- Common
  eq(parse('aa ${1:b}'), { { text = 'aa ' }, { tabstop = '1', placeholder = { { text = 'b' } } } })
  eq(parse('${1:b}'),    { { tabstop = '1', placeholder = { { text = 'b' } } } })
  eq(parse('${1:ыыы}'),  { { tabstop = '1', placeholder = { { text = 'ыыы' } } } })
  eq(parse('${1:}'),     { { tabstop = '1', placeholder = { { text = '' } } } })

  eq(parse('${1:aa} ${2:bb}'), { { tabstop = '1', placeholder = { { text = 'aa' } } }, { text = ' ' }, { tabstop = '2', placeholder = { { text = 'bb' } } } })

  eq(parse('aa ${0:b}'), { { text = 'aa ' }, { tabstop = '0', placeholder = { { text = 'b' } } } })
  eq(parse('${0:b}'),    { { tabstop = '0', placeholder = { { text = 'b' } } } })
  eq(parse('${0:}'),     { { tabstop = '0', placeholder = { { text = '' } } } })
  eq(parse('${0:ыыы}'),  { { tabstop = '0', placeholder = { { text = 'ыыы' } } } })
  eq(parse('${0:}'),     { { tabstop = '0', placeholder = { { text = '' } } } })

  -- Escaped (should ignore `\` before `$}\` and treat as text)
  eq(parse([[${1:aa\$bb\}cc\\dd}]]), { { tabstop = '1', placeholder = { { text = [[aa$bb}cc\dd]] } } } })
  eq(parse([[${1:aa\$}]]),           { { tabstop = '1', placeholder = { { text = 'aa$' } } } })
  eq(parse([[${1:aa\\}]]),           { { tabstop = '1', placeholder = { { text = [[aa\]] } } } })
  -- - Should allow unescaped `:`
  eq(parse('${1:aa:bb}'),            { { tabstop = '1', placeholder = { { text = 'aa:bb' } } } })

  -- Not spec: allow unescaped backslash
  eq(parse([[${1:aa\bb}]]), { { tabstop = '1', placeholder = { { text = [[aa\bb]] } } } })

  -- Not spec: allow unescaped dollar
  eq(parse('${1:aa$-}'),  { { tabstop = '1', placeholder = { { text = 'aa$-' } } } })
  eq(parse('${1:aa$}'),   { { tabstop = '1', placeholder = { { text = 'aa$' } } } })
  eq(parse('${1:$2$}'),   { { tabstop = '1', placeholder = { { tabstop = '2' }, { text = '$' } } } })
  eq(parse('${1:$2}$'),   { { tabstop = '1', placeholder = { { tabstop = '2' } } }, { text = '$' } })
  eq(parse('${1:aa$}$2'), { { tabstop = '1', placeholder = { { text = 'aa$' } } }, { tabstop = '2' } })

  -- Should not be ignored in `$0`
  eq(parse('${0:aa$1bb}'), { { tabstop = '0', placeholder = { { text = 'aa' }, { tabstop = '1' }, { text = 'bb' } } } })

  -- Placeholder for variable (assume implemented the same way as for tabstop)
  eq(parse('${aa:}'),         { { var = 'aa', placeholder = { { text = '' } } } })
  eq(parse('${aa:bb}'),       { { var = 'aa', placeholder = { { text = 'bb' } } } })
  eq(parse('${aa:bb:cc}'),    { { var = 'aa', placeholder = { { text = 'bb:cc' } } } })
  eq(parse('${aa:$1}'),       { { var = 'aa', placeholder = { { tabstop = '1' } } } })
  eq(parse('${aa:${1}}'),     { { var = 'aa', placeholder = { { tabstop = '1' } } } })
  eq(parse('${aa:${1:bb}}'),  { { var = 'aa', placeholder = { { tabstop = '1', placeholder = { { text = 'bb' } } } } } })
  eq(parse('${aa:${1|bb|}}'), { { var = 'aa', placeholder = { { tabstop = '1', choices = { 'bb' } } } } })
  eq(parse('${aa:${bb:cc}}'), { { var = 'aa', placeholder = { { var = 'bb',    placeholder = { { text = 'cc' } } } } } })

  -- Nested
  -- - Tabstop
  eq(parse('${1:$2}'),    { { tabstop = '1', placeholder = { { tabstop = '2' } } } })
  eq(parse('${1:$2} yy'), { { tabstop = '1', placeholder = { { tabstop = '2' } } }, { text = ' yy' } })
  eq(parse('${1:${2}}'),  { { tabstop = '1', placeholder = { { tabstop = '2' } } } })
  eq(parse('${1:${3}}'),  { { tabstop = '1', placeholder = { { tabstop = '3' } } } })

  -- - Placeholder
  eq(parse('${1:${2:aa}}'),      { { tabstop = '1', placeholder = { { tabstop = '2', placeholder = { { text = 'aa' } } } } } })
  eq(parse('${1:${2:${3:aa}}}'), { { tabstop = '1', placeholder = { { tabstop = '2', placeholder = { { tabstop = '3', placeholder = { { text = 'aa' } } } } } } } })
  eq(parse('${1:${2:${3}}}'),    { { tabstop = '1', placeholder = { { tabstop = '2', placeholder = { { tabstop = '3' } } } } } })
  eq(parse('${1:${3:aa}}'),      { { tabstop = '1', placeholder = { { tabstop = '3', placeholder = { { text = 'aa' } } } } } })

  eq(parse([[${1:${2:aa\$bb\}cc\\dd}}]]), { { tabstop = '1', placeholder = { { tabstop = '2', placeholder = { { text = [[aa$bb}cc\dd]] } } } } } })

  -- - Choice
  eq(parse('${1:${2|aa|}}'),    { { tabstop = '1', placeholder = { { tabstop = '2', choices = { 'aa' } } } } })
  eq(parse('${1:${3|aa|}}'),    { { tabstop = '1', placeholder = { { tabstop = '3', choices = { 'aa' } } } } })
  eq(parse('${1:${2|aa,bb|}}'), { { tabstop = '1', placeholder = { { tabstop = '2', choices = { 'aa', 'bb' } } } } })

  eq(parse([[${1:${2|aa\,bb\|cc\\dd|}}]]), { { tabstop = '1', placeholder = { { tabstop = '2', choices = { [[aa,bb|cc\dd]] } } } } })

  -- - Variable
  eq(parse('${1:$aa}'),                     { { tabstop = '1', placeholder = { { var = 'aa' } } } })
  eq(parse('${1:$aa} xx'),                  { { tabstop = '1', placeholder = { { var = 'aa' } } }, { text = ' xx' } })
  eq(parse('${1:${aa}}'),                   { { tabstop = '1', placeholder = { { var = 'aa' } } } })
  eq(parse('${1:${aa:bb}}'),                { { tabstop = '1', placeholder = { { var = 'aa', placeholder = { { text = 'bb' } } } } } })
  eq(parse('${1:${aa:$2}}'),                { { tabstop = '1', placeholder = { { var = 'aa', placeholder = { { tabstop = '2' } } } } } })
  eq(parse('${1:${aa:bb$2cc}}'),            { { tabstop = '1', placeholder = { { var = 'aa', placeholder = { { text = 'bb' }, { tabstop = '2' }, { text = 'cc' } } } } } })
  eq(parse('${1:${aa/.*/val/i}}'),          { { tabstop = '1', placeholder = { { var = 'aa', transform = { '.*', 'val',          'i' } } } } })
  eq(parse('${1:${aa/.*/${1}/i}}'),         { { tabstop = '1', placeholder = { { var = 'aa', transform = { '.*', '${1}',         'i' } } } } })
  eq(parse('${1:${aa/.*/${1:/upcase}/i}}'), { { tabstop = '1', placeholder = { { var = 'aa', transform = { '.*', '${1:/upcase}', 'i' } } } } })
  eq(parse('${1:${aa/.*/${1:/upcase}/i}}'), { { tabstop = '1', placeholder = { { var = 'aa', transform = { '.*', '${1:/upcase}', 'i' } } } } })

  eq(parse('${1:${aa/.*/xx${1:else}/i}}'),     { { tabstop = '1', placeholder = { { var = 'aa', transform = { '.*', 'xx${1:else}',     'i' } } } } })
  eq(parse('${1:${aa/.*/xx${1:-else}/i}}'),    { { tabstop = '1', placeholder = { { var = 'aa', transform = { '.*', 'xx${1:-else}',    'i' } } } } })
  eq(parse('${1:${aa/.*/xx${1:+if}/i}}'),      { { tabstop = '1', placeholder = { { var = 'aa', transform = { '.*', 'xx${1:+if}',      'i' } } } } })
  eq(parse('${1:${aa/.*/xx${1:?if:else}/i}}'), { { tabstop = '1', placeholder = { { var = 'aa', transform = { '.*', 'xx${1:?if:else}', 'i' } } } } })
  eq(parse('${1:${aa/.*/xx${1:/upcase}/i}}'),  { { tabstop = '1', placeholder = { { var = 'aa', transform = { '.*', 'xx${1:/upcase}',  'i' } } } } })

  eq(parse('${1:${aa/.*/${1:?${}:xx}/i}}'),                 { { tabstop = '1', placeholder = { { var = 'aa', transform = { '.*', '${1:?${}:xx}', 'i' } } } } })

  -- - Known limitation of needing to escape `}` in `if`
  eq(parse([[${1:${aa/regex/${1:?if\}:else/i}/options}}]]),                { { tabstop = '1', placeholder = { { var = 'aa', transform = { 'regex', [[${1:?if\}:else/i}]], 'options' } } } } })
  expect.no_equality(parse([[${1:${aa/regex/${1:?if}:else/i}/options}}]]), { { tabstop = '1', placeholder = { { var = 'aa', transform = { 'regex', '${1:?if}:else/i}',    'options' } } } } }) -- this is bad

  -- Combined
  eq(parse('${1:aa${2:bb}cc}'),  { { tabstop = '1', placeholder = { { text = 'aa' },  { tabstop = '2', placeholder = { { text = 'bb' } } }, { text = 'cc' } } } })
  eq(parse('${1:aa $aa bb}'),    { { tabstop = '1', placeholder = { { text = 'aa ' }, { var = 'aa' }, { text = ' bb' } } } })
  eq(parse('${1:aa${aa:xx}bb}'), { { tabstop = '1', placeholder = { { text = 'aa' },  { var = 'aa', placeholder = { { text = 'xx' } } }, { text = 'bb' } } } })
  eq(parse('${1:xx$bb}yy'),      { { tabstop = '1', placeholder = { { text = 'xx' }, { var = 'bb' } } }, { text = 'yy'} })
  eq(parse('${aa:xx$bb}yy'),     { { var = 'aa', placeholder = { { text = 'xx' }, { var = 'bb' } } }, { text = 'yy'} })

  -- Different placeholders for same id/name
  eq(
    parse('${1:xx}_${1:yy}_$1'),
    { { tabstop = '1', placeholder = { { text = 'xx' } } }, { text = '_' }, { tabstop = '1', placeholder = { { text = 'yy' } } }, { text = '_' }, { tabstop = '1' } }
  )
  eq(
    parse('${1:}_$1_${1:yy}'),
    { { tabstop = '1', placeholder = { { text = '' } } },   { text = '_' }, { tabstop = '1' }, { text = '_' }, { tabstop = '1', placeholder = { { text = 'yy' } } } }
  )

  eq(
    parse('${a:xx}_${a:yy}_$a'),
    { { var = 'a', placeholder = { { text = 'xx' } } }, { text = '_' }, { var = 'a', placeholder = { { text = 'yy' } } }, { text = '_' }, { var = 'a' } }
  )
  eq(
    parse('${a:}-$a-${a:yy}'),
    { { var = 'a', placeholder = { { text = '' } } },   { text = '-' }, { var = 'a' }, { text = '-' }, { var = 'a', placeholder = { { text = 'yy' } } } }
  )
end

--stylua: ignore
T['parse()']['transform'] = function()
  -- All transform string should be parsed as is

  -- Should be allowed in variable nodes
  eq(parse('${var/xx(yy)/${0:aaa}/i}'),     { { var = 'var', transform = { 'xx(yy)', '${0:aaa}', 'i' } } })

  eq(parse('${var/.*/${1}/i}'),             { { var = 'var', transform = { '.*', '${1}',             'i' } } })
  eq(parse('${var/.*/$1/i}'),               { { var = 'var', transform = { '.*', '$1',               'i' } } })
  eq(parse('${var/.*/$1/}'),                { { var = 'var', transform = { '.*', '$1',               ''  } } })
  eq(parse('${var/.*//}'),                  { { var = 'var', transform = { '.*', '',                 ''  } } })
  eq(parse('${var/.*/This-$1-encloses/i}'), { { var = 'var', transform = { '.*', 'This-$1-encloses', 'i' } } })
  eq(parse('${var/.*/aa${1:else}/i}'),      { { var = 'var', transform = { '.*', 'aa${1:else}',      'i' } } })
  eq(parse('${var/.*/aa${1:-else}/i}'),     { { var = 'var', transform = { '.*', 'aa${1:-else}',     'i' } } })
  eq(parse('${var/.*/aa${1:+if}/i}'),       { { var = 'var', transform = { '.*', 'aa${1:+if}',       'i' } } })
  eq(parse('${var/.*/aa${1:?if:else}/i}'),  { { var = 'var', transform = { '.*', 'aa${1:?if:else}',  'i' } } })
  eq(parse('${var/.*/aa${1:/upcase}/i}'),   { { var = 'var', transform = { '.*', 'aa${1:/upcase}',   'i' } } })

  -- Tricky transform strings
  eq(parse('${var///}'),                { { var = 'var', transform = { '', '', '' } } })

  eq(parse([[${var/.*/$\//i}]]),        { { var = 'var', transform = { '.*', [[$\/]],        'i' } } })
  eq(parse('${var/.*/$${}/i}'),         { { var = 'var', transform = { '.*', '$${}',         'i' } } }) -- `${}` directly after `$`
  eq(parse('${var/.*/${a/}/i}'),        { { var = 'var', transform = { '.*', '${a/}',        'i' } } }) -- `/` inside a proper `${...}`
  eq(parse([[${var/.*/$\x/i}]]),        { { var = 'var', transform = { '.*', [[$\x]],        'i' } } }) -- `/` after both dollar and backslash
  eq(parse([[${var/.*/\$x/i}]]),        { { var = 'var', transform = { '.*', [[\$x]],        'i' } } }) -- `/` after both dollar and backslash
  eq(parse([[${var/.*/\${x/i}]]),       { { var = 'var', transform = { '.*', [[\${x]],       'i' } } }) -- `/` after not proper `${`
  eq(parse([[${var/.*/$\{x/i}]]),       { { var = 'var', transform = { '.*', [[$\{x]],       'i' } } }) -- `/` after not proper `${`
  eq(parse('${var/.*/a$/i}'),           { { var = 'var', transform = { '.*', 'a$',           'i' } } }) -- `/` directly after dollar
  eq(parse('${var/.*/${1:?${}:aa}/i}'), { { var = 'var', transform = { '.*', '${1:?${}:aa}', 'i' } } }) -- `}` inside `format`

  -- Escaped (should ignore `\` before `$/\` and treat as text)
  eq(parse([[${var/.*/\/a\/a\//g}]]),                { { var = 'var', transform = { '.*', [[\/a\/a\/]], 'g' } } })

  -- - Known limitation of needing to escape `}` in `if` of `${1:?if:else}`
  eq(parse([[${var/.*/${1:?if\}:else/i}/options}]]),                { { var = 'var', transform = { '.*', [[${1:?if\}:else/i}]], 'options' } } })
  expect.no_equality(parse([[${var/.*/${1:?if}:else/i}/options}]]), { { var = 'var', transform = { '.*', [[${1:?if}:else/i}]],  'options' } } }) -- this is bad

  eq(parse([[${var/.*/\\aa/g}]]),  { { var = 'var', transform = { '.*', [[\\aa]],  'g' } } })
  eq(parse([[${var/.*/\$1aa/g}]]), { { var = 'var', transform = { '.*', [[\$1aa]], 'g' } } })

  -- - Should handle escaped `/` in regex
  eq(parse([[${var/\/re\/gex\//aa/}]]), { { var = 'var', transform = { [[\/re\/gex\/]], 'aa', '' } } })

  -- Should be allowed in tabstop nodes
  eq(parse('${1/.*/${0:aaa}/i} xx'),      { { tabstop = '1', transform = { '.*', '${0:aaa}', 'i' } }, { text = ' xx' } })
  eq(parse('${1/.*/${1}/i}'),             { { tabstop = '1', transform = { '.*', '${1}', 'i' } } })
  eq(parse('${1/.*/$1/i}'),               { { tabstop = '1', transform = { '.*', '$1', 'i' } } })
  eq(parse('${1/.*/$1/}'),                { { tabstop = '1', transform = { '.*', '$1', '' } } })
  eq(parse('${1/.*//}'),                  { { tabstop = '1', transform = { '.*', '', '' } } })
  eq(parse('${1/.*/This-$1-encloses/i}'), { { tabstop = '1', transform = { '.*', 'This-$1-encloses', 'i' } } })
  eq(parse('${1/.*/aa${1:else}/i}'),      { { tabstop = '1', transform = { '.*', 'aa${1:else}', 'i' } } })
  eq(parse('${1/.*/aa${1:-else}/i}'),     { { tabstop = '1', transform = { '.*', 'aa${1:-else}', 'i' } } })
  eq(parse('${1/.*/aa${1:+if}/i}'),       { { tabstop = '1', transform = { '.*', 'aa${1:+if}', 'i' } } })
  eq(parse('${1/.*/aa${1:?if:else}/i}'),  { { tabstop = '1', transform = { '.*', 'aa${1:?if:else}', 'i' } } })
  eq(parse('${1/.*/aa${1:/upcase}/i}'),   { { tabstop = '1', transform = { '.*', 'aa${1:/upcase}', 'i' } } })
end

--stylua: ignore
T['parse()']['tricky'] = function()
  eq(parse('${1:${aa:${1}}}'),                          { { tabstop = '1', placeholder = { { var = 'aa', placeholder = { { tabstop = '1' } } } } } })
  eq(parse('${1:${aa:bb$1cc}}'),                        { { tabstop = '1', placeholder = { { var = 'aa', placeholder = { { text = 'bb' }, { tabstop = '1' }, { text = 'cc' } } } } } })
  eq(parse([[${TM_DIRECTORY/.*src[\/](.*)/$1/}]]),      { { var = 'TM_DIRECTORY', transform = { [[.*src[\/](.*)]], '$1', '' } } })
  eq(parse('${aa/(void$)|(.+)/${1:?-\treturn nil;}/}'), { { var = 'aa', transform = { '(void$)|(.+)', '${1:?-\treturn nil;}', '' } } })

  eq(
    parse('${3:nest1 ${1:nest2 ${2:nest3}}} $3'),
    {
      { tabstop = '3', placeholder = { { text = 'nest1 ' }, { tabstop = '1', placeholder = { { text = 'nest2 ' }, { tabstop = '2', placeholder = { { text = 'nest3' } } } } } } },
      { text = ' ' },
      { tabstop = '3' },
    }
  )

  eq(
    parse('${1:prog}: ${2:$1.cc} - $2'), -- 'prog: .cc - '
    {
      { tabstop = '1', placeholder = { { text = 'prog' } } },
      { text = ': ' },
      { tabstop = '2', placeholder = { { tabstop = '1' }, { text = '.cc' } } },
      { text = ' - ' },
      { tabstop = '2' },
    }
  )
  eq(
    parse('${1:prog}: ${3:${2:$1.cc}.33} - $2 $3'), -- 'prog: .cc.33 -  '
    {
      { tabstop = '1', placeholder = { { text = 'prog' } } },
      { text = ': ' },
      { tabstop = '3', placeholder = { { tabstop = '2', placeholder = { { tabstop = '1' }, { text = '.cc' } } }, { text = '.33' } } },
      { text = ' - ' },
      { tabstop = '2' },
      { text = ' ' },
      { tabstop = '3' },
    }
  )
  eq(
    parse('${1:$2.one} <> ${2:$1.two}'), -- '.one <> .two'
    {
      { tabstop = '1', placeholder = { { tabstop = '2' }, { text = '.one' } } },
      { text = ' <> ' },
      { tabstop = '2', placeholder = { { tabstop = '1' }, { text = '.two' } } },
    }
  )
end

--stylua: ignore
T['parse()']['respects `opts.normalize`'] = function()
  local validate = function(snippet_body, ref_nodes) eq(parse(snippet_body, { normalize = true }), ref_nodes) end
  local final_tabstop = { tabstop = '0', text = '' }

  child.fn.setenv('AA', 'my-aa')
  child.fn.setenv('XX', 'my-xx')
  -- NOTE: on Windows setting environment variable to empty string is the same
  -- as deleting it (at least until 2024-07-11 change which enables it)
  child.fn.setenv('EMPTY', '')

  -- Resolves variables
  validate('$AA',   { { var = 'AA', text = 'my-aa' }, final_tabstop })
  validate('${AA}', { { var = 'AA', text = 'my-aa' }, final_tabstop })
  if not helpers.is_windows() then
    validate('$EMPTY',            { { var = 'EMPTY', text = '' }, final_tabstop })
    validate('${EMPTY:fallback}', { { var = 'EMPTY', text = '' }, final_tabstop })
  end

  -- Ensures text-or-placeholder
  validate('$1',         { { tabstop = '1', placeholder = { { text = '' } } },                                 final_tabstop })
  validate('${1}',       { { tabstop = '1', placeholder = { { text = '' } } } ,                                final_tabstop })
  validate('${1:val}',   { { tabstop = '1', placeholder = { { text = 'val' } } },                              final_tabstop })
  validate('${1/a/b/c}', { { tabstop = '1', placeholder = { { text = '' } }, transform = { 'a', 'b', 'c' } } , final_tabstop })
  validate('${1|u,v|}',  { { tabstop = '1', placeholder = { { text = '' } }, choices = { 'u', 'v' } } ,        final_tabstop })

  validate('$BB',         { { var = 'BB', placeholder = { { text = '' } } },                                final_tabstop })
  validate('${BB}',       { { var = 'BB', placeholder = { { text = '' } } },                                final_tabstop })
  validate('${BB:var}',   { { var = 'BB', placeholder = { { text = 'var' } } },                             final_tabstop })
  validate('${BB/a/b/c}', { { var = 'BB', placeholder = { { text = '' } }, transform = { 'a', 'b', 'c' } }, final_tabstop })

  -- - Should be exclusive OR
  validate('${AA:var}',       { { var = 'AA', text = 'my-aa' }, final_tabstop })
  validate('${AA:$1}',        { { var = 'AA', text = 'my-aa' }, final_tabstop })
  validate('${AA:$XX}',       { { var = 'AA', text = 'my-aa' }, final_tabstop })
  validate('${AA:${XX:var}}', { { var = 'AA', text = 'my-aa' }, final_tabstop })

  validate('aa', { { text = 'aa' }, final_tabstop })

  -- Should not append final tabstop if there is already one present (however deep)
  validate('$0',          { { tabstop = '0', placeholder = { { text = '' } } } })
  validate('${0:text}',   { { tabstop = '0', placeholder = { { text = 'text' } } } })
  validate('$0$1',        { { tabstop = '0', placeholder = { { text = '' } } },     { tabstop = '1', placeholder = { { text = '' } } } })
  validate('${0:text}$1', { { tabstop = '0', placeholder = { { text = 'text' } } }, { tabstop = '1', placeholder = { { text = '' } } } })
  validate('$0text',      { { tabstop = '0', placeholder = { { text = '' } } },     { text = 'text' } })

  -- Should normalize however deep
  validate('${BB:$1}',       { { var = 'BB',    placeholder = { { tabstop = '1', placeholder = { { text = '' } } } } },                                   final_tabstop })
  validate('${BB:${1:$CC}}', { { var = 'BB',    placeholder = { { tabstop = '1', placeholder = { { var = 'CC', placeholder = { { text = '' } } } } } } }, final_tabstop })
  validate('${1:${BB:$CC}}', { { tabstop = '1', placeholder = { { var = 'BB',    placeholder = { { var = 'CC', placeholder = { { text = '' } } } } } } }, final_tabstop })

  validate('${1:${AA:$XX}}', { { tabstop = '1', placeholder = { { var = 'AA',    text = 'my-aa' } } },                                   final_tabstop })
  validate('${1:${2:$AA}}',  { { tabstop = '1', placeholder = { { tabstop = '2', placeholder = { { var = 'AA', text = 'my-aa' } } } } }, final_tabstop })

  validate('${1:$0}',        { { tabstop = '1', placeholder = { { tabstop = '0', placeholder = { { text = '' } } } } }     })
  validate('${1:${0:text}}', { { tabstop = '1', placeholder = { { tabstop = '0', placeholder = { { text = 'text' } } } } } })

  -- Evaluates variable only once
  child.lua([[
    _G.log = {}
    local os_getenv_orig = vim.loop.os_getenv
    vim.loop.os_getenv = function(...)
      table.insert(_G.log, { ... })
      return os_getenv_orig(...)
    end
  ]])
  validate(
    '${AA}${AA}${BB}${BB}',
    {
      { var = 'AA', text = 'my-aa' }, { var = 'AA', text = 'my-aa' },
      { var = 'BB', placeholder = { { text = '' } } }, { var = 'BB', placeholder = { { text = '' } } },
      final_tabstop,
    }
  )
  eq(child.lua_get('_G.log'), { { 'AA' }, { 'BB' } })

  -- - But not persistently
  child.fn.setenv('AA', '!')
  child.fn.setenv('BB', '?')
  validate('${AA}${BB}', { { var = 'AA', text = '!' }, { var = 'BB', text = '?' }, final_tabstop })
end

--stylua: ignore
T['parse()']['respects `opts.lookup`'] = function()
  local validate = function(snippet_body, lookup, ref_nodes)
    eq(parse(snippet_body, { normalize = true, lookup = lookup }), ref_nodes)
  end
  local final_tabstop = { tabstop = '0', text = '' }

  -- Can resolve variables from user lookup
  validate('$BB', { BB = 'hello' }, { { var = 'BB', text = 'hello' }, final_tabstop })
  validate('$BB', { BB = 1 },       { { var = 'BB', text = '1' },     final_tabstop })

  -- Should use only string fields
  eq(
    child.lua_get('MiniSnippets.parse("$true", { normalize = true, lookup = { [true] = "x" } })'),
    { { var = 'true', placeholder = { { text = '' } } }, final_tabstop }
  )
  validate('$1', { [1] = 'x' }, { { tabstop = '1', placeholder = { { text = '' } } }, final_tabstop })

  -- - Should prefer user lookup
  child.fn.setenv('AA', 'my-aa')
  child.fn.setenv('XX', 'my-xx')
  child.fn.setenv('EMPTY', '')

  validate('$AA',    { AA = 'other' },        { { var = 'AA',    text = 'other' },     final_tabstop })
  validate('$AA',    { AA = '' },             { { var = 'AA',    text = '' },          final_tabstop })
  validate('$EMPTY', { EMPTY = 'not empty' }, { { var = 'EMPTY', text = 'not empty' }, final_tabstop })

  validate('$AA$XX', { AA = '!', XX = '?' }, { { var = 'AA', text = '!' }, { var = 'XX', text = '?' }, final_tabstop })

  -- Can resolve tabstops from user lookup
  validate('$1',       { ['1'] = 'hello' }, { { tabstop = '1', text = 'hello' }, final_tabstop })
  validate('${1}',     { ['1'] = 'hello' }, { { tabstop = '1', text = 'hello' }, final_tabstop })
  validate('${1:var}', { ['1'] = 'hello' }, { { tabstop = '1', text = 'hello' }, final_tabstop })

  -- - Should resolve all tabstop entries
  validate(
    '$1$2$1',
    { ['1'] = 'hello' },
    {
      { tabstop = '1', text = 'hello' },
      { tabstop = '2', placeholder = { { text = '' } } },
      { tabstop = '1', text = 'hello' },
      final_tabstop,
    }
  )

  validate('$0', { ['0'] = 'world' }, { { tabstop = '0', text = 'world' } })

  -- - Should use tabstop as is
  local lookup = { ['1'] = 'hello' }
  local ref_nodes = { { tabstop = '01', placeholder = { { text = '' } } }, { tabstop = '1', text = 'hello' }, final_tabstop }
  validate('${01}${1}', lookup, ref_nodes)

  -- - Should resolve on any depth
  validate('${1:$2}',      { ['2'] = 'xx' }, { { tabstop = '1', placeholder = { { tabstop = '2', text = 'xx' } } }, final_tabstop })
  validate('${1:${2:$3}}', { ['2'] = 'xx' }, { { tabstop = '1', placeholder = { { tabstop = '2', text = 'xx' } } }, final_tabstop })
  validate('${1:${2:$3}}', { ['3'] = 'xx' }, { { tabstop = '1', placeholder = { { tabstop = '2', placeholder = { { tabstop = '3', text = 'xx' } } } } }, final_tabstop })
  validate('${1:${2:$3}}', { ['2'] = 'xx', ['3'] = 'yy' }, { { tabstop = '1', placeholder = { { tabstop = '2', text = 'xx' } } }, final_tabstop })
end

--stylua: ignore
T['parse()']['can resolve special variables'] = function()
  local validate = function(snippet_body, ref_nodes) eq(parse(snippet_body, { normalize = true }), ref_nodes) end
  local final_tabstop = { tabstop = '0', text = '' }

  local path = test_dir_absolute .. '/snippets/lua.json'
  child.cmd('edit ' .. child.fn.fnameescape(path))
  set_lines({ 'abc def', 'ghi' })
  set_cursor(1, 1)
  type_keys('yvj', '<Esc>')
  set_cursor(1, 2)

  -- Mock constant clipboard for better reproducibility of system registers
  -- (mostly on CI). As `setreg('+', 'clip')` is not guaranteed to be working
  -- for system clipboard, use `g:clipboard` which copies/pastes directly.
  child.lua([[
    local clip = function() return { { 'clip' }, 'v' } end
    local board = function() return { { 'board' }, 'v' } end
    vim.g.clipboard = {
      name  = 'myClipboard',
      copy  = { ['+'] = clip, ['*'] = board },
      paste = { ['+'] = clip, ['*'] = board },
    }
  ]])
  child.bo.commentstring = '/* %s */'

  -- LSP
  validate('$TM_SELECTED_TEXT', { { var = 'TM_SELECTED_TEXT', text = 'bc def\ng' }, final_tabstop })
  validate('$TM_CURRENT_LINE',  { { var = 'TM_CURRENT_LINE',  text = 'abc def' },   final_tabstop })
  validate('$TM_CURRENT_WORD',  { { var = 'TM_CURRENT_WORD',  text = 'abc' },       final_tabstop })
  validate('$TM_LINE_INDEX',    { { var = 'TM_LINE_INDEX',    text = '0' },         final_tabstop })
  validate('$TM_LINE_NUMBER',   { { var = 'TM_LINE_NUMBER',   text = '1' },         final_tabstop })

  local validate_path = function(var, ref_text)
    local nodes = parse(var, { normalize = true })
    nodes[1].text = nodes[1].text:gsub('\\',  '/')
    eq(nodes, { { var = var:sub(2), text = ref_text }, final_tabstop })
  end
  validate_path('$TM_FILENAME',      'lua.json')
  validate_path('$TM_FILENAME_BASE', 'lua')
  validate_path('$TM_DIRECTORY',     test_dir_absolute .. '/snippets')
  validate_path('$TM_FILEPATH',      path)

  -- VS Code
  validate_path('$RELATIVE_FILEPATH', test_dir .. '/snippets/lua.json')
  validate_path('$WORKSPACE_FOLDER',  child.fn.getcwd():gsub('\\', '/'))
  validate('$CLIPBOARD',         { { var = 'CLIPBOARD', text = 'clip' },  final_tabstop })
  validate('$CURSOR_INDEX',      { { var = 'CURSOR_INDEX', text = '2' },  final_tabstop })
  validate('$CURSOR_NUMBER',     { { var = 'CURSOR_NUMBER', text = '3' }, final_tabstop })
  validate('$LINE_COMMENT',      { { var = 'LINE_COMMENT', text = '/*' }, final_tabstop })

  -- - Date/time
  child.lua([[
    _G.args_log = {}
    vim.fn.strftime = function(...)
      table.insert(_G.args_log, { ... })
      return 'datetime'
    end
  ]])
  local validate_datetime = function(var, ref_strftime_format)
    child.lua('_G.args_log = {}')
    validate(var, { { var = var:sub(2), text = 'datetime' }, final_tabstop })
    eq(child.lua_get('_G.args_log'), { { ref_strftime_format } })
  end

  validate_datetime('$CURRENT_YEAR',             '%Y')
  validate_datetime('$CURRENT_YEAR_SHORT',       '%y')
  validate_datetime('$CURRENT_MONTH',            '%m')
  validate_datetime('$CURRENT_MONTH_NAME',       '%B')
  validate_datetime('$CURRENT_MONTH_NAME_SHORT', '%b')
  validate_datetime('$CURRENT_DATE',             '%d')
  validate_datetime('$CURRENT_DAY_NAME',         '%A')
  validate_datetime('$CURRENT_DAY_NAME_SHORT',   '%a')
  validate_datetime('$CURRENT_HOUR',             '%H')
  validate_datetime('$CURRENT_MINUTE',           '%M')
  validate_datetime('$CURRENT_SECOND',           '%S')
  validate_datetime('$CURRENT_TIMEZONE_OFFSET',  '%z')

  validate('$CURRENT_SECONDS_UNIX', { { var = 'CURRENT_SECONDS_UNIX', text = tostring(child.lua_get('os.time()')) }, final_tabstop })

  -- Random values
  child.lua('vim.loop.hrtime = function() return 101 end') -- mock reproducible `math.randomseed`
  local ref_random = {
    { var = 'RANDOM', text = '491985' }, { var = 'RANDOM', text = '873024' },
    { var = 'RANDOM_HEX', text = '10347d' }, { var = 'RANDOM_HEX', text = 'df5ed0' },
    { var = 'UUID', text = '13d0871f-61d3-464a-b774-28645dca9e3a' }, { var = 'UUID', text = '7bac0382-1057-48d1-9f3b-9b45dbf681e8' },
    final_tabstop,
  }
  validate( '${RANDOM}${RANDOM}${RANDOM_HEX}${RANDOM_HEX}${UUID}${UUID}', ref_random)

  -- - Should prefer user lookup
  eq(
    parse('$TM_SELECTED_TEXT', { normalize = true, lookup = { TM_SELECTED_TEXT = 'xxx' } }),
    { { var = 'TM_SELECTED_TEXT', text = 'xxx' }, final_tabstop }
  )
  local random_opts = { normalize = true, lookup = { RANDOM = 'a', RANDOM_HEX = 'b', UUID = 'c' } }
  local random_nodes = {
    { var = 'RANDOM',     text = 'a' }, { var = 'RANDOM',     text = 'a' },
    { var = 'RANDOM_HEX', text = 'b' }, { var = 'RANDOM_HEX', text = 'b' },
    { var = 'UUID',       text = 'c' }, { var = 'UUID',       text = 'c' },
    final_tabstop,
  }
  eq(parse('${RANDOM}${RANDOM}${RANDOM_HEX}${RANDOM_HEX}${UUID}${UUID}', random_opts), random_nodes)

  -- Should evaluate variable only once
  child.lua('_G.args_log = {}')
  eq(
    parse('${CURRENT_YEAR}${CURRENT_YEAR}${CURRENT_MONTH}${CURRENT_MONTH}', { normalize = true }),
    {
      { var = 'CURRENT_YEAR',  text = 'datetime' }, { var = 'CURRENT_YEAR',  text = 'datetime' },
      { var = 'CURRENT_MONTH', text = 'datetime' }, { var = 'CURRENT_MONTH', text = 'datetime' },
      final_tabstop,
    }
  )
  eq(child.lua_get('_G.args_log'), { { '%Y' }, { '%m' } })
end

T['parse()']['throws informative errors'] = function()
  local validate = function(body, error_pattern)
    expect.error(function() parse(body) end, error_pattern)
  end

  -- Parsing
  validate('${-', '${` should be followed by digit %(in tabstop%) or letter/underscore %(in variable%), not "%-"')
  validate('${ ', '${` should be followed by digit %(in tabstop%) or letter/underscore %(in variable%), not " "')

  -- Tabstop
  -- Should be closed with `}`
  validate('${1', '"${" should be closed with "}"')
  validate('${1a}', 'Tabstop id should be followed by "}", ":", "|", or "/" not "a"')

  -- Should be followed by either `:` or `}`
  validate('${1 }', 'Tabstop id should be followed by "}", ":", "|", or "/" not " "')
  validate('${1?}', 'Tabstop id should be followed by "}", ":", "|", or "/" not "?"')
  validate('${1 |}', 'Tabstop id should be followed by "}", ":", "|", or "/" not " "')

  -- Choice
  validate('${1|a', 'Tabstop with choices should be closed with "|}"')
  validate('${1|a|', 'Tabstop with choices should be closed with "|}"')
  validate('${1|a}', 'Tabstop with choices should be closed with "|}"')
  validate([[${1|a\|}]], 'Tabstop with choices should be closed with "|}"')
  validate('${1|a,b', 'Tabstop with choices should be closed with "|}"')
  validate('${1|a,b}', 'Tabstop with choices should be closed with "|}"')
  validate('${1|a,b|', 'Tabstop with choices should be closed with "|}"')

  validate('${1|a,b| $2', 'Tabstop with choices should be closed with "|}"')
  validate('${1|a,b|,c}', 'Tabstop with choices should be closed with "|}"')

  -- Variable
  validate('${a }', 'Variable name should be followed by "}", ":" or "/", not " "')
  validate('${a?}', 'Variable name should be followed by "}", ":" or "/", not "?"')
  validate('${a :}', 'Variable name should be followed by "}", ":" or "/", not " "')
  validate('${a?:}', 'Variable name should be followed by "}", ":" or "/", not "?"')

  -- Placeholder
  validate('${1:', 'Placeholder should be closed with "}"')
  validate('${1:a', 'Placeholder should be closed with "}"')
  validate('${1:a bb', 'Placeholder should be closed with "}"')
  validate('${1:${2:a', 'Placeholder should be closed with "}"')

  -- - Nested nodes should error according to their rules
  validate('${1:${2?}}', 'Tabstop id should be followed by "}", ":", "|", or "/" not "?"')
  validate('${1:${2?', 'Tabstop id should be followed by "}", ":", "|", or "/" not "?"')
  validate('${1:${2|a}}', 'Tabstop with choices should be closed with "|}"')
  validate('${1:${a }}', 'Variable name should be followed by "}", ":" or "/", not " "')
  validate('${1:${-}}', '${` should be followed by digit %(in tabstop%) or letter/underscore %(in variable%), not "%-"')

  -- Transform
  validate([[${var/regex/format}]], 'Transform should contain 3 "/" outside of `${...}` and be closed with "}"')
  validate(
    [[${var/regex\/format/options}]],
    'Transform should contain 3 "/" outside of `${...}` and be closed with "}"'
  )
  validate([[${var/.*/$\/i}]], 'Transform should contain 3 "/" outside of `${...}` and be closed with "}"')
  validate('${var/regex/${/}options}', 'Transform should contain 3 "/" outside of `${...}` and be closed with "}"')

  validate([[${1/regex/format}]], 'Transform should contain 3 "/" outside of `${...}` and be closed with "}"')
end

T['parse()']['validates input'] = function()
  expect.error(function() parse(1) end, 'Snippet body.*string or array of strings')
end

-- Integration tests ==========================================================
T['Session'] = new_set()

local start_session = function(snippet) default_insert({ body = snippet }) end

T['Session']['properly adjusts highlighting'] = function()
  -- All nodes inside current placeholder should be highlighted the same
  MiniTest.skip()
end

T['Session']['cleans extmarks when they are not needed'] = function()
  local ns_id
  local validate_n_extmarks = function(ref_n)
    local session = get()
    if session ~= vim.NIL then ns_id = session.ns_id end
    local all_extmarks = child.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, {})
    eq(#all_extmarks, ref_n)
  end

  start_session('T1=${1:<$2>}')
  validate_n_extmarks(8)

  type_keys('x')
  validate_state('i', { 'T1=x' }, { 1, 4 })
  validate_n_extmarks(4)

  start_session('U1=$1')
  validate_n_extmarks(9)

  stop()
  validate_n_extmarks(4)
  stop()
  validate_n_extmarks(0)
end

T['Session']['persists after `:edit`'] = function()
  local path = test_dir_absolute .. '/tmp'
  child.fn.writefile({}, path)
  MiniTest.finally(function() child.fn.delete(path) end)
  edit(path)

  start_session('T1=$1 T0=$0')
  validate_active_session()

  -- NOTE: Write changes as making `:edit!` work is unreasonable
  child.cmd('write')
  child.cmd('edit')
  sleep(small_time)

  -- Should preserve both highlighting and data
  validate_active_session()
  child.expect_screenshot()
end

T['Session']['autostops when text is typed in final tabstop'] = function()
  local validate = function(key)
    start_session('T1=$1 T0=$0')
    validate_active_session()
    jump('next')
    type_keys(key)
    validate_no_active_session()
    ensure_clean_state()
  end

  -- Adding visible character
  validate('x')
  validate(' ')
  validate('\t')

  -- Adding "invisible" character (matters as `InsertCharPre` is not triggered)
  validate('<CR>')
  validate('<C-o>o')
  validate('<C-o>O')
end

T['Session']['autostops when exiting to Normal mode in final tabstop'] = function()
  start_session('T1=$1 T0=$0')
  validate_active_session()
  jump('next')
  type_keys('<Esc>')
  validate_no_active_session()
  ensure_clean_state()

  -- Should stop only when exiting in full Normal mode
  start_session('T1=$1 T0=$0')
  jump('next')
  type_keys('<C-o><Esc>')
  validate_active_session()
end

T['Session']['nesting'] = new_set({ hooks = { pre_case = setup_event_log } })

T['Session']['nesting']['works and triggers events'] = function()
  local body_1, body_2, body_3 = 'T1=$1 T0=$0', 'U1=$1 U0=$0', 'V1=$1 V0=$0'

  start_session(body_1)
  validate_n_sessions(1)
  eq(get_snippet_body(get()), body_1)
  child.expect_screenshot()

  start_session(body_2)
  eq(get_snippet_body(get()), body_2)
  validate_n_sessions(2)
  -- Highlighting of previous session should stop, but should still track
  child.expect_screenshot()

  start_session(body_3)
  -- Any user typing in nested session should be tracked in all other sessions
  type_keys('vvv')
  eq(get_snippet_body(get()), body_3)
  validate_n_sessions(3)
  child.expect_screenshot()

  -- Jumping inside nested session should be done only within its tabstops
  jump('next')
  eq(get_cursor(), { 1, 16 })
  -- - Along with wrapping
  jump('next')
  eq(get_cursor(), { 1, 12 })

  stop()
  eq(get_snippet_body(get()), body_2)
  validate_n_sessions(2)
  -- Tabstop range of previous session should track changes in nested ones
  child.expect_screenshot()

  stop()
  validate_n_sessions(1)
  eq(get_snippet_body(get()), body_1)
  child.expect_screenshot()

  stop()

  -- Should trigger proper events in proper order
  local make_ref_data = function(snippet_body)
    return { session = { insert_args = { snippet = { body = snippet_body } } } }
  end
  local cur_buf_id = get_buf()
  --stylua: ignore
  local ref_au_log_partial = {
    { event = 'MiniSnippetsSessionStart',   data = make_ref_data(body_1), buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionSuspend', data = make_ref_data(body_1), buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionStart',   data = make_ref_data(body_2), buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionSuspend', data = make_ref_data(body_2), buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionStart',   data = make_ref_data(body_3), buf_id = cur_buf_id },

    { event = 'MiniSnippetsSessionJumpPre', data = { tabstop_from = '1', tabstop_to = '0' }, buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionJump',    data = { tabstop_from = '1', tabstop_to = '0' }, buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionJumpPre', data = { tabstop_from = '0', tabstop_to = '1' }, buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionJump',    data = { tabstop_from = '0', tabstop_to = '1' }, buf_id = cur_buf_id },

    { event = 'MiniSnippetsSessionStop',   data = make_ref_data(body_3), buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionResume', data = make_ref_data(body_2), buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionStop',   data = make_ref_data(body_2), buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionResume', data = make_ref_data(body_1), buf_id = cur_buf_id },
    { event = 'MiniSnippetsSessionStop',   data = make_ref_data(body_1), buf_id = cur_buf_id },
  }
  eq_partial_tbl(get_au_log(), ref_au_log_partial)
end

T['Session']['nesting']['does not nest if no tabstops in new session'] = function()
  start_session('T1=$1 T0=$0')
  start_session('just text')
  validate_n_sessions(1)
  child.expect_screenshot()
end

T['Session']['nesting']['resuming session should not change mode/cursor/buffer'] = function()
  -- Resuming in current buffer
  start_session('T1=$1\nT0=$0\n')
  type_keys('<Down><Down>')
  start_session('U1=$1 U0=$0')
  jump('next')

  validate_state('i', { 'T1=', 'T0=', 'U1= U0=' }, { 3, 7 })
  validate_n_sessions(2)
  type_keys('x')
  validate_state('i', { 'T1=', 'T0=', 'U1= U0=x' }, { 3, 8 })
  validate_n_sessions(1)
  eq(get_snippet_body(), 'T1=$1\nT0=$0\n')

  ensure_clean_state()

  -- Resuming in another buffer
  start_session('T1=$1 T0=$0')
  child.ensure_normal_mode()
  local new_buf_id = new_buf()
  set_buf(new_buf_id)
  start_session('U1=$1 U0=$0')

  jump('next')
  eq(child.fn.mode(), 'i')
  eq(get_cur_tabstop(), '0')
  type_keys('<Esc>')
  -- Should not change mode or buffer
  eq(child.fn.mode(), 'n')
  eq(get_buf(), new_buf_id)
end

T['Session']['nesting']['can be done outside of current session region'] = function()
  start_session('T1=$1 T0=$0')
  type_keys('<Esc>', 'o', '<CR>')
  start_session('U1=$1 U0=$0')
  validate_n_sessions(2)
  child.expect_screenshot()
end

T['Session']['nesting']['can be done in different buffer'] = function()
  start_session('T1=$1 T0=$0')
  child.ensure_normal_mode()
  local prev_buf_id, new_buf_id = get_buf(), new_buf()
  set_buf(new_buf_id)
  start_session('U1=$1 U0=$0')

  validate_n_sessions(2)
  eq(get_buf(), new_buf_id)
  eq_partial_tbl(get(), { buf_id = new_buf_id, insert_args = { snippet = { body = 'U1=$1 U0=$0' } } })

  -- Stopping session should not change buffer or jump
  stop()
  eq_partial_tbl(get(), { buf_id = prev_buf_id, insert_args = { snippet = { body = 'T1=$1 T0=$0' } } })
  eq(get_buf(), new_buf_id)
  validate_state('i', { 'U1= U0=' }, { 1, 3 })
end

T['Session']['nesting']['session stack is properly cleaned when buffer is unloaded'] = function()
  local buf_id_1, buf_id_2, buf_id_3 = new_buf(), new_buf(), new_buf()
  local body_1, body_2, body_3, body_4 = 'T1=$1 T0=$0', 'U1=$1 U0=$0', 'V1=$1 V0=$0', 'W1=$1 W0=$0'
  set_buf(buf_id_1)
  start_session(body_1)
  set_buf(buf_id_2)
  start_session(body_2)
  set_buf(buf_id_3)
  start_session(body_3)
  start_session(body_4)

  local ref_sessions = {
    { buf_id = buf_id_1, insert_args = { snippet = { body = body_1 } } },
    { buf_id = buf_id_2, insert_args = { snippet = { body = body_2 } } },
    { buf_id = buf_id_3, insert_args = { snippet = { body = body_3 } } },
    { buf_id = buf_id_3, insert_args = { snippet = { body = body_4 } } },
  }
  eq_partial_tbl(get_all(), ref_sessions)

  clean_au_log()

  -- Deleting session in the middle of stack should work
  child.api.nvim_buf_delete(buf_id_2, { force = true, unload = true })
  eq_partial_tbl(get_all(), { ref_sessions[1], ref_sessions[3], ref_sessions[4] })

  -- Deleting current session should make the nearest one active
  child.api.nvim_buf_delete(buf_id_3, { force = true, unload = true })
  eq_partial_tbl(get_all(), { ref_sessions[1] })

  -- Deleting the last active session should also work
  eq(get_buf(), buf_id_1)
  child.api.nvim_buf_delete(buf_id_1, { force = true, unload = false })
  validate_n_sessions(0)

  -- Proper events should still be triggered during session clean
  local make_ref_data = function(buf_id, snippet_body)
    return { session = { buf_id = buf_id, insert_args = { snippet = { body = snippet_body } } } }
  end
  --stylua: ignore
  local ref_au_log_partial = {
    -- Event can be triggered with other buffer being current (due to
    -- `vim.schedule_wrap()` needed to make `:edit` work)
    { event = 'MiniSnippetsSessionStop',   data = make_ref_data(buf_id_2, body_2), buf_id = buf_id_3 },
    -- No 'Resume' of already active session
    -- Unloading current buffer should also be possible
    { event = 'MiniSnippetsSessionStop',   data = make_ref_data(buf_id_3, body_3), buf_id = buf_id_1 },
    { event = 'MiniSnippetsSessionStop',   data = make_ref_data(buf_id_3, body_4), buf_id = buf_id_1 },
    -- Deleting active session resumes the next available
    { event = 'MiniSnippetsSessionResume', data = make_ref_data(buf_id_1, body_1), buf_id = buf_id_1 },
    { event = 'MiniSnippetsSessionStop',   data = make_ref_data(buf_id_1, body_1), buf_id = get_buf() },
  }
  eq_partial_tbl(get_au_log(), ref_au_log_partial)
end

T['Interaction with built-in completion'] = new_set()

T['Interaction with built-in completion'] =
  new_set({ hooks = { pre_case = function() child.o.completeopt = 'menuone,noselect' end } })

T['Interaction with built-in completion']['popup removal during insert'] = function()
  set_lines({ 'abc', '' })
  set_cursor(2, 0)

  type_keys('i', '<C-n>')
  validate_pumvisible()
  default_insert({ body = 'no tabstops' })
  validate_no_pumvisible()
  validate_no_active_session()

  type_keys('<CR>', '<C-n>')
  validate_pumvisible()
  default_insert({ body = 'yes tabstops: $1' })
  validate_no_pumvisible()
  validate_active_session()
end

T['Interaction with built-in completion']['popup removal during jump'] = function()
  default_insert({ body = 'abc $1 $2' })
  type_keys('a', '<C-n>')
  validate_pumvisible()
  jump('next')
  validate_no_pumvisible()

  type_keys('a', '<C-n>')
  validate_pumvisible()
  jump('prev')
  validate_no_pumvisible()
end

T['Interaction with built-in completion']['preserves popup on autoclose'] = function()
  default_insert({ body = 'abc $1 $0' })
  jump('next')
  type_keys('<C-x><C-n>')
  validate_pumvisible()

  type_keys('a')
  sleep(small_time)
  validate_no_active_session()
  validate_pumvisible()
end

T['Interaction with built-in completion']['no affect of "exausted" popup during jump'] = function()
  default_insert({ body = 'abc $1 $2' })
  type_keys('a', '<C-n>', 'x')
  validate_no_pumvisible()
  jump('next')

  type_keys('x')
  child.expect_screenshot()
end

T['Interaction with built-in completion']['no wrong automatic session stop during jump'] = function()
  default_insert({ body = 'ab $1\n$1\n$0' })
  type_keys('a', '<C-n>')
  validate_pumvisible()
  jump('next')
  sleep(small_time)
  validate_active_session()
end

T['Interaction with built-in completion']['squeezed tabstops'] = function()
  default_insert({ body = '$1$2$1$2$1' })
  type_keys('abc', '<C-l>', 'x')
  type_keys('<C-n>')
  child.expect_screenshot()
  type_keys('y')
  -- NOTE: Requires the fix for extmarks to not be affected
  -- See https://github.com/neovim/neovim/issues/31384
  if child.fn.has('nvim-0.10.3') == 1 then child.expect_screenshot() end
end

T['Interaction with built-in completion']['cycling through candidates'] = function()
  set_lines({ 'aa bb', '' })
  set_cursor(2, 0)
  default_insert({ body = '$1$1' })
  type_keys('<C-n>', '<C-n>')
  validate_state('i', { 'aa bb', 'aaaa' }, { 2, 2 })
  validate_pumvisible()

  type_keys('<C-p>')
  -- NOTE: Requires the fix for extmarks to not be affected
  -- See https://github.com/neovim/neovim/pull/31475
  if child.fn.has('nvim-0.10.3') == 1 then validate_state('i', { 'aa bb', '' }, { 2, 0 }) end
  validate_pumvisible()
end

T['Various snippets'] = new_set()

T['Various snippets']['just text'] = function() MiniTest.skip() end

T['Tricky snippets'] = new_set()

T['Tricky snippets']['squashed and linked'] = function() MiniTest.skip() end

T['Mappings'] = new_set()

T['Mappings']['works'] = function()
  -- Should copy and restore possibly conflicting mappings
  MiniTest.skip()
end

T['Examples'] = new_set()

T['Examples']['stop session after jump to final tabstop'] = function()
  child.lua([[
    local fin_stop = function(args) if args.data.tabstop_to == '0' then MiniSnippets.session.stop() end end
    vim.api.nvim_create_autocmd('User', { pattern = 'MiniSnippetsSessionJump', callback = fin_stop })
  ]])
  start_session('T1=$1; T0=$0')
  validate_active_session()
  jump('next')
  validate_no_active_session()
end

T['Examples']['<Tab>/<S-Tab> mappings'] = function()
  child.setup()
  load_module({
    snippets = { { prefix = 'l', body = 'T1=$1 T0=0' } },
    mappings = { expand = '', jump_next = '' },
  })
  child.lua([[
    local minisnippets = require('mini-dev.snippets')
    local match_strict = function(snippets, pos)
      return minisnippets.default_match(snippets, pos, { pattern_fuzzy='%S+' })
    end
    minisnippets.setup({
      snippets = { { prefix = 'l', body = 'T1=$1 T0=0' } },
      mappings = { expand = '', jump_next = '' },
      expand = { match = match_strict },
    })
    local expand_or_jump = function()
      local can_expand = #MiniSnippets.expand({ insert = false }) > 0
      if can_expand then vim.schedule(MiniSnippets.expand); return '' end
      local is_active = MiniSnippets.session.get() ~= nil
      if is_active then MiniSnippets.session.jump('next'); return '' end
      return '\t'
    end
    local jump_prev = function() MiniSnippets.session.jump('prev') end
    vim.keymap.set('i', '<Tab>', expand_or_jump, { expr = true })
    vim.keymap.set('i', '<S-Tab>', jump_prev)
  ]])

  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })

  type_keys('l', '<Tab>')
  validate_active_session()
  eq(get_cur_tabstop(), '1')

  type_keys('l', '<Tab>')
  validate_n_sessions(2)
  eq(get_cur_tabstop(), '1')

  type_keys('<Tab>')
  validate_n_sessions(2)
  eq(get_cur_tabstop(), '0')

  type_keys('<S-Tab>')
  validate_n_sessions(2)
  eq(get_cur_tabstop(), '1')
end

T['Examples']['using `vim.snippet.expand()`'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('`vim.snippet` is present only in Neovim>=0.10') end
  child.lua([[
    require('mini-dev.snippets').setup({
      snippets = { { prefix = 't', body = 'T1=$1 T2=${2:<two>}' } },
      expand = {
        insert = function(snippet, _) vim.snippet.expand(snippet.body) end
      }
    })
    local jump_next = function()
      if vim.snippet.active({direction = 1}) then return vim.snippet.jump(1) end
    end
    local jump_prev = function()
      if vim.snippet.active({direction = -1}) then vim.snippet.jump(-1) end
    end
    vim.keymap.set({ 'i', 's' }, '<C-l>', jump_next)
    vim.keymap.set({ 'i', 's' }, '<C-h>', jump_prev)
  ]])

  type_keys('i', 't', '<C-j>')
  -- SHould not have active session from `default_insert()`
  validate_no_active_session()
  validate_state('i', { 'T1= T2=<two>' }, { 1, 3 })
  type_keys('t1')
  validate_state('i', { 'T1=t1 T2=<two>' }, { 1, 5 })
  type_keys('<C-l>')
  validate_state('s', { 'T1=t1 T2=<two>' }, { 1, 9 })
  type_keys('t2')
  validate_state('i', { 'T1=t1 T2=t2' }, { 1, 11 })
  type_keys('<C-h>')
  validate_state('s', { 'T1=t1 T2=t2' }, { 1, 3 })
end

return T
