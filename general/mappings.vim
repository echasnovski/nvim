" Russian keyboard mappings
set langmap=ё№йцукенгшщзхъфывапролджэячсмитьбюЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ;`#qwertyuiop[]asdfghjkl\\;'zxcvbnm\\,.~QWERTYUIOP{}ASDFGHJKL:\\"ZXCVBNM<>

nmap Ж :
" yank
nmap Н Y
nmap з p
nmap ф a
nmap щ o
nmap г u
nmap З P

" Disable `s` shortcut (as it can be replaced with `cl`) for safer usage of
" 'sandwich.vim'
nmap s <Nop>
xmap s <Nop>

" Copy to system clipboard
vmap <C-c> "+y

" Write current buffer with sudo privileges
cmap w!! w !sudo tee %

" Move with <Alt-hjkl> in non-normal mode
imap <M-h> <Left>
imap <M-j> <Down>
imap <M-k> <Up>
imap <M-l> <Right>
tnoremap <M-h> <Left>
tnoremap <M-j> <Down>
tnoremap <M-k> <Up>
tnoremap <M-l> <Right>
"" Move only sideways in command mode
cnoremap <M-h> <Left>
cnoremap <M-l> <Right>

" Move between buffers
if exists('g:vscode')
  " Simulate same TAB behavior in VSCode
  nmap ]b <cmd>Tabnext<CR>
  nmap [b <cmd>Tabprev<CR>
else
  " This duplicates code from 'vim-unimpaired' (just in case)
  nnoremap <silent> ]b <cmd>bnext<CR>
  nnoremap <silent> [b <cmd>bprevious<CR>
endif

" Better window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
"" Go to previous window (very useful with 'pop-up' function documentation)
nnoremap <C-p> <C-w>p
"" When in terminal, use this as escape to normal mode (might be handy when
"" followed by <C-l> to, almost always, return to terminal)
tnoremap <C-h> <C-\><C-N><C-w>h

" Use alt + hjkl to resize windows
nnoremap <silent> <M-j> <cmd>resize -2<CR>
nnoremap <silent> <M-k> <cmd>resize +2<CR>
nnoremap <silent> <M-h> <cmd>vertical resize -2<CR>
nnoremap <silent> <M-l> <cmd>vertical resize +2<CR>

" Alternative way to save
nnoremap <C-s> <cmd>w<CR>
inoremap <C-s> <Esc><cmd>w<CR>

" Move inside completion list with <TAB>
inoremap <silent> <expr><TAB> pumvisible() ? "\<C-n>" : "\<TAB>"
inoremap <silent> <expr><S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

" Extra jumps between folds
"" Jump to the beginning of previous fold
nnoremap zK zk[z
"" Jump to the end of next fold
nnoremap zJ zj]z

" Reselect previously changed, put or yanked text
nnoremap gV `[v`]

" " These mappings are useful to quickly go in insert mode at certain place or
" " in terminal window after scrolling
" nnoremap <RightMouse>   <LeftMouse>:startinsert<CR>
" nnoremap <RightRelease> <LeftMouse>:startinsert<CR>
" inoremap <RightMouse>   <LeftMouse>
" inoremap <RightRelease> <LeftMouse>

" Make `q:` do nothing instead of opening command-line-window, because it is
" often hit by accident
" Use c_CTRL-F or fzf's analogue
nnoremap q: <nop>

" Search visually highlighted text
vnoremap <silent> g/ y/\V<C-R>=escape(@",'/\')<CR><CR>

" Stop highlighting of search results
nnoremap <silent> // :nohlsearch<C-R>=has('diff')?'<BAR>diffupdate':''<CR><CR>

" Delete selection in Select mode (helpful when editing snippet placeholders)
snoremap <silent> <BS> <BS>i
