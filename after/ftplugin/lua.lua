vim.api.nvim_buf_set_keymap(0, 'i', '<M-i>', ' = ', { noremap = true })

-- Use custom comment leaders to allow both nested variants (`--` and `----`)
-- and "docgen" variant (`---`).
vim.cmd([[setlocal comments=:---,:--]])

-- Customize 'mini.nvim'
vim.b.minisurround_config = {
  custom_surroundings = {
    s = { input = { '%[%[().-()%]%]' }, output = { left = '[[', right = ']]' } },
  },
}

vim.b.miniai_config = {
  custom_textobjects = {
    s = { '%[%[().-()%]%]' },
  },
}
