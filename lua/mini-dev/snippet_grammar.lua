-- Reference from LSP specification version 3.18:
--
-- any         ::= tabstop | placeholder | choice | variable | text
-- tabstop     ::= '$' int | '${' int '}'
-- placeholder ::= '${' int ':' any '}'
-- choice      ::= '${' int '|' choicetext (',' choicetext)* '|}'
-- variable    ::= '$' var | '${' var }'
--                 | '${' var ':' any '}'
--                 | '${' var '/' regex '/' (format | formattext)* '/' options '}'
-- format      ::= '$' int | '${' int '}'
--                 | '${' int ':' ('/upcase' | '/downcase' | '/capitalize') '}'
--                 | '${' int ':+' ifOnly '}'
--                 | '${' int ':?' if ':' else '}'
--                 | '${' int ':-' else '}' | '${' int ':' else '}'
-- regex       ::= Regular Expression value (ctor-string)
-- options     ::= Regular Expression option (ctor-options)
-- var         ::= [_a-zA-Z] [_a-zA-Z0-9]*
-- int         ::= [0-9]+
-- text        ::= ([^$}\] | '\$' | '\}' | '\\')*
-- choicetext  ::= ([^,|\] | '\,' | '\|' | '\\')*
-- formattext  ::= ([^$/\] | '\$' | '\/' | '\\')*
-- ifOnly      ::= text
-- if          ::= ([^:\] | '\:' | '\\')*
-- else        ::= text

