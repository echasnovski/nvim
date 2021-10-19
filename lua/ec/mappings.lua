-- Russian keyboard mappings
-- stylua: ignore start
local langmap_keys = {
  'ёЁ;`~', '№;#',
  'йЙ;qQ', 'цЦ;wW', 'уУ;eE', 'кК;rR', 'еЕ;tT', 'нН;yY', 'гГ;uU', 'шШ;iI', 'щЩ;oO', 'зЗ;pP', 'хХ;[{', 'ъЪ;]}',
  'фФ;aA', 'ыЫ;sS', 'вВ;dD', 'аА;fF', 'пП;gG', 'рР;hH', 'оО;jJ', 'лЛ;kK', 'дД;lL', [[жЖ;\;:]], [[эЭ;'\"]],
  'яЯ;zZ', 'чЧ;xX', 'сС;cC', 'мМ;vV', 'иИ;bB', 'тТ;nN', 'ьЬ;mM', [[бБ;\,<]], 'юЮ;.>',
}
vim.opt.langmap = table.concat(langmap_keys, ',')
-- stylua: ignore end

-- Helper function
local default_opts = {
  noremap = true,
  silent = true,
  expr = false,
  nowait = false,
  script = false,
  unique = false,
}

local keymap = function(mode, keys, cmd, opts)
  local o = vim.tbl_deep_extend('force', default_opts, opts or {})
  vim.api.nvim_set_keymap(mode, keys, cmd, o)
end

-- Disable `s` shortcut (use `cl` instead) for safer usage of 'mini.surround'
keymap('n', [[s]], [[<Nop>]])
keymap('x', [[s]], [[<Nop>]])

-- Copy to system clipboard
keymap('v', [[<C-c>]], [["+y]])

-- Move with <Alt-hjkl> in non-normal mode. Don't `noremap` in insert mode to
-- have these keybindings behave exactly like arrows (crucial inside
-- TelescopePrompt)
keymap('i', [[<M-h>]], [[<Left>]], { noremap = false })
keymap('i', [[<M-j>]], [[<Down>]], { noremap = false })
keymap('i', [[<M-k>]], [[<Up>]], { noremap = false })
keymap('i', [[<M-l>]], [[<Right>]], { noremap = false })
keymap('t', [[<M-h>]], [[<Left>]])
keymap('t', [[<M-j>]], [[<Down>]])
keymap('t', [[<M-k>]], [[<Up>]])
keymap('t', [[<M-l>]], [[<Right>]])
---- Move only sideways in command mode. Using `silent = false` makes movements
---- to be immediately shown.
keymap('c', [[<M-h>]], [[<Left>]], { silent = false })
keymap('c', [[<M-l>]], [[<Right>]], { silent = false })

-- Move between buffers
if vim.fn.exists('g:vscode') == 1 then
  -- Simulate same TAB behavior in VSCode
  keymap('n', [[]b]], [[<Cmd>Tabnext<CR>]])
  keymap('n', [[[b]], [[<Cmd>Tabprev<CR>]])
else
  -- This duplicates code from 'vim-unimpaired' (just in case)
  keymap('n', [[]b]], [[<Cmd>bnext<CR>]])
  keymap('n', [[[b]], [[<Cmd>bprevious<CR>]])
end

-- Simpler window navigation
keymap('n', [[<C-h>]], [[<C-w>h]])
keymap('n', [[<C-j>]], [[<C-w>j]])
keymap('n', [[<C-k>]], [[<C-w>k]])
keymap('n', [[<C-l>]], [[<C-w>l]])
---- Go to previous window (very useful with floating function documentation)
keymap('n', [[<C-p>]], [[<C-w>p]])
---- When in terminal, use this to go to Normal mode
keymap('t', [[<C-h>]], [[<C-\><C-N><C-w>h]])

-- Use alt + hjkl to resize windows
keymap('n', [[<M-h>]], [[<Cmd>vertical resize -2<CR>]])
keymap('n', [[<M-j>]], [[<Cmd>resize -2<CR>]])
keymap('n', [[<M-k>]], [[<Cmd>resize +2<CR>]])
keymap('n', [[<M-l>]], [[<Cmd>vertical resize +2<CR>]])

-- Alternative way to save
keymap('n', [[<C-s>]], [[<Cmd>silent w<CR>]])
keymap('i', [[<C-s>]], [[<Esc><Cmd>silent w<CR>]])

-- Move inside completion list with <TAB>
keymap('i', [[<Tab>]], [[pumvisible() ? "\<C-n>" : "\<Tab>"]], { expr = true })
keymap('i', [[<S-Tab>]], [[pumvisible() ? "\<C-p>" : "\<S-Tab>"]], { expr = true })

-- Extra jumps between folds
---- Jump to the beginning of previous fold
keymap('n', [[zK]], [[zk[z]])
---- Jump to the end of next fold
keymap('n', [[zJ]], [[zj]z]])

-- Reselect latest changed, put or yanked text
keymap('n', [[gV]], '`[v`]')

-- Make `q:` do nothing instead of opening command-line-window, because it is
-- often hit by accident
-- Use c_CTRL-F or Telescope
keymap('n', [[q:]], [[<Nop>]])

-- Search visually highlighted text
keymap('v', [[g/]], [[y/\V<C-R>=escape(@",'/\')<CR><CR>]])

-- Stop highlighting of search results
keymap('n', [[//]], [[:nohlsearch<C-R>=has('diff')?'<BAR>diffupdate':''<CR><CR>]])

-- Delete selection in Select mode (helpful when editing snippet placeholders)
keymap('s', [[<BS>]], [[<BS>i]])

-- Make `<CR>` mapping in the end of startup for it to not be overridden
vim.cmd([[au VimEnter * ++once imap <expr> <CR> v:lua.EC.cr_action()]])
