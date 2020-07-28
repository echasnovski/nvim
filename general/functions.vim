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
