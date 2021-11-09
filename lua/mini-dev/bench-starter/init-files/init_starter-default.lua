vim.cmd([[set packpath=/tmp/nvim/site]])
vim.cmd([[packadd mini.nvim]])

require('mini.starter').setup()

-- Close Neovim just after fully opening it
vim.defer_fn(function()
  vim.cmd([[quit]])
end, 250)
