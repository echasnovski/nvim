-- Show line after desired maximum text width
vim.cmd('setlocal colorcolumn=81')

-- Keybindings
vim.keymap.set('i', '<M-i>', ' <- ', { buffer = 0 })
vim.keymap.set('i', '<M-p>', ' |>', { buffer = 0 })

-- Indentation
-- Don't align indentation of function args on new line with opening `(`
vim.g.r_indent_align_args = 0

-- Disable ESS comments
vim.g.r_indent_ess_comments = 0
vim.g.r_indent_ess_compatible = 0

-- Use specific comment headers
vim.bo.comments = [[:#',:###,:##,:#]]
