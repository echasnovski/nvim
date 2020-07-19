" Configurations for 'vim-startify' plugin
let g:startify_session_dir = '~/.config/nvim/session'

let g:startify_lists = [
    \ { 'type': 'sessions',  'header': ['   Sessions']       },
    \ { 'type': 'bookmarks', 'header': ['   Bookmarks']      },
    \ ]

let g:startify_bookmarks = [
    \ { 'n': '~/.config/nvim/' },
    \ ]

let g:startify_custom_header = 'startify#pad(startify#fortune#boxed())'
let g:startify_fortune_use_unicode = 1

let g:startify_skiplist = ['COMMIT_EDITMSG']

let g:startify_session_autoload = 1
let g:startify_session_persistence = 1
