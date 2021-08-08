syntax on

" My personal "Mint" theme, derived from base16
" (https://github.com/chriskempson/base16)

" GUI color definitions, done using HSL color space
"" First four: dark scale with 'cool' in mind
"" Second four: light scale with 'mint' in mind
"" Colors are 4 pairs:
"" - Saturation is always 80.
"" - Hues for pairs are 30, 120, 200, and 300.
"" - Within pair colors are light (lightness 75) and dark (lightness 50).
let s:gui00        = "#1f252d"
let g:base16_gui00 = "#1f252d"
let s:gui01        = "#343e4b"
let g:base16_gui01 = "#343e4b"
let s:gui02        = "#495769"
let g:base16_gui02 = "#495769"
let s:gui03        = "#8797ab"
let g:base16_gui03 = "#8797ab"
let s:gui04        = "#c4cd98"
let g:base16_gui04 = "#c4cd98"
let s:gui05        = "#d2d9b0"
let g:base16_gui05 = "#d2d9b0"
let s:gui06        = "#e0e4c8"
let g:base16_gui06 = "#e0e4c8"
let s:gui07        = "#edf0e0"
let g:base16_gui07 = "#edf0e0"
let s:gui08        = "#f2bf8c"
let g:base16_gui08 = "#f2bf8c"
let s:gui09        = "#e68019"
let g:base16_gui09 = "#e68019"
let s:gui0A        = "#19e619"
let g:base16_gui0A = "#19e619"
let s:gui0B        = "#8cf28c"
let g:base16_gui0B = "#8cf28c"
let s:gui0C        = "#19a1e6"
let g:base16_gui0C = "#19a1e6"
let s:gui0D        = "#8cd0f2"
let g:base16_gui0D = "#8cd0f2"
let s:gui0E        = "#f28cf2"
let g:base16_gui0E = "#f28cf2"
let s:gui0F        = "#e619e5"
let g:base16_gui0F = "#e619e5"

"" Theme setup (using only gui elements, no term elements)
hi clear
syntax reset
let g:colors_name = "mint"

"" Highlighting function
"" Optional variables are attributes and guisp
function! g:Base16hi(group, guifg, guibg, ...)
  let l:attr = get(a:, 1, "")
  let l:guisp = get(a:, 2, "")

  if a:guifg != ""
    exec "hi " . a:group . " guifg=" . a:guifg
  endif
  if a:guibg != ""
    exec "hi " . a:group . " guibg=" . a:guibg
  endif
  if l:attr != ""
    exec "hi " . a:group . " gui=" . l:attr
  endif
  if l:guisp != ""
    exec "hi " . a:group . " guisp=" . l:guisp
  endif
endfunction

fun <sid>hi(group, guifg, guibg, attr, guisp)
  call g:Base16hi(a:group, a:guifg, a:guibg, a:attr, a:guisp)
endfun

"" Vim editor colors
call <sid>hi("Normal",        s:gui05, s:gui00, "", "")
call <sid>hi("Bold",          "", "", "bold", "")
call <sid>hi("Debug",         s:gui08, "", "", "")
call <sid>hi("Directory",     s:gui0D, "", "", "")
call <sid>hi("Error",         s:gui00, s:gui08, "", "")
call <sid>hi("ErrorMsg",      s:gui08, s:gui00, "", "")
call <sid>hi("Exception",     s:gui08, "", "", "")
call <sid>hi("FoldColumn",    s:gui0C, s:gui01, "", "")
call <sid>hi("Folded",        s:gui03, s:gui01, "", "")
call <sid>hi("IncSearch",     s:gui01, s:gui09, "none", "")
call <sid>hi("Italic",        "", "", "none", "")
call <sid>hi("Macro",         s:gui08, "", "", "")
""" Slight difference from base16, where `s:gui03` is used. This makes it
""" possible to comfortably this highlighting in comments.
call <sid>hi("MatchParen",    "", s:gui02, "", "")
call <sid>hi("ModeMsg",       s:gui0B, "", "", "")
call <sid>hi("MoreMsg",       s:gui0B, "", "", "")
call <sid>hi("Question",      s:gui0D, "", "", "")
call <sid>hi("Search",        s:gui01, s:gui0A,  "", "")
call <sid>hi("Substitute",    s:gui01, s:gui0A, "none", "")
call <sid>hi("SpecialKey",    s:gui03, "", "", "")
call <sid>hi("TooLong",       s:gui08, "", "", "")
call <sid>hi("Underlined",    s:gui08, "", "", "")
call <sid>hi("Visual",        "", s:gui02, "", "")
call <sid>hi("VisualNOS",     s:gui08, "", "", "")
call <sid>hi("WarningMsg",    s:gui08, "", "", "")
call <sid>hi("WildMenu",      s:gui08, s:gui0A, "", "")
call <sid>hi("Title",         s:gui0D, "", "none", "")
call <sid>hi("Conceal",       s:gui0D, s:gui00, "", "")
call <sid>hi("Cursor",        s:gui00, s:gui05, "", "")
call <sid>hi("NonText",       s:gui03, "", "", "")
call <sid>hi("LineNr",        s:gui03, s:gui01, "", "")
call <sid>hi("SignColumn",    s:gui03, s:gui01, "", "")
call <sid>hi("StatusLine",    s:gui04, s:gui02, "none", "")
call <sid>hi("StatusLineNC",  s:gui03, s:gui01, "none", "")
call <sid>hi("VertSplit",     s:gui02, s:gui02, "none", "")
call <sid>hi("ColorColumn",   "", s:gui01, "none", "")
call <sid>hi("CursorColumn",  "", s:gui01, "none", "")
call <sid>hi("CursorLine",    "", s:gui01, "none", "")
call <sid>hi("CursorLineNr",  s:gui04, s:gui01, "", "")
call <sid>hi("QuickFixLine",  "", s:gui01, "none", "")
call <sid>hi("PMenu",         s:gui05, s:gui01, "none", "")
call <sid>hi("PMenuSel",      s:gui01, s:gui05, "", "")
call <sid>hi("TabLine",       s:gui03, s:gui01, "none", "")
call <sid>hi("TabLineFill",   s:gui03, s:gui01, "none", "")
call <sid>hi("TabLineSel",    s:gui0B, s:gui01, "none", "")

