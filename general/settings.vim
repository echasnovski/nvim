" Use more convenient (for me) exclusive visual selection
set selection=exclusive

set iskeyword+=-         " Treat dash separated words as a word text object "
set formatoptions-=cro   " Stop newline continution of comments

if !exists('g:vscode')

  syntax enable          " Enables syntax highlighing
  set hidden             " Required to keep multiple buffers open multiple buffers
  set nowrap             " Display long lines as just one line
  set encoding=utf-8     " The encoding displayed
  set pumheight=10       " Makes popup menu smaller
  set fileencoding=utf-8 " The encoding written to file
  set ruler              " Show the cursor position all the time
  set cmdheight=2        " More space for displaying messages
  set mouse=a            " Enable your mouse
  set splitbelow         " Horizontal splits will automatically be below
  set splitright         " Vertical splits will automatically be to the right
  set t_Co=256           " Support 256 colors
  set conceallevel=0     " So that I can see `` in markdown files
  set tabstop=2          " Insert 2 spaces for a tab
  set shiftwidth=2       " Change the number of space characters inserted for indentation
  set smarttab           " Makes tabbing smarter will realize you have 2 vs 4
  set expandtab          " Converts tabs to spaces
  set smartindent        " Makes indenting smart
  set autoindent         " Good auto indent
  set laststatus=2       " Always display the status line
  set number             " Line numbers
  set cursorline         " Enable highlighting of the current line
  set background=dark    " Tell vim what the background color looks like
  set showtabline=2      " Always show tabs
  set noshowmode         " We don't need to see things like -- INSERT -- anymore
  set nobackup           " This is recommended by coc
  set nowritebackup      " This is recommended by coc
  set shortmess+=c       " Don't pass messages to |ins-completion-menu|
  set signcolumn=yes     " Always show the signcolumn, otherwise it would shift the text each time
  set updatetime=300     " Faster completion
  set timeoutlen=250     " By default timeoutlen is 1000 ms. Not 100, because vim-commentary breaks
  set incsearch          " Show search results while typing
  set noshowmode         " Don't show things like -- INSERT -- (it is handled by vim-airline)
  set termguicolors      " Enable gui colors
  set switchbuf=usetab   " Use already opened buffers when switching
  set colorcolumn=+1     " Draw colored column one step to the right of desired maximum width
  set virtualedit=block  " Allow going past the end of line in visual block mode

  set undofile                           " Enable persistent undo
  set undodir=$HOME/.config/nvim/undodir " Set directory for persistent undo

  " Enable filetype plugins and indentation
  filetype plugin indent on

  " Don't auto-wrap comments and don't insert comment leader after hitting 'o'
  autocmd FileType * setlocal formatoptions-=c formatoptions-=o
  " But insert comment leader after hitting <CR>
  autocmd FileType * setlocal formatoptions+=r

  " Start integrated terminal already in insert mode
  autocmd TermOpen * startinsert

  " You can't stop me
  cmap w!! w !sudo tee %

  let g:python3_host_prog = expand("~/.pyenv/versions/neovim/bin/python3.8")
  let g:node_host_prog = expand("~/.nvm/versions/node/v12.18.2/bin/node")

endif
