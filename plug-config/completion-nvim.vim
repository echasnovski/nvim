if has("nvim-0.5.0")
  " Use completion-nvim in every buffer
  autocmd BufEnter * lua require'completion'.on_attach()

  " Use all available sources automatically
  let g:completion_auto_change_source = 1

  " Use smartcase when searching for match
  let g:completion_matching_smart_case = 1

  " Still use completion when deleting
  let g:completion_trigger_on_delete = 1

  " Setup matching strategy
	let g:completion_matching_strategy_list = ['exact', 'substring']

  " Set up 'precedence' between completion sources
  let g:completion_chain_complete_list = [
    \{'complete_items': ['lsp', 'keyn', 'snippet']},
    \{'mode': '<c-n>'}
  \]

  " Make completion work nicely with auto-pairs plugin ('pear-tree' in my
  " setup)
	let g:completion_confirm_key = ""
	imap <expr> <cr>  pumvisible() ? complete_info()["selected"] != "-1" ?
			\ "\<Plug>(completion_confirm_completion)"  :
			\ "\<c-e>\<CR>" : "\<CR>"

  " Don't use any sorting, as it not always intuitive (for example, puts
  " suggestions starting with '_' on top in case of 'alphabetical')
  let g:completion_sorting = 'none'
endif
