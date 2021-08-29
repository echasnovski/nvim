local has_treesitter, treesitter = pcall(require, 'nvim-treesitter')
if not has_treesitter then
  return
end

require('nvim-treesitter.configs').setup({
  ensure_installed = {
    'bash',
    'css',
    'html',
    'json',
    'julia',
    'lua',
    'python',
    'r',
    'regex',
    'rst',
    'toml',
    'yaml',
  },
  highlight = { enable = true },
  textobjects = {
    -- Not having textobjects for arguments (`parameter.inner` and
    -- `parameter.outer`) because it currently doesn't always work intuitively.
    -- For example, in Python's list `[1, 2, 3]` elements are not recognized as
    -- arguments. 'Sideways.vim' plugin handles this better.
    enable = true,
    select = {
      enable = true,
      keymaps = {
        ['ac'] = '@class.outer',
        ['ic'] = '@class.inner',
        ['af'] = '@function.outer',
        ['if'] = '@function.inner',
        ['aF'] = '@call.outer',
        ['iF'] = '@call.inner',
        -- Used in R
        ['io'] = '@pipe',
      },
    },
    move = {
      enable = true,
      goto_next_start = {
        [']m'] = '@function.outer',
        [']]'] = '@class.outer',
      },
      goto_previous_start = {
        ['[m'] = '@function.outer',
        ['[['] = '@class.outer',
      },
    },
  },
  indent = { enable = false },
  playground = {
    enable = true,
    disable = {},
    updatetime = 25, -- Debounced time for highlighting nodes in the playground from source code
    persist_queries = false, -- Whether the query persists across vim sessions
  },
  -- incremental_selection = {
  --   enable = true,
  --   keymaps = {
  --     init_selection = 'gnn',
  --     node_incremental = 'grn',
  --     scope_incremental = 'grc',
  --     node_decremental = 'grm',
  --   },
  -- },
})
