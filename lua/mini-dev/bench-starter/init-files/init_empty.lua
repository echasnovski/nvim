-- Close Neovim just after fully opening it
vim.defer_fn(function()
  vim.cmd([[quit]])
end, 250)
