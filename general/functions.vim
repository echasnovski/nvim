" Split functional sequence into lines ending with pattern.
" This is designed to be mostly used to format R's pipe (`%>%`) sequences.
" Prerequisite for proper usage:
" - All patterns on single line are indicators of future line splits.
" - All sequence elements should be typed with `()`.
function SplitFunSeq(pattern, match_paren)
  call cursor(line('.'), 1)
  let did_move = SplitPattern(a:pattern)

  while did_move
    if a:match_paren
      execute "normal! %"
    endif

    let did_move = SplitPattern(a:pattern)
  endwhile
endfunction

function SplitPattern(pattern)
  let cur_line = line('.')
  let [patt_line, patt_col] = searchpos(a:pattern, "cenz")

  if cur_line != patt_line
    " If pattern is not on the current line, do nothing
    return v:false
  else
    " If pattern is on the current line, make a split just after pattern
    " ending by hitting `<CR>`. This usually gets nice automatic indentation.
    call cursor(patt_line, patt_col)
    execute "normal! a\<CR>"
    return v:true
  endif
endfunction

" Resize so that first defined colorcolumn is displayed at the last column of
" the window. If no `colorcolumn` option is set, resize to maximum from
" `textwidth` option and 60 (just some appropriate number).
function ResizeToColorColumn()
  " Compute number of columns in the resulting width
  if &colorcolumn == ""
    let l:width = max([&textwidth, 60])
    echo "No colorcolumn. Resizing to `max([&textwidth, 60])`"
  else
    let l:cc = split(&colorcolumn, ",")[0]

    if l:cc[0] =~# '[\-\+]'
      " If textwidth is zero, do nothing (as there is no color column)
      if &textwidth == 0
        echo "No resizing because `textwidth` is 0 and `colorcolumn` is relative"
        return
      endif
      let l:width = &textwidth + str2nr(l:cc)
    else
      let l:width = l:cc
    endif
  endif

  " Get width of the 'non-editable' side area (gutter)
  let l:gutterwidth = GetGutterWidth()

  " Resize
  let l:win_width = l:width + l:gutterwidth
  execute "vertical resize " . l:win_width
endfunction

function GetGutterWidth()
  " Compute number of 'editable' columns in current window
  "" Store current options
  let l:virtedit = &virtualedit
  let l:curpos = getpos('.')

  "" Move cursor to the last visible column
  set virtualedit=all
  norm! g$
  let l:last_col = virtcol('.')

  "" Restore options
  let &virtualedit=l:virtedit
  call setpos(".", l:curpos)

  " Compute result
  return winwidth(0) - l:last_col
endfunction

" Create scratch buffer
function Scratch()
  enew
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
endfunction

" Add multiple consecutive comment leader
function AddMultipleCommentLeader()
  if &commentstring == '' | return | endif
  " Make raw comment leader from 'commentstring' option
  let l:comment = split(&commentstring, '%s')

  " Don't do anything if 'commentstring' is like '/*%s*/' (as in 'json')
  if len(l:comment) > 1
    return
  endif

  " Get comment leader
  let l:comment = l:comment[0]
  " Strip all possible whitespace
  let l:comment = substitute(l:comment, '\s', '', 'g')
  " Escape possible 'dangerous' characters
  let l:comment = escape(l:comment, '"')

  " Remove possible 'single' comment leader and some of its forced multiples
  " (as in 'r' filetype)
  let l:removed_comment = l:comment
  for i in [1, 2, 3, 4, 5]
    exe 'setlocal comments-=:'  . l:removed_comment
    let l:removed_comment = l:removed_comment . l:comment
  endfor

  " Add possibility of 'multiple' comment leader
  exe 'setlocal comments+=n:' . l:comment
endfunction
