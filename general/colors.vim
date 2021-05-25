let python_highlight_all = 1

syntax on

" General theme
let g:gruvbox_contrast_dark='medium'
colorscheme gruvbox
" colorscheme one
" let ayucolor = 'mirage'
" colorscheme ayu

" " Remove modifications (bold, etc.) from highliting group while keeping color
" function! s:copy_only_color(from, to)
"   " Source: https://vi.stackexchange.com/a/20757
"   let col = synIDattr(synIDtrans(hlID(a:from)), 'fg#')

"   execute 'silent hi ' . a:to . ' guifg=' . col
" endfunction

" call s:copy_only_color('Function', 'Function')

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
    hi punc ctermfg=Black guifg=#000000 cterm=bold gui=bold
  else
    hi punc ctermfg=White guifg=#FFFFFF cterm=bold gui=bold
  endif
endfunction

autocmd VimEnter,BufWinEnter * call <SID>hi_base_syntax()

"" Buffers with treesitter highlighting
if has("nvim-0.5")
  hi TSPunctBracket ctermfg=208 guifg=#FF8700
  if &background == "light"
    hi TSOperator ctermfg=Black guifg=#000000 cterm=bold gui=bold
    hi TSPunctDelimiter ctermfg=Black guifg=#000000 cterm=bold gui=bold
    hi TSPunctSpecial ctermfg=Black guifg=#000000 cterm=bold gui=bold
  else
    hi TSOperator ctermfg=White guifg=#FFFFFF cterm=bold gui=bold
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
hi ColorColumn ctermbg=grey guibg=#555555

" Current word
hi CurrentWord term=underline cterm=underline gui=underline

" Trailing whitespace
highlight TrailWhitespace ctermbg=red ctermfg=white guibg=#FB4934
