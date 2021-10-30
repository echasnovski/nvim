-- Use custom comment leaders to allow both nested variants (`--` and `----`)
-- and "docgen" variant (`---`).
-- Using `defer_fn` to ensure this is executed after all possible autocommands.
vim.defer_fn(function()
  vim.opt.comments = ':----,:---,:--'
end, 0)
