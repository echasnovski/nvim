-- Make vim-rooter behave like `autochdir` if it can't find project root
vim.g.rooter_change_directory_for_non_project_files = 'current'
vim.g.rooter_patterns = { 'Makefile', '.git', '*.Rproj', 'pyproject.toml' }

-- Change directory without giving message
vim.g.rooter_silent_chdir = 1
