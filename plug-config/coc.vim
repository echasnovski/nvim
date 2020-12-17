let g:coc_global_extensions = [
  \ 'coc-highlight',
  \ 'coc-json',
  \ 'coc-python',
  \ 'coc-r-lsp',
  \ 'coc-snippets',
  \ 'coc-vimlsp'
  \ ]

let g:coc_node_path = expand('~/.nvm/versions/node/v14.15.2/bin/node')

" Map function and class text objects
" NOTE: Requires 'textDocument.documentSymbol' support from the language server.
xmap if <Plug>(coc-funcobj-i)
omap if <Plug>(coc-funcobj-i)
xmap af <Plug>(coc-funcobj-a)
omap af <Plug>(coc-funcobj-a)
xmap ic <Plug>(coc-classobj-i)
omap ic <Plug>(coc-classobj-i)
xmap ac <Plug>(coc-classobj-a)
omap ac <Plug>(coc-classobj-a)

" Use <c-space> to trigger completion.
inoremap <silent><expr> <c-space> coc#refresh()

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

" Use custom highlighting of Coc labels
hi CocErrorHighlight   guisp=#ff0000 gui=undercurl
hi CocWarningHighlight guisp=#ffa500 gui=undercurl
hi CocInfoHighlight    guisp=#ffff00 gui=undercurl
hi CocHintHighlight    guisp=#00ff00 gui=undercurl

" Snippets
"" Use <C-j> for both expand and jump (make expand higher priority.)
imap <C-j> <Plug>(coc-snippets-expand-jump)

"" Use <C-k> for jump to previous placeholder, it's default of coc.nvim
let g:coc_snippet_prev = '<c-k>'

" Enable coc.nvim in accompanying files
let g:coc_filetype_map = {
  \ 'rmarkdown': 'r',
  \ 'rmd': 'r',
  \ }
