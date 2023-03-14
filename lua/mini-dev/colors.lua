-- TODO:
--
-- Code:
-- - Think about more proper ways to name color scheme snapshot.
--
-- - Define `Colorscheme` class. Should be the return value of
--   `as_colorscheme()` and `get_current_colorscheme()`.
--
-- - Implement Oklab (https://bottosson.github.io/posts/oklab/) color space
--   with modified lightness component
--   (https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab).
--
-- - Explore possibility of making `animate_change()` function. Ideally should
--   be a replacement for `:colorscheme` which takes color scheme name and
--   performs smooth animated transition.
--   Might have problems due to redraw (maybe use `lazyredraw`?).
--
-- - Explore possibility of `average()`: take array of `Colorscheme` objects
--   and return `Colorscheme` object which is an "average" of all of them:
--     - For boolean options take the mode.
--     - For colors take average Oklab lightness and saturation, but use arc
--       median for circular hues (point which minimizes sum of circular
--       distances to input points). Use color at specific highlight field (fg,
--       bg, sp) only if it is used in the majority of input color schemes.
--
-- - Fields of `Colorscheme` object:
--     - `name`
--     - `groups`
--     - ??? Get rid of it entirely ??? As there are actually created highlight
--       groups if plugin is actually loaded. This simplifies **A LOT**.
--       `integrations` - set of supported plugin integrations which provide
--       theming not through highlight groups. Like 'nvim-lualine/lualine.nvim'
--       and 'utilyre/barbecue.nvim'.
--
-- - Planned methods of `Colorscheme` object:
--     - `optimize()` - remove rarely used/unnecessary/known to come from
--       plugin highlight groups (by providing pattern; '^DevIcon' or '^Nvim'),
--       possibly make new highlight groups which later will be linked to
--       (presumably, this improves startup speed).
--     - `write()` - save as plain Lua script file in
--       '<stdpath('config')>/colors/<name>.lua'. The file should be sourceable
--       (and thus usable with `:colorscheme`).
--     - `ensure_cterm({force = false})` - compute closest terminal colors for
--       all present gui ones. If `opts.force`, redo present terminal colors.
--     - `apply()` - apply all colors from color scheme to current session.
--       See https://github.com/rktjmp/lush.nvim/blob/62180850d230e1650fe5543048bb15c4452916d6/lua/lush.lua#L29
--     - `invert()` - invert colors. General idea is to make dark/light color
--       scheme be light/dark while preserving "overall feel".
--     - `change_lightness()` - take one parameter from -1 to 1. Here -1 makes
--       all black and 1 makes all white.
--     - `change_temperature()` - take one parameter from -1 to 1. Here -1 makes
--       the most cool and 1 makes the most warm variant of current colors.
--     - `change_saturation()` - take one parameter from -1 to 1. Here -1 makes
--       all grayscale and 1 makes the most saturated variant of current colors.
--     - `change_colorblind_friendly()` (come up with better name) - takes some
--       parameters and modifies color scheme to be more colorblind friendly.
--
-- Reference color schemes (for testing purposes):
-- - folke/tokyonight.nvim (3260 stars)
-- - catppuccin/nvim (2360 stars)
-- - rebelot/kanagawa.nvim (2023 stars)
-- - EdenEast/nightfox.nvim (1935 stars)
-- - sainnhe/everforest (1743 stars)
-- - projekt0n/github-nvim-theme (1312 stars)
-- - sainnhe/gruvbox-material (1273 stars)
-- - dracula/vim (1216 stars)
-- - sainnhe/sonokai (1156 stars)
-- - ellisonleao/gruvbox.nvim (904 stars)
-- - Maybe:
--     - navarasu/onedark.nvim (882 stars)
--     - tomasiser/vim-code-dark (837 stars)
--     - rose-pine/neovim (836 stars)
--     - marko-cerovac/material.nvim (723 stars)
--     - sainnhe/edge (703 stars)
--     - bluz71/vim-nightfly-colors (586 stars)
--     - shaunsingh/nord.nvim (578 stars)
--     - bluz71/vim-moonfly-colors (564 stars)
--     - embark-theme/vim (531 stars)
--
-- Tests:
--
-- Documentation:
--

--- *mini.colors* Modify and save any color scheme
--- *MiniColors*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- Notes:
---
--- # Setup~
---
--- This module doesn't need setup, but it can be done to improve usability.
--- Setup with `require('mini.colors').setup({})` (replace `{}` with your
--- `config` table). It will create global Lua table `MiniColors` which you can
--- use for scripting or manually (with `:lua MiniColors.*`).
---
--- See |MiniColors.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.minicolors_config`
--- will have no effect here.
---
--- # Comparisons ~
---
--- - 'lifepillar/vim-colortemplate':
--- - 'rktjmp/lush.nvim':

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
-- TODO: make local before public release
MiniColors = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniSplitjoin.config|.
---
---@usage `require('mini.colors').setup({})` (replace `{}` with your `config` table)
MiniColors.setup = function(config)
  -- Export module
  _G.MiniColors = MiniColors

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniColors.config = {}
--minidoc_afterlines_end

MiniColors.as_colorscheme = function(x)
  local res = vim.deepcopy(x)

  -- Fields
  res.name = res.name or 'minicolors_snapshot'
  res.groups = res.groups or {}
  res.integrations = res.integrations or {}

  -- Methods
  res.write = H.colorscheme_write

  return res
end

MiniColors.get_current_colorscheme = function(opts)
  opts = vim.tbl_deep_extend('force', { integration_themes = {}, make_unique_name = true }, opts or {})

  return MiniColors.as_colorscheme({
    name = H.colorscheme_get_current_name(opts.make_unique_name),
    groups = H.colorscheme_get_current_groups(),
    integrations = H.colorscheme_get_current_integrations(opts.integration_themes),
  })
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniColors.config

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  return config
end

H.apply_config = function(config) MiniColors.config = config end

-- Color scheme ---------------------------------------------------------------
H.colorscheme_write = function(self, opts)
  opts =
    vim.tbl_extend('force', { directory = (vim.fn.stdpath('config') .. '/colors'), ensure_unique = true }, opts or {})

  if opts.ensure_unique then H.colorscheme_ensure_unique(self.name) end

  -- Create file lines
  local lines = {
    [[-- Made with 'mini.colors' module of https://github.com/echasnovski/mini.nvim]],
    '',
    [[vim.cmd('highlight clear')]],
    'vim.g.colors_name = ' .. vim.inspect(self.name),
    '',
    '-- Highlight groups',
    'local hi = function(name, hl_data) vim.api.nvim_set_hl(0, name, hl_data) end',
    '',
  }

  -- - Highlight groups
  local lines_groups = vim.tbl_map(
    function(hl) return string.format('hi("%s", %s)', hl.name, vim.inspect(hl.spec, { newline = ' ', indent = '' })) end,
    H.hl_groups_to_array(self.groups)
  )
  vim.list_extend(lines, lines_groups)

  -- - Plugin integrations
  vim.list_extend(lines, { '', '-- Plugin integrations' })

  local barbecue = self.integrations.barbecue
  if barbecue.module ~= nil then
    vim.list_extend(lines, { '' })
    local barbecue_lines =
      string.format([[package.loaded['barbecue.theme.%s'] = %s]], barbecue.theme, vim.inspect(barbecue.module))
    vim.list_extend(lines, vim.split(barbecue_lines, '\n'))
  end

  local lualine = self.integrations.lualine
  if lualine.module ~= nil then
    vim.list_extend(lines, { '' })
    local lualine_lines =
      string.format([[package.loaded['lualine.themes.%s'] = %s]], lualine.theme, vim.inspect(lualine.module))
    vim.list_extend(lines, vim.split(lualine_lines, '\n'))
  end

  -- Create file and populate with computed lines
  vim.fn.mkdir(opts.directory, 'p')
  local path = string.format('%s/%s.lua', opts.directory, self.name)
  vim.fn.writefile(lines, path)
end

H.colorscheme_get_current_name = function(make_unique_name)
  local res = vim.g.colors_name or 'minicolors_snapshot'
  if make_unique_name then res = res .. vim.fn.strftime('_%Y%m%d_%H%M%S') end
  return res
end

H.colorscheme_get_current_groups = function()
  -- Get present highlight group names and if they are linked
  local group_data = vim.split(vim.api.nvim_exec('highlight', true), '\n')
  local group_names = vim.tbl_map(function(x) return x:match('^(%S+)') end, group_data)
  local link_data = vim.tbl_map(function(x) return x:match('^%S+.* links to %s-(%S+)$') end, group_data)

  local res = {}
  for i, name in pairs(group_names) do
    if link_data[i] ~= nil then
      res[name] = { link = link_data[i] }
    else
      res[name] = H.get_hl_by_name(name)
    end
  end
  return res
end

H.colorscheme_get_current_integrations = function(themes)
  themes = themes or {}
  local res = {}

  -- nvim-lualine/lualine.nvim
  if type(themes.lualine) ~= 'string' then
    local lualine = H.require_safe('lualine')
    themes.lualine = lualine == nil and 'auto' or lualine.get_config().options.theme
  end

  res.lualine = { theme = themes.lualine, module = H.require_safe('lualine.themes.' .. themes.lualine) }

  -- utilyre/barbecue.nvim
  if type(themes.barbecue) ~= 'string' then
    local barbecue_config = H.require_safe('barbecue.config')
    themes.barbecue = barbecue_config == nil and 'auto' or barbecue_config.user.theme
  end
  -- - Using 'auto' as theme in config leads to 'barbecue.theme.default' theme
  if themes.barbecue == 'auto' then themes.barbecue = 'default' end

  res.barbecue = { theme = themes.barbecue, module = H.require_safe('barbecue.theme.' .. themes.barbecue) }

  return res
end

H.colorscheme_ensure_unique = function(name)
  local all_colorschemes_files = vim.api.nvim_get_runtime_file('colors/*.{vim,lua}', true)

  for _, path in ipairs(all_colorschemes_files) do
    local file_name = vim.fn.fnamemodify(path, ':t:r')
    if name == file_name then
      local msg = string.format('Color scheme "%s" is already present in runtime at "%s".', name, path)
      H.error(msg)
    end
  end
end

H.get_hl_by_name = function(name)
  local res = vim.api.nvim_get_hl_by_name(name, true)

  -- At the moment, having `res[true] = 6` indicates that group is cleared
  if res[true] ~= nil then return nil end

  -- Convert decimal colors to hex strings
  res.fg = H.dec2hex(res.foreground)
  res.bg = H.dec2hex(res.background)
  res.sp = H.dec2hex(res.special)

  res.foreground, res.background, res.special = nil, nil, nil

  -- Add terminal colors
  local cterm_data = vim.api.nvim_get_hl_by_name(name, false)
  res.ctermfg = cterm_data.foreground
  res.ctermbg = cterm_data.background

  return res
end

H.dec2hex = function(dec)
  if dec == nil then return nil end
  return string.format('#%06x', dec)
end

H.hl_groups_to_array = function(hl_groups)
  local res = {}
  for name, spec in pairs(hl_groups) do
    table.insert(res, { name = name, spec = spec })
  end
  table.sort(res, function(a, b) return a.name < b.name end)
  return res

  -- -- Deal with linked and non-linked hl_groups separately
  -- local linked, non_linked = {}, {}
  -- for name, spec in pairs(hl_groups) do
  --   if spec.link ~= nil then
  --     table.insert(linked, { name = name, spec = spec })
  --   else
  --     table.insert(non_linked, { name = name, spec = spec })
  --   end
  -- end
  --
  -- -- Sort non-linked hl_groups alphabetically but put `Normal` first (as it is
  -- -- "main" group which is nice having listed first)
  -- table.sort(non_linked, function(a, b)
  --   if a.name == 'Normal' then return true end
  --   if b.name == 'Normal' then return false end
  --   return a.name < b.name
  -- end)
  --
  -- -- Sort linked hl_groups alphabetically. NOTE: there is no need to account
  -- -- for nested linking because linking to (yet) not existing highlight
  -- -- group works just fine.
  -- table.sort(linked, function(a, b) return a.name < b.name end)
  --
  -- return vim.list_extend(non_linked, linked)
end

H.hl_groups_to_strings = function(hl_groups)
  return vim.tbl_map(
    function(hl) return string.format('hi("%s", %s)', hl.name, vim.inspect(hl.spec, { newline = ' ', indent = ' ' })) end,
    H.hl_groups_to_array(hl_groups)
  )
end

-- Oklab ----------------------------------------------------------------------

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.colors) %s', msg), 0) end

H.require_safe = function(module)
  local ok, res = pcall(require, module)
  if not ok then return nil end
  return res
end

return MiniColors
