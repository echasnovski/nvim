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
