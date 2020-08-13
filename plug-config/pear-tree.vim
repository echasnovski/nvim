let g:pear_tree_pairs = {
  \  '('  : {'closer': ')'},
  \  '['  : {'closer': ']'},
  \  '{'  : {'closer': '}'},
  \  "'"  : {'closer': "'"},
  \  '"'  : {'closer': '"'},
  \  '`'  : {'closer': '`'},
  \ }

" Possible entry in `g:pear_tree_pairs` for tags
" \  '<*>': {'closer': '</*>', 'not_if': ['br', 'meta'], 'not_in': ['String', 'Comment']},
" Or better use 'vim-surround' plugin to 'surroung' empty space with `vS`

" Disable repeatable expand to immediately show closing character on new line
let g:pear_tree_repeatable_expand = 0

" Check open-close balancing
let g:pear_tree_smart_openers   = 1
let g:pear_tree_smart_closers   = 1
let g:pear_tree_smart_backspace = 1

" Unmap 'Finish expansion' keymap as it is not needed
let g:pear_tree_map_special_keys = 0
imap <CR> <Plug>(PearTreeExpand)
imap <BS> <Plug>(PearTreeBackspace)
