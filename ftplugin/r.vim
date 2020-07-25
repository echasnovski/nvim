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

