" Custom minimal autopairs plugin rewritten in Vimscript (to be used in Vim,
" not in Neovim). For more information see 'lua/mini/pairs.lua'.

" Helpers
function s:IsInList(val, l)
  return index(a:l, a:val) >= 0
endfunction

function s:GetCursorChars(start, finish)
  if mode() == 'c'
    let l:line = getcmdline()
    let l:col = getcmdpos()
  else
    let l:line = getline('.')
    let l:col = col('.')
  endif

  return l:line[(l:col + a:start - 2):(l:col + a:finish - 2)]
endfunction

" NOTE: use `s:GetArrowKey()` instead of `keys.left` or `keys.right`
let s:keys = {
  \ 'above'    : "\<C-o>O",
  \ 'bs'       : "\<bs>",
  \ 'cr'       : "\<cr>",
  \ 'del'      : "\<del>",
  \ 'keep_undo': "\<C-g>U",
  \ 'left'     : "\<left>",
  \ 'right'    : "\<right>"
\ }

" Using left/right keys in insert mode breaks undo sequence and, more
" importantly, dot-repeat. To avoid this, use 'i_CTRL-G_U' mapping.
function s:GetArrowKey(key)
  if mode() == 'i'
    return s:keys['keep_undo'] . s:keys[a:key]
  else
    return s:keys[a:key]
  endif
endfunction

" Pair actions.
" They are intended to be used inside `_noremap <expr> ...` type of mappings,
" as they return sequence of keys (instead of other possible approach of
" simulating them with `feedkeys()`).
function g:MiniPairsActionOpen(pair)
  return a:pair . s:GetArrowKey('left')
endfunction

"" NOTE: `pair` as argument is used for consistency (when `right` is enough)
function g:MiniPairsActionClose(pair)
  let l:close = a:pair[1:1]
  if s:GetCursorChars(1, 1) == l:close
    return s:GetArrowKey('right')
  else
    return l:close
  endif
endfunction

function g:MiniPairsActionCloseopen(pair)
  if s:GetCursorChars(1, 1) == a:pair[1:1]
    return s:GetArrowKey('right')
  else
    return a:pair . s:GetArrowKey('left')
  endif
endfunction

"" Each argument should be a pair which triggers extra action
function g:MiniPairsActionBS(pair_set)
  let l:res = s:keys['bs']

  if s:IsInList(s:GetCursorChars(0, 1), a:pair_set)
    let l:res = l:res . s:keys['del']
  endif

  return l:res
endfunction

function g:MiniPairsActionCR(pair_set)
  let l:res = s:keys['cr']

  if s:IsInList(s:GetCursorChars(0, 1), a:pair_set)
    let l:res = l:res . s:keys['above']
  endif

  return l:res
endfunction

" Helper for remapping auto-pair from '""' quotes to '\'\''
function g:MiniPairsRemapQuotes()
  " Map '"' to original key (basically, unmap it)
  inoremap <buffer> " "

  " Map '\''
  inoremap <buffer> <expr> ' g:MiniPairsActionCloseopen("''")
endfunction

" Setup mappings
"" Insert mode
inoremap <expr> ( g:MiniPairsActionOpen('()')
inoremap <expr> [ g:MiniPairsActionOpen('[]')
inoremap <expr> { g:MiniPairsActionOpen('{}')

inoremap <expr> ) g:MiniPairsActionClose('()')
inoremap <expr> ] g:MiniPairsActionClose('[]')
inoremap <expr> } g:MiniPairsActionClose('{}')

inoremap <expr> " g:MiniPairsActionCloseopen('""')
""" No auto-pair for '\'' because it messes up with plain English used in
""" comments (like can't, etc.)
inoremap <expr> ` g:MiniPairsActionCloseopen('``')

inoremap <expr> <BS> g:MiniPairsActionBS(['()', '[]', '{}', '""', "''", '``'])
inoremap <expr> <CR> g:MiniPairsActionCR(['()', '[]', '{}'])

"" Command mode
cnoremap <expr> ( g:MiniPairsActionOpen('()')
cnoremap <expr> [ g:MiniPairsActionOpen('[]')
cnoremap <expr> { g:MiniPairsActionOpen('{}')

cnoremap <expr> ) g:MiniPairsActionClose('()')
cnoremap <expr> ] g:MiniPairsActionClose('[]')
cnoremap <expr> } g:MiniPairsActionClose('{}')

cnoremap <expr> " g:MiniPairsActionCloseopen('""')
cnoremap <expr> ' g:MiniPairsActionCloseopen("''")
cnoremap <expr> ` g:MiniPairsActionCloseopen('``')

cnoremap <expr> <BS> g:MiniPairsActionBS(['()', '[]', '{}', '""', "''", '``'])

"" Terminal mode
tnoremap <expr> ( g:MiniPairsActionOpen('()')
tnoremap <expr> [ g:MiniPairsActionOpen('[]')
tnoremap <expr> { g:MiniPairsActionOpen('{}')

tnoremap <expr> ) g:MiniPairsActionClose('()')
tnoremap <expr> ] g:MiniPairsActionClose('[]')
tnoremap <expr> } g:MiniPairsActionClose('{}')

tnoremap <expr> " g:MiniPairsActionCloseopen('""')
cnoremap <expr> ' g:MiniPairsActionCloseopen("''")
tnoremap <expr> ` g:MiniPairsActionCloseopen('``')

tnoremap <expr> <BS> g:MiniPairsActionBS(['()', '[]', '{}', '""', "''", '``'])
tnoremap <expr> <CR> g:MiniPairsActionCR(['()', '[]', '{}'])

"" Remap quotes in certain filetypes
au FileType lua call g:MiniPairsRemapQuotes()
au FileType vim call g:MiniPairsRemapQuotes()
