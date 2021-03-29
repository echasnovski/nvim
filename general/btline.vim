" Vimscript code for custom tabline (called 'btline', short of 'buftabline').
" General idea: show all listed buffers in case of one tab, fall back for
" deafult otherwise. NOTE: this is superseded by a more faster Lua
" implementation ('lua/btline.lua'). Kept here for historical reasons.
"
" This code is a truncated version of 'ap/vim-buftabline' with the following
" options:
" - let g:buftabline_numbers    = 0
" - let g:buftabline_indicators = 0
" - let g:buftabline_separators = 0
" - let g:buftabline_show       = 2
" - let g:buftabline_plug_max   = <removed manually>
"
" NOTE that I also removed handling of certain isoteric edge cases which I
" don't fully understand but in truncated code they seem to be redundant:
" - Having extra 'centerbuf' variable which is said to 'prevent tabline
"   jumping around when non-user buffer current (e.g. help)'.
" - Having `set guioptions+=e` and `set guioptions-=e` in update function.

function! UserBuffers() " help buffers are always unlisted, but quickfix buffers are not
  return filter(range(1,bufnr('$')),'buflisted(v:val) && "quickfix" !=? getbufvar(v:val, "&buftype")')
endfunction

function! s:SwitchBuffer(bufnum, clicks, button, mod)
  execute 'buffer' a:bufnum
endfunction

function s:SID()
  return matchstr(expand('<sfile>'), '<SNR>\d\+_')
endfunction

let s:dirsep = fnamemodify(getcwd(),':p')[-1:]
let s:centerbuf = winbufnr(0)
let s:tablineat = has('tablineat')
let s:sid = s:SID() | delfunction s:SID

" Track all scratch and unnamed buffers for disambiguation. These dictionaries
" are designed to store 'sequential' buffer identifier. This approach allows
" to have the following behavior:
" - Create three scratch (or unnamed) buffers.
" - Delete second one.
" - Tab label for third one remains the same.
let s:unnamed_tabs = {}

