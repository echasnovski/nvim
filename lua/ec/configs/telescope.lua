require('telescope').setup({
  defaults = {
    sorting_strategy = 'ascending',
    layout_strategy = 'flex',
    layout_config = {
      prompt_position = 'top',
      vertical = { mirror = true },
      flex = { flip_columns = 140 },
    },
    -- Use custom sorter based on more intuitive (at least for me) fuzzy logic
    file_sorter = require('mini.fuzzy').get_telescope_sorter,
    generic_sorter = require('mini.fuzzy').get_telescope_sorter,
  },
  pickers = {
    buffers = { ignore_current_buffer = true },
    file_browser = { hidden = true },
    git_commits = {
      mappings = {
        -- Disable mappings to avoid accidental checkout
        i = {
          ['<cr>'] = false,
          ['<C-r>m'] = false,
          ['<C-r>s'] = false,
          ['<C-r>h'] = false,
        },
      },
    },
  },
})

-- Disable folds in normal mode inside window of picker results (not sure why
-- this happens: only telescope with `foldenabe` and `foldmethod=indent`
-- doesn't show this behavior)
vim.cmd([[au FileType TelescopeResults setlocal nofoldenable]])

-- Custom 'find files': using `git_files` in the first place in order to ignore
-- results from submodules. Original source:
-- https://github.com/nvim-telescope/telescope.nvim/issues/410#issuecomment-765656002
EC.telescope_project_files = function()
  local ok = pcall(require('telescope.builtin').git_files)
  if not ok then require('telescope.builtin').find_files({ follow = true, hidden = true }) end
end
