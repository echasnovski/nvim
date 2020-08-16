" Define 'argument' text object to replace one from 'targets.vim'
" This is better as it more intuitively handles multiline function calls and
" presence of comma in string
omap aa <Plug>SidewaysArgumentTextobjA
xmap aa <Plug>SidewaysArgumentTextobjA
omap ia <Plug>SidewaysArgumentTextobjI
xmap ia <Plug>SidewaysArgumentTextobjI

" Jump to to previous/next argument
nmap [a :SidewaysJumpLeft<CR>
nmap ]a :SidewaysJumpRight<CR>
