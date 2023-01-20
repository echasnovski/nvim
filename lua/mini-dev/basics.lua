-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO
--
-- Code:
-- - Implement options.
-- - Implement mappings.
-- - Implement autocommands.
-- - Think more about config structure and options/mappings grouping.
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
--- You can override runtime config settings (like `config.modifiers`) locally
--- to buffer inside `vim.b.minibasics_config` which should have same structure
--- as `MiniBasics.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'tpope/vim-sensible':
--- - 'tpope/vim-unimpaired':
---
--- # Disabling~
---
--- To disable, set `g:minibasics_disable` (globally) or `b:minibasics_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.basics
---@tag Minibasics

---@diagnostic disable:undefined-field

-- Module definition ==========================================================
-- TODO: make local after release
MiniBasics = {}
H = {}

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
    -- Or make it `flavor = 'basic'` with later customization?
    basic = true,

    -- Extra UI features ('winblend', 'pumblend', 'cmdheight=0')
    extra_ui = false,

    -- Wrapper for 'fillchars' parts. Possible values: default, single, double,
    -- rounded, bold, dot (with all `·`), none, ...?
    win_border = 'default',

    -- Wrapper for 'guicursor'. Possible values: default, blink, ...?
    cursor = 'default',
  },

  -- !!! Add descriptions to all mappings
  mappings = {
    -- Or make it `flavor = 'basic'` with later customization?
    basic = true,

    -- `[` / `]` pair mappings from 'tpope/vim-unimpaired'
    -- Plus:
    -- - Windows: `[w`, `]w`.
    -- - Tabpages: `[t`, `]t`.
    -- - Diagnostic: `[d`, `]d`.
    -- - Comment lines block: `[c`, `]c` (???)
    next_prev = true,

    -- Like in 'tpope/vim-unimpaired' but instead of `yo` use `\` (or `,` if it
    -- is used as leader)
    -- Plus:
    -- - Diagnstics: `\d` (`:h vim.diagnostic.enable`)
    toggle_options = true,

    -- Better window focus: <C-hjkl> for normal mode, <C-w> for Terminal mode
    -- (use `<C-w><Esc>` to escape Terminal mode)
    window_focus = true,
  },

  autocommands = {
    basic = true,

    relnum_in_visual_mode = false,
  },

  -- ? Abbreviations ? :
  -- - Insert date `iabbrev date@ <C-R>=strftime("%Y-%m-%d")<CR>`
}
--minidoc_afterlines_end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniBasics.config

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    -- TODO: add validations
  })

  return config
end

H.apply_config = function(config)
  MiniBasics.config = config

  H.apply_options(config)
  H.apply_mappings(config)
  H.apply_autocommands(config)
end

H.is_disabled = function() return vim.g.minibasics_disable == true or vim.b.minibasics_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniBasics.config, vim.b.minibasics_config or {}, config or {})
end

-- Options --------------------------------------------------------------------
--stylua: ignore
H.apply_options = function(config)
  -- Use `local o = vim.o` to copy lines as is or use `vim.o` instead of `o`
  local o = H.vim_o

  -- Basic options
  if config.options.basic then
    -- Leader key
    if vim.g.mapleader == nil then
      vim.g.mapleader = ' ' -- Use space as the one and only true Leader key
    end

    -- General
    o.splitbelow  = true  -- Horizontal splits will be below
    o.splitright  = true  -- Vertical splits will be to the right
    o.undofile    = true  -- Enable persistent undo (see also `:h undodir`)

    o.backup      = false -- Don't store backup while overwriting the file
    o.writebackup = false -- Don't store backup while overwriting the file

    o.timeoutlen  = 300   -- Wait less for mapping to complete (less lag in some situations)
    o.updatetime  = 300   -- Make CursorHold faster and more frequent swap writing

    o.mouse       = 'a'   -- Enable mouse for all available modes

    vim.cmd('filetype plugin indent on') -- Enable all filetype plugins

    -- UI
    o.cursorline    = true    -- Highlight current line
    o.number        = true    -- Show line numbers
    o.termguicolors = true    -- Enable gui colors

    o.ruler         = false   -- Don't show cursor position in command line
    o.showmode      = false   -- Don't show mode in command line
    o.wrap          = false   -- Display long lines as just one line

    o.signcolumn    = 'yes'   -- Always show sign column (otherwise it will shift text)
    o.fillchars     = 'eob: ' -- Don't show `~` past last buffer line

    -- Editing
    o.autoindent  = true -- Use auto indent
    o.breakindent = true -- Indent wrapped lines to match line start
    o.ignorecase  = true -- Ignore case when searching (use `\C` to force not doing that)
    o.incsearch   = true -- Show search results while typing
    o.infercase   = true -- Infer letter cases for a richer built-in keyword completion
    o.linebreak   = true -- Wrap long lines at 'breakat' (if 'wrap' is set)
    o.smartcase   = true -- Don't ignore case when searching if pattern has upper case
    o.smartindent = true -- Make indenting smart

    o.completeopt   = 'menuone,noinsert,noselect' -- Customize completions
    o.virtualedit   = 'block'                     -- Allow going past the end of line in visual block mode
    o.formatoptions = 'qjl1'                      -- Don't autoformat comments

    -- Neovim version dependent
    if vim.fn.has('nvim-0.9') == 1 then
      o.shortmess = 'cCFoOTt' -- Reduce command line messages
      o.splitkeep = 'screen'  -- Reduce scrolling during window split
    else
      o.shortmess = 'cFoOTt'  -- Reduce command line messages
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
end

H.vim_o = setmetatable({}, {
  __newindex = function(_, name, value)
    local was_set = vim.api.nvim_get_option_info(name).was_set
    if was_set then return end

    vim.o[name] = value
  end,
})

-- Mappings -------------------------------------------------------------------
H.apply_mappings = function(config)
  -- TODO
end

H.keymap_set = function(mode, lhs, rhs, opts)
  -- Don't map if mapping was already set
  local map = vim.fn.maparg(lhs, mode)
  local is_default = map == ''
    -- Some mappings are set by default in Neovim
    or (mode == 'x' and lhs == '*' and map == [[y/\V<C-R>"<CR>]])
    or (mode == 'x' and lhs == '#' and map == [[y?\V<C-R>"<CR>]])
  if not is_default then return end

  -- Map
  H.map(mode, lhs, rhs, opts)
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

  if config.autocommands.relnum_in_visual_mode then
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
