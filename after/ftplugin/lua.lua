vim.api.nvim_buf_set_keymap(0, 'i', '<M-i>', ' = ', { noremap = true })

-- Use custom comment leaders to allow both nested variants (`--` and `----`)
-- and "docgen" variant (`---`).
-- Using `defer_fn` to ensure this is executed after all possible autocommands.
vim.opt.comments = ':---,:--'

vim.b.minisurround_config = {
  custom_surroundings = {
    s = {
      input = { find = '%[%[.-%]%]', extract = '^(..).*(..)$' },
      output = { left = '[[', right = ']]' },
    },
  },
}
