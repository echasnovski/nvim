" Leader key
let mapleader = "\<Space>"

" Map leader to which_key
nnoremap <silent> <Leader> :silent <c-u> :silent WhichKey '<Space>'<CR>
vnoremap <silent> <Leader> :silent <c-u> :silent WhichKeyVisual '<Space>'<CR>

" Create map to add keys to
let g:which_key_map =  {}

" Single mappings
nnoremap <silent> <Leader>w :call ToggleWrap()<CR>
let g:which_key_map['w'] = 'wrap toggle'

"" Execute in jupyter current line and go down by one line
nmap <silent> <Leader>j  <Plug>(IPy-Run)j
"" Execute in jupyter selection and go down by one line after the end of
"" selection
vmap <silent> <Leader>j  <Plug>(IPy-Run)'>j
let g:which_key_map['j'] = 'jupyter run'

" b is for 'buffer'
nnoremap <silent> <Leader>bd :Bclose<CR>
nnoremap <silent> <Leader>bd! :Bclose!<CR>
let g:which_key_map.b = {
    \ 'name' : '+buffer' ,
    \ 'd'  : [':Bclose'  , 'delete'],
    \ "d!" : [":Bclose!" , "delete!"],
    \ }

" c is for 'coc.nvim'
let g:which_key_map.c = {
    \ 'name' : '+Coc' ,
    \ '.' : [':CocConfig'                        , 'config'],
    \ ';' : ['<Plug>(coc-refactor)'              , 'refactor'],
    \ 'A' : ['<Plug>(coc-codeaction-selected)'   , 'selected action'],
    \ 'a' : ['<Plug>(coc-codeaction)'            , 'line action'],
    \ 'B' : [':CocPrev'                          , 'prev action'],
    \ 'b' : [':CocNext'                          , 'next action'],
    \ 'c' : [':CocList commands'                 , 'commands'],
    \ 'D' : ['<Plug>(coc-declaration)'           , 'declaration'],
    \ 'd' : ['<Plug>(coc-definition)'            , 'definition'],
    \ 'e' : [':CocList extensions'               , 'extensions'],
    \ 'F' : ['<Plug>(coc-format)'                , 'format'],
    \ 'f' : ['<Plug>(coc-format-selected)'       , 'format selected'],
    \ 'h' : ['<Plug>(coc-float-hide)'            , 'hide'],
    \ 'I' : [':CocList -A --normal diagnostics'  , 'diagnostics'],
    \ 'i' : ['<Plug>(coc-implementation)'        , 'implementation'],
    \ 'J' : ['<Plug>(coc-diagnostic-next-error)' , 'next error'],
    \ 'j' : ['<Plug>(coc-diagnostic-next)'       , 'next diagnostic'],
    \ 'K' : ['<Plug>(coc-diagnostic-prev-error)' , 'prev error'],
    \ 'k' : ['<Plug>(coc-diagnostic-prev)'       , 'prev diagnostic'],
    \ 'l' : ['<Plug>(coc-codelens-action)'       , 'code lens'],
    \ 'O' : [':CocList outline'                  , 'outline'],
    \ 'o' : ['<Plug>(coc-openlink)'              , 'open link'],
    \ 'q' : ['<Plug>(coc-fix-current)'           , 'quickfix'],
    \ 'R' : ['<Plug>(coc-references)'            , 'references'],
    \ 'r' : ['<Plug>(coc-rename)'                , 'rename'],
    \ 'S' : [':CocList snippets'                 , 'snippets'],
    \ 's' : [':CocList -A --normal -I symbols'   , 'references'],
    \ 't' : ['<Plug>(coc-type-definition)'       , 'type definition'],
    \ 'U' : [':CocUpdate'                        , 'update CoC'],
    \ 'u' : [':CocListResume'                    , 'resume list'],
    \ 'Z' : [':CocEnable'                        , 'enable CoC'],
    \ 'z' : [':CocDisable'                       , 'disable CoC'],
    \ }

" e is for 'explorer'
let g:which_key_map.e = {
    \ 'name' : '+explorer' ,
    \ 't' : [':NERDTreeToggle' , 'toggle'],
    \ 'f' : [':NERDTreeFind'   , 'find file'],
    \ }