_G.parse = function(snippet)
  -- State tracking table: `name` - state name, `depth_arrays` - node array for
  -- each depth of nested placeholders.
  local state = { name = 'text', depth_arrays = { { { text = { '' } } } } }

  for i = 0, vim.fn.strchars(snippet) - 1 do
    -- Infer helperd data
    state.depth = #state.depth_arrays
    state.arr = state.depth_arrays[state.depth]
    local processor, node = H.processors[state.name], state.arr[#state.arr]
    processor(vim.fn.strcharpart(snippet, i, 1), state, node)
  end

  H.verify(state)
  return H.post_process(state.depth_arrays[1])
end

H = {}

H.verify = function(state)
  if state.name == 'dollar' then H.error('"$" should be followed by tabstop id or variable name') end
  if state.name == 'dollar_lbrace' then H.error('"${" should be closed with "}"') end
  if state.name == 'choice' then H.error('Tabstop with choices should be closed with "|}"') end
  if vim.startswith(state.name, 'transform_') then
    H.error('Variable transform should contain 3 "/" outside of `${...}` and be closed with "}"')
  end
  if #state.depth_arrays > 1 then H.error('Placeholder should be closed with "}"') end
end

H.post_process = function(node_arr)
  local traverse
  traverse = function(arr)
    for _, node in ipairs(arr) do
      -- Clean up trailing `\`
      if node.after_slash and node.text ~= nil then table.insert(node.text, '\\') end
      node.after_slash = nil

      -- Convert arrays to strings
      if node.text then node.text = table.concat(node.text, '') end
      if node.tabstop then node.tabstop = table.concat(node.tabstop, '') end
      if node.choices then node.choices = vim.tbl_map(table.concat, node.choices) end
      if node.var then node.var = table.concat(node.var, '') end
      if node.transform then node.transform = table.concat(node.transform, '') end

      -- Ignore choices in `0` tabstop
      if node.tabstop == '0' then node.choices = nil end

      -- Recursively post-process placeholders
      if node.placeholder ~= nil then node.placeholder = traverse(node.placeholder) end
    end
    arr = vim.tbl_filter(function(n) return n.text == nil or (n.text ~= nil and n.text:len() > 0) end, arr)
    if #arr == 0 then return { { text = '' } } end
    return arr
  end

  -- TODO:
  -- - Should ensure presence of final tabstop (`$0`). Append at end if none.

  return traverse(node_arr)
end

H.rise_depth = function(state)
  -- Set the deepest array as a placeholder of the last node of previous layer.
  -- This can happen only after `}` which does not close current node.
  local depth = #state.depth_arrays
  local cur_layer, prev_layer = state.depth_arrays[depth], state.depth_arrays[depth - 1]
  prev_layer[#prev_layer].placeholder = vim.deepcopy(cur_layer)
  table.insert(prev_layer, { text = {} })
  state.depth_arrays[state.depth] = nil
end

-- Each entry processes single character based on the character (`c`),
-- state (`s`), and current node (`n`).
H.processors = {}

--stylua: ignore
H.processors.text = function(c, s, n)
  if n.after_slash then
    -- Escape `$}\` and allow unescaped '\\' to preceed any character
    if not (c == '$' or c == '}' or c == '\\') then table.insert(n.text, '\\') end
    n.text[#n.text + 1], n.after_slash = c, nil
    return
  end
  if c == '}' and s.depth > 1 then H.rise_depth(s); return end
  if c == '\\' then n.after_slash = true; return end
  if c == '$' then s.name = 'dollar'; return end
  table.insert(n.text, c)
end

--stylua: ignore
H.processors.dollar = function(c, s, n)
  if c == '}' and s.depth > 1 then H.rise_depth(s); return end
  -- Detect `$1` and `$var` as a new node
  local no_brace_node = c:find('^[0-9]$') and 'tabstop' or (c:find('^[_a-zA-Z]$') and 'var' or '')
  if no_brace_node ~= '' then
    table.insert(s.arr, { [no_brace_node] = { c } })
    s.name = 'dollar_' .. no_brace_node
    return
  end
  if c == '{' then s.name = 'dollar_lbrace'; return end
  -- Allow unescaped `$`
  n.text[#n.text + 1], n.text[#n.text + 2], s.name = '$', c, 'text'
end

--stylua: ignore
H.processors.dollar_tabstop = function(c, s, n)
  if c == '}' and s.depth > 1 then H.rise_depth(s); return end
  if c:find('^[0-9]$') then table.insert(n.tabstop, c); return end
  table.insert(s.arr, { text = {} })
  if c == '$' then s.name = 'dollar'; return end
  s.arr[#s.arr].text[1], s.name = c, 'text'
end

--stylua: ignore
H.processors.dollar_var = function(c, s, n)
  if c == '}' and s.depth > 1 then H.rise_depth(s); return end
  if c:find('^[_a-zA-Z0-9]$') then table.insert(n.var, c); return end
  table.insert(s.arr, { text = {} })
  if c == '$' then s.name = 'dollar'; return end
  s.arr[#s.arr].text[1], s.name = c, 'text'
end

--stylua: ignore
H.processors.dollar_lbrace = function(c, s, n)
  if n.tabstop == nil and n.var == nil then
    if c:find('^[0-9]$') then table.insert(s.arr, { tabstop = { c } }) return end
    if c:find('^[_a-zA-Z]$') then table.insert(s.arr, { var = { c } }); return end
    H.error('`${` should be followed by digit (for tabstop) or letter/underscore (for variable), not ' .. vim.inspect(c))
  end
  if c == '}' then table.insert(s.arr, { text = {} }); s.name = 'text'; return end
  if c == ':' then table.insert(s.depth_arrays, { { text = { '' } } }); s.name = 'text'; return end
  if n.tabstop ~= nil then
    if c:find('^[0-9]$') then table.insert(n.tabstop, c); return end
    if c == '|' then n.choices = { {} }; s.name = 'choice'; return end
    H.error('Tabstop id should be followed by "}", ":" or "|", not ' .. vim.inspect(c))
  end
  if c:find('^[_a-zA-Z0-9]$') then table.insert(n.var, c); return end
  if c == '/' then n.transform = {}; s.name = 'transform_regex'; return end
  H.error('Variable name should be followed by "}", ":" or "/", not ' .. vim.inspect(c))
end

--stylua: ignore
H.processors.choice = function(c, s, n)
  if n.wait_rbrace then
    if c ~= '}' then H.error('Choice node should be closed with `|}`') end
    n.wait_rbrace = nil;
    table.insert(s.arr, { text = {} })
    s.name = 'text'
    return
  end

  local cur = n.choices[#n.choices]
  if n.after_slash then
    -- Escape `$}\` and allow unescaped '\\' to preceed any character
    if not (c == ',' or c == '|' or c == '\\') then table.insert(cur, '\\') end
    cur[#cur + 1], n.after_slash = c, nil
    return
  end
  if c == '\\' then n.after_slash = true; return end
  if c == ',' then table.insert(n.choices, {}); return end
  if c == '|' then n.wait_rbrace = true; return end
  table.insert(cur, c)
end

-- Ignore all the transform data and wait until proper `}`
--stylua: ignore
H.processors.transform_regex = function(c, s, n)
  table.insert(n.transform, c)
  if n.after_slash then n.after_slash = nil; return end
  if c == '\\' then n.after_slash = true; return end
  if c == '/' then s.name = 'transform_format'; return end
end

--stylua: ignore
H.processors.transform_format = function(c, s, n)
  table.insert(n.transform, c)
  if n.after_slash then n.after_slash = nil; return end
  if n.after_dollar then
    n.after_dollar = nil
    if c == '{' and not n.inside_braces then n.inside_braces = true; return end
  end
  if c == '\\' then n.after_slash = true; return end
  if c == '$' then n.after_dollar = true; return end

  -- If inside `${}`, wait until the first (unescaped) `}`. Techincally, this
  -- breaks LSP spec in `${1:?if:else}` (`if` doesn't have to escape `}`).
  -- Accept this as known limitation and ask to escape `}` in such cases.
  if c == '}' and n.inside_braces then n.inside_braces = nil; return end

  if c == '/' and not n.inside_braces then s.name = 'transform_options'; return end
end

--stylua: ignore
H.processors.transform_options = function(c, s, n)
  table.insert(n.transform, c)
  if n.after_slash then n.after_slash = nil; return end
  if c == '\\' then n.after_slash = true; return end
  if c == '}' then
    n.transform[#n.transform] = nil; table.insert(s.arr, { text = {} }); s.name = 'text'; return
  end
end

H.error = function(msg) error('(mini.snippets) ' .. msg, 0) end

-- Tests ======================================================================
vim.keymap.set('n', '<Leader>ps', function()
  local line = vim.api.nvim_get_current_line():gsub('%-%-.*$', '')
  local indent, snippet = line:match('^%s*'), line:match('^%s*(.*),%s*$')
  local code = 'local ok, res = pcall(_G.parse, ' .. snippet .. '); return res'
  local parsed_snippet = loadstring(code)()
  local lines = vim.split(vim.inspect(parsed_snippet, { newline = ' ', indent = '' }), '\n')
  vim.fn.append('.', vim.tbl_map(function(l) return indent .. l end, lines))
end, { desc = 'Parse current line snippet test case' })

-- Many examples of passing and failing snippet bodies are taken from VS Code
-- tests. NOTE: not all handling there is according to LSP spec; prefer spec.
_G.corpus_pass = {
  text = {
    -- Common
    'aa',
    'ыыы ффф',
    '',

    -- Simple
    [[\]],

    -- Escaped (should ignore `\` before `$}\`)
    [[aa\$bb\}cc\\dd]],
    [[aa\$]],
    [[aa\${}]],
    '{',
    [[\}]],
    [[aa \\\$]], -- [[I need \$]]
    [[\${1|aa,bb|}]], -- a text '${1|aa,bb|}'

    -- Not spec: allow unescaped backslash
    [[aa\bb]],

    -- Not spec: allow unescaped $ when can not be mistaken for tabstop or var
    'aa$ bb',
    'aa$$bb',

    -- Not spec: allow unescaped `}` in top-level text
    '{ aa }',
    '{\n\taa\n}',
    'aa{1}',
    'aa{1:bb}',
    'aa{1:{2:cc}}',
    'aa{var:{1:bb}}',
  },

  tabstop = {
    -- Common
    'aa $1',
    'aa $1 bb',
    'aa$1bb',
    'hello_$1_bb',
    'ыыы $1 ффф',

    'aa ${1}',
    'aa${1}bb',
    'hello_${1}_bb',
    'ыыы ${1} ффф',

    'aa $0',
    'aa $1 $0',

    [[aa\\$bb]], -- `$bb` should be variable

    -- Only tabstop(s)
    '$1',
    '${1}',

    -- Adjacent tabstops
    'aa$1$2',
    'aa$1$0',
    '$1$2',
    '${1}${2}',
    '$1${2}',
    '${1}$2',

    -- Can be any numbering in any order
    'aa $2',
    'aa $3 $10',
    'aa $3 $2 $0',

    -- Tricky
    '$1$a',
    '$1$-',
  },

  placeholder = {
    -- Common
    'aa ${1:b}',
    'aa ${1:}',
    'aa ${1:ыыы}',
    '${1:}',

    '${1:aa} ${2:bb}',

    'aa ${0:b}',
    'aa ${0:}',
    'aa ${0:ыыы}',
    '${0:}',

    -- Escaped (should ignore `\` before `$}\` and treat as text)
    [[xx ${1:aa\$bb\}cc\\dd}]],
    [[xx ${1:aa\$}]],
    [[xx ${1:aa\\}]],
    '${1:aa:bb}', -- should allow unescaped `:`

    -- Not spec: allow unescaped backslash
    [[xx ${1:aa\bb}]],

    -- Different placeholders (should be later resolved somehow)
    'aa${1:xx}_${1:yy}',
    'aa${1:}_$1_${1:yy}', -- should allow empty string as placeholder

    -- Nested
    -- - Tabstop
    'xx ${1:$2}',
    'xx ${1:$2} yy',
    'xx ${1:${2}}',
    'xx ${1:${3}}',

    -- - Placeholder
    'xx ${1:${2:aa}}',
    'xx ${1:${2:${3:aa}}}',
    'xx ${1:${2:${3}}}',
    'xx ${1:${3:aa}}',

    [[xx ${1:${2:aa\$bb\}cc\\dd}}]],

    -- - Choice
    'xx ${1:${2|aa|}}',
    'xx ${1:${3|aa|}}',
    'xx ${1:${2|aa,bb|}}',

    [[xx ${1:${2|aa\,bb\|cc\\dd|}}]],
    'xx ${1:${2|aa,bb|}}',

    -- - Variable
    '${1:$var}',
    '${1:$var} xx',
    '${1:${var}}',
    '${1:${var:aa}}',
    '${1:${var:$2}}',
    '${1:${var:aa$2bb}}',
    '${1:${var/.*/val/i}}',
    '${1:${var/.*/${1}/i}}',
    '${1:${var/.*/${1:/upcase}/i}}',
    '${1:${var/.*/${1:/upcase}/i}}',

    '${1:${var/.*/aa${1:else}/i}}',
    '${1:${var/.*/aa${1:-else}/i}}',
    '${1:${var/.*/aa${1:+if}/i}}',
    '${1:${var/.*/aa${1:?if:else}/i}}',
    '${1:${var/.*/aa${1:/upcase}/i}}',

    '${1:${var/.*/${1:?${}:aa}/i}}',
    [[${1:${var/regex/${1:?if\}:else/i}/options}}]], -- known limitation of needing to escape `}` in `if`

    -- Combined
    '${1:aa${2:bb}cc}', -- should resolve to 'aabbcc'
    '${1:aa $var bb}', -- should resolve to 'aa ! bb' (if `var` is set to "!")
    '${1:aa${var:xx}bb}', -- should resolve to 'aaxxbb' (if `var` is not set)
  },

  choice = {
    'xx ${1|aa|}',
    'xx ${2|aa|}',
    'xx ${1|aa,bb|}',

    -- Escape (should ignore `\` before `,|\` and treat as text)
    [[${1|\,,},$,\|,\\|}]], -- choices are `,`, `}`, `$`, `|`, `\`
    [[xx ${1|aa\,bb|}]], -- single choice is `aa,bb`

    -- Empty choices
    'xx ${1|,|}',
    'xx ${1|aa,|}',
    'xx ${1|,aa|}',
    'xx ${1|aa,,bb|}',
    'xx ${1|aa,,,bb|}', -- two empty strings as choices should be allowed

    -- Not spec: allow unescaped backslash
    [[xx ${1|aa\bb|}]],

    -- Should be ignored in `$0`
    '${0|aa|}',
    '${0|aa,bb|}',
  },

  var = {
    '$aa',
    '$a_b',
    '$_a',
    '$a1',
    '${aa}',
    '${a_b}',
    '${_a}',
    '${a1}',

    [[aa\\$bb]], -- `$bb` should be variable

    -- Should recognize only [_a-zA-Z] [_a-zA-Z0-9]*
    '$aa-bb', -- `$aa` variable and `-bb` text
    '$aa bb', -- `$aa` variable and ` bb` text
    'aa$bb cc',
    'aa${bb} cc',

    -- Fallback in case variable is not defined
    '${var:}',
    '${var:aa}',
    '${var:aa:bb}', -- should allow unescaped `:`
    '${var:$1}',
    '${var:${1}}',
    '${var:${1:aa}}',
    '${var:${1|aa|}}',
    '${var:${var2:aa}}',

    -- Transform (should ignore all data and just register variable name)
    '${var/.*/${0:aaa}/i}',
    '${var/.*/${1}/i}',
    '${var/.*/$1/i}',
    '${var/.*/$1/}',
    '${var/.*//}',
    '${var/.*/This-$1-encloses/i}',
    '${var/.*/aa${1:else}/i}',
    '${var/.*/aa${1:-else}/i}',
    '${var/.*/aa${1:+if}/i}',
    '${var/.*/aa${1:?if:else}/i}',
    '${var/.*/aa${1:/upcase}/i}',

    -- - Tricky transform strings
    '${var///}',
    [[${var/.*/$\//i}]],
    '${var/.*/$${}/i}', -- `${}` directly after `$`
    '${var/.*/${a/}/i}', -- `/` inside a proper `${...}`
    [[${var/.*/$\x/i}]], -- `/` after both dollar and slash
    [[${var/.*/\$x/i}]], -- `/` after both dollar and slash
    [[${var/.*/\${x/i}]], -- `/` after not proper `${`
    [[${var/.*/$\{x/i}]], -- `/` after not proper `${`
    '${var/.*/a$/i}', -- `/` directlyafter dollar
    '${var/.*/${1:?${}:aa}/i}', -- `}` inside `format`

    -- Escaped (should ignore `\` before `$/\` and treat as text)
    [[${var/regex/\/a\/a\//g}]],

    -- - Known limitation of needing to escape `}` in `if` of `${1:?if:else}`
    [[${var/regex/${1:?if\}:else/i}/options}]],

    [[${var/regex/\\aa/g}]],
    [[${var/regex/\$1aa/g}]],

    [[${var/\/re\/gex\//aa/}]], -- should handle escaped `/` in regex
  },

  combined = {
    'aa_${bb}_cc_$0',

    -- Different pure tabstop and with placeholder
    'aa${1:xx}_$1',
    'aa${1:xx}_${1}',
    'aa$1_${1:xx}',
    'aa${1}_${1:xx}',
  },

  tricky = {
    '${1:${aa:${1}}}',
    '${1:${aa:bb$1cc}}',
    '${TM_DIRECTORY/.*src[\\/](.*)/$1/}',
    '${aa/(void$)|(.+)/${1:?-\treturn nil;}/}',
    '${3:nest1 ${1:nest2 ${2:nest3}}} $3',
    '${1:prog}: ${2:$1.cc} - $2', -- 'prog: prog.cc - prog.cc'
    '${1:prog}: ${3:${2:$1.cc}.33} - $2 $3', -- 'prog: prog.cc.33 - prog.cc prog.cc.33'
    '${1:$2.one} <> ${2:$1.two}', -- '.two.one.two.one <> .one.two.one.two'
  },
}

_G.corpus_fail = {
  text = {},
  tabstop = {
    -- Should be closed with `}`
    '${1:',
    '${1',

    -- Should be followed by either `:` or `}`
    '${1 }',
    '${1?}',
    '${1 |}',
  },
  placeholder = {
    -- Should be closed with `}`
    '${1:a',
    '${1:a bb',
    '${1:${2:a',

    -- Nested nodes should error according to their rules
    '${1:${2?}}',
    '${1:${2?',
    '${1:${2|a}}',
    '${1:${a }}',
    '${1:${-}}',
  },
  choice = {
    -- Should be closed with `|}`
    '${1|a',
    '${1|a|',
    '${1|a}',
    [[${1|a\|}]],
    '${1|a,b',
    '${1|a,b}',
    '${1|a,b|',

    '${1|a,b|,c}', -- should escape `|`
  },
  var = {
    -- Can not start with digit
    '${1a}',

    -- Should be followed by either `:`, `/`, or `}`
    '${a }',
    '${a?}',
    '${a :}',
    '${a?:}',

    -- Transform
    [[${var/regex/format}]], -- not enough `/`
    [[${var/regex\/format/options}]],
    [[${var/.*/$\/i}]],
    '${var/regex/${/}options}', -- not enough `/` outside of `${...}`

    -- - Known limitation of unescaped `}` in `if` of `${1:?if:else}`
    '${var/regex/${1:?if}:else/i}/options}',
  },
  other = {
    -- Should start with [_0-9a-zA-Z]
    '${-',
    '${ ',
    'aa$',
  },
}
