-- MIT License Copyright (c) 2021 Evgeni Chasnovski

---@brief [[
--- |mini.nvim| is a collection of minimal, independent, and fast Lua modules
--- dedicated to improve Neovim experience.
---
--- # Plugin colorscheme
---
--- This plugin comes with an official colorscheme named `minischeme`. This is
--- a |MiniBase16| theme created with faster version of the following Lua code:
--- `require('mini.base16').setup({palette = palette, name = 'minischeme', use_cterm = true})`
--- where `palette` is:
--- - For dark 'background': `require('mini.base16').mini_palette('#112641', '#e2e98f', 75)`
--- - For light 'background': `require('mini.base16').mini_palette('#e2e5ca', '#002a83', 75)`
---
--- Activate it as a regular |colorscheme|.
---@brief ]]
---@tag mini.nvim

vim.notify([[Do not `require('mini')` directly. Setup every module separately.]])

return {}