" f is for both 'fzf' and 'find'
let g:which_key_map.f = {
    \ 'name' : '+fzf' ,
    \ '/' : [':History/'         , '"/" history'],
    \ ';' : [':Commands'         , 'commands'],
    \ 'b' : [':Buffers'          , 'open buffers'],
    \ 'C' : [':BCommits'         , 'buffer commits'],
    \ 'c' : [':Commits'          , 'commits'],
    \ 'f' : [':Files'            , 'files'],
    \ 'g' : [':GFiles'           , 'git files'],
    \ 'G' : [':GFiles?'          , 'modified git files'],
    \ 'H' : [':History:'         , 'command history'],
    \ 'h' : [':History'          , 'file history'],
    \ 'L' : [':BLines'           , 'lines (current buffer)'],
    \ 'l' : [':Lines'            , 'lines (all buffers)'],
    \ 'M' : [':Maps'             , 'normal maps'],
    \ 'm' : [':Marks'            , 'marks'],
    \ 'p' : [':Helptags'         , 'help tags'],
    \ 'r' : [':Rg'               , 'text Rg'],
    \ 'S' : [':Colors'           , 'color schemes'],
    \ 's' : [':CocList snippets' , 'snippets'],
    \ 'T' : [':BTags'            , 'buffer tags'],
    \ 't' : [':Tags'             , 'project tags'],
    \ 'w' : [':Windows'          , 'search windows'],
    \ 'y' : [':Filetypes'        , 'file types'],
    \ 'z' : [':FZF'              , 'FZF'],
    \ }

" g is for git
"" Functions `GitGutterNextHunkCycle()` and `GitGutterPrevHunkCycle()` are
"" defined in 'general/functions.vim'
let g:which_key_map.g = {
    \ 'name' : '+git' ,
    \ 'A' : [':Git add %'                     , 'add buffer'],
    \ 'a' : ['<Plug>(GitGutterStageHunk)'     , 'add hunk'],
    \ 'b' : [':Git blame'                     , 'blame'],
    \ 'D' : [':Gvdiffsplit'                   , 'diff split'],
    \ 'd' : [':Git diff'                      , 'diff'],
    \ 'f' : [':GitGutterFold'                 , 'fold unchanged'],
    \ 'g' : [':Git'                           , 'git window'],
    \ 'j' : [':call GitGutterNextHunkCycle()' , 'next hunk'],
    \ 'k' : [':call GitGutterPrevHunkCycle()' , 'prev hunk'],
    \ 'p' : ['<Plug>(GitGutterPreviewHunk)'   , 'preview hunk'],
    \ 'q' : [':GitGutterQuickFix | copen'     , 'quickfix hunks'],
    \ 'R' : [':Git reset %'                   , 'reset buffer'],
    \ 't' : [':GitGutterLineHighlightsToggle' , 'toggle highlight'],
    \ 'u' : ['<Plug>(GitGutterUndoHunk)'      , 'undo hunk'],
    \ 'V' : [':GV!'                           , 'view buffer commits'],
    \ 'v' : [':GV'                            , 'view commits'],
    \ }

" i is for IPython
"" Qt Console connection.
""" **To create working connection, execute both keybindings** (second after
""" console is created).
""" **Note**: Qt Console is opened with Python interpreter that is used in
""" terminal when opened NeoVim (i.e. output of `which python`). As a
""" consequence, if that Python interpreter doesn't have 'jupyter' or
""" 'qtconsole' installed, Qt Console will not be created.
""" `CreateQtConsole()` is defined in 'plug-config/nvim-ipy.vim'.
nmap <silent> <Leader>iq :call CreateQtConsole()<CR>
nmap <silent> <Leader>ik :IPython<Space>--existing<Space>--no-window<CR>

"" Execution
nmap <silent> <Leader>ic  <Plug>(IPy-RunCell)
nmap <silent> <Leader>ia  <Plug>(IPy-RunAll)

""" One can also setup a completion connection (generate a completion list
""" inside NeoVim but options taken from IPython session), but it seems to be
""" a bad practice methodologically.
"" imap <silent> <C-k> <Cmd>call IPyComplete()<cr>
""   " This one should be used only when inside Insert mode after <C-o>
"" nmap <silent> <Leader>io <Cmd>call IPyComplete()<cr>

let g:which_key_map.i = {
    \ 'name' : '+IPython',
    \ 'a' : 'run all',
    \ 'c' : 'run cell',
    \ 'k' : 'connect',
    \ 'q' : 'Qt Console',
    \ }

" t is for 'terminal' (uses 'neoterm')
let g:which_key_map.t = {
    \ 'name' : '+terminal' ,
    \ 'a' : [':TREPLSetTerm 1'   , 'focus term #1'],
    \ 'b' : [':TREPLSetTerm 2'   , 'focus term #2'],
    \ 'c' : [':TREPLSetTerm 3'   , 'focus term #3'],
    \ 's' : [':belowright Tnew'  , 'split terminal'],
    \ 'v' : [':vertical Tnew'    , 'vsplit terminal'],
    \ }

" s is for 'send'
nnoremap <Leader>s :TREPLSendLine<cr>j
vnoremap <Leader>s :TREPLSendSelection<cr>'>j

" Register 'which-key' mappings
call which_key#register('<Space>', "g:which_key_map")

