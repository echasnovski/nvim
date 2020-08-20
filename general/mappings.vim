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

" Copy to system clipboard
vmap <C-c> "+y

" Write current buffer with sudo privileges
cmap w!! w !sudo tee %

" Move with <Alt-hjkl> in non-normal mode
inoremap <M-h> <Left>
inoremap <M-j> <Down>
inoremap <M-k> <Up>
inoremap <M-l> <Right>
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
  nmap <Tab> :Tabnext<CR>
  nmap <S-Tab> :Tabprev<CR>
else
  " TAB in general mode will move to text buffer
  nnoremap <silent> <TAB> :bnext<CR>
  " SHIFT-TAB will go back
  nnoremap <silent> <S-TAB> :bprevious<CR>
endif

" Better window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
"" Go to previous window (very useful with "pop-up" 'coc.nvim' documentation)
nnoremap <C-p> <C-w>p
"" When in terminal, use this as escape to normal mode (might be handy when
"" followed by <C-l> to, almost always, return to terminal)
tnoremap <C-h> <C-\><C-N><C-w>h

" Use alt + hjkl to resize windows
nnoremap <silent> <M-j>    :resize -2<CR>
nnoremap <silent> <M-k>    :resize +2<CR>
nnoremap <silent> <M-h>    :vertical resize -2<CR>
nnoremap <silent> <M-l>    :vertical resize +2<CR>

" Alternate way to save
nnoremap <C-s> :w<CR>
inoremap <C-s> <Esc>:w<CR>

" Go into completion list with <TAB>
inoremap <silent> <expr><TAB> pumvisible() ? "\<C-n>" : "\<TAB>"

" Extra jumps between folds
"" Jump to the beginning of previous fold
nnoremap zK zk[z
"" Jump to the end of next fold
nnoremap zJ zj]z

" " These mappings are useful to quickly go in insert mode at certain place or
" " in terminal window after scrolling
" nnoremap <RightMouse>   <LeftMouse>:startinsert<CR>
" nnoremap <RightRelease> <LeftMouse>:startinsert<CR>
" inoremap <RightMouse>   <LeftMouse>
" inoremap <RightRelease> <LeftMouse>
