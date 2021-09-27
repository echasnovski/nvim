vim.bo.shiftwidth = 2

-- Make sure that '"' is reserved for comments and won't get 'auto-paired'
vim.api.nvim_buf_set_keymap(0, 'i', [["]], [["]], { noremap = true })
