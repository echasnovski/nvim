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

-- TODO:
-- - Parsing should ensure presence of the final tabstop (`$0`). Append at the
--   end if missing.

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

    -- Not spec, but seems reasonable to allow unescaped backslash
    [[aa\bb]],

    -- Not spec, but seems reasonable to allow unescaped `}` in top-level text
    '{ aa }',
    [[{\n\taa\n}]],
    'aa{1}',
    'aa{1:bb}',
    'aa{1:{2:cc}}',
    'aa{var:{1:bb}}',
  },

  tabstop = {
    -- Common
    'hello $1',
    'hello $1 world',
    'hello_$1_world',
    'ыыы $1 ффф',

    'hello ${1}',
    'hello ${1} world',
    'hello_${1}_world',
    'ыыы ${1} ффф',

    'hello $0',
    'hello $1 $0',

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
  },

  placeholder = {
    -- Common
    'aa ${1:b}',
    'aa ${1:}',
    'aa ${1:ыыы}',
    '${1:}',

    'aa ${0:b}',
    'aa ${0:}',
    'aa ${0:ыыы}',
    '${0:}',

    -- Escaped (should ignore `\` before `$}\` and treat as text)
    [[xx ${1:aa\$bb\}cc\\dd}]],
    [[xx ${1:aa\$}]],
    [[xx ${1:aa\$}]],
    '${1:aa:bb}', -- should allow unescaped `:`

    -- Not spec, but seems reasonable to allow unescaped backslash
    [[xx ${1:aa\bb}]],

    -- Different placeholders (should be later resolved somehow)
    'aa${1:xx}_${1:yy}',

    -- Nested
    -- - Tabstop
    'xx ${1:$2}',
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
    '${1:${var}}',
    --
    -- TODO

    -- Combined
    '${1:aa${2:bb}cc}', -- should resolve to 'aabbcc'
    '${1:aa $var bb}', -- should resolve to 'aa ! bb' (if `var` is set to "!")
  },

  choice = {
    'xx ${1|aa|}',
    'xx ${2|aa|}',
    'xx ${1|aa,bb|}',

    -- Escape (should ignore `\` before `,|\` and treat as text)
    [[${1|\,,},$,\|,\\|}]], -- choices are `,`, `}`, `$`, `|`, `\`
    [[xx {1|aa\,bb|}]], -- single choice is `aa,bb`

    -- Empty choices
    'xx ${1|,|}',
    'xx ${1|aa,|}',
    'xx ${1|,aa|}',
    'xx {1|aa,,bb|}',
    'xx {1|aa,,,bb|}', -- two empty strings as choices should be allowed

    -- Not spec, but seems reasonable to allow unescaped backslash
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

    -- Regex
    '${var/.*/${0:aaa}/i}',
    '${var/.*/${1}/i}',
    '${var/.*/$1/i}',
    '${var/.*/This-$1-encloses/i}',
    '${var/.*/complex${1:else}/i}',
    '${var/.*/complex${1:-else}/i}',
    '${var/.*/complex${1:+if}/i}',
    '${var/.*/complex${1:?if:else}/i}',
    '${var/.*/complex${1:/upcase}/i}',

    -- Escaped (should ignore `\` before `$/\` and treat as text)
    [[${var/regex/\/aa/g}]],
    [[${var/regex/a\/a/g}]],
    [[${var/regex/aa\//g}]],

    [[${var/regex/\\aa/g}]],
    [[${var/regex/\$1aa/g}]],

    [[${var/reg\/ex/aa/}]], -- should handle escaped `/` in regex
    [[${var/regex\//aa/}]],
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
    '${1/(void$)|(.+)/${1:?-\treturn nil;}/}',
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
    '${1 ',
    '${1',
    'aa ${1 bb',
  },
  placeholder = {
    -- Should be closed with `}`
    '${1:a',
    'xx ${1:a bb',

    -- Nested placeholders should error according to their parsing rules
    'xx ${1:${2:a',
    'xx ${1:${2:a$b}}',
    'xx ${1:${2:a$b}}',
  },
  choice = {
    -- Should be closed with `|}`
    '${1|a',
    '${1|a|',
    '${1|a}',
    '${1|a,b',
    '${1|a,b}',
    '${1|a,b|',

    '${1|a,b|,c}', -- should escape `|`
  },
  var = {
    '${aa }', -- should contain only allowed characters
    '${1a }', -- can not start with digit

    -- Format
    [[${var/regex/format}]], -- not enough `/`
    [[${var/regex\/format/options}]], -- not enough `/`
  },
}