"" Standard syntax highlighting
call <sid>hi("Boolean",      s:gui09, "", "", "")
call <sid>hi("Character",    s:gui08, "", "", "")
call <sid>hi("Comment",      s:gui03, "", "", "")
call <sid>hi("Conditional",  s:gui0E, "", "", "")
call <sid>hi("Constant",     s:gui09, "", "", "")
call <sid>hi("Define",       s:gui0E, "", "none", "")
call <sid>hi("Delimiter",    s:gui0F, "", "", "")
call <sid>hi("Float",        s:gui09, "", "", "")
call <sid>hi("Function",     s:gui0D, "", "", "")
call <sid>hi("Identifier",   s:gui08, "", "none", "")
call <sid>hi("Include",      s:gui0D, "", "", "")
call <sid>hi("Keyword",      s:gui0E, "", "", "")
call <sid>hi("Label",        s:gui0A, "", "", "")
call <sid>hi("Number",       s:gui09, "", "", "")
call <sid>hi("Operator",     s:gui05, "", "none", "")
call <sid>hi("PreProc",      s:gui0A, "", "", "")
call <sid>hi("Repeat",       s:gui0A, "", "", "")
call <sid>hi("Special",      s:gui0C, "", "", "")
call <sid>hi("SpecialChar",  s:gui0F, "", "", "")
call <sid>hi("Statement",    s:gui08, "", "", "")
call <sid>hi("StorageClass", s:gui0A, "", "", "")
call <sid>hi("String",       s:gui0B, "", "", "")
call <sid>hi("Structure",    s:gui0E, "", "", "")
call <sid>hi("Tag",          s:gui0A, "", "", "")
call <sid>hi("Todo",         s:gui0A, s:gui01, "", "")
call <sid>hi("Type",         s:gui0A, "", "none", "")
call <sid>hi("Typedef",      s:gui0A, "", "", "")

"" Diff highlighting
call <sid>hi("DiffAdd",      s:gui0B, s:gui01, "", "")
call <sid>hi("DiffChange",   s:gui03, s:gui01, "", "")
call <sid>hi("DiffDelete",   s:gui08, s:gui01, "", "")
call <sid>hi("DiffText",     s:gui0D, s:gui01, "", "")
call <sid>hi("DiffAdded",    s:gui0B, s:gui00, "", "")
call <sid>hi("DiffFile",     s:gui08, s:gui00, "", "")
call <sid>hi("DiffNewFile",  s:gui0B, s:gui00, "", "")
call <sid>hi("DiffLine",     s:gui0D, s:gui00, "", "")
call <sid>hi("DiffRemoved",  s:gui08, s:gui00, "", "")

"" Spelling highlighting
call <sid>hi("SpellBad",     "", "", "undercurl", s:gui08)
call <sid>hi("SpellLocal",   "", "", "undercurl", s:gui0C)
call <sid>hi("SpellCap",     "", "", "undercurl", s:gui0D)
call <sid>hi("SpellRare",    "", "", "undercurl", s:gui0E)

"" Remove functions
delf <sid>hi

"" Remove color variables
unlet s:gui00 s:gui01 s:gui02 s:gui03  s:gui04  s:gui05  s:gui06  s:gui07  s:gui08  s:gui09 s:gui0A  s:gui0B  s:gui0C  s:gui0D  s:gui0E  s:gui0F

" Highlight punctuation
"" General Vim buffers
"" Sources: https://stackoverflow.com/a/18943408 and https://superuser.com/a/205058
function! s:hi_base_syntax()
  " Highlight parenthesis
  syntax match parens /[(){}[\]]/
  " Highlight dots, commas, colons and semicolons with contrast color
  syntax match punc /[.,:;=]/
  if &background == "light"
    hi punc ctermfg=Black guifg=#000000 cterm=bold gui=bold
    hi parens ctermfg=Black guifg=#000000
  else
    hi punc ctermfg=White guifg=#FFFFFF cterm=bold gui=bold
    hi parens ctermfg=White guifg=#FFFFFF
  endif
endfunction

autocmd VimEnter,BufWinEnter * call <SID>hi_base_syntax()

"" Buffers with treesitter highlighting
if &background == "light"
  hi TSPunctBracket ctermfg=Black guifg=#000000 cterm=bold gui=bold
  hi TSOperator ctermfg=Black guifg=#000000 cterm=bold gui=bold
  hi TSPunctDelimiter ctermfg=Black guifg=#000000 cterm=bold gui=bold
  hi TSPunctSpecial ctermfg=Black guifg=#000000 cterm=bold gui=bold
else
  hi TSPunctBracket ctermfg=White guifg=#FFFFFF cterm=bold gui=bold
  hi TSOperator ctermfg=White guifg=#FFFFFF cterm=bold gui=bold
  hi TSPunctDelimiter ctermfg=White guifg=#FFFFFF cterm=bold gui=bold
  hi TSPunctSpecial ctermfg=White guifg=#FFFFFF cterm=bold gui=bold
endif
