let python_highlight_all = 1

syntax on
colorscheme gruvbox

" Highlight punctuation
" Sources: https://stackoverflow.com/a/18943408 and https://superuser.com/a/205058
function! s:hi_base_syntax()
  " Highlight parenthesis
  syntax match parens /[(){}\[\]]/
  hi parens ctermfg=208
  " Highlight dots, commas, colons and semicolons
  syntax match punc /[\.,:;]/
  hi punc ctermfg=White cterm=bold
endfunction

autocmd VimEnter,BufRead,BufNewFile * call <SID>hi_base_syntax() 

" Use terminal's background (needed to use transparent background)
hi! Normal ctermbg=NONE guibg=NONE
hi! NonText ctermbg=NONE guibg=NONE guifg=NONE ctermfg=NONE

" Use custom colors for highlighting spelling information
hi SpellBad     guisp=#CC0000   gui=undercurl
hi SpellCap     guisp=#7070F0   gui=undercurl
hi SpellLocal   guisp=#70F0F0   gui=undercurl
hi SpellRare    guisp=#FFFFFF   gui=undercurl
