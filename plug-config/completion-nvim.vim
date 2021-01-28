if has("nvim-0.5.0")
  " Use completion-nvim in every buffer
  autocmd BufEnter * lua require'completion'.on_attach()

  " Use all available sources automatically
  let g:completion_auto_change_source = 1

  " Setup matching strategy
	let g:completion_matching_strategy_list = ['exact', 'substring', 'fuzzy']

  " Set up 'precedence' between completion sources
  let g:completion_chain_complete_list = [
    \{'complete_items': ['lsp', 'snippet']},
    \{'mode': '<c-n>'}
  \]
endif
