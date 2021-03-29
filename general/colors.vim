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
highlight ColorColumn ctermbg=grey guibg=#555555

" Statusline colors (from Gruvbox bright palette)
hi StatusLineModeNormal  guibg=#BDAE93 guifg=#1D2021 gui=bold
hi StatusLineModeInsert  guibg=#83A598 guifg=#1D2021 gui=bold
hi StatusLineModeVisual  guibg=#B8BB26 guifg=#1D2021 gui=bold
hi StatusLineModeReplace guibg=#FB4934 guifg=#1D2021 gui=bold
hi StatusLineModeCommand guibg=#FABD2F guifg=#1D2021 gui=bold
hi StatusLineModeOther   guibg=#8EC07C guifg=#1D2021 gui=bold

hi link StatusLineInactive StatusLineNC
hi link StatusLineDevinfo  StatusLine
hi link StatusLineFilename StatusLineNC
hi link StatusLineFileinfo StatusLine

" Btline (custom tabline) colors (from Gruvbox palette)
hi BtlineCurrent         guibg=#7C6F64 guifg=#EBDBB2 gui=bold
hi BtlineActive          guibg=#3C3836 guifg=#EBDBB2 gui=bold
hi link BtlineHidden StatusLineNC

hi BtlineModifiedCurrent guibg=#458588 guifg=#EBDBB2 gui=bold
hi BtlineModifiedActive  guibg=#076678 guifg=#EBDBB2 gui=bold
hi BtlineModifiedHidden  guibg=#076678 guifg=#BDAE93

hi BtlineFill NONE
