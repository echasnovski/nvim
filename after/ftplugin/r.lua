-- Show line after desired maximum text width
vim.opt_local.colorcolumn = '81'

-- Keybindings
vim.api.nvim_buf_set_keymap(0, 'i', '<M-i>', ' <- ', { noremap = true })
vim.api.nvim_buf_set_keymap(0, 'i', '<M-p>', ' %>%', { noremap = true })

-- Indentation
-- Don't align indentation of function args on new line with opening `(`
vim.g.r_indent_align_args = 0

-- Disable ESS comments
vim.g.r_indent_ess_comments = 0
vim.g.r_indent_ess_compatible = 0
