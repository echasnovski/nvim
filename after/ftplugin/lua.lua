-- Use custom comment leaders to allow both nested variants (`--` and `----`)
-- and "docgen" variant (`---`).
-- Using `defer_fn` to ensure this is executed after all possible autocommands.
vim.defer_fn(function() vim.opt.comments = ':---,:--' end, 0)

vim.b.minisurround_config = {
  custom_surroundings = {
    s = {
      input = { find = '%[%[.-%]%]', extract = '^(..).*(..)$' },
      output = { left = '[[', right = ']]' },
    },
  },
}
