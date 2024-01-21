--stylua: ignore
local ensure_installed = {
  'bash',  'c',    'cpp',      'css',             'html',   'javascript', 'json',
  'julia', 'lua',  'markdown', 'markdown_inline', 'python', 'r',          'regex',
  'rst',   'rust', 'toml',     'tsx',             'yaml',   'vim',        'vimdoc',
}

require('nvim-treesitter.configs').setup({
  ensure_installed = ensure_installed,
  highlight = { enable = true },
  incremental_selection = { enable = false },
  textobjects = { enable = false },
  indent = { enable = false },
})

-- Disable injections in 'lua' language. In Neovim<0.9 it is
-- `vim.treesitter.query.set_query()`; in Neovim>=0.9 it is
-- `vim.treesitter.query.set()`.
local ts_query = require('vim.treesitter.query')
local ts_query_set = ts_query.set or ts_query.set_query
ts_query_set('lua', 'injections', '')
