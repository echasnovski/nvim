local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq, no_eq = helpers.expect, helpers.expect.equality, helpers.expect.no_equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('snippets', config) end
local unload_module = function() child.mini_unload('snippets') end
--stylua: ignore end

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

T['Parsing'] = new_set()

local parse = forward_lua('MiniSnippets._parse')

T['Parsing']['works'] = function()
  eq(
    parse('hello $1 $var world$0'),
    { { text = 'hello ' }, { tabstop = '1' }, { text = ' ' }, { var = 'var' }, { text = ' world' }, { tabstop = '0' } }
  )
end

-- TODO:
-- - Use `[[]]` where there is backslash.
-- - Use '' instead of "".
-- - Show `tabstop` or `var` field first.

--stylua: ignore
T['Parsing']['text'] = function()
  -- Common
  eq(parse('aa'),      { { text = 'aa' } })
  eq(parse('ыыы ффф'), { { text = 'ыыы ффф' } })

  -- Simple
  eq(parse(''),   { { text = '' } })
  eq(parse('\\'), { { text = '\\' } })

  -- Escaped (should ignore `\` before `$}\`)
  eq(parse('aa\\$bb\\}cc\\\\dd'), { { text = 'aa$bb}cc\\dd' } })
  eq(parse('aa\\$'),              { { text = 'aa$' } })
  eq(parse('aa\\${}'),            { { text = 'aa${}' } })
  eq(parse('{'),                  { { text = '{' } })
  eq(parse('\\}'),                { { text = '}' } })
  eq(parse('aa \\\\\\$'),         { { text = 'aa \\$' } })
  eq(parse('\\${1|aa,bb|}'),      { { text = '${1|aa,bb|}' } })

  -- Not spec: allow unescaped backslash
  eq(parse('aa\\bb'), { { text = 'aa\\bb' } })

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
T['Parsing']['tabstop'] = function()
  -- Common
  eq(parse("aa $1"),       { { text = "aa " }, { tabstop = "1" } })
  eq(parse("aa $1 bb"),    { { text = "aa " }, { tabstop = "1" }, { text = " bb" } })
  eq(parse("aa$1bb"),      { { text = "aa" }, { tabstop = "1" }, { text = "bb" } })
  eq(parse("hello_$1_bb"), { { text = "hello_" }, { tabstop = "1" }, { text = "_bb" } })
  eq(parse("ыыы $1 ффф"),  { { text = "ыыы " },   { tabstop = "1" }, { text = " ффф" } })

  eq(parse("aa ${1}"),       { { text = "aa " }, { tabstop = "1" } })
  eq(parse("aa${1}bb"),      { { text = "aa" }, { tabstop = "1" }, { text = "bb" } })
  eq(parse("hello_${1}_bb"), { { text = "hello_" }, { tabstop = "1" }, { text = "_bb" } })
  eq(parse("ыыы ${1} ффф"),  { { text = "ыыы " }, { tabstop = "1" }, { text = " ффф" } })

  eq(parse("aa $0"),    { { text = "aa " }, { tabstop = "0" } })
  eq(parse("aa $1 $0"), { { text = "aa " }, { tabstop = "1" }, { text = " " }, { tabstop = "0" } })

  eq(parse("aa\\\\$bb"), { { text = "aa\\" }, { var = "bb" } })

  -- Simple
  eq(parse("$1"),   { { tabstop = "1" } })
  eq(parse("${1}"), { { tabstop = "1" } })

  -- Adjacent tabstops
  eq(parse("aa$1$2"),   { { text = "aa" }, { tabstop = "1" }, { tabstop = "2" } })
  eq(parse("aa$1$0"),   { { text = "aa" }, { tabstop = "1" }, { tabstop = "0" } })
  eq(parse("$1$2"),     { { tabstop = "1" }, { tabstop = "2" } })
  eq(parse("${1}${2}"), { { tabstop = "1" }, { tabstop = "2" } })
  eq(parse("$1${2}"),   { { tabstop = "1" }, { tabstop = "2" } })
  eq(parse("${1}$2"),   { { tabstop = "1" }, { tabstop = "2" } })

  -- Can be any numbering in any order
  eq(parse("$2"),       { { tabstop = "2" } })
  eq(parse("$3 $10"),   { { tabstop = "3" }, { text = " " }, { tabstop = "10" } })
  eq(parse("$3 $2 $0"), { { tabstop = "3" }, { text = " " }, { tabstop = "2" }, { text = " " }, { tabstop = "0" } })

  -- Tricky
  eq(parse("$1$a"), { { tabstop = "1" }, { var = "a" } })
  eq(parse("$1$-"), { { tabstop = "1" }, { text = "$-" } })
  eq(parse("$a$1"), { { var = "a" }, { tabstop = "1" } })
  eq(parse("$-$1"), { { text = "$-" }, { tabstop = "1" } })
  eq(parse("$$1"),  { { text = "$" }, { tabstop = "1" } })
  eq(parse("$1$"),  { { tabstop = "1" }, { text = "$" } })
end

--stylua: ignore
T['Parsing']['choice'] = function()
  -- Common
  eq(parse("xx ${1|aa|}"),    { { text = "xx " }, { choices = { "aa" }, tabstop = "1" } })
  eq(parse("xx ${2|aa|}"),    { { text = "xx " }, { choices = { "aa" }, tabstop = "2" } })
  eq(parse("xx ${1|aa,bb|}"), { { text = "xx " }, { choices = { "aa", "bb" }, tabstop = "1" } })

  -- Escape (should ignore `\` before `,|\` and treat as text)
  eq(parse("${1|},$,\\,,\\|,\\\\|}"), { { choices = { "}", "$", ",", "|", "\\" }, tabstop = "1" } })
  eq(parse("xx ${1|aa\\,bb|}"),       { { text = "xx " }, { choices = { "aa,bb" }, tabstop = "1" } })

  -- Empty choices
  eq(parse("xx ${1|,|}"),       { { text = "xx " }, { choices = { "", "" }, tabstop = "1" } })
  eq(parse("xx ${1|aa,|}"),     { { text = "xx " }, { choices = { "aa", "" }, tabstop = "1" } })
  eq(parse("xx ${1|,aa|}"),     { { text = "xx " }, { choices = { "", "aa" }, tabstop = "1" } })
  eq(parse("xx ${1|aa,,bb|}"),  { { text = "xx " }, { choices = { "aa", "", "bb" }, tabstop = "1" } })
  eq(parse("xx ${1|aa,,,bb|}"), { { text = "xx " }, { choices = { "aa", "", "", "bb" }, tabstop = "1" } })

  -- Not spec: allow unescaped backslash
  eq(parse("xx ${1|aa\\bb|}"), { { text = "xx " }, { choices = { "aa\\bb" }, tabstop = "1" } })

  -- Should not be ignored in `$0`
  eq(parse("${0|aa|}"),    { { choices = { "aa" }, tabstop = "0" } })
  eq(parse("${0|aa,bb|}"), { { choices = { "aa", "bb" }, tabstop = "0" } })
end

--stylua: ignore
T['Parsing']['var'] = function()
  -- Common
  eq(parse("$aa"),    { { var = "aa" } })
  eq(parse("$a_b"),   { { var = "a_b" } })
  eq(parse("$_a"),    { { var = "_a" } })
  eq(parse("$a1"),    { { var = "a1" } })
  eq(parse("${aa}"),  { { var = "aa" } })
  eq(parse("${a_b}"), { { var = "a_b" } })
  eq(parse("${_a}"),  { { var = "_a" } })
  eq(parse("${a1}"),  { { var = "a1" } })

  eq(parse("aa\\\\$bb"), { { text = "aa\\" }, { var = "bb" } })
  eq(parse("$$aa"),      { { text = "$" }, { var = "aa" } })
  eq(parse("$aa$"),      { { var = "aa" }, { text = "$" } })

  -- Should recognize only [_a-zA-Z] [_a-zA-Z0-9]*
  eq(parse("$aa-bb"),     { { var = "aa" }, { text = "-bb" } })
  eq(parse("$aa bb"),     { { var = "aa" }, { text = " bb" } })
  eq(parse("aa$bb cc"),   { { text = "aa" }, { var = "bb" }, { text = " cc" } })
  eq(parse("aa${bb} cc"), { { text = "aa" }, { var = "bb" }, { text = " cc" } })

  -- Placeholder (more tests in tabstop placeholder)
  eq(parse("${var:}"),           { { placeholder = { { text = "" } }, var = "var" } })
  eq(parse("${var:aa}"),         { { placeholder = { { text = "aa" } }, var = "var" } })
  eq(parse("${var:aa:bb}"),      { { placeholder = { { text = "aa:bb" } }, var = "var" } })
  eq(parse("${var:$1}"),         { { placeholder = { { tabstop = "1" } }, var = "var" } })
  eq(parse("${var:${1}}"),       { { placeholder = { { tabstop = "1" } }, var = "var" } })
  eq(parse("${var:${1:aa}}"),    { { placeholder = { { placeholder = { { text = "aa" } }, tabstop = "1" } }, var = "var" } })
  eq(parse("${var:${1|aa|}}"),   { { placeholder = { { choices = { "aa" }, tabstop = "1" } }, var = "var" } })
  eq(parse("${var:${var2:aa}}"), { { placeholder = { { placeholder = { { text = "aa" } }, var = "var2" } }, var = "var" } })
end

--stylua: ignore
T['Parsing']['placeholder'] = function()
  -- Common
  eq(parse("aa ${1:b}"),   { { text = "aa " }, { placeholder = { { text = "b" } }, tabstop = "1" } })
  eq(parse("aa ${1:}"),    { { text = "aa " }, { placeholder = { { text = "" } }, tabstop = "1" } })
  eq(parse("aa ${1:ыыы}"), { { text = "aa " }, { placeholder = { { text = "ыыы" } }, tabstop = "1" } })
  eq(parse("${1:}"),       { { placeholder = { { text = "" } }, tabstop = "1" } })

  eq(parse("${1:aa} ${2:bb}"), { { placeholder = { { text = "aa" } }, tabstop = "1" }, { text = " " }, { placeholder = { { text = "bb" } }, tabstop = "2" } })

  eq(parse("aa ${0:b}"),   { { text = "aa " }, { placeholder = { { text = "b" } }, tabstop = "0" } })
  eq(parse("aa ${0:}"),    { { text = "aa " }, { placeholder = { { text = "" } }, tabstop = "0" } })
  eq(parse("aa ${0:ыыы}"), { { text = "aa " }, { placeholder = { { text = "ыыы" } }, tabstop = "0" } })
  eq(parse("${0:}"),       { { placeholder = { { text = "" } }, tabstop = "0" } })

  -- Escaped (should ignore `\` before `$}\` and treat as text)
  eq(parse("${1:aa\\$bb\\}cc\\\\dd}"), { { placeholder = { { text = "aa$bb}cc\\dd" } }, tabstop = "1" } })
  eq(parse("${1:aa\\$}"),              { { placeholder = { { text = "aa$" } }, tabstop = "1" } })
  eq(parse("${1:aa\\\\}"),             { { placeholder = { { text = "aa\\" } }, tabstop = "1" } })
  -- - Should allow unescaped `:`
  eq(parse("${1:aa:bb}"),              { { placeholder = { { text = "aa:bb" } }, tabstop = "1" } })

  -- Not spec: allow unescaped backslash
  eq(parse("${1:aa\\bb}"), { { placeholder = { { text = "aa\\bb" } }, tabstop = "1" } })

  -- Not spec: allow unescaped dollar
  eq(parse("${1:aa$-}"),  { { placeholder = { { text = "aa$-" } }, tabstop = "1" } })
  eq(parse("${1:aa$}"),   { { placeholder = { { text = "aa$" } }, tabstop = "1" } })
  eq(parse("${1:$2$}"),   { { placeholder = { { tabstop = "2" }, { text = "$" } }, tabstop = "1" } })
  eq(parse("${1:$2}$"),   { { placeholder = { { tabstop = "2" } }, tabstop = "1" }, { text = "$" } })
  eq(parse("${1:aa$}$2"), { { placeholder = { { text = "aa$" } }, tabstop = "1" }, { tabstop = "2" } })

  -- Different placeholders for same id/name
  eq(parse("${1:xx}_${1:yy}_$1"), { { placeholder = { { text = "xx" } }, tabstop = "1" }, { text = "_" }, { placeholder = { { text = "yy" } }, tabstop = "1" }, { text = "_" }, { tabstop = "1" } })
  eq(parse("${1:}_$1_${1:yy}"),   { { placeholder = { { text = "" } }, tabstop = "1" }, { text = "_" }, { tabstop = "1" }, { text = "_" }, { placeholder = { { text = "yy" } }, tabstop = "1" } })

  eq(parse("${a:xx}_${a:yy}"),  { { placeholder = { { text = "xx" } }, var = "a" }, { text = "_" }, { placeholder = { { text = "yy" } }, var = "a" } })
  eq(parse("${a:}-$a-${a:yy}"), { { placeholder = { { text = "" } }, var = "a" }, { text = "-" }, { var = "a" }, { text = "-" }, { placeholder = { { text = "yy" } }, var = "a" } })

  -- Nested
  -- - Tabstop
  eq(parse("${1:$2}"),    { { placeholder = { { tabstop = "2" } }, tabstop = "1" } })
  eq(parse("${1:$2} yy"), { { placeholder = { { tabstop = "2" } }, tabstop = "1" }, { text = " yy" } })
  eq(parse("${1:${2}}"),  { { placeholder = { { tabstop = "2" } }, tabstop = "1" } })
  eq(parse("${1:${3}}"),  { { placeholder = { { tabstop = "3" } }, tabstop = "1" } })

  -- - Placeholder
  eq(parse("${1:${2:aa}}"),      { { placeholder = { { placeholder = { { text = "aa" } }, tabstop = "2" } }, tabstop = "1" } })
  eq(parse("${1:${2:${3:aa}}}"), { { placeholder = { { placeholder = { { placeholder = { { text = "aa" } }, tabstop = "3" } }, tabstop = "2" } }, tabstop = "1" } })
  eq(parse("${1:${2:${3}}}"),    { { placeholder = { { placeholder = { { tabstop = "3" } }, tabstop = "2" } }, tabstop = "1" } })
  eq(parse("${1:${3:aa}}"),      { { placeholder = { { placeholder = { { text = "aa" } }, tabstop = "3" } }, tabstop = "1" } })

  eq(parse("${1:${2:aa\\$bb\\}cc\\\\dd}}"), { { placeholder = { { placeholder = { { text = "aa$bb}cc\\dd" } }, tabstop = "2" } }, tabstop = "1" } })

  -- - Choice
  eq(parse("${1:${2|aa|}}"),    { { placeholder = { { choices = { "aa" }, tabstop = "2" } }, tabstop = "1" } })
  eq(parse("${1:${3|aa|}}"),    { { placeholder = { { choices = { "aa" }, tabstop = "3" } }, tabstop = "1" } })
  eq(parse("${1:${2|aa,bb|}}"), { { placeholder = { { choices = { "aa", "bb" }, tabstop = "2" } }, tabstop = "1" } })

  eq(parse("${1:${2|aa\\,bb\\|cc\\\\dd|}}"), { { placeholder = { { choices = { "aa,bb|cc\\dd" }, tabstop = "2" } }, tabstop = "1" } })
  eq(parse("${1:${2|aa,bb|}}"),              { { placeholder = { { choices = { "aa", "bb" }, tabstop = "2" } }, tabstop = "1" } })

  -- - Variable
  eq(parse("${1:$var}"),                     { { placeholder = { { var = "var" } }, tabstop = "1" } })
  eq(parse("${1:$var} xx"),                  { { placeholder = { { var = "var" } }, tabstop = "1" }, { text = " xx" } })
  eq(parse("${1:${var}}"),                   { { placeholder = { { var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var:aa}}"),                { { placeholder = { { placeholder = { { text = "aa" } }, var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var:$2}}"),                { { placeholder = { { placeholder = { { tabstop = "2" } }, var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var:aa$2bb}}"),            { { placeholder = { { placeholder = { { text = "aa" }, { tabstop = "2" }, { text = "bb" } }, var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var/.*/val/i}}"),          { { placeholder = { { transform = ".*/val/i", var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var/.*/${1}/i}}"),         { { placeholder = { { transform = ".*/${1}/i", var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var/.*/${1:/upcase}/i}}"), { { placeholder = { { transform = ".*/${1:/upcase}/i", var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var/.*/${1:/upcase}/i}}"), { { placeholder = { { transform = ".*/${1:/upcase}/i", var = "var" } }, tabstop = "1" } })

  eq(parse("${1:${var/.*/aa${1:else}/i}}"),     { { placeholder = { { transform = ".*/aa${1:else}/i", var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var/.*/aa${1:-else}/i}}"),    { { placeholder = { { transform = ".*/aa${1:-else}/i", var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var/.*/aa${1:+if}/i}}"),      { { placeholder = { { transform = ".*/aa${1:+if}/i", var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var/.*/aa${1:?if:else}/i}}"), { { placeholder = { { transform = ".*/aa${1:?if:else}/i", var = "var" } }, tabstop = "1" } })
  eq(parse("${1:${var/.*/aa${1:/upcase}/i}}"),  { { placeholder = { { transform = ".*/aa${1:/upcase}/i", var = "var" } }, tabstop = "1" } })

  eq(parse("${1:${var/.*/${1:?${}:aa}/i}}"),                { { placeholder = { { transform = ".*/${1:?${}:aa}/i", var = "var" } }, tabstop = "1" } })
  -- - Known limitation of needing to escape `}` in `if`
  eq(parse("${1:${var/regex/${1:?if\\}:else/i}/options}}"), { { placeholder = { { transform = "regex/${1:?if\\}:else/i}/options", var = "var" } }, tabstop = "1" } })

  -- Combined
  eq(parse("${1:aa${2:bb}cc}"),   { { placeholder = { { text = "aa" }, { placeholder = { { text = "bb" } }, tabstop = "2" }, { text = "cc" } }, tabstop = "1" } })
  eq(parse("${1:aa $var bb}"),    { { placeholder = { { text = "aa " }, { var = "var" }, { text = " bb" } }, tabstop = "1" } })
  eq(parse("${1:aa${var:xx}bb}"), { { placeholder = { { text = "aa" }, { placeholder = { { text = "xx" } }, var = "var" }, { text = "bb" } }, tabstop = "1" } })
end

--stylua: ignore
T['Parsing']['transform'] = function()
  -- All transform string should be parsed as is

  -- Should be allowed in variable nodes
  eq(parse('${var/xx(yy)/${0:aaa}/i}'),     { { transform = 'xx(yy)/${0:aaa}/i', var = 'var' } })
  eq(parse('${var/.*/${1}/i}'),             { { transform = '.*/${1}/i', var = 'var' } })
  eq(parse('${var/.*/$1/i}'),               { { transform = '.*/$1/i', var = 'var' } })
  eq(parse('${var/.*/$1/}'),                { { transform = '.*/$1/', var = 'var' } })
  eq(parse('${var/.*//}'),                  { { transform = '.*//', var = 'var' } })
  eq(parse('${var/.*/This-$1-encloses/i}'), { { transform = '.*/This-$1-encloses/i', var = 'var' } })
  eq(parse('${var/.*/aa${1:else}/i}'),      { { transform = '.*/aa${1:else}/i', var = 'var' } })
  eq(parse('${var/.*/aa${1:-else}/i}'),     { { transform = '.*/aa${1:-else}/i', var = 'var' } })
  eq(parse('${var/.*/aa${1:+if}/i}'),       { { transform = '.*/aa${1:+if}/i', var = 'var' } })
  eq(parse('${var/.*/aa${1:?if:else}/i}'),  { { transform = '.*/aa${1:?if:else}/i', var = 'var' } })
  eq(parse('${var/.*/aa${1:/upcase}/i}'),   { { transform = '.*/aa${1:/upcase}/i', var = 'var' } })

  -- Tricky transform strings
  eq(parse('${var///}'),                { { var = 'var', transform = '//' } })
  eq(parse('${var/.*/$\\//i}'),         { { var = 'var', transform = '.*/$\\//i' } })
  eq(parse('${var/.*/$${}/i}'),         { { var = 'var', transform = '.*/$${}/i' } }) -- `${}` directly after `$`
  eq(parse('${var/.*/${a/}/i}'),        { { var = 'var', transform = '.*/${a/}/i' } }) -- `/` inside a proper `${...}`
  eq(parse('${var/.*/$\\x/i}'),         { { var = 'var', transform = '.*/$\\x/i' } }) -- `/` after both dollar and slash
  eq(parse('${var/.*/\\$x/i}'),         { { var = 'var', transform = '.*/\\$x/i' } }) -- `/` after both dollar and slash
  eq(parse('${var/.*/\\${x/i}'),        { { var = 'var', transform = '.*/\\${x/i' } }) -- `/` after not proper `${`
  eq(parse('${var/.*/$\\{x/i}'),        { { var = 'var', transform = '.*/$\\{x/i' } }) -- `/` after not proper `${`
  eq(parse('${var/.*/a$/i}'),           { { var = 'var', transform = '.*/a$/i' } }) -- `/` directly after dollar
  eq(parse('${var/.*/${1:?${}:aa}/i}'), { { var = 'var', transform = '.*/${1:?${}:aa}/i' } }) -- `}` inside `format`

  -- Escaped (should ignore `\` before `$/\` and treat as text)
  eq(parse('${var/.*/\\/a\\/a\\//g}'),              { { transform = '.*/\\/a\\/a\\//g', var = 'var' } })
  -- - Known limitation of needing to escape `}` in `if` of `${1:?if:else}`
  eq(parse('${var/.*/${1:?if\\}:else/i}/options}'), { { transform = '.*/${1:?if\\}:else/i}/options', var = 'var' } })

  eq(parse('${var/.*/\\\\aa/g}'), { { transform = '.*/\\\\aa/g', var = 'var' } })
  eq(parse('${var/.*/\\$1aa/g}'), { { transform = '.*/\\$1aa/g', var = 'var' } })

  -- - Should handle escaped `/` in regex
  eq(parse('${var/\\/re\\/gex\\//aa/}'), { { transform = '\\/re\\/gex\\//aa/', var = 'var' } })

  -- Should be allowed in tabstop nodes
  eq(parse('${1/.*/${0:aaa}/i} xx'),      { { tabstop = '1', transform = '.*/${0:aaa}/i' }, { text = ' xx' } })
  eq(parse('${1/.*/${1}/i}'),             { { tabstop = '1', transform = '.*/${1}/i' } })
  eq(parse('${1/.*/$1/i}'),               { { tabstop = '1', transform = '.*/$1/i' } })
  eq(parse('${1/.*/$1/}'),                { { tabstop = '1', transform = '.*/$1/' } })
  eq(parse('${1/.*//}'),                  { { tabstop = '1', transform = '.*//' } })
  eq(parse('${1/.*/This-$1-encloses/i}'), { { tabstop = '1', transform = '.*/This-$1-encloses/i' } })
  eq(parse('${1/.*/aa${1:else}/i}'),      { { tabstop = '1', transform = '.*/aa${1:else}/i' } })
  eq(parse('${1/.*/aa${1:-else}/i}'),     { { tabstop = '1', transform = '.*/aa${1:-else}/i' } })
  eq(parse('${1/.*/aa${1:+if}/i}'),       { { tabstop = '1', transform = '.*/aa${1:+if}/i' } })
  eq(parse('${1/.*/aa${1:?if:else}/i}'),  { { tabstop = '1', transform = '.*/aa${1:?if:else}/i' } })
  eq(parse('${1/.*/aa${1:/upcase}/i}'),   { { tabstop = '1', transform = '.*/aa${1:/upcase}/i' } })
end

--stylua: ignore
T['Parsing']['tricky'] = function()
  eq(parse("${1:${aa:${1}}}"),                          { { placeholder = { { placeholder = { { tabstop = "1" } }, var = "aa" } }, tabstop = "1" } })
  eq(parse("${1:${aa:bb$1cc}}"),                        { { placeholder = { { placeholder = { { text = "bb" }, { tabstop = "1" }, { text = "cc" } }, var = "aa" } }, tabstop = "1" } })
  eq(parse("${TM_DIRECTORY/.*src[\\/](.*)/$1/}"),       { { transform = ".*src[\\/](.*)/$1/", var = "TM_DIRECTORY" } })
  eq(parse("${aa/(void$)|(.+)/${1:?-\treturn nil;}/}"), { { transform = "(void$)|(.+)/${1:?-\treturn nil;}/", var = "aa" } })
  eq(parse("${3:nest1 ${1:nest2 ${2:nest3}}} $3"),      { { placeholder = { { text = "nest1 " }, { placeholder = { { text = "nest2 " }, { placeholder = { { text = "nest3" } }, tabstop = "2" } }, tabstop = "1" } }, tabstop = "3" }, { text = " " }, { tabstop = "3" } })

  eq(parse("${1:prog}: ${2:$1.cc} - $2"),            { { placeholder = { { text = "prog" } }, tabstop = "1" }, { text = ": " }, { placeholder = { { tabstop = "1" }, { text = ".cc" } }, tabstop = "2" }, { text = " - " }, { tabstop = "2" } }) -- 'prog: prog.cc - prog.cc'
  eq(parse("${1:prog}: ${3:${2:$1.cc}.33} - $2 $3"), { { placeholder = { { text = "prog" } }, tabstop = "1" }, { text = ": " }, { placeholder = { { placeholder = { { tabstop = "1" }, { text = ".cc" } }, tabstop = "2" }, { text = ".33" } }, tabstop = "3" }, { text = " - " }, { tabstop = "2" }, { text = " " }, { tabstop = "3" } }) -- 'prog: prog.cc.33 - prog.cc prog.cc.33'
  eq(parse("${1:$2.one} <> ${2:$1.two}"),            { { placeholder = { { tabstop = "2" }, { text = ".one" } }, tabstop = "1" }, { text = " <> " }, { placeholder = { { tabstop = "1" }, { text = ".two" } }, tabstop = "2" } }) -- '.two.one.two.one <> .one.two.one.two'
end

return T
