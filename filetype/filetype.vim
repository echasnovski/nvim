" Function `ToggleWrap()` is defined in 'general/mappings.vim' which should be
" sourced before this one
au BufRead,BufNewFile *.md,*.txt,*.Rmd setlocal spell
au BufRead,BufNewFile *.md,*.txt,*.Rmd execute ToggleWrap()

" Set different desired line length
au BufRead,BufNewFile *.py setlocal colorcolumn=89
au BufRead,BufNewFile *.R,*.Rmd setlocal colorcolumn=81

