" Custom statusline rewritten in Vimscript (to be used in Vim, not in Neovim).
" For more information see 'lua/statusline.lua'.

" Helper functions
function s:IsTruncated(width)
  return winwidth(0) < a:width
endfunction

function IsTruncated(width)
  return winwidth(0) < a:width
endfunction

function s:IsntNormalBuffer()
  " For more information see ':h buftype'
  return &buftype != ''
endfunction

function s:CombineSections(sections)
  let l:res = ''
  for s in a:sections
    if type(s) == v:t_string
      let l:res = l:res . s
    elseif s['string'] != ''
      if s['hl'] != v:null
        let l:res = l:res . printf('%s %s ', s['hl'], s['string'])
      else
        let l:res = l:res . printf('%s ', s['string'])
      endif
    endif
  endfor

  return l:res
endfunction

" Statusline behavior
augroup Statusline
  au!
  au WinEnter,BufEnter * setlocal statusline=%!StatuslineActive()
  au WinLeave,BufLeave * setlocal statusline=%!StatuslineInactive()
augroup END

" High-level definition of statusline content
function StatuslineActive()
  let l:mode_info = s:statusline_modes[mode()]

  let l:mode = s:SectionMode(l:mode_info, 120)
  let l:spell = s:SectionSpell(120)
  let l:wrap = s:SectionWrap()
  let l:git = s:SectionGit(75)
  " Diagnostics section is missing as this is a script for Vim
  let l:filename = s:SectionFilename(140)
  let l:fileinfo = s:SectionFileinfo(120)
  let l:location = s:SectionLocation()

  return s:CombineSections([
    \ {'string': l:mode, 'hl': l:mode_info['hl']},
    \ {'string': l:spell, 'hl': v:null},
    \ {'string': l:wrap, 'hl': v:null},
    \ {'string': l:git, 'hl': '%#StatusLineDevinfo#'},
    \ '%<',
    \ {'string': l:filename, 'hl': '%#StatusLineFilename#'},
    \ '%=',
    \ {'string': l:fileinfo, 'hl': '%#StatusLineFileinfo#'},
    \ {'string': l:location, 'hl': l:mode_info['hl']},
    \ ])
endfunction

function StatuslineInactive()
  return '%#StatuslineInactive#%F%='
endfunction

" Mode
let s:statusline_modes = {
  \ 'n' : {'long': 'Normal'  , 'short' : 'N'  , 'hl' : '%#StatusLineModeNormal#'},
  \ 'v' : {'long': 'Visual'  , 'short' : 'V'  , 'hl' : '%#StatusLineModeVisual#'},
  \ 'V' : {'long': 'V-Line'  , 'short' : 'V-L', 'hl' : '%#StatusLineModeVisual#'},
  \ '': {'long': 'V-Block' , 'short' : 'V-B', 'hl' : '%#StatusLineModeVisual#'},
  \ 's' : {'long': 'Select'  , 'short' : 'S'  , 'hl' : '%#StatusLineModeVisual#'},
  \ 'S' : {'long': 'S-Line'  , 'short' : 'S-L', 'hl' : '%#StatusLineModeVisual#'},
  \ '': {'long': 'S-Block' , 'short' : 'S-B', 'hl' : '%#StatusLineModeVisual#'},
  \ 'i' : {'long': 'Insert'  , 'short' : 'I'  , 'hl' : '%#StatusLineModeInsert#'},
  \ 'R' : {'long': 'Replace' , 'short' : 'R'  , 'hl' : '%#StatusLineModeReplace#'},
  \ 'c' : {'long': 'Command' , 'short' : 'C'  , 'hl' : '%#StatusLineModeCommand#'},
  \ 'r' : {'long': 'Prompt'  , 'short' : 'P'  , 'hl' : '%#StatusLineModeOther#'},
  \ '!' : {'long': 'Shell'   , 'short' : 'Sh' , 'hl' : '%#StatusLineModeOther#'},
  \ 't' : {'long': 'Terminal', 'short' : 'T'  , 'hl' : '%#StatusLineModeOther#'},
  \ }

function s:SectionMode(mode_info, trunc_width)
  return s:IsTruncated(a:trunc_width) ?
    \ a:mode_info['short'] :
    \ a:mode_info['long']
endfunction

