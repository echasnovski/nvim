vim.cmd([[set packpath=/tmp/nvim/site]])
vim.cmd([[packadd mini.nvim]])

local starter = require('mini.starter')
starter.setup({
  evaluate_single = true,
  items = {
    {
      { name = 'Edit file', action = [[enew]], section = 'Actions' },
      { name = 'Quit', action = [[quit]], section = 'Actions' },
    },
    starter.sections.recent_files(10, false),
    starter.sections.recent_files(10, true),
  },
  content_hooks = {
    starter.gen_hook.adding_bullet(),
    starter.gen_hook.indexing('all', { 'Actions' }),
    starter.gen_hook.padding(3, 2),
  },
})

-- Close Neovim just after fully opening it
vim.defer_fn(function()
  vim.cmd([[quit]])
end, 250)
