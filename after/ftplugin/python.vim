setlocal colorcolumn=89 " Show line after desired maximum text width

" Keybindings
inoremap <buffer> <M-i> <Space>=<Space>

" Indentation
let g:pyindent_open_paren = 'shiftwidth()'
let g:pyindent_continue   = 'shiftwidth()'

" Section insert
function SectionPy()
  " Insert section template
  call append(line("."), "# %% ")

  " Enable Insert mode in appropriate place
  call cursor(line(".")+1, 5)
  startinsert!
endfunction

nnoremap <buffer> <M-s> :call SectionPy()<CR>
inoremap <buffer> <M-s> <C-o>:call SectionPy()<CR>

" Neoformat configuration
let black_root = $HOME . "/.pyenv/versions/neovim/bin/black"

" neoformat config needs to be set up for each tool
let g:neoformat_python_black = {
    \ 'exe': black_root,
    \ 'args': ['-'],
    \ 'stdin': 1
\}
let g:neoformat_enabled_python = ['black']

" " Possible ALE configuration.
" let b:ale_fix_on_save = 1
" let b:ale_fixers = ['black', 'isort']
" let b:ale_python_black_executable = expand('~/.pyenv/versions/neovim/bin/black')

" let b:ale_lint_on_save = 1
" let b:ale_linters = ['pylint']

" Ultisnips configuration
let g:ultisnips_python_quoting_style = "double"
let g:ultisnips_python_style = "numpy"
