" This is a slightly modified version of this original source:
" https://www.blog.gambitaccepted.com/2020/04/26/neovim-qtconsole-setup/
function CreateQtConsole()
  call jobstart("jupyter qtconsole --JupyterWidget.include_other_output=True --style='solarized-light'")
endfunction

let g:ipy_celldef = '^##' " regex for cell start and end

" Qt Console connection.
" To create working connection, execute both keybindings (second after console
" is created).
" **Note**: Qt Console is opened with Python interpreter that is used in
" terminal when opened NeoVim (i.e. output of `which python`). As a
" consequence, if that Python interpreter doesn't have 'jupyter' or
" 'qtconsole' installed, Qt Console will not be created.
nmap <silent> <Leader>jq :call CreateQtConsole()<CR>
nmap <silent> <Leader>jk :IPython<Space>--existing<Space>--no-window<CR>

" Execution
" Execute current line and go down by one line
nmap <silent> <Leader>j   <Plug>(IPy-Run)j
" Execute selection and go down by one line after the end of selection
vmap <silent> <Leader>j   <Plug>(IPy-Run)'>j
nmap <silent> <Leader>jc  <Plug>(IPy-RunCell)
nmap <silent> <Leader>ja  <Plug>(IPy-RunAll)

" One can also setup a completion connection (generate a completion list
" inside NeoVim but options taken from IPython session), but it seems to be a
" bad practice methodologically.
" imap <silent> <C-k> <Cmd>call IPyComplete()<cr>
"   " This one should be used only when inside Insert mode after <C-o>
" nmap <silent> <Leader>jj <Cmd>call IPyComplete()<cr>
