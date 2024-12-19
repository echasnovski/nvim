--stylua: ignore
return {
  { prefix = 'do',     body = 'do\n\t$0\nend' },
  { prefix = 'eif',    body = 'elseif $1 then\n\t$0\nend' },
  { prefix = 'f',      body = 'function($1)\n\t$0\nend' },
  { prefix = 'ff',     body = 'function($1) $0 end' },
  { prefix = 'for',    body = 'for ${1:i} = ${2:1}, ${3:to} do\n\t$0\nend' },
  { prefix = 'fori',   body = 'for ${1:i}, ${2:v} in ipairs($3) do\n\t$0\nend' },
  { prefix = 'forp',   body = 'for ${1:k}, ${2:v} in pairs($3) do\n\t$0\nend' },
  { prefix = 'if',     body = 'if $1 then\n\t$0\nend' },
  { prefix = 'ife',    body = 'if $1 then\n\t$0\nelse\n\t-- TODO\nend' },
  { prefix = 'l',      body = 'local $1 = $0' },
  { prefix = 'pcall',  body = 'local ok, $1 = pcall($0)' },
  { prefix = 'repeat', body = 'repeat\n\t$1\nuntil $0' },
  { prefix = 'then',   body = 'then\n\t$0\nend' },
  { prefix = 'while',  body = 'while $1 do\n\t$0\nend' },

  { prefix = 'api',   body = 'vim.api.nvim_' },
  { prefix = 'map',   body = 'vim.tbl_map($2, $1)' },
  { prefix = 'bench', body = '_G.${1:durations} = {}\nlocal ${2:start_time} = vim.loop.hrtime()\ntable.insert($1, 0.000001 * (vim.loop.hrtime() - $2))' },

  { prefix = 'desc',   body = "describe('$1',function()\n\t$0\nend)" },
  { prefix = 'it',     body = "it('$1',function()\n\t$0\nend)" },

  { prefix = { '  el', '\tel' }, body = 'else\n\t$0' },

  -- Remove some snippets from 'friendly-snippets'
  { prefix = { 'fu', 'f=', 'll', 'p', 'lpca' } },
}
