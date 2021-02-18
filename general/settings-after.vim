" Settings to be sourced after everything else

if exists('vscode') == 0
  if has('nvim-0.5.0')
    " Make completion work nicely with auto-pairs plugin ('pear-tree' in my
    " setup). This should be sourced after everything else because otherwise
    " snippet expansion doesn't seem to work.
    let g:completion_confirm_key = ''
    imap <expr> <cr>  pumvisible() ? complete_info()["selected"] != "-1" ?
      \ "\<Plug>(completion_confirm_completion)"  :
      \ "\<c-e>\<CR>" : "\<CR>"
  endif
endif
