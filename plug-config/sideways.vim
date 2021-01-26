" Define 'argument' text object to replace one from 'targets.vim'
" This is better as it more intuitively handles multiline function calls and
" presence of comma in string
omap <silent> aa <Plug>SidewaysArgumentTextobjA
xmap <silent> aa <Plug>SidewaysArgumentTextobjA
omap <silent> ia <Plug>SidewaysArgumentTextobjI
xmap <silent> ia <Plug>SidewaysArgumentTextobjI

" Jump to to previous/next argument
nnoremap <silent> [a :SidewaysJumpLeft<CR>
nnoremap <silent> ]a :SidewaysJumpRight<CR>
