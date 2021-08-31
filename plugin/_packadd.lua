local function packadd(plugin)
  vim.cmd(string.format([[packadd %s]], plugin))
end

-- More text objects ('wellle/targets.vim')
packadd('targets')

-- Generate all helptags later (find a better way for this)
vim.cmd([[autocmd VimEnter * ++once lua vim.defer_fn(function() vim.cmd('helptags ALL') end, 15)]])
