-- Setup
-- stylua: ignore start
require('gitsigns').setup({
  signs = {
    add = {text = '▍'},
    change = {text = '▍'},
    delete = {text = '▁'},
    topdelete = {text = '▔'},
    changedelete = {text = '█'},
  },
  keymaps = {
    -- Default keymap options
    noremap = true,
    silent = true,

    -- Text objects
    ['o ih'] = ':<C-U>lua require"gitsigns".select_hunk()<CR>',
    ['x ih'] = ':<C-U>lua require"gitsigns".select_hunk()<CR>',
  },
  watch_gitdir = { interval = 1000 },
})
-- stylua: ignore end
