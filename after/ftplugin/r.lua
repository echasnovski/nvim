-- Show line after desired maximum text width
vim.opt_local.colorcolumn = '81'

-- Keybindings
vim.api.nvim_buf_set_keymap(0, 'i', '<M-i>', ' <- ', { noremap = true })
vim.api.nvim_buf_set_keymap(0, 'i', '<M-p>', ' %>%', { noremap = true })

-- Indentation
---- Don't align indentation of function args on new line with opening `(`
vim.g.r_indent_align_args = 0

---- Disable ESS comments
vim.g.r_indent_ess_comments = 0
vim.g.r_indent_ess_compatible = 0

-- Section insert
EC.section_r = function()
  -- Insert section template
  local section_template = string.format('# %s', string.rep('-', 73))
  vim.fn.append(vim.fn.line('.'), section_template)

  -- Enable Replace mode in appropriate place
  vim.fn.cursor(vim.fn.line('.') + 1, 3)
  vim.cmd([[startreplace]])
end

vim.api.nvim_buf_set_keymap(0, 'n', '<M-s>', '<Cmd>lua EC.section_r()<CR>', { noremap = true })
---- Using `<Esc>:` and not `<Cmd>` because latter doesn't start replace mode
vim.api.nvim_buf_set_keymap(0, 'i', '<M-s>', '<Esc>:lua EC.section_r()<CR>', { noremap = true })
