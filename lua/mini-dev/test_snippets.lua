local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq, no_eq = helpers.expect, helpers.expect.equality, helpers.expect.no_equality
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
--stylua: ignore end

local test_dir = 'tests/dir-snippets'
local test_dir_absolute = vim.fn.fnamemodify(test_dir, ':p'):gsub('\\', '/'):gsub('(.)/$', '%1')

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
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
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniSnippetsCurrent', 'links to DiffText')
  has_highlight('MiniSnippetsPlaceholder', 'links to DiffAdd')
  has_highlight('MiniSnippetsVisited', 'links to DiffChange')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniSnippets.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniSnippets.config.' .. field), value) end

  expect_config('snippets', {})
  expect_config('match', { find = nil, select = nil, expand = nil })
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
  expect_config_error({ match = 1 }, 'match', 'table')
  expect_config_error({ match = { find = 1 } }, 'match.find', 'function')
  expect_config_error({ match = { select = 1 } }, 'match.select', 'function')
  expect_config_error({ match = { expand = 1 } }, 'match.expand', 'function')
end

T['_parse()'] = new_set()

local parse = forward_lua('MiniSnippets._parse')

T['_parse()']['works'] = function()
  --stylua: ignore
  eq(
    parse('hello ${1:xx} $var world$0'),
    {
      { text = 'hello ' }, { tabstop = '1', placeholder = { { text = 'xx' } } }, { text = ' ' },
      { var = 'var' }, { text = ' world' }, { tabstop = '0' },
    }
  )
  eq(parse({ 'aa', '$1', '$var' }), { { text = 'aa\n' }, { tabstop = '1' }, { text = '\n' }, { var = 'var' } })
end

--stylua: ignore
T['_parse()']['text'] = function()
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
T['_parse()']['tabstop'] = function()
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
T['_parse()']['choice'] = function()
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
T['_parse()']['var'] = function()
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
T['_parse()']['placeholder'] = function()
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
T['_parse()']['transform'] = function()
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
T['_parse()']['tricky'] = function()
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

T['_parse()']['respects `opts.resolve_vars`'] = function()
  local validate = function(snippet_body, ref_nodes) eq(parse(snippet_body, { resolve_vars = true }), ref_nodes) end
  local is_win = helpers.is_windows()

  child.fn.setenv('AA', 'my-aa')
  child.fn.setenv('XX', 'my-xx')
  -- NOTE: on Windows setting environment variable to empty string is the same
  -- as deleting it (at least until 2024-07-11 change which enables it)
  child.fn.setenv('EMPTY', '')

  -- Resolve variables if `resolve_vars` is true-ish
  validate('$AA', { { text = 'my-aa' } })
  validate('${AA}', { { text = 'my-aa' } })
  validate('$EMPTY', { { text = '' } })

  -- Falls back to placeholder
  validate('${BB:fallback}', { { text = 'fallback' } })
  validate('aa${BB:_$1!}bb', { { text = 'aa' }, { text = '_' }, { tabstop = '1' }, { text = '!' }, { text = 'bb' } })
  validate('$1${BB:xx}${2|uu,vv|}', { { tabstop = '1' }, { text = 'xx' }, { tabstop = '2', choices = { 'uu', 'vv' } } })

  -- Should not use placeholder if variable is set
  if not is_win then validate('${EMPTY:fallback}', { { text = '' } }) end

  -- Preserves node if evaluation failed and no placeholder
  validate('$BB', { { text = '' } })
  validate('${BB}', { { text = '' } })
  validate('aa${BB}bb', { { text = 'aa' }, { text = '' }, { text = 'bb' } })
  validate('aa${BB}', { { text = 'aa' }, { text = '' } })
  validate('${BB}bb', { { text = '' }, { text = 'bb' } })
  validate('$1$BB${2|uu,vv|}', { { tabstop = '1' }, { text = '' }, { tabstop = '2', choices = { 'uu', 'vv' } } })

  -- Resolves all variables (however deep)
  validate('${XX}$AA$BB', { { text = 'my-xx' }, { text = 'my-aa' }, { text = '' } })

  validate('${BB:$AA}', { { text = 'my-aa' } })
  validate('${BB:${CC:$AA}}', { { text = 'my-aa' } })

  validate('${BB:xx${AA}yy}', { { text = 'xx' }, { text = 'my-aa' }, { text = 'yy' } })
  validate('${BB:xx${CC:yy$AA}}', { { text = 'xx' }, { text = 'yy' }, { text = 'my-aa' } })

  -- Can resolve variables from user lookup
  eq(parse('$BB', { resolve_vars = { BB = 'hello' } }), { { text = 'hello' } })
  eq(parse('$BB', { resolve_vars = { BB = 1 } }), { { text = '1' } })

  -- - Should prefer user lookup
  eq(parse('$AA', { resolve_vars = { AA = 'other' } }), { { text = 'other' } })
  eq(parse('$AA', { resolve_vars = { AA = '' } }), { { text = '' } })
  eq(parse('$EMPTY', { resolve_vars = { EMPTY = 'not empty' } }), { { text = 'not empty' } })

  eq(parse('$AA$XX', { resolve_vars = { AA = '!', XX = '?' } }), { { text = '!' }, { text = '?' } })

  -- Evaluates variable only once
  child.lua([[
    _G.log = {}
    local os_getenv_orig = vim.loop.os_getenv
    vim.loop.os_getenv = function(...)
      table.insert(_G.log, { ... })
      return os_getenv_orig(...)
    end
  ]])
  validate('${AA}${AA}${BB}${BB}', { { text = 'my-aa' }, { text = 'my-aa' }, { text = '' }, { text = '' } })
  eq(child.lua_get('_G.log'), { { 'AA' }, { 'BB' } })

  -- - But not persistently
  child.fn.setenv('AA', '!')
  child.fn.setenv('BB', '?')
  validate('${AA}${BB}', { { text = '!' }, { text = '?' } })
