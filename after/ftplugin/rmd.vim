" Copy settings from 'r.vim'
runtime! ftplugin/r.vim

" Manually copy some settings from 'markdown.vim' to avoid conflicts with
" 'vim-markdown' extension
setlocal spell " Enable spelling
execute StartWrap()

function RmdBlock()
  call append(line("."), "```")
  call append(line("."), "```{r }")
  call cursor(line(".")+1, 7)
  startinsert
endfunction

nnoremap <buffer> <M-b> :call RmdBlock()<CR>
