" Function `ToggleWrap()` is defined in 'general/functions.vim'
au Filetype markdown,text,rmd setlocal spell
au Filetype markdown,text,rmd execute StartWrap()

" Set different desired line length
au Filetype python setlocal colorcolumn=89
au Filetype r,rmd setlocal colorcolumn=81

" Spelling in git commits
autocmd FileType gitcommit setlocal spell

" Filetype specific keybindings
au Filetype r,rmd inoremap <buffer> <M-i> <Space><-<Space>
au Filetype r,rmd inoremap <buffer> <M-k> <Space>%>%

au Filetype python inoremap <buffer> <M-i> <Space>=<Space>

