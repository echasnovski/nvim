-- Define 'argument' text object to replace one from 'targets.vim'
-- This is better as it more intuitively handles multiline function calls and
-- presence of comma in string
vim.api.nvim_set_keymap('o', 'aa', '<Plug>SidewaysArgumentTextobjA', { silent = true })
vim.api.nvim_set_keymap('x', 'aa', '<Plug>SidewaysArgumentTextobjA', { silent = true })
vim.api.nvim_set_keymap('o', 'ia', '<Plug>SidewaysArgumentTextobjI', { silent = true })
vim.api.nvim_set_keymap('x', 'ia', '<Plug>SidewaysArgumentTextobjI', { silent = true })

-- Jump to to previous/next argument
vim.api.nvim_set_keymap('n', '[a', '<cmd>SidewaysJumpLeft<CR>', { silent = true })
vim.api.nvim_set_keymap('n', ']a', '<cmd>SidewaysJumpRight<CR>', { silent = true })
