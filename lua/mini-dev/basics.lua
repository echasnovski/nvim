-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO
--
-- Code:
-- - Find and add new mappings.
-- - Find and add new autocommands.
-- - Add mappings descriptions.
-- - Add as beginner friendly comments as possible.
--
-- Tests:
--
-- Docs:
-- - Mention that it is ok to look at source code and copy things.
--

-- Documentation ==============================================================
--- Set basic options and mappings
---
--- Features:
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.basics').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniBasics`
--- which you can use for scripting or manually (with `:lua MiniBasics.*`).
---
--- See |MiniBasics.config| for available config settings.
---
--- # Comparisons ~
---
--- - 'tpope/vim-sensible':
--- - 'tpope/vim-unimpaired':
---
--- # Disabling~
---
--- This module can not be disabled.
---@tag mini.basics
---@tag Minibasics

---@diagnostic disable:undefined-field

-- Module definition ==========================================================
local MiniBasics = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniBasics.config|.
---
---@usage `require('mini.basics').setup({})` (replace `{}` with your `config` table)
MiniBasics.setup = function(config)
  -- Export module
  _G.MiniBasics = MiniBasics

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text
MiniBasics.config = {
  options = {
    -- Basic options
    basic = true,

    -- Extra UI features
    extra_ui = false,

    -- Presets for window borders ('single', 'double', etc.)
    win_border = 'default',
  },

  -- TODO: !!! Add descriptions to all mappings
  mappings = {
    -- Basic mappings
    basic = true,

    -- Mappings for toggling common options. Highly recommended to enable.
    -- Like in 'tpope/vim-unimpaired' but instead of `yo` use `\` (or `,` if it
    -- is used as leader)
    -- Plus:
    -- - Diagnstics: `\d` (`:h vim.diagnostic.enable`)
    toggle_options = false,

    -- Mappings for common "next-previous" pairs. Highly recommended to enable.
    -- `[` / `]` pair mappings from 'tpope/vim-unimpaired'
    -- Plus:
    -- - Windows: `[w`, `]w`.
    -- - Diagnostic: `[d`, `]d`.
    -- - Comment lines block: `[c`, `]c` (???)
    next_prev = false,

    -- Mapping for common "first-last" pairs.
    first_last = false,

    -- Better window navigation: <C-hjkl> for normal mode, <C-w> for Terminal
    -- mode (use `<C-w><Esc>` to escape Terminal mode)
    window_navigation = false,

    -- Resize windows with <C-arrows>
    window_resize = false,

    -- Move cursor in Insert, Command, and Terminal mode with <M-hjkl>
    move_with_alt = false,
  },

  autocommands = {
    basic = true,

    relnum_in_visual_mode = false,
  },

  -- ? Abbreviations ? :
  -- - Insert date `iabbrev date@ <C-R>=strftime("%Y-%m-%d")<CR>`
}
--minidoc_afterlines_end

MiniBasics.toggle_diagnostic = function()
  local buf_id = vim.api.nvim_get_current_buf()
  local buf_state = H.buffer_diagnostic_state[buf_id]
  if buf_state == nil then buf_state = true end

  if buf_state then
    vim.diagnostic.disable(buf_id)
  else
    vim.diagnostic.enable(buf_id)
  end

  local new_buf_state = not buf_state
  H.buffer_diagnostic_state[buf_id] = new_buf_state

  return new_buf_state and '  diagnostic' or 'nodiagnostic'
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniBasics.config

-- Diagnostic state per buffer
H.buffer_diagnostic_state = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    options = { config.options, 'table' },
    mappings = { config.mappings, 'table' },
    autocommands = { config.autocommands, 'table' },
  })

  vim.validate({
    ['options.basic'] = { config.options.basic, 'boolean' },
    ['options.extra_ui'] = { config.options.extra_ui, 'boolean' },
    ['options.win_border'] = { config.options.win_border, 'string' },

    ['mappings.basic'] = { config.mappings.basic, 'boolean' },
    ['mappings.toggle_options'] = { config.mappings.toggle_options, 'boolean' },
    ['mappings.next_prev'] = { config.mappings.next_prev, 'boolean' },
    ['mappings.first_last'] = { config.mappings.first_last, 'boolean' },
    ['mappings.window_navigation'] = { config.mappings.window_navigation, 'boolean' },
    ['mappings.window_resize'] = { config.mappings.window_resize, 'boolean' },
    ['mappings.move_with_alt'] = { config.mappings.move_with_alt, 'boolean' },

    ['autocommands.basic'] = { config.autocommands.basic, 'boolean' },
    ['autocommands.relnum_in_visual_mode'] = { config.autocommands.relnum_in_visual_mode, 'boolean' },
  })

  return config
end

H.apply_config = function(config)
  MiniBasics.config = config

  H.apply_options(config)
  H.apply_mappings(config)
  H.apply_autocommands(config)
end

-- Options --------------------------------------------------------------------
--stylua: ignore
H.apply_options = function(config)
  -- Use `local o, opt = vim.o, vim.opt` to copy lines as is.
  -- Or use `vim.o` and `vim.opt` directly.
  local o, opt = H.vim_o, H.vim_opt

  -- Basic options
  if config.options.basic then
    -- Leader key
    if vim.g.mapleader == nil then
      vim.g.mapleader = ' ' -- Use space as the one and only true Leader key
    end

    -- General
    o.undofile    = true  -- Enable persistent undo (see also `:h undodir`)

    o.backup      = false -- Don't store backup while overwriting the file
    o.writebackup = false -- Don't store backup while overwriting the file

    o.mouse       = 'a'   -- Enable mouse for all available modes

    vim.cmd('filetype plugin indent on') -- Enable all filetype plugins

    -- UI
    o.breakindent   = true    -- Indent wrapped lines to match line start
    o.cursorline    = true    -- Highlight current line
    o.linebreak     = true    -- Wrap long lines at 'breakat' (if 'wrap' is set)
    o.number        = true    -- Show line numbers
    o.splitbelow    = true    -- Horizontal splits will be below
    o.splitright    = true    -- Vertical splits will be to the right
    o.termguicolors = true    -- Enable gui colors

    o.ruler         = false   -- Don't show cursor position in command line
    o.showmode      = false   -- Don't show mode in command line
    o.wrap          = false   -- Display long lines as just one line

    o.signcolumn    = 'yes'   -- Always show sign column (otherwise it will shift text)
    o.fillchars     = 'eob: ' -- Don't show `~` outside of buffer

    -- Editing
    o.autoindent  = true -- Use auto indent
    o.ignorecase  = true -- Ignore case when searching (use `\C` to force not doing that)
    o.incsearch   = true -- Show search results while typing
    o.infercase   = true -- Infer letter cases for a richer built-in keyword completion
    o.smartcase   = true -- Don't ignore case when searching if pattern has upper case
    o.smartindent = true -- Make indenting smart

    o.completeopt   = 'menuone,noinsert,noselect' -- Customize completions
    o.virtualedit   = 'block'                     -- Allow going past the end of line in visual block mode
    o.formatoptions = 'qjl1'                      -- Don't autoformat comments

    -- Neovim version dependent
    if vim.fn.has('nvim-0.9') == 1 then
      opt.shortmess:append('WcC') -- Reduce command line messages
      o.splitkeep = 'screen'      -- Reduce scrolling during window split
    else
      opt.shortmess:append('Wc')  -- Reduce command line messages
    end
  end

  -- Some opinioneted extra UI options
  if config.options.extra_ui then
    o.pumblend  = 10 -- Make builtin completion menus slightly transparent
    o.pumheight = 10 -- Make popup menu smaller
    o.winblend  = 10 -- Make floating windows slightly transparent

    o.listchars = 'extends:…,precedes:…,nbsp:␣' -- Define which helper symbols to show
    o.list      = true                          -- Show some helper symbols

    -- Enable syntax highlighing if it wasn't already (as it is time consuming)
    if vim.fn.exists("syntax_on") ~= 1 then
      vim.cmd([[syntax enable]])
    end

    -- Neovim version dependent
    if vim.fn.has('nvim-0.9') == 1 then
      o.cmdheight = 0 -- Don't show command line (increases screen space)
    end
  end

  -- Use some common window borders presets
  local borders = H.win_borders[config.options.win_border]
  if borders ~= nil then
    local chars = borders.vert .. (vim.fn.has('nvim-0.7') == 1 and borders.rest or '')
    vim.opt.fillchars:append(chars)
  end
end

H.vim_o = setmetatable({}, {
  __newindex = function(_, name, value)
    local was_set = vim.api.nvim_get_option_info(name).was_set
    if was_set then return end

    vim.o[name] = value
  end,
})

H.vim_opt = setmetatable({}, {
  __index = function(_, name)
    local was_set = vim.api.nvim_get_option_info(name).was_set
    if was_set then return { append = function() end, remove = function() end } end

    return vim.opt[name]
  end,
})

--stylua: ignore
H.win_borders = {
  bold    = { vert = 'vert:┃', rest = ',horiz:━,horizdown:┳,horizup:┻,,verthoriz:╋,vertleft:┫,vertright:┣' },
  dot     = { vert = 'vert:·', rest = ',horiz:·,horizdown:·,horizup:·,,verthoriz:·,vertleft:·,vertright:·' },
  double  = { vert = 'vert:║', rest = ',horiz:═,horizdown:╦,horizup:╩,,verthoriz:╬,vertleft:╣,vertright:╠' },
  single  = { vert = 'vert:│', rest = ',horiz:─,horizdown:┬,horizup:┴,,verthoriz:┼,vertleft:┤,vertright:├' },
  solid   = { vert = 'vert: ', rest = ',horiz: ,horizdown: ,horizup: ,,verthoriz: ,vertleft: ,vertright: ' },
}

-- Mappings -------------------------------------------------------------------
--stylua: ignore
H.apply_mappings = function(config)
  -- Use `local map = vim.keymap.set` to copy lines as is. Or use it directly.
  local map = H.keymap_set

  if config.mappings.basic then
    -- Move by visible lines. Notes:
    -- - Don't map in Operator-pending mode because it severely changes behavior:
    --   like `dj` on non-wrapped line will not delete it.
    -- - Condition on `v:count == 0` to allow easier use of relative line numbers.
    map({ 'n', 'x' }, 'j', [[v:count == 0 ? 'gj' : 'j']], { expr = true })
    map({ 'n', 'x' }, 'k', [[v:count == 0 ? 'gk' : 'k']], { expr = true })

    -- Alternative way to save and exit in Normal mode
    map(  'n',        '<C-s>', '<Cmd>silent w<CR>')
    map({ 'i', 'x' }, '<C-s>', '<Esc><Cmd>silent w<CR>')

    -- Copy/paste with system clipboard
    map({ 'n', 'x' }, 'gy', '"+y')
    map(  'n',        'gp', '"+p')
    -- - Paste in Visual with `P` to not copy selected text (`:h v_P`)
    map(  'x',        'gp', '"+P')

    -- Reselect latest changed, put or yanked text
    map('n', 'gV', '"`[" . strpart(getregtype(), 0, 1) . "`]"', { expr = true })

    -- Search visually selected text (slightly better than builtins in Neovim>=0.8)
    map('x', '*', [[y/\V<C-R>=escape(@", '/\')<CR><CR>]])
    map('x', '#', [[y?\V<C-R>=escape(@", '?\')<CR><CR>]])

    -- Search inside visually highlighted text. Use `silent = false` for it to
    -- make effect immediately.
    map('x', 'g/', '<esc>/\\%V', { silent = false })

    -- Correct latest misspelled word by taking first suggestion. Use `<C-g>u`
    -- in Insert mode to mark this as separate undoable action.
    -- Source: https://stackoverflow.com/a/16481737
    -- NOTE: this remaps `<C-z>` in Normal mode (completely stops Neovim), but
    -- it seems to be too harmful anyway.
    map('n', '<C-z>', '[s1z=')
    map('i', '<C-z>', '<C-g>u<Esc>[s1z=`]a<C-g>u')

    -- Add empty lines before and after cursor line
    map('n', 'gO', "<Cmd>call append(line('.') - 1, repeat([''], v:count1))<CR>")
    map('n', 'go', "<Cmd>call append(line('.'),     repeat([''], v:count1))<CR>")
  end

  if config.mappings.toggle_options then
    -- Define prefix. If you know your leader keys, choose manually.
    local prefix = [[\]]
    local leader, local_leader = vim.g.mapleader, vim.g.maplocalleader
    -- - Default leader key is `\`, so also check for not set Leader key
    if leader == nil or leader == '' or leader == prefix or local_leader == prefix then
      -- Try ',' or '|'
      prefix = (leader ~= ',' and local_leader ~= ',') and ',' or '|'
    end

    -- Define mappings
    local map_toggle = function(lhs, rhs, desc) map('n', prefix .. lhs, rhs, { desc = desc }) end

    map_toggle('b', '<Cmd>lua vim.o.bg = vim.o.bg == "dark" and "light" or "dark"<CR>', "Toggle 'background'")
    map_toggle('c', '<Cmd>setlocal cursorline! cursorline?<CR>',                        "Toggle 'cursorline'")
    map_toggle('C', '<Cmd>setlocal cursorcolumn! cursorcolumn?<CR>',                    "Toggle 'cursorcolumn'")
    map_toggle('d', '<Cmd>lua print(MiniBasics.toggle_diagnostic())<CR>',               'Toggle diagnostic')
    map_toggle('h', '<Cmd>let v:hlsearch = 1 - v:hlsearch<CR>',                         'Toggle search highlight')
    map_toggle('i', '<Cmd>setlocal ignorecase! ignorecase?<CR>',                        "Toggle 'ignorecase'")
    map_toggle('l', '<Cmd>setlocal list! list?<CR>',                                    "Toggle 'list'")
    map_toggle('r', '<Cmd>setlocal relativenumber! relativenumber?<CR>',                "Toggle 'relativenumber'")
    map_toggle('s', '<Cmd>setlocal spell! spell?<CR>',                                  "Toggle 'spell'")
    map_toggle('w', '<Cmd>setlocal wrap! wrap?<CR>',                                    "Toggle 'wrap'")
  end

  if config.mappings.window_navigation then
    map('n', '<C-h>', '<C-w>h')
    map('n', '<C-j>', '<C-w>j')
    map('n', '<C-k>', '<C-w>k')
    map('n', '<C-l>', '<C-w>l')

    map('t', '<C-w>', [[<C-\><C-N><C-w>]])
  end

  if config.mappings.window_resize then
    -- Make it respect `v:count`
    map('n', '<C-Left>',  '"<Cmd>vertical resize -" . v:count1 . "<CR>"', { expr = true })
    map('n', '<C-Down>',  '"<Cmd>resize -"          . v:count1 . "<CR>"', { expr = true })
    map('n', '<C-Up>',    '"<Cmd>resize +"          . v:count1 . "<CR>"', { expr = true })
    map('n', '<C-Right>', '"<Cmd>vertical resize +" . v:count1 . "<CR>"', { expr = true })
  end

  if config.mappings.move_with_alt then
    -- Don't `noremap` in insert mode to have these keybindings behave exactly
    -- like arrows (crucial inside TelescopePrompt)
    map('i', '<M-h>', '<Left>',  { noremap = false })
    map('i', '<M-j>', '<Down>',  { noremap = false })
    map('i', '<M-k>', '<Up>',    { noremap = false })
    map('i', '<M-l>', '<Right>', { noremap = false })

    map('t', '<M-h>', '<Left>')
    map('t', '<M-j>', '<Down>')
    map('t', '<M-k>', '<Up>')
    map('t', '<M-l>', '<Right>')

    -- Move only sideways in command mode. Using `silent = false` makes movements
    -- to be immediately shown.
    map('c', '<M-h>', '<Left>',  { silent = false })
    map('c', '<M-l>', '<Right>', { silent = false })
  end
end

H.keymap_set = function(modes, lhs, rhs, opts)
  if type(modes) == 'string' then modes = { modes } end

  for _, mode in ipairs(modes) do
    -- Don't map if mapping was already set
    local map = vim.fn.maparg(lhs, mode)
    local is_default = map == ''
      -- Some mappings are set by default in Neovim
      or (mode == 'n' and lhs == '<C-l>' and map:find('nohl') ~= nil)
      or (mode == 'x' and lhs == '*' and map == [[y/\V<C-R>"<CR>]])
      or (mode == 'x' and lhs == '#' and map == [[y?\V<C-R>"<CR>]])
    if not is_default then return end

    -- Map
    H.map(mode, lhs, rhs, opts)
  end
end

-- Autocommands ---------------------------------------------------------------
H.apply_autocommands = function(config)
  -- TODO: use `nvim_create_autocmd()` after Neovim<=0.6 support is dropped

  vim.cmd([[augroup MiniBasicsAutocommands]])
  vim.cmd([[autocmd!]])

  if config.autocommands.basic then
    -- Start builtin terminal in Insert mode
    vim.cmd([[autocmd TermOpen * startinsert]])

    -- Highlight yanked text
    vim.cmd([[autocmd TextYankPost * silent! lua vim.highlight.on_yank()]])
  end

  if config.autocommands.relnum_in_visual_mode and vim.fn.exists('##ModeChanged') == 1 then
    -- Show relative line numbers only when they matter (linewise and blockwise
    -- selection) and 'number' is set (avoids horizontal flickering)
    vim.cmd([[autocmd ModeChanged *:[V\x16]* let &l:relativenumber = &l:number == 1]])
    -- - Using `mode () =~#...` handles switching between linewise and blockwise mode.
    vim.cmd([[autocmd ModeChanged [V\x16]*:* let &l:relativenumber = mode() =~# '^[V\x16]']])

    -- - This is a part of example in `:h ModeChanged`, but I am yet to find the
    --   use case for it, as it seems like working fine without it.
    -- vim.cmd([[autocmd WinEnter,WinLeave    * let &l:relativenumber = mode() =~# '^[V\x16]']])
  end

  vim.cmd([[augroup END]])
end

-- Predicators ----------------------------------------------------------------
-- H.is_config_cursor = function(x)
--   if type(x) ~= 'table' then return false, H.msg_config('cursor', 'table') end
--   if type(x.enable) ~= 'boolean' then return false, H.msg_config('cursor.enable', 'boolean') end
--   if not vim.is_callable(x.timing) then return false, H.msg_config('cursor.timing', 'callable') end
--   if not vim.is_callable(x.path) then return false, H.msg_config('cursor.path', 'callable') end
--
--   return true
-- end

H.msg_config = function(x_name, msg) return string.format('`%s` should be %s.', x_name, msg) end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.basics) %s', msg), 0) end

H.validate_if = function(predicate, x, x_name)
  local is_valid, msg = predicate(x, x_name)
  if not is_valid then H.error(msg) end
end

H.map = function(mode, key, rhs, opts)
  if key == '' then return end

  opts = vim.tbl_deep_extend('force', { noremap = true, silent = true }, opts or {})

  -- Use mapping description only in Neovim>=0.7
  if vim.fn.has('nvim-0.7') == 0 then opts.desc = nil end

  vim.api.nvim_set_keymap(mode, key, rhs, opts)
end

return MiniBasics
