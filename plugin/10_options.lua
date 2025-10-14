--stylua: ignore start
-- General ====================================================================
vim.g.mapleader = ' ' -- Use `<Space>` as a leader key

vim.o.mouse       = 'a'            -- Enable mouse
vim.o.mousescroll = 'ver:25,hor:6' -- Customize mouse scroll
vim.o.switchbuf   = 'usetab'       -- Use already opened buffers when switching
vim.o.undofile    = true           -- Enable persistent undo

vim.o.shada = "'100,<50,s10,:1000,/100,@100,h" -- Limit ShaDa file (for startup)

-- Enable all filetype plugins and syntax
vim.cmd('filetype plugin indent on')
if vim.fn.exists('syntax_on') ~= 1 then vim.cmd('syntax enable') end

-- UI =========================================================================
vim.o.breakindent    = true       -- Indent wrapped lines to match line start
vim.o.breakindentopt = 'list:-1'  -- Add padding for lists (if 'wrap' is set)
vim.o.colorcolumn    = '+1'       -- Draw column on the right of maximum width
vim.o.cursorline     = true       -- Enable current line highlighting
vim.o.linebreak      = true       -- Wrap lines at 'breakat' (if 'wrap' is set)
vim.o.list           = true       -- Show helpful text indicators
vim.o.number         = true       -- Show line numbers
vim.o.pumheight      = 10         -- Make popup menu smaller
vim.o.ruler          = false      -- Don't show cursor coordinates
vim.o.shortmess      = 'CFOSWaco' -- Disable some built-in completion messages
vim.o.showmode       = false      -- Don't show mode in command line
vim.o.signcolumn     = 'yes'      -- Always show signcolumn (less flicker)
vim.o.splitbelow     = true       -- Horizontal splits will be below
vim.o.splitkeep      = 'screen'   -- Reduce scroll during window split
vim.o.splitright     = true       -- Vertical splits will be to the right
vim.o.wrap           = false      -- Don't visually wrap lines (toggle with \w)

vim.o.cursorlineopt  = 'screenline,number' -- Show cursor line per screen line

-- Special UI symbols
vim.o.fillchars = 'eob: ,fold:╌'
vim.o.listchars = 'extends:…,nbsp:␣,precedes:…,tab:> '

-- Folds (default behavior; see `:h Folding`)
vim.o.foldlevel   = 1        -- Fold everything except top level
vim.o.foldmethod  = 'indent' -- Fold based on indent level
vim.o.foldnestmax = 10       -- Limit number of fold levels

-- Neovim version specific
if vim.fn.has('nvim-0.10') == 0 then
  vim.o.termguicolors = true
end

if vim.fn.has('nvim-0.10') == 1 then
  vim.o.foldtext = '' -- Show text under fold with its highlighting
end

if vim.fn.has('nvim-0.11') == 1 then
  vim.o.winborder = 'double' -- Use border in floating windows

  -- Disable "press-enter" for messages not from manually executing a command
  vim.o.messagesopt = 'wait:500,history:500'
  local make_set_messagesopt = function(value) return vim.schedule_wrap(function() vim.o.messagesopt = value end) end
  _G.Config.new_autocmd('CmdlineEnter', '*', make_set_messagesopt('hit-enter,history:500'))
  _G.Config.new_autocmd('CmdlineLeave', '*', make_set_messagesopt('wait:500,history:500'))
end

if vim.fn.has('nvim-0.12') == 1 then
  vim.o.pummaxwidth = 100 -- Limit maximum width of popup menu
  vim.o.completefuzzycollect = 'keyword,files,whole_line' -- Use fuzzy matching when collecting candidates
  vim.o.completetimeout = 100

  vim.o.pumborder = 'single'

  require('vim._extui').enable({ enable = true })

  -- -- Command line autocompletion
  -- vim.cmd([[autocmd CmdlineChanged [:/\?@] call wildtrigger()]])
  -- vim.o.wildmode = 'noselect:lastused'
  -- vim.o.wildoptions = 'pum,fuzzy'
  -- vim.keymap.set('c', '<Up>', '<C-u><Up>')
  -- vim.keymap.set('c', '<Down>', '<C-u><Down>')
  -- -- TODO: Make this part of 'mini.keymap'
  -- vim.keymap.set('c', '<Tab>', [[cmdcomplete_info().pum_visible ? "\<C-n>" : "\<Tab>"]], { expr = true })
  -- vim.keymap.set('c', '<S-Tab>', [[cmdcomplete_info().pum_visible ? "\<C-p>" : "\<S-Tab>"]], { expr = true })
