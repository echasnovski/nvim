local gitsigns = require('gitsigns')
gitsigns.setup({
  signs = {
    add = { text = '▒' },
    change = { text = '▒' },
    changedelete = { text = '▓' },
    delete = { text = '▓' },
    topdelete = { text = '▓' },
    untracked = { text = '░' },
  },
  preview_config = { border = 'double' },
  diff_opts = { linematch = 60 },
})

vim.keymap.set('n', '[h', gitsigns.prev_hunk, { desc = 'Backward hunk' })
vim.keymap.set('n', ']h', gitsigns.next_hunk, { desc = 'Forward hunk' })
