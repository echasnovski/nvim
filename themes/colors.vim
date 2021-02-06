let python_highlight_all = 1

syntax on

" General theme
let g:gruvbox_contrast_dark='medium'
colorscheme gruvbox
" let ayucolor = 'mirage'
" colorscheme ayu

" Highlight punctuation
"" General Vim buffers
"" Sources: https://stackoverflow.com/a/18943408 and https://superuser.com/a/205058
function! s:hi_base_syntax()
  " Highlight parenthesis
  syntax match parens /[(){}[\]]/
  hi parens ctermfg=208 guifg=#FF8700
  " Highlight dots, commas, colons and semicolons with contrast color
  syntax match punc /[.,:;=]/
  if &background == "light"
    hi punc ctermfg=White guifg=#000000 cterm=bold gui=bold
  else
    hi punc ctermfg=White guifg=#FFFFFF cterm=bold gui=bold
  endif
endfunction

autocmd VimEnter,BufWinEnter * call <SID>hi_base_syntax()

"" Buffers with treesitter highlighting
if has("nvim-0.5.0")
  hi TSPunctBracket ctermfg=208 guifg=#FF8700
  if &background == "light"
    hi TSPunctDelimiter ctermfg=White guifg=#000000 cterm=bold gui=bold
    hi TSPunctSpecial ctermfg=White guifg=#000000 cterm=bold gui=bold
  else
    hi TSPunctDelimiter ctermfg=White guifg=#FFFFFF cterm=bold gui=bold
    hi TSPunctSpecial ctermfg=White guifg=#FFFFFF cterm=bold gui=bold
  endif
endif

" " Use terminal's background (needed if transparent background is used)
" hi! Normal ctermbg=NONE guibg=NONE
" hi! NonText ctermbg=NONE guibg=NONE guifg=NONE ctermfg=NONE

" Use custom colors for highlighting spelling information
hi SpellBad     guisp=#CC0000   gui=undercurl
hi SpellCap     guisp=#7070F0   gui=undercurl
hi SpellLocal   guisp=#70F0F0   gui=undercurl
hi SpellRare    guisp=#FFFFFF   gui=undercurl

" Use custom color for highlighting 'maximum width' column
highlight ColorColumn ctermbg=grey guibg=#555555

