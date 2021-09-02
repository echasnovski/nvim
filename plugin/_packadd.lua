local function packadd(plugin)
  vim.cmd(string.format([[packadd %s]], plugin))
end

-- More text objects
packadd('targets')

if vim.fn.exists('vscode') ~= 1 then
  -- Fuzzy finder
  packadd('telescope')
end

-- Generate all helptags later (find a better way for this)
vim.cmd([[autocmd VimEnter * ++once lua vim.defer_fn(function() vim.cmd('helptags ALL') end, 15)]])
