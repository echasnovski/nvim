" Custom minimal 'highlight word under cursor' plugin (mainly to be used in
" Vim, not in Neovim). For more information see 'lua/mini/cursorword.lua'.

" Setup behavior
augroup MiniCursorword
  au!

  " NOTE: if this updates too frequently, use `CursorHold`
  autocmd CursorMoved * call MiniCursorwordHighlight()
  " Force remove highlighing when entering Insert or Terminal mode
  autocmd InsertEnter,TermEnter,QuitPre * call MiniCursorwordUnhighlight()
augroup END

" Highlighting
hi MiniCursorword term=underline cterm=underline gui=underline

" Indicator of whether to actually do highlighting
let s:highlight_curword = 1

" Functions
"" A modified version of https://stackoverflow.com/a/25233145
"" Using `matchadd()` instead of a simpler `:match` to tweak priority of
"" 'current word' highlighting: with `:match` it is higher than for
"" `incsearch` which is not convenient.
function! MiniCursorwordHighlight()
  if s:highlight_curword
    " Remove current match so that only current word will be highlighted
    " (otherwise they will add up as a result of `matchadd` calls)
    call MiniCursorwordUnhighlight()

    " Highlight word only if cursor is on 'keyword' character
    if getline(".")[col(".")-1] =~ '\k'
      let l:curword = escape(expand('<cword>'), '\/')
      " Highlight with 'very nomagic' pattern match ('\V') and for pattern to
      " match whole word ('\<' and '\>')
      let l:current_pattern = '\V\<' . l:curword . '\>'
      " Store match identifier per *window*
      let w:_curword_lastmatch = matchadd('MiniCursorword', l:current_pattern, -1)
    endif
  endif
endfunction

function MiniCursorwordUnhighlight()
  if exists('w:_curword_lastmatch')
    call matchdelete(w:_curword_lastmatch)
    unlet w:_curword_lastmatch
  endif
endfunction

function MiniCursorwordToggle()
  if s:highlight_curword
    let s:highlight_curword = 0
    " Remove all current highlights
    call MiniCursorwordUnhighlight()
  else
    let s:highlight_curword = 1
    " Add current highlights
    call MiniCursorwordHighlight()
  endif
endfunction