" NOTE: Timing execution of `BtlineRender()` on 16 buffers gives around 3 ms
" execution time (with occasional 7 ms) with rise to around 10 ms in case of
" duplicating file names. If this is too much, consider rewriting in Lua (for
" Neovim).
function! BtlineRender()
  " let start_time = reltime()

  " Pick up data on all the buffers
  let tabs = []
  let path_tabs = []
  let tabs_per_tail = {}
  let currentbuf = winbufnr(0)
  for bufnum in UserBuffers()
    let tab = { 'num': bufnum }

    " Functional label for possible clicks (see ':h statusline')
    let tab.func_label = '%' . bufnum . '@' . s:sid . 'SwitchBuffer@'

    " Determine highlight group
    let hl_type =
    \ currentbuf == bufnum
    \ ? 'Current'
    \ : bufwinnr(bufnum) > 0 ? 'Active' : 'Hidden'
    if getbufvar(bufnum, '&modified')
      let hl_type = 'Modified' . hl_type
    endif
    let tab.hl = '%#Btline' . hl_type . '#'

    if currentbuf == bufnum | let s:centerbuf = bufnum | endif

    let bufpath = bufname(bufnum)
    if strlen(bufpath)
      " Process buffers which have path
      let tab.path = fnamemodify(bufpath, ':p:~:.')
      let tab.sep = strridx(tab.path, s:dirsep, strlen(tab.path) - 2) " Keep trailing dirsep
      let tab.label = tab.path[tab.sep + 1:]
      let tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
      let path_tabs += [tab]
    elseif -1 < index(['nofile','acwrite'], getbufvar(bufnum, '&buftype'))
      " Process scratch buffer
      if has_key(s:unnamed_tabs, bufnum) == 0
        let s:unnamed_tabs[bufnum] = len(s:unnamed_tabs) + 1
      endif
      let tab_id = s:unnamed_tabs[bufnum]
      "" Only show 'sequential' id starting from second tab
      if tab_id == 1
        let tab.label = '!'
      else
        let tab.label = '!(' . tab_id . ')'
      endif
    else
      " Process unnamed buffer
      if has_key(s:unnamed_tabs, bufnum) == 0
        let s:unnamed_tabs[bufnum] = len(s:unnamed_tabs) + 1
      endif
      let tab_id = s:unnamed_tabs[bufnum]
      "" Only show 'sequential' id starting from second tab
      if tab_id == 1
        let tab.label = '*'
      else
        let tab.label = '*(' . tab_id . ')'
      endif
    endif

    let tabs += [tab]
  endfor

  " Disambiguate same-basename files by adding trailing path segments
  " Algorithm: iteratively add parent directories to duplicated buffer labels
  " until there are no duplicates
  while len(filter(tabs_per_tail, 'v:val > 1'))
    let [ambiguous, tabs_per_tail] = [tabs_per_tail, {}]
    for tab in path_tabs
      " Add one parent directory if there is any and if tab's label is
      " duplicated
      if -1 < tab.sep && has_key(ambiguous, tab.label)
        let tab.sep = strridx(tab.path, s:dirsep, tab.sep - 1)
        let tab.label = tab.path[tab.sep + 1:]
      endif
      let tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
    endfor
  endwhile

  " Now keep the current buffer center-screen as much as possible:

  " 1. Setup
  let lft = { 'lasttab':  0, 'cut':  '.', 'indicator': '<', 'width': 0, 'half': &columns / 2 }
  let rgt = { 'lasttab': -1, 'cut': '.$', 'indicator': '>', 'width': 0, 'half': &columns - lft.half }

  " 2. Sum the string lengths for the left and right halves
  let currentside = lft
  for tab in tabs
    let tab.width = 1 + strwidth(tab.label) + 1
    let tab.label = ' ' . substitute(strtrans(tab.label), '%', '%%', 'g') . ' '
    if s:centerbuf == tab.num
      let halfwidth = tab.width / 2
      let lft.width += halfwidth
      let rgt.width += tab.width - halfwidth
      let currentside = rgt
      continue
    endif
    let currentside.width += tab.width
  endfor
  if currentside is lft " Centered buffer not seen?
    " Then blame any overflow on the right side, to protect the left
    let [lft.width, rgt.width] = [0, lft.width]
  endif

  " 3. Toss away tabs and pieces until all fits:
  if ( lft.width + rgt.width ) > &columns
    let oversized
    \ = lft.width < lft.half ? [ [ rgt, &columns - lft.width ] ]
    \ : rgt.width < rgt.half ? [ [ lft, &columns - rgt.width ] ]
    \ :                        [ [ lft, lft.half ], [ rgt, rgt.half ] ]
    for [side, budget] in oversized
      let delta = side.width - budget
      " Toss entire tabs to close the distance
      while delta >= tabs[side.lasttab].width
        let delta -= remove(tabs, side.lasttab).width
      endwhile
      " Then snip at the last one to make it fit
      let endtab = tabs[side.lasttab]
      while delta > ( endtab.width - strwidth(strtrans(endtab.label)) )
        let endtab.label = substitute(endtab.label, side.cut, '', '')
      endwhile
      let endtab.label = substitute(endtab.label, side.cut, side.indicator, '')
    endfor
  endif

  " If available add possibility of clicking on buffer tabs
  if s:tablineat
    let tab_strings = map(tabs, 'v:val.hl . v:val.func_label . v:val.label')
  else
    let tab_strings = map(tabs, 'v:val.hl . v:val.label')
  endif

  " let res = join(tab_strings, '') . '%#BtlineFill#'
  " echo reltimefloat(reltime(start_time))
  " return res

  return join(tab_strings, '') . '%#BtlineFill#'
endfunction

function! BtlineUpdate()
  if tabpagenr('$') > 1
    set tabline=
  else
    set tabline=%!BtlineRender()
  endif
endfunction

augroup Btline
  autocmd!
  autocmd VimEnter   * call BtlineUpdate()
  autocmd TabEnter   * call BtlineUpdate()
  autocmd BufAdd     * call BtlineUpdate()
  autocmd FileType  qf call BtlineUpdate()
  autocmd BufDelete  * call BtlineUpdate()
augroup END
