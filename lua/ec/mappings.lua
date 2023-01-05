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

-- Move by visible lines (don't map in Operator-pending mode because it
-- severely changes behavior; like `dj` on non-wrapped line will not delete it)
keymap('n', 'j', 'gj')
keymap('x', 'j', 'gj')
keymap('n', 'k', 'gk')
keymap('x', 'k', 'gk')

-- Move visually selected lines up/down (respects count), autoformat, reselect
keymap('x', 'J', [[":move '>+" . v:count1     . "<CR>gv=gv"]], { expr = true })
keymap('x', 'K', [[":move '<-" . (v:count1+1) . "<CR>gv=gv"]], { expr = true })

-- Copy visual selection to system clipboard
keymap('x', [[<C-c>]], [["+y]])

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
-- Move only sideways in command mode. Using `silent = false` makes movements
-- to be immediately shown.
keymap('c', [[<M-h>]], [[<Left>]], { silent = false })
keymap('c', [[<M-l>]], [[<Right>]], { silent = false })

-- Simpler window navigation
keymap('n', [[<C-h>]], [[<C-w>h]])
keymap('n', [[<C-j>]], [[<C-w>j]])
keymap('n', [[<C-k>]], [[<C-w>k]])
keymap('n', [[<C-l>]], [[<C-w>l]])
-- When in terminal, use this to go to Normal mode
keymap('t', [[<C-h>]], [[<C-\><C-N><C-w>h]])

-- Use ctrl + arrows to resize windows
keymap('n', [[<C-Left>]], [[<Cmd>vertical resize -1<CR>]])
keymap('n', [[<C-Down>]], [[<Cmd>resize -1<CR>]])
keymap('n', [[<C-Up>]], [[<Cmd>resize +1<CR>]])
keymap('n', [[<C-Right>]], [[<Cmd>vertical resize +1<CR>]])

-- Alternative way to save
keymap('n', [[<C-s>]], [[<Cmd>silent w<CR>]])
keymap('i', [[<C-s>]], [[<Esc><Cmd>silent w<CR>]])

-- Move inside completion list with <TAB>
keymap('i', [[<Tab>]], [[pumvisible() ? "\<C-n>" : "\<Tab>"]], { expr = true })
keymap('i', [[<S-Tab>]], [[pumvisible() ? "\<C-p>" : "\<S-Tab>"]], { expr = true })

-- Reselect latest changed, put or yanked text
keymap('n', [[gV]], '`[v`]')

-- Join lines without moving cursor (set context mark, execute `J` respecting
-- count, go back to context mark)
keymap('n', 'J', [['m`' . v:count1 . 'J``']], { expr = true })

-- Make `q:` do nothing instead of opening command-line-window, because it is
-- often hit by accident
-- Use c_CTRL-F or Telescope
keymap('n', [[q:]], [[<Nop>]])

-- Search visually selected text (slightly better than builtins in Neovim>=0.8)
keymap('x', '*', [[y/\V<C-R>=escape(@", '/\')<CR><CR>]])
keymap('x', '#', [[y?\V<C-R>=escape(@", '/\')<CR><CR>]])

-- Search inside visually highlighted text
keymap('x', 'g/', '<esc>/\\%V', { silent = false })

-- Stop highlighting of search results. NOTE: this can be done with default
-- `<C-l>` but this solution deliberately uses `:` instead of `<Cmd>` to go
-- into Command mode and back which updates 'mini.map'.
keymap('n', '//', ':nohlsearch | diffupdate<CR>')

-- Delete selection in Select mode (helpful when editing snippet placeholders)
keymap('s', [[<BS>]], [[<BS>i]])
