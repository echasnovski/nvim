setlocal colorcolumn=81 " Show line after desired maximum text width

" Keybindings
inoremap <buffer> <M-i> <Space><-<Space>
inoremap <buffer> <M-k> <Space>%>%

" Indentation
"" Don't align indentation of function args on new line with opening `(`
let r_indent_align_args = 0

"" Disable ESS comments
let r_indent_ess_comments = 0
let r_indent_ess_compatible = 0

" Section insert
let s:section = "# " . repeat("-", 73)

function RSection()
  call append(line("."), s:section)
endfunction

" Section folding
set foldmethod=expr
set foldexpr=RFoldexpr(v:lnum)

function! RFoldexpr(lnum)
  if getline(a:lnum) =~ '^#\s\(.*\)\+-\{4\}$'
    " Start a new level-one fold
    return '>1'
  else
    " Use the same foldlevel as the previous line
    return '='
  endif
endfunction
