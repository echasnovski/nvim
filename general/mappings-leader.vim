" Leader key
let mapleader = "\<Space>"

" Map leader to which_key
nnoremap <silent> <leader> :silent <c-u> :silent WhichKey '<Space>'<CR>
vnoremap <silent> <leader> :silent <c-u> :silent WhichKeyVisual '<Space>'<CR>

" Create map to add keys to
let g:which_key_map =  {}

" Single mappings
let g:which_key_map['q'] = [':bd'            , 'delete buffer']
let g:which_key_map['Q'] = [':bd!'           , 'delete buffer!']

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
    \ 'c' : [':Commits'          , 'commits'],
    \ 'C' : [':BCommits'         , 'buffer commits'],
    \ 'f' : [':Files'            , 'files'],
    \ 'g' : [':GFiles'           , 'git files'],
    \ 'G' : [':GFiles?'          , 'modified git files'],
    \ 'h' : [':History'          , 'file history'],
    \ 'H' : [':History:'         , 'command history'],
    \ 'l' : [':Lines'            , 'lines (all buffers)'],
    \ 'L' : [':BLines'           , 'lines (current buffer)'],
    \ 'm' : [':Marks'            , 'marks'],
    \ 'M' : [':Maps'             , 'normal maps'],
    \ 'p' : [':Helptags'         , 'help tags'],
    \ 'P' : [':Tags'             , 'project tags'],
    \ 'r' : [':Rg'               , 'text Rg'],
    \ 's' : [':CocList snippets' , 'snippets'],
    \ 'S' : [':Colors'           , 'color schemes'],
    \ 'T' : [':BTags'            , 'buffer tags'],
    \ 'w' : [':Windows'          , 'search windows'],
    \ 'y' : [':Filetypes'        , 'file types'],
    \ 'z' : [':FZF'              , 'FZF'],
    \ }

" Register 'which-key' mappings
call which_key#register('<Space>', "g:which_key_map")

