--stylua: ignore start
-- Leader key
vim.g.mapleader = ' '

-- General
vim.opt.hidden       = true     -- Allow switching from unsaved buffer
vim.opt.wrap         = false    -- Display long lines as just one line
vim.opt.encoding     = 'utf-8'  -- Display this encoding
vim.opt.fileencoding = 'utf-8'  -- Use this encoding when writing to file
vim.opt.mouse        = 'a'      -- Enable mouse
vim.opt.backup       = false    -- Don't store backup
vim.opt.writebackup  = false    -- Don't store backup
vim.opt.timeoutlen   = 250      -- Faster response at cost of fast typing
vim.opt.updatetime   = 300      -- Faster CursorHold
vim.opt.switchbuf    = 'usetab' -- Use already opened buffers when switching
vim.opt.modeline     = true     -- Allow modeline

vim.opt.undofile = true                              -- Enable persistent undo
vim.opt.undodir  = vim.fn.expand('$HOME/.config/nvim/misc/undodir') -- Set directory for persistent undo

-- UI
vim.opt.termguicolors = true  -- Enable gui colors
vim.opt.laststatus    = 2     -- Always show statusline
vim.opt.showtabline   = 2     -- Always show tabline
vim.opt.cursorline    = true  -- Enable highlighting of the current line
vim.opt.number        = true  -- Show line numbers
vim.opt.signcolumn    = 'yes' -- Always show signcolumn or it would frequently shift
vim.opt.pumheight     = 10    -- Make popup menu smaller
vim.opt.ruler         = true  -- Always show cursor position
vim.opt.splitbelow    = true  -- Horizontal splits will be below
vim.opt.splitright    = true  -- Vertical splits will be to the right
vim.opt.conceallevel  = 0     -- Don't hide (conceal) special symbols (like `` in markdown)
vim.opt.shortmess:append('c') -- Don't pass messages to 'ins-completion-menu'
vim.opt.shortmess:append('F') -- Don't give the file info when editing a file
vim.opt.incsearch     = true  -- Show search results while typing
vim.opt.showmode      = false -- Don't show things like --INSERT -- (it is handled in statusline)
vim.opt.colorcolumn   = '+1'  -- Draw colored column one step to the right of desired maximum width
vim.opt.winwidth      = 80    -- Use this as reference window width
vim.opt.linebreak     = true  -- Wrap long lines at 'breakat' (if 'wrap' is set)

-- Colors
vim.opt.background = 'dark'         -- Use dark background
vim.cmd([[syntax enable]])          -- Enable syntax highlighing

vim.cmd([[colorscheme minischeme]]) -- Use custom 'minischeme' color scheme
---- Other interesting color schemes:
---- - 'morhetz/gruvbox'
---- - 'rakr/vim-one'
---- - 'ayu-theme/ayu-vim' (use `let ayucolor = 'mirage'`)
---- - 'arcticicestudio/nord-vim'

-- Editing
vim.opt.expandtab   = true    -- Convert tabs to spaces
vim.opt.tabstop     = 2       -- Insert 2 spaces for a tab
vim.opt.smarttab    = true    -- Make tabbing smarter (will realize you have 2 vs 4)
vim.opt.shiftwidth  = 2       -- Use this number of spaces for indentation
vim.opt.smartindent = true    -- Make indenting smart
vim.opt.autoindent  = true    -- Use auto indent
vim.opt.iskeyword:append('-') -- Treat dash separated words as a word text object
vim.opt.virtualedit = 'block' -- Allow going past the end of line in visual block mode
vim.opt.startofline = false   -- Don't position cursor on line start after certain operations
vim.opt.breakindent = true    -- Indent wrapped lines to match line start

vim.opt.completeopt = { 'menu', 'noinsert', 'noselect' } -- Customize completions

-- Spelling
vim.opt.spelllang    = 'en,ru'    -- Define spelling dictionaries
vim.opt.complete:append('kspell') -- Add spellcheck options for autocomplete
vim.opt.spelloptions = 'camel'    -- Treat parts of camelCase words as seprate words

vim.opt.dictionary = vim.fn.expand('$HOME/.config/nvim/misc/dict/english.txt') -- Use specific dictionaries

---- Define pattern for a start of 'numbered' list. This is responsible for
---- correct formatting of lists when using `gq`. This basically reads as 'one
---- of: 1) space + character + `.` or `)` + space; 2) space + `-` or `+` or
---- `*` + space. Source: https://stackoverflow.com/a/37172060
vim.opt.formatlistpat = [[^\\s*\\w\\+[.\)]\\s\\+\\\\|^\\s*[\\-\\+\\*]\\+\\s\\+]]

-- Folds
vim.opt.foldenable  = true     -- Enable folding by default
vim.opt.foldmethod  = 'indent' -- Set 'indent' folding method
vim.opt.foldlevel   = 0        -- Display all folds
vim.opt.foldnestmax = 10       -- Create folds only for some number of nested levels
vim.opt.foldcolumn  = '0'      -- Disable fold column

-- Filetype plugins and indentation
vim.cmd([[filetype plugin indent on]])

-- Syntax highlighing
vim.cmd([[syntax enable]])

-- Custom autocommands
vim.cmd([[augroup CustomSettings]])
  vim.cmd([[autocmd!]])

  -- Don't auto-wrap comments and don't insert comment leader after hitting 'o'
  vim.cmd([[autocmd FileType * setlocal formatoptions-=c formatoptions-=o]])
  -- But insert comment leader after hitting <CR> and respect 'numbered' lists
  vim.cmd([[autocmd FileType * setlocal formatoptions+=r formatoptions+=n]])

  -- Allow nested 'default' comment leaders to be treated as comment leader
  vim.cmd([[autocmd FileType * lua pcall(_G.add_nested_comment_leader)]])

  -- Start integrated terminal already in insert mode
  vim.cmd([[autocmd TermOpen * startinsert]])

  -- Highlight yanked text
  vim.cmd([[autocmd TextYankPost * silent! lua vim.highlight.on_yank()]])
vim.cmd([[augroup END]])

-- Paths to important executables
vim.g.python3_host_prog = vim.fn.expand('$HOME/.pyenv/versions/neovim/bin/python3.8')
vim.g.node_host_prog    = vim.fn.expand('$HOME/.nvm/versions/node/v14.15.2/bin/node')
--stylua: ignore end
