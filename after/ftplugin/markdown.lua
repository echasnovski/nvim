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
local has_mini_ai, mini_ai = pcall(require, 'mini.ai')
if has_mini_ai then
  vim.b.miniai_config = {
    custom_textobjects = {
      ['*'] = mini_ai.gen_spec.pair('*', '*', { type = 'greedy' }),
      ['_'] = mini_ai.gen_spec.pair('_', '_', { type = 'greedy' }),
    },
  }
end

local has_mini_surround, mini_surround = pcall(require, 'mini.surround')
if has_mini_surround then
  vim.b.minisurround_config = {
    custom_surroundings = {
      -- Bold
      B = { input = { '%*%*().-()%*%*' }, output = { left = '**', right = '**' } },

      -- Link
      L = {
        input = { '%[().-()%]%(.-%)' },
        output = function()
          local link = mini_surround.user_input('Link: ')
          return { left = '[', right = '](' .. link .. ')' }
        end,
      },
    },
  }
end
