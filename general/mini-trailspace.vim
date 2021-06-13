" Setup behavior
augroup MiniTrailspace
  au!
  au WinEnter,BufWinEnter,InsertLeave * call MiniTrailspaceHighlight()
  au WinLeave,BufWinLeave,InsertEnter * call MiniTrailspaceUnhighlight()
augroup END

" Highlight group
highlight MiniTrailspace ctermbg=red ctermfg=white guibg=#FB4934

" Functions to enable/disable whole module
let s:enabled = 1

function MiniTrailspaceEnable()
  let s:enabled = 1
  " Add highlights
  call MiniTrailspaceHighlight()
  echo 'mini-trailspace.vim enabled'
endfunction

function MiniTrailspaceDisable()
  let s:enabled = 0
  " Remove highlights
  call MiniTrailspaceUnhighlight()
  echo 'mini-trailspace.vim disabled'
endfunction

function MiniTrailspaceToggle()
  if s:enabled
    call MiniTrailspaceDisable()
  else
    call MiniTrailspaceEnable()
  endif
endfunction

" Functions to perform actions
function MiniTrailspaceHighlight()
  " Do nothing if disabled
  if s:enabled == 0 | return | endif

  " Don't add match id on top of existing one (prevents multiple calls of
  " `MiniTrailspaceEnable()`)
  if !exists('w:_trailspace_match')
    let w:_trailspace_match = matchadd('MiniTrailspace', '\s\+$')
  end
endfunction

function MiniTrailspaceUnhighlight()
  if exists('w:_trailspace_match')
    call matchdelete(w:_trailspace_match)
    unlet w:_trailspace_match
  endif
endfunction

function MiniTrailspaceTrim()
  " Save cursor position to later restore
  let curpos = getpos('.')
  " Search and replace trailing whitespace
  keeppatterns %s/\s\+$//e
  call setpos('.', curpos)
endfunction
