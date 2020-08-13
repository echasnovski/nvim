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
function SectionR()
  " Insert section template
  let l:section_r = "# " . repeat("-", 73)
  call append(line("."), l:section_r)

  " Enable Replace mode in appropriate place
  call cursor(line(".")+1, 3)
  startreplace
endfunction

nnoremap <buffer> <M-s> :call SectionR()<CR>
inoremap <buffer> <M-s> <C-o>:call SectionR()<CR>

" You can use this as custom "format on save" instead of "r" option inside
" "coc.preferences.formatOnSaveFiletypes" in 'coc-settings.json'.
" Difference is that with this approach save will not be done until formatting
" is done. This eliminates problem of "not saved file after 'Format on Save'"
" but on the other hand it freezes Neovim until formatting is done.
" As 'styler' (used R formatter) is notoriously slow, this will be convenient
" for small files and **very** inconvenient for big (>100 lines) files.
" autocmd BufWritePre <buffer> call CocAction('format')
