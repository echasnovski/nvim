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

    folds = false,

    -- Wrapper for 'fillchars' parts. Possible values: default, single, double,
    -- rounded, bold, none, ...?
    win_border = 'default',

    -- Wrapper for 'guicursor'. Possible values: default, blink, ...?
    cursor = 'default',
  },

  mappings = {
    -- Or make it `flavor = 'basic'` with later customization?
    basic = true,

    -- `[` / `]` pair mappings from 'tpope/vim-unimpaired'
    -- Plus:
    -- - Windows: `[w`, `]w`.
    -- - Tabpages: `[t`, `]t`.
    next_prev = true,

    -- Like in 'tpope/vim-unimpaired' but instead of `yo` use `\` (or `,` if it
    -- is used as leader)
    toggle_options = true,

    -- Better window focus: <C-hjkl> for normal mode, <C-w> for Terminal mode
    -- (use `<C-w><Esc>` to escape Terminal mode)
    window_focus = true,
  },

  autocommands = {},

  -- ? Abbreviations ?
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

H.apply_config = function(config) MiniBasics.config = config end

H.is_disabled = function() return vim.g.minibasics_disable == true or vim.b.minibasics_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniBasics.config, vim.b.minibasics_config or {}, config or {})
end

-- Config options -------------------------------------------------------------
H.set_option = function(name, value)
  local was_set = vim.api.nvim_get_option_info(name).was_set
  if was_set then return end

  vim.go[name] = value
end

-- Config mappings ------------------------------------------------------------
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
