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
if has("nvim-0.5.0")
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
highlight ColorColumn ctermbg=grey guibg=#555555

" Statusline colors
hi StatusLineModeNormal   guibg=#928374 guifg=#1D2021 gui=bold
hi StatusLineModeInsert   guibg=#458588 guifg=#1D2021 gui=bold
hi StatusLineModeVisual   guibg=#b8bb26 guifg=#1D2021 gui=bold
hi StatusLineModeReplace  guibg=#fb4934 guifg=#1D2021 gui=bold
hi StatusLineModeCommand  guibg=#d79921 guifg=#1D2021 gui=bold
hi StatusLineModeOther    guibg=#689D6A guifg=#1D2021 gui=bold

hi StatusLineActive       guibg=#3C3836 guifg=#EBDBB2
hi StatusLineInactive     guibg=#3C3836 guifg=#928374
hi StatusLineLineCol      guibg=#928374 guifg=#1D2021 gui=bold
hi StatusLineGit          guibg=#504945 guifg=#EBDBB2
hi StatusLineFileinfo     guibg=#504945 guifg=#EBDBB2
hi StatusLineFilename     guibg=#504945 guifg=#EBDBB2

hi StatusLineDiagn        guibg=#3C3836
hi StatusLineDiagnError   guibg=#3C3836 guifg=#CC3333
hi StatusLineDiagnWarning guibg=#3C3836 guifg=#FFCC33
hi StatusLineDiagnInfo    guibg=#3C3836 guifg=#33CC33
hi StatusLineDiagnHint    guibg=#3C3836 guifg=#99CCCC