end

-- Editing ====================================================================
vim.o.autoindent    = true       -- Use auto indent
vim.o.expandtab     = true       -- Convert tabs to spaces
vim.o.formatoptions = 'rqnl1j'   -- Improve comment editing
vim.o.ignorecase    = true       -- Ignore case during search
vim.o.incsearch     = true       -- Show search matches while typing
vim.o.infercase     = true       -- Infer case in built-in completion
vim.o.shiftwidth    = 2          -- Use this number of spaces for indentation
vim.o.smartcase     = true       -- Respect case if search pattern has upper case
vim.o.smartindent   = true       -- Make indenting smart
vim.o.spelllang     = 'en,uk,ru' -- Define spelling dictionaries
vim.o.spelloptions  = 'camel'    -- Treat camelCase word parts as separate words
vim.o.tabstop       = 2          -- Show tab as this number of spaces
vim.o.virtualedit   = 'block'    -- Allow going past end of line in blockwise mode

vim.o.iskeyword = '@,48-57,_,192-255,-' -- Treat dash as `word` textobject part
vim.o.dictionary = vim.fn.stdpath('config') .. '/misc/dict/english.txt' -- Use specific dictionaries

-- Pattern for a start of 'numbered' list (used in `gw`). This reads as
-- "Start of list item is: at least one special character (digit, -, +, *)
-- possibly followed by punctuation (. or `)`) followed by at least one space".
vim.o.formatlistpat = [[^\s*[0-9\-\+\*]\+[\.\)]*\s\+]]

-- Built-in completion
vim.o.complete    = '.,w,b,kspell'     -- Use less sources
vim.o.completeopt = 'menuone,noselect' -- Use custom behavior

if vim.fn.has('nvim-0.11') == 1 then
  vim.o.completeopt = 'menuone,noselect,fuzzy,nosort'
end

-- Cyrillic keyboard layout
local langmap_keys = {
  'ёЁ;`~', '№;#',
  'йЙ;qQ', 'цЦ;wW', 'уУ;eE', 'кК;rR', 'еЕ;tT', 'нН;yY', 'гГ;uU', 'шШ;iI', 'щЩ;oO', 'зЗ;pP', 'хХ;[{', 'ъЪ;]}',
  'фФ;aA', 'ыЫ;sS', 'вВ;dD', 'аА;fF', 'пП;gG', 'рР;hH', 'оО;jJ', 'лЛ;kK', 'дД;lL', [[жЖ;\;:]], [[эЭ;'\"]],
  'яЯ;zZ', 'чЧ;xX', 'сС;cC', 'мМ;vV', 'иИ;bB', 'тТ;nN', 'ьЬ;mM', [[бБ;\,<]], 'юЮ;.>',
}
vim.o.langmap = table.concat(langmap_keys, ',')

-- Autocommands ===============================================================
-- Don't auto-wrap comments and don't insert comment leader after hitting 'o'.
-- Do on `FileType` to always override these changes from filetype plugins.
local ensure_fo = function() vim.cmd('setlocal formatoptions-=c formatoptions-=o') end
_G.Config.new_autocmd('FileType', '*', ensure_fo, "Proper 'formatoptions'")

-- Diagnostics ================================================================
local diagnostic_opts = {
  -- Show signs on top of any other sign, but only for warnings and errors
  signs = { priority = 9999, severity = { min = 'WARN', max = 'ERROR' } },

  -- Show all diagnostics as underline (for their meessages type `<Leader>ld`)
  underline = { severity = { min = 'HINT', max = 'ERROR' } },

  -- Show more details immediately only for errors at current line end
  virtual_lines = false,
  virtual_text = {
    current_line = true,
    severity = { min = 'ERROR', max = 'ERROR' },
  },

  -- Don't update diagnostics when typing
  update_in_insert = false,
}

-- Use `later()` to avoid sourcing `vim.diagnostic` on startup
MiniDeps.later(function() vim.diagnostic.config(diagnostic_opts) end)
--stylua: ignore end
