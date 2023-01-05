--stylua: ignore start
-- Leader key =================================================================
vim.g.mapleader = ' '

-- General ====================================================================
vim.go.wrap         = false          -- Display long lines as just one line
vim.go.mouse        = 'a'            -- Enable mouse
vim.go.mousescroll  = 'ver:25,hor:6' -- Customize mouse scroll
vim.go.backup       = false          -- Don't store backup
vim.go.writebackup  = false          -- Don't store backup
vim.go.timeoutlen   = 250            -- Faster response at cost of fast typing
vim.go.updatetime   = 300            -- Faster CursorHold
vim.go.switchbuf    = 'usetab'       -- Use already opened buffers when switching

vim.go.undofile = true                              -- Enable persistent undo
vim.go.undodir  = vim.fn.expand('$HOME/.config/nvim/misc/undodir') -- Set directory for persistent undo

-- UI =========================================================================
vim.go.termguicolors = true    -- Enable gui colors
vim.go.laststatus    = 2       -- Always show statusline
vim.go.showtabline   = 2       -- Always show tabline
vim.go.cursorline    = true    -- Enable highlighting of the current line
vim.go.number        = true    -- Show line numbers
vim.go.signcolumn    = 'yes'   -- Always show signcolumn or it would frequently shift
vim.go.pumheight     = 10      -- Make popup menu smaller
vim.go.ruler         = false   -- Don't show cursor position
vim.go.splitbelow    = true    -- Horizontal splits will be below
vim.go.splitright    = true    -- Vertical splits will be to the right
vim.go.incsearch     = true    -- Show search results while typing
vim.go.colorcolumn   = '+1'    -- Draw colored column one step to the right of desired maximum width
vim.go.linebreak     = true    -- Wrap long lines at 'breakat' (if 'wrap' is set)
vim.go.shortmess     = 'aoOFc' -- Disable certain messages from |ins-completion-menu|
vim.go.showmode      = false   -- Don't show mode in command line
vim.go.list          = true    -- Show helpful character indicators

vim.go.fillchars = 'eob: ,fold:╌,horiz:═,horizdown:╦,horizup:╩,vert:║,verthoriz:╬,vertleft:╣,vertright:╠'
vim.go.listchars = 'extends:»,precedes:«,nbsp:␣,tab:> '

if vim.fn.has('nvim-0.9') == 1 then
  -- Don't show "Scanning..." messages (improves 'mini.completion')
  vim.opt.shortmess:append('C')

  vim.go.cmdheight = 0
end

-- Colors =====================================================================
-- Enable syntax highlighing if it wasn't already (as it is time consuming)
-- Don't use defer it because it affects start screen appearance
if vim.fn.exists("syntax_on") ~= 1 then
  vim.cmd([[syntax enable]])
end

-- Use colorscheme later when its plugin is enabled
-- Use `nested` to allow `ColorScheme` event
vim.cmd([[au VimEnter * nested ++once colorscheme minicyan]])
vim.cmd([[au ColorScheme * hi! link WinSeparator NormalFloat]])

-- Other interesting color schemes:
-- - 'morhetz/gruvbox'
-- - 'ayu-theme/ayu-vim' (use `let ayucolor = 'mirage'`)
-- - 'sainnhe/everforest'
-- - 'EdenEast/nightfox.nvim' ('terafox' in particular)

-- Editing ====================================================================
vim.go.expandtab   = true     -- Convert tabs to spaces
vim.go.tabstop     = 2        -- Insert 2 spaces for a tab
vim.go.shiftwidth  = 2        -- Use this number of spaces for indentation
vim.go.smartindent = true     -- Make indenting smart
vim.go.autoindent  = true     -- Use auto indent
vim.go.virtualedit = 'block'  -- Allow going past the end of line in visual block mode
vim.go.breakindent = true     -- Indent wrapped lines to match line start
vim.go.ignorecase  = true     -- Ignore case when searching (use `\C` to force not doing that)
vim.go.smartcase   = true     -- Don't ignore case when searching if pattern has upper case
vim.opt.iskeyword:append('-') -- Treat dash separated words as a word text object

vim.go.completeopt = 'menuone,noinsert,noselect' -- Customize completions

vim.go.formatoptions = 'rqnl1j'

-- Spelling ===================================================================
vim.go.spelllang    = 'en,ru,uk'  -- Define spelling dictionaries
vim.go.spelloptions = 'camel'     -- Treat parts of camelCase words as seprate words
vim.opt.complete:append('kspell') -- Add spellcheck options for autocomplete
vim.opt.complete:remove('t')      -- Don't use tags for completion

vim.go.dictionary = vim.fn.expand('$HOME/.config/nvim/misc/dict/english.txt') -- Use specific dictionaries

-- Define pattern for a start of 'numbered' list. This is responsible for
-- correct formatting of lists when using `gw`. This basically reads as 'at
-- least one special character (digit, -, +, *) possibly followed some
-- punctuation (. or `)`) followed by at least one space is a start of list
-- item'
vim.go.formatlistpat = [[^\s*[0-9\-\+\*]\+[\.\)]*\s\+]]

-- Folds ======================================================================
vim.go.foldenable   = true     -- Enable folding by default
vim.go.foldmethod   = 'indent' -- Set 'indent' folding method
vim.go.foldlevel    = 1        -- Display all folds except top ones
vim.go.foldnestmax  = 10       -- Create folds only for some number of nested levels
vim.go.foldcolumn   = '0'      -- Disable fold column

-- Filetype plugins and indentation ===========================================
-- Don't defer it because it might break `FileType` related autocommands
vim.cmd([[filetype plugin indent on]])

-- Custom autocommands ========================================================
vim.cmd([[augroup CustomSettings]])
  vim.cmd([[autocmd!]])

  -- Don't auto-wrap comments and don't insert comment leader after hitting 'o'
  -- If don't do this on `FileType`, this keeps magically reappearing.
  vim.cmd([[autocmd FileType * setlocal formatoptions-=c formatoptions-=o]])

  -- Start integrated terminal already in insert mode
  vim.cmd([[autocmd TermOpen * startinsert]])

  -- Highlight yanked text
  vim.cmd([[autocmd TextYankPost * silent! lua vim.highlight.on_yank()]])

  -- Show relative line numbers only when they matter
  vim.cmd([[autocmd ModeChanged [V\x16]*:* let &l:rnu = mode() =~# '^[V\x16]']])
  vim.cmd([[autocmd ModeChanged *:[V\x16]* let &l:rnu = mode() =~# '^[V\x16]']])
  vim.cmd([[autocmd WinEnter,WinLeave * let &l:rnu = mode() =~# '^[V\x16]']])
vim.cmd([[augroup END]])
--stylua: ignore end
