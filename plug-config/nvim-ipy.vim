" **After initial install, run `:UpdateRemotePlugins`**. If not, 'E117:
" Unknown function: IPyConnect' error will be shown.
" To run it, `g:python3_host_prog` should point to Python interpreter needs to
" have **both** 'pynvim' and 'jupyter' installed. There are two possible
" solutions:
" - Install 'jupyter' to default interpreter (which is already set in
"   `g:python3_host_prog`).
" - Temporarily have `g:python3_host_prog` point to interpreter in separate
"   environment with installed 'pynvim' and 'jupyter'.
" It doesn't seem to be necessary to have 'jupyter' installed in interpreter
" stored in `g:python3_host_prog`.

" If you see 'AttributeError: 'IPythonPlugin' object has no attribute 'km''
" error, it might mean that no connection with `:IPython` was done.  In
" present setup, it means you forgot to type `<Leader>ik` after `<Leader>iq`.

" This setup is a slightly modified version of this original source:
" https://www.blog.gambitaccepted.com/2020/04/26/neovim-qtconsole-setup/
function CreateQtConsole()
  call jobstart("jupyter qtconsole --JupyterWidget.include_other_output=True --style='solarized-light'")
endfunction

let g:ipy_celldef = '^##' " regex for cell start and end
let g:nvim_ipy_perform_mappings = 0

" Extra information about leader mappings are stored in
" 'general/mappings-leader.vim'

