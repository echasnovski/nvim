" Make vim-rooter behave like `autochdir` if it can't find project root
let g:rooter_change_directory_for_non_project_files = 'current'
let g:rooter_patterns = ['Rakefile', '.git/', '*.Rproj', 'pyproject.toml']
