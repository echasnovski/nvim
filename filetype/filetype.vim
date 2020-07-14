" Function `ToggleWrap()` is defined in 'general/mappings.vim' which should be
" sourced before this one
au BufRead,BufNewFile *.md setlocal spell
au BufRead,BufNewFile *.md execute ToggleWrap()
au BufRead,BufNewFile *.txt setlocal spell
au BufRead,BufNewFile *.txt execute ToggleWrap()

