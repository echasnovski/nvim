" auto-install vim-plug
if empty(glob('~/.config/nvim/autoload/plug.vim'))
  silent !curl -fLo ~/.config/nvim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  "autocmd VimEnter * PlugInstall
  "autocmd VimEnter * PlugInstall | source $MYVIMRC
endif

call plug#begin('~/.config/nvim/autoload/plugged')

  " Surround with (), [], "", etc.
  Plug 'machakann/vim-sandwich'

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

  " Pairs of handy bracket mappings
  Plug 'tpope/vim-unimpaired'

  if has("nvim-0.5") == 0
    " Python movements and text objects
    Plug 'jeetsukumaran/vim-pythonsense'
  endif

  if !exists('g:vscode')
    " Neovim version-specific sets of plugins
    if has("nvim-0.5")
      "" Fuzzy finder for future
      " Plug 'nvim-lua/popup.nvim'
      " Plug 'nvim-lua/plenary.nvim'
      " Plug 'nvim-telescope/telescope.nvim'

      "" Completion
      Plug 'nvim-lua/completion-nvim'
      "" Other option of completion. Some say that it is far faster on big
      "" projects than 'completion-nvim'. For suggested configuration see
      "" README on Github. There were some problems which I didn't find a way
      "" to solve:
      "" - Hard to setup other sources of completion. For example, completion
      ""   from open buffers. Currently under discussion:
      ""   https://github.com/hrsh7th/nvim-compe/issues/147
      "" - No popup with function signature when typing inside `()`. This is
      ""   currently out of scope:
      ""   https://github.com/hrsh7th/nvim-compe/issues/120#issuecomment-777333663
      " Plug 'hrsh7th/nvim-compe'

      "" Language server
      Plug 'neovim/nvim-lspconfig'

      "" Code formatter
      Plug 'sbdchd/neoformat'

      "" Treesitter: incremental parsing of file
      "" Deals with highlighting and specific textobjects
      Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
      Plug 'nvim-treesitter/nvim-treesitter-textobjects'
      " Plug 'nvim-treesitter/playground'

      "" Colorful icons
      Plug 'kyazdani42/nvim-web-devicons'

      "" File tree explorer
      " Plug 'kyazdani42/nvim-tree.lua'
    else
      "" Intellisense
      Plug 'neoclide/coc.nvim', {'branch': 'release'}

      "" Linting and fixing (autoformatting, etc.)
      " Plug 'dense-analysis/ale'

      "" Semantic code highlighting for Python files
      Plug 'numirias/semshi', {'do': ':UpdateRemotePlugins'}

      "" Useful icons
      Plug 'ryanoasis/vim-devicons'

      "" Statusline and bufferline
      Plug 'vim-airline/vim-airline'
    endif

    " General
    "" fzf support
    Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
    Plug 'junegunn/fzf.vim'

    "" Session manager
    Plug 'mhinz/vim-startify'

    "" Update file system working directory
    Plug 'airblade/vim-rooter'

    "" File Explorer
    Plug 'kevinhwang91/rnvimr'

    "" Tweak Neovim's terminal to be more REPL-aware
    Plug 'kassio/neoterm'

    "" Git integration
    Plug 'tpope/vim-fugitive'
    Plug 'junegunn/gv.vim'
    Plug 'airblade/vim-gitgutter'
    """ Lua alternative of 'vim-gitgutter'. Currently is very slow on big
    """ files:
    " Plug 'lewis6991/gitsigns.nvim'

    "" Show keybindings
    Plug 'liuchengxu/vim-which-key'

    "" Visualize undo-tree
    Plug 'mbbill/undotree'

    "" Work with tags
    " Plug 'ludovicchabant/vim-gutentags'

    "" Snippets
    Plug 'SirVer/ultisnips'
    Plug 'honza/vim-snippets'

    " "" Possible alternative
    " Plug 'hrsh7th/vim-vsnip'
    " Although recommended, currently doesn't seem to be needed
    " Plug 'hrsh7th/vim-vsnip-integ'

    " Appearence
    "" Grubvox theme
    Plug 'morhetz/gruvbox'

    "" Other possible themes (from most to least) if got bored with gruvbox
    " "" Onedark
    " Plug 'rakr/vim-one'
    " "" Ayu
    " "" NOTE: use `let ayucolor = 'mirage'`
    " Plug 'ayu-theme/ayu-vim'
    " "" Nord
    " Plug 'arcticicestudio/nord-vim'

    "" Show colors
    Plug 'norcalli/nvim-colorizer.lua'

    " Languages workflow
    "" Better Syntax Support (has rather big disk size usage, around 10M)
    "" This should be included before loading 'polyglot'
    "" See https://github.com/sheerun/vim-polyglot#troubleshooting and
    "" https://github.com/sheerun/vim-polyglot/issues/546
    let g:polyglot_disabled = ["csv", "python", "python-indent", "python-compiler", "r-lang"]
    Plug 'sheerun/vim-polyglot'

    "" Documentation generator
    Plug 'kkoomen/vim-doge', { 'do': { -> doge#install() } }

    "" Test runner
    Plug 'vim-test/vim-test'
    """ Currently used only for populating quickfix list with test results
    Plug 'tpope/vim-dispatch'

    "" IPython integration
    Plug 'bfredl/nvim-ipy'

    "" Work with Jupyter
    Plug 'goerz/jupytext.vim'

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

    " Future possibilities
    " "" Find and replace
    " Plug 'brooth/far.vim'

    " " Git message under cursor
    " Plug 'rhysd/git-messenger.vim'
  endif

call plug#end()

