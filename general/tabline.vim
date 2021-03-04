" This code is a truncated version of 'ap/vim-buftabline' with the following
" options:
" - let g:buftabline_numbers    = 0
" - let g:buftabline_indicators = 0
" - let g:buftabline_separators = 0
" - let g:buftabline_show       = 2
" - let g:buftabline_plug_max   = <removed manually>

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

function! TablineRender()
  let lpad = ' '

  let bufnums = UserBuffers()
  let centerbuf = s:centerbuf " prevent tabline jumping around when non-user buffer current (e.g. help)

  " pick up data on all the buffers
  let tabs = []
  let path_tabs = []
  let tabs_per_tail = {}
  let currentbuf = winbufnr(0)
  for bufnum in bufnums
    let tab = { 'num': bufnum, 'pre': '' }
    let tab.hilite = currentbuf == bufnum ? 'Current' : bufwinnr(bufnum) > 0 ? 'Active' : 'Hidden'
    if currentbuf == bufnum | let [centerbuf, s:centerbuf] = [bufnum, bufnum] | endif
    let bufpath = bufname(bufnum)
    if strlen(bufpath)
      let tab.path = fnamemodify(bufpath, ':p:~:.')
      let tab.sep = strridx(tab.path, s:dirsep, strlen(tab.path) - 2) " keep trailing dirsep
      let tab.label = tab.path[tab.sep + 1:]
      if getbufvar(bufnum, '&modified')
        let tab.hilite = 'Modified' . tab.hilite
      endif
      let tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
      let path_tabs += [tab]
    elseif -1 < index(['nofile','acwrite'], getbufvar(bufnum, '&buftype')) " scratch buffer
      let tab.label = '!'
    else " unnamed file
      let tab.label = ( getbufvar(bufnum, '&mod') ? '+' : '' ) . '*'
    endif
    let tabs += [tab]
  endfor

  " disambiguate same-basename files by adding trailing path segments
  while len(filter(tabs_per_tail, 'v:val > 1'))
    let [ambiguous, tabs_per_tail] = [tabs_per_tail, {}]
    for tab in path_tabs
      if -1 < tab.sep && has_key(ambiguous, tab.label)
        let tab.sep = strridx(tab.path, s:dirsep, tab.sep - 1)
        let tab.label = tab.path[tab.sep + 1:]
      endif
      let tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
    endfor
  endwhile

  " now keep the current buffer center-screen as much as possible:

  " 1. setup
  let lft = { 'lasttab':  0, 'cut':  '.', 'indicator': '<', 'width': 0, 'half': &columns / 2 }
  let rgt = { 'lasttab': -1, 'cut': '.$', 'indicator': '>', 'width': 0, 'half': &columns - lft.half }

  " 2. sum the string lengths for the left and right halves
  let currentside = lft
  let lpad_width = strwidth(lpad)
  for tab in tabs
    let tab.width = lpad_width + strwidth(tab.pre) + strwidth(tab.label) + 1
    let tab.label = lpad . tab.pre . substitute(strtrans(tab.label), '%', '%%', 'g') . ' '
    if centerbuf == tab.num
      let halfwidth = tab.width / 2
      let lft.width += halfwidth
      let rgt.width += tab.width - halfwidth
      let currentside = rgt
      continue
    endif
    let currentside.width += tab.width
  endfor
  if currentside is lft " centered buffer not seen?
    " then blame any overflow on the right side, to protect the left
    let [lft.width, rgt.width] = [0, lft.width]
  endif

  " 3. toss away tabs and pieces until all fits:
  if ( lft.width + rgt.width ) > &columns
    let oversized
    \ = lft.width < lft.half ? [ [ rgt, &columns - lft.width ] ]
    \ : rgt.width < rgt.half ? [ [ lft, &columns - rgt.width ] ]
    \ :                        [ [ lft, lft.half ], [ rgt, rgt.half ] ]
    for [side, budget] in oversized
      let delta = side.width - budget
      " toss entire tabs to close the distance
      while delta >= tabs[side.lasttab].width
        let delta -= remove(tabs, side.lasttab).width
      endwhile
      " then snip at the last one to make it fit
      let endtab = tabs[side.lasttab]
      while delta > ( endtab.width - strwidth(strtrans(endtab.label)) )
        let endtab.label = substitute(endtab.label, side.cut, '', '')
      endwhile
      let endtab.label = substitute(endtab.label, side.cut, side.indicator, '')
    endfor
  endif

  if len(tabs) | let tabs[0].label = substitute(tabs[0].label, lpad, ' ', '') | endif

  let swallowclicks = '%'.(1 + tabpagenr('$')).'X'
  return s:tablineat
    \ ? join(map(tabs,'"%#TabLine".v:val.hilite."#" . "%".v:val.num."@'.s:sid.'SwitchBuffer@" . strtrans(v:val.label)'),'') . '%#TabLineFill#' . swallowclicks
    \ : swallowclicks . join(map(tabs,'"%#TabLine".v:val.hilite."#" . strtrans(v:val.label)'),'') . '%#TabLineFill#'
endfunction

function! TablineUpdate()
  if tabpagenr('$') > 1
    set tabline=
  else
    set tabline=%!TablineRender()
  endif
endfunction

augroup TabLine
  autocmd!
  autocmd VimEnter   * call TablineUpdate()
  autocmd TabEnter   * call TablineUpdate()
  autocmd BufAdd     * call TablineUpdate()
  autocmd FileType  qf call TablineUpdate()
  autocmd BufDelete  * call TablineUpdate()
augroup END
