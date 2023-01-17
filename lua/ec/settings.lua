--stylua: ignore start
-- Leader key =================================================================
vim.g.mapleader = ' '

-- General ====================================================================
vim.o.wrap         = false          -- Display long lines as just one line
vim.o.mouse        = 'a'            -- Enable mouse
vim.o.mousescroll  = 'ver:25,hor:6' -- Customize mouse scroll
vim.o.backup       = false          -- Don't store backup
vim.o.writebackup  = false          -- Don't store backup
vim.o.timeoutlen   = 250            -- Faster response at cost of fast typing
vim.o.updatetime   = 300            -- Faster CursorHold and more frequent swap writing
vim.o.switchbuf    = 'usetab'       -- Use already opened buffers when switching

vim.o.undofile = true                              -- Enable persistent undo
vim.o.undodir  = vim.fn.expand('$HOME/.config/nvim/misc/undodir') -- Set directory for persistent undo

-- UI =========================================================================
vim.o.termguicolors = true    -- Enable gui colors
vim.o.laststatus    = 2       -- Always show statusline
vim.o.showtabline   = 2       -- Always show tabline
vim.o.cursorline    = true    -- Enable highlighting of the current line
vim.o.number        = true    -- Show line numbers
vim.o.signcolumn    = 'yes'   -- Always show signcolumn or it would frequently shift
vim.o.pumheight     = 10      -- Make popup menu smaller
vim.o.ruler         = false   -- Don't show cursor position
vim.o.splitbelow    = true    -- Horizontal splits will be below
vim.o.splitright    = true    -- Vertical splits will be to the right
vim.o.incsearch     = true    -- Show search results while typing
vim.o.colorcolumn   = '+1'    -- Draw colored column one step to the right of desired maximum width
vim.o.linebreak     = true    -- Wrap long lines at 'breakat' (if 'wrap' is set)
vim.o.shortmess     = 'aoOFc' -- Disable certain messages from |ins-completion-menu|
vim.o.showmode      = false   -- Don't show mode in command line
vim.o.list          = true    -- Show helpful character indicators
vim.o.winblend      = 10      -- Make floating windows slightly transparent
vim.o.pumblend      = 10      -- Make builtin completion menus slightly transparent

vim.o.fillchars = 'eob: ,fold:╌,horiz:═,horizdown:╦,horizup:╩,vert:║,verthoriz:╬,vertleft:╣,vertright:╠'
vim.o.listchars = 'extends:…,precedes:…,nbsp:␣,tab:> '

if vim.fn.has('nvim-0.9') == 1 then
  -- Don't show "Scanning..." messages (improves 'mini.completion')
  vim.opt.shortmess:append('C')

  vim.o.splitkeep = 'screen'

  vim.o.cmdheight = 0
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
vim.cmd([[au ColorScheme * hi PmenuSel blend=0]])

-- Other interesting color schemes:
-- - 'morhetz/gruvbox'
-- - 'ayu-theme/ayu-vim' (use `let ayucolor = 'mirage'`)
-- - 'sainnhe/everforest'
-- - 'EdenEast/nightfox.nvim' ('terafox' in particular)

-- Editing ====================================================================
vim.o.expandtab   = true     -- Convert tabs to spaces
vim.o.tabstop     = 2        -- Insert 2 spaces for a tab
vim.o.shiftwidth  = 2        -- Use this number of spaces for indentation
vim.o.smartindent = true     -- Make indenting smart
vim.o.autoindent  = true     -- Use auto indent
vim.o.virtualedit = 'block'  -- Allow going past the end of line in visual block mode
vim.o.breakindent = true     -- Indent wrapped lines to match line start
vim.o.ignorecase  = true     -- Ignore case when searching (use `\C` to force not doing that)
vim.o.smartcase   = true     -- Don't ignore case when searching if pattern has upper case
vim.o.infercase   = true     -- Infer letter cases for a richer built-in keyword completion
vim.opt.iskeyword:append('-') -- Treat dash separated words as a word text object

vim.o.completeopt = 'menuone,noinsert,noselect' -- Customize completions

vim.o.formatoptions = 'rqnl1j'

-- Spelling ===================================================================
vim.o.spelllang    = 'en,ru,uk'  -- Define spelling dictionaries
vim.o.spelloptions = 'camel'     -- Treat parts of camelCase words as seprate words
vim.opt.complete:append('kspell') -- Add spellcheck options for autocomplete
vim.opt.complete:remove('t')      -- Don't use tags for completion

vim.o.dictionary = vim.fn.expand('$HOME/.config/nvim/misc/dict/english.txt') -- Use specific dictionaries

-- Define pattern for a start of 'numbered' list. This is responsible for
-- correct formatting of lists when using `gw`. This basically reads as 'at
-- least one special character (digit, -, +, *) possibly followed some
-- punctuation (. or `)`) followed by at least one space is a start of list
-- item'
vim.o.formatlistpat = [[^\s*[0-9\-\+\*]\+[\.\)]*\s\+]]

-- Folds ======================================================================
vim.o.foldenable   = true     -- Enable folding by default
vim.o.foldmethod   = 'indent' -- Set 'indent' folding method
vim.o.foldlevel    = 1        -- Display all folds except top ones
vim.o.foldnestmax  = 10       -- Create folds only for some number of nested levels
vim.o.foldcolumn   = '0'      -- Disable fold column

-- Filetype plugins and indentation ===========================================
-- Don't defer it because it might break `FileType` related autocommands
vim.cmd([[filetype plugin indent on]])

-- Custom autocommands ========================================================
vim.cmd([[augroup CustomSettings]])
  vim.cmd([[autocmd!]])

  -- Don't auto-wrap comments and don't insert comment leader after hitting 'o'
  -- If don't do this on `FileType`, this keeps magically reappearing.
  vim.cmd([[autocmd FileType * setlocal formatoptions-=c formatoptions-=o]])

  -- Start builtin terminal in Insert mode
  -- Note: always entering Insert mode in terminal buffer seems like an
  -- antipattern. Its `BufEnter` autocommand implementation might also bring
  -- scheduling problems when quickly enter and exit terminal buffer.
  vim.cmd([[autocmd TermOpen * startinsert]])

  -- Highlight yanked text
  vim.cmd([[autocmd TextYankPost * silent! lua vim.highlight.on_yank()]])

  -- Show relative line numbers only when they matter (linewise and blockwise
  -- selection) and 'number' is set (avoids horizontal flickering)
  vim.cmd([[autocmd ModeChanged *:[V\x16]* let &l:relativenumber = &l:number == 1]])
  -- - Using `mode () =~#...` handles switching between linewise and blockwise mode.
  vim.cmd([[autocmd ModeChanged [V\x16]*:* let &l:relativenumber = mode() =~# '^[V\x16]']])
  -- - This is a part of example in `:h ModeChanged`, but I am yet to find the
  --   use case for it, as it seems like working fine without it.
  -- vim.cmd([[autocmd WinEnter,WinLeave    * let &l:relativenumber = mode() =~# '^[V\x16]']])
vim.cmd([[augroup END]])
--stylua: ignore end