end

--stylua: ignore
T['_parse()']['can resolve special variables'] = function()
  local validate = function(snippet_body, ref_nodes) eq(parse(snippet_body, { resolve_vars = true }), ref_nodes) end

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
  validate('$TM_SELECTED_TEXT', { { text = 'bc def\ng' } })
  validate('$TM_CURRENT_LINE',  { { text = 'abc def' } })
  validate('$TM_CURRENT_WORD',  { { text = 'abc' } })
  validate('$TM_LINE_INDEX',    { { text = '0' } })
  validate('$TM_LINE_NUMBER',   { { text = '1' } })

  local validate_path = function(snippet_body, ref_text)
    local nodes = parse(snippet_body, { resolve_vars = true })
    nodes[1].text = nodes[1].text:gsub('\\',  '/')
    eq(nodes, { { text = ref_text } })
  end
  validate_path('$TM_FILENAME',      'lua.json')
  validate_path('$TM_FILENAME_BASE', 'lua')
  validate_path('$TM_DIRECTORY',     test_dir_absolute .. '/snippets')
  validate_path('$TM_FILEPATH',      path)

  -- VS Code
  validate_path('$RELATIVE_FILEPATH', test_dir .. '/snippets/lua.json')
  validate_path('$WORKSPACE_FOLDER',  child.fn.getcwd():gsub('\\', '/'))
  validate('$CLIPBOARD',         { { text = 'clip' } })
  validate('$CURSOR_INDEX',      { { text = '2' } })
  validate('$CURSOR_NUMBER',     { { text = '3' } })
  validate('$LINE_COMMENT',      { { text = '/*' } })

  -- - Date/time
  child.lua([[
    _G.args_log = {}
    vim.fn.strftime = function(...)
      table.insert(_G.args_log, { ... })
      return 'datetime'
    end
  ]])
  local validate_datetime = function(snippet_body, ref_strftime_format)
    child.lua('_G.args_log = {}')
    validate(snippet_body, { { text = 'datetime' } })
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

  validate('$CURRENT_SECONDS_UNIX', { { text = tostring(child.lua_get('os.time()')) } })

  -- Random values
  child.lua('vim.loop.hrtime = function() return 101 end') -- mock reproducible `math.randomseed`
  child.lua('math.randomseed(101)')
  local ref_random = {
    { text = '491985' }, { text = '873024' },
    { text = '10347d' }, { text = 'df5ed0' },
    { text = '13d0871f-61d3-464a-b774-28645dca9e3a' }, { text = '7bac0382-1057-48d1-9f3b-9b45dbf681e8' },
  }
  validate( '${RANDOM}${RANDOM}${RANDOM_HEX}${RANDOM_HEX}${UUID}${UUID}', ref_random)

  -- - Should prefer user lookup
  eq(parse('$TM_SELECTED_TEXT', { resolve_vars = { TM_SELECTED_TEXT = 'xxx' } }), { { text = 'xxx' } })
  local random_opts = { resolve_vars = { RANDOM = 'a', RANDOM_HEX = 'b', UUID = 'c' } }
  local random_nodes = { { text = 'a' }, { text = 'a' }, { text = 'b' }, { text = 'b' }, { text = 'c' }, { text = 'c' } }
  eq(parse('${RANDOM}${RANDOM}${RANDOM_HEX}${RANDOM_HEX}${UUID}${UUID}', random_opts), random_nodes)

  -- Should evaluate variable only once
  child.lua('_G.args_log = {}')
  eq(
    parse('${CURRENT_YEAR}${CURRENT_YEAR}${CURRENT_MONTH}${CURRENT_MONTH}', { resolve_vars = true }),
    { { text = 'datetime' }, { text = 'datetime' }, { text = 'datetime' }, { text = 'datetime'} }
  )
  eq(child.lua_get('_G.args_log'), { { '%Y' }, { '%m' } })
end

T['_parse()']['throws informative errors'] = function()
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

T['_parse()']['validates input'] = function()
  expect.error(function() parse(1) end, 'Snippet body.*string or array of strings')
end

return T
