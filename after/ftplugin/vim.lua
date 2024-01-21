vim.bo.shiftwidth = 2

-- Make sure that '"' is reserved for comments and won't get 'auto-paired'
vim.keymap.set('i', '"', '"', { buffer = 0 })
