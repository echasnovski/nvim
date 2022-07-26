-- Using `vim.cmd` instead of `opt_local` because it is currently more stable
-- See https://github.com/neovim/neovim/issues/14670
vim.cmd([[setlocal spell]])
vim.cmd([[setlocal wrap]])

-- Use custom folding based on treesitter parsing
vim.cmd([[setlocal foldmethod=expr]])
vim.cmd([[setlocal foldexpr=v:lua.EC.markdown_foldexpr()]])
vim.cmd([[normal! zx]]) -- Update folds

-- NOTE: Alternative solution for markdown folding is to use builtin syntax
-- folding for only headings. Use this and disable custom expression folding.
-- This might be a bit slow on large files.
-- vim.g.markdown_folding = 1

-- Customize 'mini.nvim'
vim.b.miniai_config = {
  custom_textobjects = {
    ['*'] = { { '%*().-()%*', '%*%*().-()%*%*' } },
    ['_'] = { { '_().-()_', '__().-()__' } },
  },
}
