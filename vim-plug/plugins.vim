" auto-install vim-plug
if empty(glob('~/.config/nvim/autoload/plug.vim'))
  silent !curl -fLo ~/.config/nvim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  "autocmd VimEnter * PlugInstall
  "autocmd VimEnter * PlugInstall | source $MYVIMRC
endif

call plug#begin('~/.config/nvim/autoload/plugged')

    " Surround with (), [], "", etc.
    Plug 'tpope/vim-surround'

    " More text objects
    Plug 'wellle/targets.vim'

    " Python movements and text objects
    Plug 'jeetsukumaran/vim-pythonsense'
    
    if !exists('g:vscode')
        " Grubvox theme
        Plug 'morhetz/gruvbox'

        " Intellisense
        Plug 'neoclide/coc.nvim', {'branch': 'release'}

        " Better Syntax Support
        Plug 'sheerun/vim-polyglot'

        " Semantic code highlighting for Python files
        Plug 'numirias/semshi', {'do': ':UpdateRemotePlugins'}

        " File Explorer
        Plug 'scrooloose/NERDTree'

        " Auto pairs for '(' '[' '{'
        Plug 'jiangmiao/auto-pairs'

        " Parenthesis coloring
        Plug 'luochen1990/rainbow'

        " Commenting
        Plug 'tpope/vim-commentary'
    endif

call plug#end()

