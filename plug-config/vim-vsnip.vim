" let g:vsnip_snippet_dir = expand('$HOME/.config/nvim/snippets/vim-vsnip')

" " Keybinding for expand or jump
" imap <expr> <C-l> vsnip#available(1) ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'
" smap <expr> <C-l> vsnip#available(1) ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'

" imap <expr> <C-h> vsnip#jumpable(-1) ? '<Plug>(vsnip-jump-prev)' : '<C-h>'
" smap <expr> <C-h> vsnip#jumpable(-1) ? '<Plug>(vsnip-jump-prev)' : '<C-h>'
