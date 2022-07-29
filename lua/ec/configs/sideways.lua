-- Jump to to previous/next argument
vim.api.nvim_set_keymap('n', '[a', '<cmd>SidewaysJumpLeft<CR>', { silent = true })
vim.api.nvim_set_keymap('n', ']a', '<cmd>SidewaysJumpRight<CR>', { silent = true })
