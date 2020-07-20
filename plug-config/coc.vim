let g:coc_global_extensions = [
    \ 'coc-highlight',
    \ 'coc-json',
    \ 'coc-python',
    \ 'coc-r-lsp',
    \ 'coc-snippets'
    \ ]

let g:coc_node_path = expand('~/.nvm/versions/node/v12.18.2/bin/node')

" Use <c-space> to trigger completion.
inoremap <silent><expr> <c-space> coc#refresh()

" Use `[g` and `]g` to navigate diagnostics
" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

" GoTo code navigation.
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use K to show documentation in preview window.
nnoremap <silent> K :call <SID>show_documentation()<CR>

function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  else
    call CocAction('doHover')
  endif
endfunction

" Highlight the symbol and its references when holding the cursor (except in
" '.csv' files, because they tend to be large which negatively affects
" performance)
let cursorHoldIgnore = ['csv']
autocmd CursorHold * if index(cursorHoldIgnore, &ft) < 0 | silent call CocActionAsync('highlight')

" Show all diagnostics
nnoremap <silent> <Leader>cd  :<C-u>CocList --auto-preview --normal diagnostics<cr>
" Search workspace symbols
nnoremap <silent> <Leader>cs  :<C-u>CocList --interactive symbols<cr>

" Use custom highlighting of Coc labels
hi CocErrorHighlight   guisp=#ff0000 gui=undercurl
hi CocWarningHighlight guisp=#ffa500 gui=undercurl
hi CocInfoHighlight    guisp=#ffff00 gui=undercurl
hi CocHintHighlight    guisp=#00ff00 gui=undercurl
