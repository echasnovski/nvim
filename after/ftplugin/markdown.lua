-- Using `vim.cmd` instead of `vim.wo` because it is yet more reliable
vim.cmd('setlocal spell')
vim.cmd('setlocal wrap')

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
