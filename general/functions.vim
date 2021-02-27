" Wrap-unwrap text
function ToggleWrap()
  if &wrap
    echo "Wrap OFF"
    setlocal nowrap
    silent! nunmap <buffer> <Up>
    silent! nunmap <buffer> <Down>
    silent! nunmap <buffer> <Home>
    silent! nunmap <buffer> <End>
    silent! iunmap <buffer> <Up>
    silent! iunmap <buffer> <Down>
    silent! iunmap <buffer> <Home>
    silent! iunmap <buffer> <End>
  else
    echo "Wrap ON"
    setlocal wrap linebreak nolist
    setlocal display+=lastline
    noremap  <buffer> <silent> <Up>   gk
    noremap  <buffer> <silent> <Down> gj
    noremap  <buffer> <silent> <Home> g<Home>
    noremap  <buffer> <silent> <End>  g<End>
    inoremap <buffer> <silent> <Up>   <C-o>gk
    inoremap <buffer> <silent> <Down> <C-o>gj
    inoremap <buffer> <silent> <Home> <C-o>g<Home>
    inoremap <buffer> <silent> <End>  <C-o>g<End>
  endif
endfunction

function StartWrap()
  setlocal wrap linebreak nolist
  setlocal display+=lastline
  noremap  <buffer> <silent> <Up>   gk
  noremap  <buffer> <silent> <Down> gj
  noremap  <buffer> <silent> <Home> g<Home>
  noremap  <buffer> <silent> <End>  g<End>
  inoremap <buffer> <silent> <Up>   <C-o>gk
  inoremap <buffer> <silent> <Down> <C-o>gj
  inoremap <buffer> <silent> <Home> <C-o>g<Home>
  inoremap <buffer> <silent> <End>  <C-o>g<End>
endfunction

" Cycle trough git-gutter hunks in a file
function! GitGutterNextHunkCycle()
  let line = line('.')
  silent! GitGutterNextHunk
  if line('.') == line
    " Go to first line and then to next hunk
    1
    GitGutterNextHunk
  endif
endfunction

function! GitGutterPrevHunkCycle()
  let line = line('.')
  silent! GitGutterPrevHunk
  if line('.') == line
    " Got to last line and then to next hunk
    $
    GitGutterPrevHunk
  endif
endfunction

" Show Neoterm's active REPL, i.e. in which command will be executed when one
" of `TREPLSend*` will be used
function ShowActiveNeotermREPL()
  if exists("g:neoterm.repl") && exists("g:neoterm.repl.instance_id")
    let l:msg = "Active REPL neoterm id: " . g:neoterm.repl.instance_id
  elseif g:neoterm.last_id != 0
    let l:msg = "Active REPL neoterm id: " . g:neoterm.last_id
  else
    let l:msg = "No active REPL"
  endif

  echo l:msg
endfunction

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

" Zoom into a pane, making it full screen (in a tab)
" This function is useful when working with multiple panes but temporarily
" needing to zoom into one to see more of the code from that buffer.
" Triggering the function again from the zoomed in tab brings it back to its
" original pane location
" Source: https://github.com/nicknisi/dotfiles/blob/master/config/nvim/plugin/zoom.vim
function Zoom()
    if winnr('$') > 1
        tab split
    elseif len(filter(map(range(tabpagenr('$')), 'tabpagebuflist(v:val + 1)'),
        \ 'index(v:val, ' . bufnr('') . ') >= 0')) > 1
        tabclose
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

" Toggle spelling
let g:_custom_spell_completion_enabled = 1
function SpellCompletionToggle()
  if g:_custom_spell_completion_enabled == 1
    echo "Disable spell completion"
    set complete-=k
    set complete-=kspell
    set complete-=kdict
    let g:_custom_spell_completion_enabled = 0
  else
    echo "Enable spell completion"
    set complete+=kspell,kdict,k
    let g:_custom_spell_completion_enabled = 1
  end
endfunction

" Create scratch buffer
function Scratch()
  enew
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
endfunction
