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

        " Status bar
        Plug 'vim-airline/vim-airline'

        " Intellisense
        Plug 'neoclide/coc.nvim', {'branch': 'release'}

        " fzf support
        Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
        Plug 'junegunn/fzf.vim'

        " Manage sessions
        Plug 'mhinz/vim-startify'

        " Update file system working directory
        Plug 'airblade/vim-rooter'

        " File Explorer
        Plug 'scrooloose/NERDTree'

        " Tweak Neovim's terminal to be more REPL-aware
        Plug 'kassio/neoterm'

        " Git integration
        Plug 'tpope/vim-fugitive'
        Plug 'airblade/vim-gitgutter'
        Plug 'junegunn/gv.vim'
        Plug 'xuyuanp/nerdtree-git-plugin'

        " Show keybindings
        Plug 'liuchengxu/vim-which-key'

        " Better Syntax Support (has rather big disk size usage, around 10M)
        Plug 'sheerun/vim-polyglot'

        " Documentation generator
        Plug 'kkoomen/vim-doge'

        " IPython integration
        Plug 'bfredl/nvim-ipy'

        " Semantic code highlighting for Python files
        Plug 'numirias/semshi', {'do': ':UpdateRemotePlugins'}

        " Useful icons
        Plug 'ryanoasis/vim-devicons'

        " Auto pairs for '(' '[' '{'
        Plug 'jiangmiao/auto-pairs'

        " Show and remove whitespace
        Plug 'ntpeters/vim-better-whitespace'

        " Commenting
        Plug 'tpope/vim-commentary'

        " Tabularize text
        Plug 'godlygeek/tabular'

        " Work with csv
        Plug 'mechatroner/rainbow_csv'

        " Pandoc
        "" This option should be set before loading plugin to take effect
        "" See https://github.com/vim-pandoc/vim-pandoc/issues/342
        let g:pandoc#filetypes#pandoc_markdown = 0
        Plug 'vim-pandoc/vim-pandoc'
        Plug 'vim-pandoc/vim-pandoc-syntax'

        " Work with markdown
        Plug 'plasticboy/vim-markdown'

        " Markdown preview (has rather big disk size usage, around 50M)
        Plug 'iamcco/markdown-preview.nvim', { 'do': { -> mkdp#util#install() }, 'for': ['markdown', 'vim-plug']}

        " LaTeX (has rather big disk size usage, around 14M)
        Plug 'lervag/vimtex'
    endif

call plug#end()

