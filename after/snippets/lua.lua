--stylua: ignore
return {
  { prefix = 'T',      body = "T['$1']['$2'] = function()\n\t$0MiniTest.skip()\nend" },
  { prefix = 'TS',     body = "T['$1'] = new_set()$0" },
  { prefix = 'desc',   body = "describe('$1',function()\n\t$0\nend)" },
  { prefix = 'do',     body = 'do\n\t$0\nend' },
  { prefix = 'eif',    body = 'elseif $1 then\n\t$0\nend' },
  { prefix = 'f',      body = 'function($1)\n\t$0\nend' },
  { prefix = 'for',    body = 'for ${1:i}=${2:first},${3:last}${4:,step} do\n\t$0\nend' },
  { prefix = 'fori',   body = 'for ${1:idx},${2:val} in ipairs(${3:table_name}) do\n\t$0\nend' },
  { prefix = 'forp',   body = 'for ${1:name},${2:val} in pairs(${3:table_name}) do\n\t$0\nend' },
  { prefix = 'if',     body = 'if $1 then\n\t$0\nend' },
  { prefix = 'ife',    body = 'if $1 then\n\t$0\nelse\n\t-- TODO\nend' },
  { prefix = 'it',     body = "it('$1',function()\n\t$0\nend)" },
  { prefix = 'l',      body = 'local $1 = $0' },
  { prefix = 'pcall',  body = 'local ok,$1 = pcall($0)' },
  { prefix = 'repeat', body = 'repeat\n\t$1\nuntil $0' },
  { prefix = 'then',   body = 'then\n\t$0\nend' },
  { prefix = 'wh',     body = 'while $1 do\n\t$0\nend' },

  { prefix = { '  el', '\tel' }, body = 'else\n\t$0' },

  -- Remove some snippets from 'friendly-snippets'
  { prefix = { 'fu', 'f=', 'll', 'p', 'lpca' } },
}
