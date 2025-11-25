-- Add project root as full path to runtime path (in order to be able to
-- `require()` modules
vim.cmd([[let &rtp.=','.getcwd()]])

-- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.hues'
-- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
vim.cmd('set rtp+=deps/mini.nvim')

-- Ensure persistent color scheme (matters after new default in Neovim 0.10)
vim.o.background = 'dark'
require('mini.hues').setup({ background = '#11262d', foreground = '#c0c8cc' })

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- Set up 'mini.test'
  require('mini.test').setup()
end

-- - Make screenshot tests more robust across Neovim versions
vim.o.statusline = '%<%f %l,%c%V'

if vim.fn.has('nvim-0.11') == 1 then
  vim.api.nvim_set_hl(0, 'ComplMatchIns', {})
  vim.api.nvim_set_hl(0, 'PmenuMatch', { link = 'Pmenu' })
  vim.api.nvim_set_hl(0, 'PmenuMatchSel', { link = 'PmenuSel' })
end
