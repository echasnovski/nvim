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

" Comment identifiers
set comments=:###,:##,:#

" " Possible ALE configuration.
" let b:ale_fix_on_save = 1
" let b:ale_fixers = ['black', 'isort']
" let b:ale_python_black_executable = expand('~/.pyenv/versions/neovim/bin/black')

" let b:ale_lint_on_save = 1
" let b:ale_linters = ['pylint']
