-- Copy settings from 'r.vim'
vim.cmd([[runtime! ftplugin/r.lua]])

-- Manually copy some settings from 'markdown.vim' to avoid conflicts with
-- 'vim-markdown' extension
vim.cmd([[setlocal spell]])
vim.cmd([[setlocal wrap]])

EC.rmd_block = function()
  vim.fn.append(vim.fn.line('.'), '```')
  vim.fn.append(vim.fn.line('.'), '```{r }')
  vim.fn.cursor(vim.fn.line('.') + 1, 7)
  vim.cmd([[startinsert]])
end

vim.api.nvim_buf_set_keymap(0, 'n', '<M-b>', '<Cmd>lua EC.rmd_block()<CR>', { noremap = true })