" Spell
function s:SectionSpell(trunc_width)
  if &spell == 0 | return '' | endif

  if s:IsTruncated(a:trunc_width) | return 'SPELL' | endif

  return printf('SPELL(%s)', &spelllang)
endfunction

" Wrap
function s:SectionWrap()
  if &wrap == 0 | return '' | endif

  return 'WRAP'
endfunction

" Git
function s:GetGitBranch()
  if exists('*FugitiveHead') == 0 | return '<no fugitive>' | endif

  " Use commit hash truncated to 7 characters in case of detached HEAD
  let l:branch = FugitiveHead(7)
  if l:branch == '' | return '<no branch>' | endif
  return l:branch
endfunction

function s:GetGitSigns()
  if exists('*GitGutterGetHunkSummary') == 0 | return '' | endif

  let l:signs = GitGutterGetHunkSummary()
  let l:res = []
  if l:signs[0] > 0 | let l:res = l:res + ['+' . l:signs[0]] | endif
  if l:signs[1] > 0 | let l:res = l:res + ['~' . l:signs[1]] | endif
  if l:signs[2] > 0 | let l:res = l:res + ['-' . l:signs[2]] | endif

  if len(l:res) == 0 | return '' | endif
  return join(l:res, ' ')
endfunction

function s:SectionGit(trunc_width)
  if s:IsntNormalBuffer() | return '' | endif

  " NOTE: this information doesn't change on every entry but these functions
  " are called on every statusline update (which is **very** often). Currently
  " this doesn't introduce noticeable overhead because of a smart way used
  " functions of 'vim-gitgutter' and 'vim-fugitive' are written (seems like
  " they just take value of certain buffer variable, which is quick).
  " If ever encounter overhead, write 'update_val()' wrapper which updates
  " module's certain variable and call it only on certain event. Example:
  " ```lua
  " Statusline.git_signs_str = ''
  " Statusline.update_git_signs = function(self)
  "   self.git_signs_str = get_git_signs()
  " end
  " vim.api.nvim_exec([[
  "   au BufEnter,User GitGutter lua Statusline:update_git_signs()
  " ]], false)
  " ```
  let l:res = s:GetGitBranch()

  if s:IsTruncated(a:trunc_width) == 0
    let l:signs = s:GetGitSigns()
    if l:signs != '' | let l:res = printf('%s %s', l:res, l:signs) | endif
  endif

  if l:res == '' | let l:res = '-' | endif
  return printf(' %s', l:res)
endfunction

" File name
function s:SectionFilename(trunc_width)
  " In terminal always use plain name
  if &buftype == 'terminal'
    return '%t'
  " File name with 'truncate', 'modified', 'readonly' flags
  elseif s:IsTruncated(a:trunc_width)
    " Use relative path if truncated
    return '%f%m%r'
  else
    " Use fullpath if not truncated
    return '%F%m%r'
  endif
endfunction

" File information
function s:GetFilesize()
  let l:size = getfsize(getreg('%'))
  if l:size < 1024
    let l:data = l:size . 'B'
  elseif l:size < 1048576
    let l:data = printf('%.2fKiB', l:size / 1024.0)
  else
    let l:data = printf('%.2fMiB', l:size / 1048576.0)
  end

  return l:data
endfunction

function s:GetFiletypeIcon()
  if exists('*WebDevIconsGetFileTypeSymbol') != 0
    return WebDevIconsGetFileTypeSymbol()
  endif

  return ''
endfunction

function s:SectionFileinfo(trunc_width)
  let l:filetype = &filetype

  " Don't show anything if can't detect file type or not inside a 'normal
  " buffer'
  if ((l:filetype == '') || s:IsntNormalBuffer()) | return '' | endif

  " Add filetype icon
  let l:icon = s:GetFiletypeIcon()
  if l:icon != '' | let l:filetype = l:icon . ' ' . l:filetype | endif

  " Construct output string if truncated
  if s:IsTruncated(a:trunc_width) | return l:filetype | endif

  " Construct output string with extra file info
  let l:encoding = &fileencoding
  if l:encoding == '' | let l:encoding = &encoding | endif
  let l:format = &fileformat
  let l:size = s:GetFilesize()

  return printf('%s %s[%s] %s', l:filetype, l:encoding, l:format, l:size)
endfunction

" Location inside buffer
function s:SectionLocation()
  " Use virtual column number to allow update when paste last column
  return '%l|%L│%2v|%-2{col("$") - 1}'
endfunction
