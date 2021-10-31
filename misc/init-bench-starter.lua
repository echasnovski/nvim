-- -- mini.nvim
-- vim.cmd([[packadd mini]])
-- vim.cmd([[packadd nvim-web-devicons]])
--
-- local starter = require('mini-dev.starter')
-- starter.setup({
--   items = {
--     {
--       { action = [[enew]], name = 'Edit file', section = 'Actions' },
--       { action = [[quit]], name = 'Quit', section = 'Actions' },
--     },
--     starter.section_mru_files(10, false, true),
--     starter.section_mru_files(10, true, true),
--   },
--   content_hooks = {
--     starter.get_hook_item_bullets(),
--     starter.get_hook_indexing('all', { 'Actions' }),
--     starter.get_hook_padding(3, 2),
--   },
-- })

-- -- alpha-nvim
-- vim.cmd([[packadd alpha-nvim]])
-- vim.cmd([[packadd nvim-web-devicons]])
-- require('alpha').setup(require('alpha.themes.startify').opts)

-- vim-startify
vim.cmd([[packadd vim-startify]])
vim.cmd([[packadd nvim-web-devicons]])
