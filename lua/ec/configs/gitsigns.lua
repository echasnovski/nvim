-- Setup
require('gitsigns').setup({
  signs = {
    add = { text = '▒' },
    change = { text = '▒' },
    changedelete = { text = '▓' },
    delete = { text = '▓' },
    topdelete = { text = '▓' },
    untracked = { text = '░' },
  },
  preview_config = { border = 'double' },
  watch_gitdir = { interval = 1000 },
})
