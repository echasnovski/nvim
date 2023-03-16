-- TODO:
--
-- Code:
-- - Try to understand whether adding `compile` option to `colorscheme.write()`
--   is worth it. Generally, look at 'catppuccin.nvim', which seems to
--   mean mostly the same thing as current `write()` (create all
--   highlight groups with `nvim_set_hl()`). Difference is that Catppuccin
--   creates two binary files and uses `f = loadfile(...); f()`
--   instead of `:source`.
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
--
-- - Planned methods of `Colorscheme` object:
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
  res.groups = res.groups or {}
  res.name = res.name

  -- Methods
  res.apply = H.cs_apply
  res.compress = H.cs_compress
  res.write = H.cs_write

  return res
end

MiniColors.get_current_colorscheme = function(opts)
  opts = vim.tbl_deep_extend('force', { new_name = nil }, opts or {})

  return MiniColors.as_colorscheme({
    name = opts.new_name or vim.g.colors_name,
    groups = H.cs_get_current_groups(),
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

-- Color scheme methods -------------------------------------------------------
H.cs_apply = function(self)
  if vim.g.colors_name ~= nil then vim.cmd('highlight clear') end
  vim.g.colors_name = self.name

  local hi = vim.api.nvim_set_hl
  local groups_arr = H.hl_groups_to_array(self.groups)
  for _, hl_data in ipairs(groups_arr) do
    hi(0, hl_data.name, hl_data.spec)
  end
end

H.cs_compress = function(self)
  local current_cs = MiniColors.get_current_colorscheme()

  vim.cmd('highlight clear')
  local clear_cs_groups = MiniColors.get_current_colorscheme().groups

  local new_groups = {}
  for name, spec in pairs(self.groups) do
    -- Group should stay only if it adds new information compared to the state
    -- after `:hi clear`
    local is_from_clear = vim.deep_equal(clear_cs_groups[name], spec)

    -- `^DevIcon` groups come from 'nvim-tree/nvim-web-devicons' and don't
    -- really have value outside of that plugin. Plus there are **many** of
    -- them and they are created in that plugin.
    local is_devicon = name:find('^DevIcon') ~= nil

    -- `^colorizer_` groups come from 'norcalli/nvim-colorizer.lua' plugin and
    -- don't really have value outside of that plugin.
    local is_colorizer = name:find('^colorizer_') ~= nil

    if not (is_from_clear or is_devicon or is_colorizer) then new_groups[name] = spec end
  end

  current_cs:apply()

  return MiniColors.as_colorscheme({ name = self.name, groups = new_groups })
end

H.cs_write = function(self, opts)
  opts = vim.tbl_extend('force', { directory = (vim.fn.stdpath('config') .. '/colors'), name = nil }, opts or {})

  local name = opts.name or H.cs_make_file_basename(self.name)

  -- Create file lines
  local lines = {
    [[-- Made with 'mini.colors' module of https://github.com/echasnovski/mini.nvim]],
    '',
    [[if vim.g.colors_name ~= nil then vim.cmd('highlight clear') end]],
    'vim.g.colors_name = ' .. vim.inspect(self.name),
    '',
    '-- Highlight groups',
    'local hi = vim.api.nvim_set_hl',
    '',
  }

  local lines_groups = vim.tbl_map(
    function(hl) return string.format('hi(0, "%s", %s)', hl.name, vim.inspect(hl.spec, { newline = ' ', indent = '' })) end,
    H.hl_groups_to_array(self.groups)
  )
  vim.list_extend(lines, lines_groups)

  -- Create file and populate with computed lines
  vim.fn.mkdir(opts.directory, 'p')
  local path = string.format('%s/%s.lua', opts.directory, name)
  vim.fn.writefile(lines, path)
end

-- Color scheme helpers -------------------------------------------------------
H.cs_make_file_basename = function(name)
  -- If there already is color scheme file named `name`, append unique suffix
  local all_colorschemes_files = vim.api.nvim_get_runtime_file('colors/*.{vim,lua}', true)

  for _, path in ipairs(all_colorschemes_files) do
    local file_name = vim.fn.fnamemodify(path, ':t:r')
    if name == file_name then return name .. vim.fn.strftime('_%Y%m%d_%H%M%S') end
  end

  return name
end

H.cs_get_current_groups = function()
  -- Get present highlight group names and if they are linked
  local group_data = vim.split(vim.api.nvim_exec('highlight', true), '\n')
  local group_names = vim.tbl_map(function(x) return x:match('^(%S+)') end, group_data)
  local link_data = vim.tbl_map(function(x) return x:match('^%S+.* links to (%S+)$') end, group_data)

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
end

-- Oklab ----------------------------------------------------------------------

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.colors) %s', msg), 0) end

return MiniColors
