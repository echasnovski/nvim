-- Copy settings from 'r.vim'
vim.cmd('runtime! ftplugin/r.lua')

-- Manually copy some settings from 'markdown.lua'
vim.cmd([[setlocal spell]])
vim.cmd([[setlocal wrap]])
