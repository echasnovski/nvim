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

  " Align text
  Plug 'tommcdo/vim-lion'

  " Wrap function arguments
  Plug 'FooSoft/vim-argwrap'

  " Swap function arguments (and define better 'argument' text object)
  Plug 'AndrewRadev/sideways.vim'

  " Exchange regions
  Plug 'tommcdo/vim-exchange'

  " Python movements and text objects
  Plug 'jeetsukumaran/vim-pythonsense'

  if !exists('g:vscode')
    " General
    "" Intellisense
    Plug 'neoclide/coc.nvim', {'branch': 'release'}

    "" fzf support
    Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
    Plug 'junegunn/fzf.vim'

    "" Session manager
    Plug 'mhinz/vim-startify'

    "" Update file system working directory
    Plug 'airblade/vim-rooter'

    "" File Explorer
    Plug 'scrooloose/NERDTree'
    Plug 'kevinhwang91/rnvimr', {'do': 'make sync'}

    "" Tweak Neovim's terminal to be more REPL-aware
    Plug 'kassio/neoterm'

    "" Git integration
    Plug 'tpope/vim-fugitive'
    Plug 'airblade/vim-gitgutter'
    Plug 'junegunn/gv.vim'
    Plug 'xuyuanp/nerdtree-git-plugin'

    "" Show keybindings
    Plug 'liuchengxu/vim-which-key'

    " Appearence
    "" Grubvox theme
    Plug 'morhetz/gruvbox'

    "" Status bar
    Plug 'vim-airline/vim-airline'

    "" Useful icons
    Plug 'ryanoasis/vim-devicons'

    " Languages workflow
    "" Better Syntax Support (has rather big disk size usage, around 10M)
    Plug 'sheerun/vim-polyglot'

    "" Documentation generator
    Plug 'kkoomen/vim-doge'

    "" Test runner
    Plug 'vim-test/vim-test'
    """ Currently used only for populating quickfix list with test results
    Plug 'tpope/vim-dispatch'

    "" IPython integration
    Plug 'bfredl/nvim-ipy'

    "" Semantic code highlighting for Python files
    Plug 'numirias/semshi', {'do': ':UpdateRemotePlugins'}

    " Text formatting and typing
    "" Auto pairs for '(' '[' '{'
    "" 'pear-tree' provides more intuitive experience than 'auto-pairs':
    "" 'smart opener/closer', not inserting closer when before word, etc.
    Plug 'tmsvg/pear-tree'

    "" Show and remove whitespace
    Plug 'ntpeters/vim-better-whitespace'

    "" Commenting
    Plug 'tpope/vim-commentary'

    " Filetypes
    "" Work with csv
    Plug 'mechatroner/rainbow_csv'

    "" Pandoc and Rmarkdown support
    """ This option should be set before loading plugin to take effect
    """ See https://github.com/vim-pandoc/vim-pandoc/issues/342
    let g:pandoc#filetypes#pandoc_markdown = 0
    Plug 'vim-pandoc/vim-pandoc'
    Plug 'vim-pandoc/vim-pandoc-syntax'
    Plug 'vim-pandoc/vim-rmarkdown'

    "" Work with markdown
    Plug 'plasticboy/vim-markdown'

    "" Markdown preview (has rather big disk size usage, around 50M)
    Plug 'iamcco/markdown-preview.nvim', { 'do': { -> mkdp#util#install() }, 'for': ['markdown', 'vim-plug']}

    "" LaTeX (has rather big disk size usage, around 14M)
    " Plug 'lervag/vimtex'
  endif

call plug#end()

