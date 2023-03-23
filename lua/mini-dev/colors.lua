-- TODO:
--
-- Code:
-- - Think whether it is reasonable to have both 'red-green' and 'blue-yellow'
--   as they seem to be almost the same thing under current implementation
--   (which operates on hue circle trying to preserve lightness and chroma).
--
-- - Explore possibility of hooking into `ColorSchemePre` and `ColorScheme`
--   events to perform automatic transition animation.
--
-- - Generally think about unifying units of channels in `color_adjust()` and
--   `color_shift()`.
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
--     - `terminal` - terminal colors (see `:h terminal-config`)
--
-- - Planned methods of `Colorscheme` object:
--     - `ensure_cterm({force = false})` - compute closest terminal colors for
--       all present gui ones. If `opts.force`, redo present terminal colors.
--     - `apply()` - apply all colors from color scheme to current session.
--       See https://github.com/rktjmp/lush.nvim/blob/62180850d230e1650fe5543048bb15c4452916d6/lua/lush.lua#L29
--     - `color_adjust(channel, dial, predicate)`. `channel`: "lightness",
--       "chroma", "red", "green", "blue", ?"temperature"?, ?"color-blind" or
--       "red-gree"/"blue-yellow"?
--     - `color_shift(channel, by, predicate)`.
--     - `change_colorblind_friendly()` (come up with better name) - takes some
--       parameters and modifies color scheme to be more colorblind friendly.
--     - `make_transparent()`
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
-- - Channels:
--     - Lightness - corrected `l` component of Oklch.
--     - Chroma - `c` component of Oklch.
--     - Hue - `h` component of Oklch.
--     - Temperature - `b` component of Oklab.
--     - ????? - `a` component of Oklab.
--     - Red-green - absolute value of `a` of Oklab.
--     - Blue-yellow - absolute value of `b` of Oklab.
--     - Red - `r` component of RGB.
--     - Green - `g` component of RGB.
--     - Blue - `b` component of RGB.
--
-- - Give examples of approximate hue degree names:
--     - 0 - pink.
--     - 30 - red.
--     - 45 - orange.
--     - 90 - yellow.
--     - 135 - green.
--     - 180 - cyan.
--     - 225 - light blue.
--     - 270 - blue.
--     - 315 - magenta/purple.

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
  res.terminal = res.terminal or {}

  -- Methods
  res.apply = H.cs_apply
  res.color_adjust = H.cs_color_adjust
  res.color_invert = H.cs_color_invert
  res.color_shift = H.cs_color_shift
  res.color_map = H.cs_color_map
  res.compress = H.cs_compress
  res.write = H.cs_write

  return res
end

MiniColors.get_current_colorscheme = function(opts)
  opts = vim.tbl_deep_extend('force', { new_name = nil }, opts or {})

  return MiniColors.as_colorscheme({
    name = opts.new_name or vim.g.colors_name,
    groups = H.get_current_groups(),
    terminal = H.get_current_terminal(),
  })
end

MiniColors.hex2oklab = function(hex, opts)
  if hex == nil then return nil end
  opts = vim.tbl_deep_extend('force', { corrected_l = true }, opts or {})

  local res = H.rgb2oklab(H.hex2rgb(hex))
  res.l, res.a, res.b = 100 * res.l, 100 * res.a, 100 * res.b
  if opts.corrected_l then res.l = H.correct_lightness(res.l) end

  return res
end

MiniColors.oklab2hex = function(lab, opts)
  if lab == nil then return nil end
  opts = vim.tbl_deep_extend('force', { corrected_l = true, clip_method = 'chroma' }, opts or {})

  -- Use Oklch color space because it is used for gamut clipping
  return MiniColors.oklch2hex(H.oklab2oklch(lab), opts)
end

MiniColors.hex2oklch = function(hex, opts)
  if hex == nil then return nil end
  opts = vim.tbl_deep_extend('force', { corrected_l = true }, opts or {})

  return H.oklab2oklch(MiniColors.hex2oklab(hex, opts))
end

MiniColors.oklch2hex = function(lch, opts)
  if lch == nil then return nil end
  opts = vim.tbl_deep_extend('force', { corrected_l = true, clip_method = 'chroma' }, opts or {})

  -- Make effort to have point inside gamut. NOTE: not always precise, i.e. not
  -- always results into point in gamut, but sufficiently close.
  lch.h = lch.h % 360
  local lch_in_gamut = H.clip_to_gamut(lch, opts.clip_method)

  local lab = H.oklch2oklab(lch_in_gamut)
  if opts.corrected_l then lab.l = H.correct_lightness_inv(lab.l) end
  lab.l, lab.a, lab.b = 0.01 * lab.l, 0.01 * lab.a, 0.01 * lab.b

  return H.rgb2hex(H.oklab2rgb(lab))
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniColors.config

-- Color conversion constants
H.tau = 2 * math.pi

-- Cusps for Oklch color space. These represent (c, l) points of Oklch space
-- (with **not corrected lightness**) inside a hue leaf (points with
-- `math.floor(h) = <index>`) with the highest value of chroma (`c`).
-- They are used to model the whole RGB gamut (region inside which sRGB colors
-- are converted in Oklch space). It is modelled as triangle with vertices:
-- (0, 0), (0, 100) and cusp. NOTE: this is an approximation, i.e. not all RGB
-- colors lie inside this triangle **AND** not all points inside triangle are
-- RGB colors. But both proportions are small: around 0.5% with similar modeled
-- RGB color for first one and around 2.16% for second one.
---@diagnostic disable-next-line
--stylua: ignore
H.cusps = {
  [0] = {26.23,64.74},
  {26.14,64.65},{26.06,64.56},{25.98,64.48},{25.91,64.39},{25.82,64.29},{25.76,64.21},{25.70,64.13},{25.65,64.06},
  {25.59,63.97},{25.55,63.90},{25.52,63.83},{25.48,63.77},{25.45,63.69},{25.43,63.63},{25.41,63.55},{25.40,63.50},
  {25.39,63.43},{25.40,63.33},{25.40,63.27},{25.42,63.22},{25.44,63.15},{25.46,63.11},{25.50,63.05},{25.53,63.00},
  {25.58,62.95},{25.63,62.90},{25.69,62.85},{25.75,62.81},{25.77,62.80},{25.34,63.25},{24.84,63.79},{24.37,64.32},
  {23.92,64.83},{23.48,65.35},{23.08,65.85},{22.65,66.38},{22.28,66.86},{21.98,67.27},{21.67,67.70},{21.36,68.14},
  {21.05,68.60},{20.74,69.08},{20.50,69.45},{20.27,69.83},{20.04,70.22},{19.82,70.62},{19.60,71.03},{19.38,71.44},
  {19.17,71.87},{19.03,72.16},{18.83,72.59},{18.71,72.89},{18.52,73.34},{18.40,73.64},{18.28,73.95},{18.17,74.26},
  {18.01,74.74},{17.91,75.05},{17.82,75.38},{17.72,75.70},{17.64,76.03},{17.56,76.36},{17.48,76.69},{17.41,77.03},
  {17.35,77.36},{17.29,77.71},{17.24,78.05},{17.19,78.39},{17.15,78.74},{17.12,79.09},{17.09,79.45},{17.07,79.80},
  {17.05,80.16},{17.04,80.52},{17.04,81.06},{17.04,81.42},{17.05,81.79},{17.07,82.16},{17.08,82.53},{17.11,82.72},
  {17.14,83.09},{17.18,83.46},{17.22,83.84},{17.27,84.22},{17.33,84.60},{17.39,84.98},{17.48,85.56},{17.56,85.94},
  {17.64,86.33},{17.73,86.72},{17.81,87.10},{17.91,87.50},{18.04,88.09},{18.16,88.48},{18.27,88.88},{18.40,89.48},
  {18.57,89.87},{18.69,90.27},{18.88,90.87},{19.03,91.48},{19.22,91.88},{19.44,92.49},{19.66,93.10},{19.85,93.71},
  {20.04,94.33},{20.33,94.94},{20.60,95.56},{20.85,96.18},{21.10,96.80},{21.19,96.48},{21.27,96.24},{21.38,95.93},
  {21.47,95.70},{21.59,95.40},{21.72,95.10},{21.86,94.80},{21.97,94.58},{22.12,94.30},{22.27,94.02},{22.43,93.74},
  {22.64,93.40},{22.81,93.14},{23.04,92.81},{23.22,92.56},{23.45,92.25},{23.68,91.95},{23.92,91.65},{24.21,91.31},
  {24.45,91.04},{24.74,90.72},{25.08,90.36},{25.37,90.07},{25.70,89.74},{26.08,89.39},{26.44,89.07},{26.87,88.69},
  {27.27,88.34},{27.72,87.98},{28.19,87.61},{28.68,87.23},{29.21,86.84},{29.48,86.64},{28.99,86.70},{28.13,86.81},
  {27.28,86.92},{26.56,87.02},{25.83,87.12},{25.18,87.22},{24.57,87.32},{24.01,87.41},{23.53,87.49},{23.03,87.58},
  {22.53,87.68},{22.10,87.76},{21.68,87.84},{21.26,87.93},{20.92,88.01},{20.58,88.08},{20.25,88.16},{19.92,88.24},
  {19.59,88.33},{19.35,88.39},{19.12,88.46},{18.81,88.55},{18.58,88.61},{18.36,88.68},{18.14,88.76},{17.93,88.83},
  {17.79,88.88},{17.59,88.95},{17.39,89.03},{17.26,89.08},{17.08,89.16},{16.96,89.21},{16.79,89.29},{16.68,89.35},
  {16.58,89.41},{16.43,89.49},{16.33,89.55},{16.24,89.60},{16.16,89.66},{16.04,89.75},{15.96,89.81},{15.89,89.87},
  {15.83,89.93},{15.77,89.99},{15.71,90.05},{15.66,90.12},{15.61,90.18},{15.57,90.24},{15.54,90.31},{15.51,90.37},
  {15.48,90.44},{15.46,90.51},{15.40,90.30},{15.30,89.83},{15.21,89.36},{15.12,88.89},{15.03,88.67},{14.99,88.18},
  {14.92,87.71},{14.85,87.24},{14.78,86.77},{14.75,86.53},{14.70,86.06},{14.65,85.59},{14.61,85.12},{14.60,84.89},
  {14.57,84.42},{14.54,83.94},{14.53,83.71},{14.52,83.24},{14.51,82.77},{14.52,82.30},{14.52,81.83},{14.53,81.60},
  {14.55,81.13},{14.58,80.66},{14.59,80.43},{14.63,79.96},{14.68,79.49},{14.70,79.26},{14.76,78.79},{14.82,78.32},
  {14.85,78.09},{14.93,77.62},{15.01,77.16},{15.10,76.69},{15.19,76.23},{15.24,76.00},{15.34,75.54},{15.45,75.07},
  {15.57,74.61},{15.69,74.15},{15.82,73.69},{15.96,73.23},{16.10,72.77},{16.24,72.31},{16.39,71.86},{16.55,71.40},
  {16.71,70.95},{16.96,70.26},{17.14,69.81},{17.32,69.36},{17.59,68.69},{17.88,68.02},{18.07,67.57},{18.37,66.90},
  {18.67,66.24},{18.99,65.58},{19.30,64.93},{19.74,64.06},{20.07,63.42},{20.51,62.57},{20.97,61.73},{21.54,60.69},
  {22.00,59.87},{22.70,58.66},{23.39,57.49},{24.19,56.16},{25.20,54.52},{26.38,52.66},{28.55,49.32},{31.32,45.20},
  {31.15,45.42},{30.99,45.64},{30.85,45.85},{30.72,46.06},{30.57,46.31},{30.47,46.50},{30.34,46.75},{30.23,46.97},
  {30.13,47.20},{30.03,47.45},{29.93,47.71},{29.86,47.91},{29.77,48.20},{29.71,48.43},{29.65,48.66},{29.58,48.98},
  {29.53,49.23},{29.48,49.48},{29.44,49.74},{29.41,50.01},{29.37,50.29},{29.35,50.57},{29.33,50.86},{29.31,51.16},
  {29.30,51.56},{29.29,51.87},{29.29,52.39},{29.30,52.72},{29.31,53.05},{29.33,53.38},{29.35,53.72},{29.37,54.06},
  {29.40,54.41},{29.43,54.76},{29.47,55.12},{29.52,55.60},{29.56,55.97},{29.61,56.34},{29.66,56.72},{29.73,57.22},
  {29.79,57.61},{29.84,57.99},{29.93,58.52},{29.99,58.91},{30.08,59.44},{30.15,59.84},{30.24,60.38},{30.34,60.93},
  {30.42,61.34},{30.52,61.90},{30.63,62.45},{30.73,63.02},{30.85,63.58},{30.96,64.15},{31.08,64.72},{31.19,65.30},
  {31.31,65.88},{31.44,66.46},{31.59,67.20},{31.72,67.79},{31.88,68.53},{32.01,69.12},{32.18,69.87},{32.25,70.17},
  {32.06,69.99},{31.76,69.70},{31.45,69.42},{31.21,69.20},{30.97,68.98},{30.68,68.71},{30.44,68.50},{30.21,68.29},
  {29.98,68.09},{29.75,67.89},{29.53,67.69},{29.31,67.50},{29.09,67.31},{28.88,67.12},{28.72,66.98},{28.52,66.80},
  {28.31,66.63},{28.16,66.50},{27.97,66.33},{27.78,66.17},{27.64,66.05},{27.49,65.94},{27.33,65.77},{27.20,65.66},
  {27.04,65.51},{26.92,65.40},{26.81,65.30},{26.66,65.16},{26.55,65.06},{26.45,64.96},{26.35,64.87},
}

H.allowed_channels = { 'lightness', 'chroma', 'hue', 'temperature', 'red-green', 'blue-yellow', 'red', 'green', 'blue' }

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

  -- Highlight groups
  local hi = vim.api.nvim_set_hl
  local groups_arr = H.hl_groups_to_array(self.groups)
  for _, hl_data in ipairs(groups_arr) do
    hi(0, hl_data.name, hl_data.spec)
  end

  -- Terminal colors
  for i, val in pairs(self.terminal) do
    vim.g['terminal_color_' .. i] = val
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

  return MiniColors.as_colorscheme({ name = self.name, groups = new_groups, terminal = self.terminal })
end

H.cs_color_adjust = function(self, channel, dial, predicate, opts)
  channel = H.normalize_channel(channel or 'lightness')
  dial = H.normalize_dial(dial or 0)
  predicate = H.normalize_predicate(predicate)
  opts = vim.tbl_extend('force', { clip_method = 'chroma' }, opts or {})

  if dial == 0 then return self end

  local adjust_channel = H.color_adjusters[channel]
  if adjust_channel == nil then
    local msg = string.format('Channel %s is not supported in `color_adjust()`.', vim.inspect(channel))
    H.error(msg)
  end

  local f = function(hex, data)
    if not predicate(hex, data) then return hex end
    return adjust_channel(hex, dial, opts.clip_method)
  end

  return self:color_map(f)
end

H.cs_color_map = function(self, f)
  local res = vim.deepcopy(self)

  -- Highlight groups
  for name, spec in pairs(res.groups) do
    if spec.fg ~= nil then spec.fg = f(spec.fg, { attr = 'fg', group = name }) end
    if spec.bg ~= nil then spec.bg = f(spec.bg, { attr = 'bg', group = name }) end
    if spec.sp ~= nil then spec.sp = f(spec.sp, { attr = 'sp', group = name }) end
  end

  -- Terminal colors
  for i, hex in pairs(res.terminal) do
    res.terminal[i] = f(hex, { attr = 'term', group = 'terminal_color_' .. i })
  end

  return res
end

H.cs_color_invert = function(self, channel, predicate, opts)
  channel = H.normalize_channel(channel or 'lightness')
  predicate = H.normalize_predicate(predicate)
  opts = vim.tbl_extend('force', { clip_method = 'chroma' }, opts or {})

  local invert_channel = H.color_inverters[channel]
  if invert_channel == nil then
    local msg = string.format('Channel %s is not supported in `color_invert()`.', vim.inspect(channel))
    H.error(msg)
  end

  local f = function(hex, data)
    if not predicate(hex, data) then return hex end
    return invert_channel(hex, opts.clip_method)
  end

  return self:color_map(f)
end

H.cs_color_shift = function(self, channel, by, predicate, opts)
  channel = H.normalize_channel(channel or 'lightness')
  by = H.normalize_by(by or 0)
  predicate = H.normalize_predicate(predicate)
  opts = vim.tbl_extend('force', { clip_method = 'chroma' }, opts or {})

  if by == 0 then return self end

  local shift_channel = H.color_shifters[channel]
  if shift_channel == nil then
    local msg = string.format('Channel %s is not supported in `color_shift()`.', vim.inspect(channel))
    H.error(msg)
  end

  local f = function(hex, data)
    if not predicate(hex, data) then return hex end
    return shift_channel(hex, by, opts.clip_method)
  end

  return self:color_map(f)
end

H.cs_write = function(self, opts)
  opts = vim.tbl_extend(
    'force',
    { compress = true, directory = (vim.fn.stdpath('config') .. '/colors'), name = nil },
    opts or {}
  )

  local name = opts.name or H.make_file_basename(self.name)

  local cs = opts.compress and vim.deepcopy(self):compress() or self

  -- Create file lines
  -- - Header
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

  -- - Highlight groups
  local lines_groups = vim.tbl_map(
    function(hl) return string.format('hi(0, "%s", %s)', hl.name, vim.inspect(hl.spec, { newline = ' ', indent = '' })) end,
    H.hl_groups_to_array(self.groups)
  )
  vim.list_extend(lines, lines_groups)

  -- - Terminal colors
  if vim.tbl_count(self.terminal) > 0 then
    vim.list_extend(lines, { '', '-- Terminal colors', 'local g = vim.g', '' })
  end
  for i, hex in pairs(self.terminal) do
    local l = string.format('g.terminal_color_%d = "%s"', i, hex)
    table.insert(lines, l)
  end

  -- Create file and populate with computed lines
  vim.fn.mkdir(opts.directory, 'p')
  local path = string.format('%s/%s.lua', opts.directory, name)
  vim.fn.writefile(lines, path)
end

H.normalize_channel = function(x)
  if not vim.tbl_contains(H.allowed_channels, x) then
    local msg =
      string.format('Channel should be one of %s. Not %s.', table.concat(H.allowed_channels, ', '), vim.inspect(x))
    H.error(msg)
  end
  return x
end

H.normalize_predicate = function(x)
  -- Treat `nil` predicate as no predicate
  if x == nil then x = function() return true end end

  -- Treat string predicate as filter on attribute ('fg', 'bg', etc.)
  if type(x) == 'string' then
    local attr_val = x
    x = function(_, data) return data.attr == attr_val end
  end

  if not vim.is_callable(x) then H.error('Argument `predicate` should be either attribute string or callable.') end

  return x
end

H.normalize_dial = function(x)
  if type(x) ~= 'number' or x < -1 or 1 < x then H.error('Argument `dial` should be a number between -1 and 1.') end
  return x
end

H.normalize_by = function(x)
  if type(x) ~= 'number' then H.error('Argument `by` should be a number.') end
  return x
end

-- Color scheme helpers -------------------------------------------------------
H.make_file_basename = function(name)
  -- If there already is color scheme file named `name`, append unique suffix
  local all_colorschemes_files = vim.api.nvim_get_runtime_file('colors/*.{vim,lua}', true)

  for _, path in ipairs(all_colorschemes_files) do
    local file_name = vim.fn.fnamemodify(path, ':t:r')
    if name == file_name then return name .. vim.fn.strftime('_%Y%m%d_%H%M%S') end
  end

  return name
end

H.get_current_groups = function()
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

H.get_current_terminal = function()
  local res = {}
  for i = 0, 15 do
    local col = vim.g['terminal_color_' .. i]
    -- Use only defined colors with proper HEX values (ignores color names)
    if type(col) == 'string' and col:find('^#%x%x%x%x%x%x$') ~= nil then res[i] = col end
  end

  return res
end

H.get_hl_by_name = function(name)
  local res = vim.api.nvim_get_hl_by_name(name, true)

  -- At the moment, having `res[true] = 6` indicates that group is cleared
  -- NOTE: actually return empty dictionary and not `nil` to preserve
  -- information that group was cleared. This might matter if highlight group
  -- was cleared but default links to something else (like if group
  -- `@lsp.type.variable` is cleared to use tree-sitter highlighting but by
  -- default it links to `Identifier`).
  if res[true] ~= nil then return {} end

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

-- Color adjust ---------------------------------------------------------------
H.color_adjusters = {}

H.color_adjusters.lightness = function(hex, dial)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = true })
  local gamut_points = H.get_gamut_points({ l = H.correct_lightness_inv(lch.l), c = lch.c, h = lch.h })

  local l_lower = H.correct_lightness(gamut_points.l_lower)
  local l_upper = H.correct_lightness(gamut_points.l_upper)
  lch.l = H.doubleconvex_point(lch.l, l_lower, l_upper, dial)

  return MiniColors.oklch2hex(lch, { corrected_l = true })
end

H.color_adjusters.chroma = function(hex, dial)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = false })
  if lch.c == 0 then return hex end

  local gamut_points = H.get_gamut_points(lch)

  lch.c = H.doubleconvex_point(lch.c, gamut_points.c_lower, gamut_points.c_upper, dial)

  return MiniColors.oklch2hex(lch, { corrected_l = false })
end

-- No adjuster for hue directly as there is no reasonable minimum and maximum

H.color_adjusters.temperature = function(hex, dial, clip_method)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = true })

  -- Minimum temperature is at 270 degree hue, maximum is 90
  -- After shift minimum is at 0, maximum is 180
  local h_shifted = (lch.h + 90) % 360
  local h_new = (h_shifted <= 180) and H.doubleconvex_point(h_shifted, 0, 180, dial)
    or H.doubleconvex_point(h_shifted, 180, 360, -dial)
  lch.h = (h_new - 90) % 360

  return MiniColors.oklch2hex(lch, { corrected_l = true, clip_method = clip_method })
end

H.color_adjusters['red-green'] = function(hex, dial, clip_method)
  local lch = MiniColors.hex2oklch(hex)

  -- Adjust absolute value of `a` based on quadrant edges:
  -- - Dial -1 should adjust towards y-axis.
  -- - Dial 1  should adjust away from y-axis.
  local quadrant = H.get_quadrant(lch.h)
  if quadrant == 1 then lch.h = H.doubleconvex_point(lch.h, 90, 0, dial) end
  if quadrant == 2 then lch.h = H.doubleconvex_point(lch.h, 90, 180, dial) end
  if quadrant == 3 then lch.h = H.doubleconvex_point(lch.h, 270, 180, dial) end
  if quadrant == 4 then lch.h = H.doubleconvex_point(lch.h, 270, 360, dial) end

  return MiniColors.oklch2hex(lch, { clip_method = clip_method })
end

H.color_adjusters['blue-yellow'] =
  function(hex, dial, clip_method) return H.color_adjusters['red-green'](hex, -dial, clip_method) end

H.color_adjusters.red = function(hex, dial)
  local rgb = H.hex2rgb(hex)
  rgb.r = H.doubleconvex_point(rgb.r, 0, 1, dial)
  return H.rgb2hex(rgb)
end

H.color_adjusters.green = function(hex, dial)
  local rgb = H.hex2rgb(hex)
  rgb.g = H.doubleconvex_point(rgb.g, 0, 1, dial)
  return H.rgb2hex(rgb)
end

H.color_adjusters.blue = function(hex, dial)
  local rgb = H.hex2rgb(hex)
  rgb.b = H.doubleconvex_point(rgb.b, 0, 1, dial)
  return H.rgb2hex(rgb)
end

-- Color inversion ------------------------------------------------------------
H.color_inverters = {}

H.color_inverters.lightness = function(hex, clip_method)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = true })
  -- This results into a better output but might result into point outside of
  -- gamut. That is why gamut clipping is important here. This approach also is
  -- not one-to-one invertable: applying it twice might lead to slightly
  -- different colors depending on clip method (like smaller chroma with
  -- default "chroma" clip method).
  lch.l = 100 - lch.l
  return MiniColors.oklch2hex(lch, { corrected_l = true, clip_method = clip_method })
end

H.color_inverters.chroma = function(hex, clip_method)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = false })
  -- Don't invert achromatic colors (black, greys, white)
  if lch.c == 0 then return hex end

  local gamut_points = H.get_gamut_points(lch)
  lch.c = gamut_points.c_upper - lch.c
  return MiniColors.oklch2hex(lch, { corrected_l = false, clip_method = clip_method })
end

-- No inverter for hue directly as there is no reasonable inversion

H.color_inverters.temperature = function(hex, clip_method)
  -- This is a simpler approach of inverting along the hue circle based on 90
  -- (highest temperature) and 270 (lowest) degrees
  local lab = MiniColors.hex2oklab(hex)
  lab.b = -lab.b
  return MiniColors.oklab2hex(lab, { clip_method = clip_method })
end

H.color_inverters['red-green'] = function(hex, clip_method)
  local lch = MiniColors.hex2oklch(hex)
  -- Invert absolute value of `a` based on quadrant edges towards y-axis
  local quadrant = H.get_quadrant(lch.h)
  lch.h = 90 * (quadrant - 1) + (90 * quadrant - lch.h)
  return MiniColors.oklch2hex(lch, { clip_method = clip_method })
end

-- Inverter for 'blue-yellow' is the same as 'red-green' because reducing
-- red-green along the circle increases blue-yellow and vice versa.
H.color_inverters['blue-yellow'] = H.color_inverters['red-green']

H.color_inverters.red = function(hex)
  local rgb = H.hex2rgb(hex)
  rgb.r = 1 - rgb.r
  return H.rgb2hex(rgb)
end

H.color_inverters.green = function(hex)
  local rgb = H.hex2rgb(hex)
  rgb.g = 1 - rgb.g
  return H.rgb2hex(rgb)
end

H.color_inverters.blue = function(hex)
  local rgb = H.hex2rgb(hex)
  rgb.b = 1 - rgb.b
  return H.rgb2hex(rgb)
end

-- Color shift ----------------------------------------------------------------
H.color_shifters = {}

H.color_shifters.lightness = function(hex, by, clip_method)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = true })
  lch.l = H.clip(lch.l + by, 0, 100)
  return MiniColors.oklch2hex(lch, { corrected_l = true, clip_method = clip_method })
end

H.color_shifters.chroma = function(hex, by, clip_method)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = false })
  local gamut_points = H.get_gamut_points(lch)
  lch.c = H.clip(lch.c + by, gamut_points.c_lower, gamut_points.c_upper)
  return MiniColors.oklch2hex(lch, { corrected_l = false, clip_method = clip_method })
end

H.color_shifters.hue = function(hex, by, clip_method)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = true })
  -- Positive direction is counter-clockwise
  lch.h = (lch.h + by) % 360
  return MiniColors.oklch2hex(lch, { corrected_l = true, clip_method = clip_method })
end

H.color_shifters.temperature = function(hex, by, clip_method)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = true })

  -- Positive direction is towards 90 degree angle
  -- Clip to not leave current vertical half
  local quadrant = H.get_quadrant(lch.h)
  if quadrant == 1 then lch.h = H.clip(lch.h + by, -90, 90) end
  if quadrant == 2 then lch.h = H.clip(lch.h - by, 90, 270) end
  if quadrant == 3 then lch.h = H.clip(lch.h - by, 90, 270) end
  if quadrant == 4 then lch.h = H.clip(lch.h + by, 270, 450) % 360 end

  return MiniColors.oklch2hex(lch, { corrected_l = true, clip_method = clip_method })
end

H.color_shifters['red-green'] = function(hex, by, clip_method)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = true })

  -- Positive direction is away from y-axis
  -- Clip to not leave current quadrant
  local quadrant = H.get_quadrant(lch.h)
  if quadrant == 1 then lch.h = H.clip(lch.h - by, 0, 90) end
  if quadrant == 2 then lch.h = H.clip(lch.h + by, 90, 180) end
  if quadrant == 3 then lch.h = H.clip(lch.h - by, 180, 270) end
  if quadrant == 4 then lch.h = H.clip(lch.h + by, 270, 360) % 360 end

  return MiniColors.oklch2hex(lch, { corrected_l = true, clip_method = clip_method })
end

H.color_shifters['blue-yellow'] = function(hex, by, clip_method)
  -- Positive direction is away from x-axis
  -- Clip to not leave current quadrant
  return H.color_shifters['red-green'](hex, -by, clip_method)
end

-- Oklab/Oklch ----------------------------------------------------------------
-- Sources:
-- https://github.com/bottosson/bottosson.github.io/blob/master/misc/colorpicker/colorconversion.js
-- https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab

-- HEX <-> RGB in [0;1]
H.hex2rgb = function(hex)
  local dec = tonumber(hex:sub(2), 16)

  local b = math.fmod(dec, 256)
  local g = math.fmod((dec - b) / 256, 256)
  local r = math.floor(dec / 65536)

  return { r = r / 255, g = g / 255, b = b / 255 }
end

H.rgb2hex = function(rgb)
  -- Use straightforward clipping to [0; 255] here to ensure correctness.
  -- Modify `rgb` prior to this to ensure only a small distortion.
  local r = H.clip(H.round(255 * rgb.r), 0, 255)
  local g = H.clip(H.round(255 * rgb.g), 0, 255)
  local b = H.clip(H.round(255 * rgb.b), 0, 255)

  return string.format('#%02x%02x%02x', r, g, b)
end

-- RGB in [0; 1] <-> Oklab in [0; 1]
-- https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
H.rgb2oklab = function(rgb)
  -- Convert to linear RGB
  local r, g, b = H.correct_channel(rgb.r), H.correct_channel(rgb.g), H.correct_channel(rgb.b)

  -- Convert to Oklab
  local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
  local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
  local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

  local l_, m_, s_ = H.cuberoot(l), H.cuberoot(m), H.cuberoot(s)

  local L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
  local A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
  local B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

  -- Explicitly convert for nearly achromatic colors
  if math.abs(A) < 1e-4 then A = 0 end
  if math.abs(B) < 1e-4 then B = 0 end

  return { l = L, a = A, b = B }
end

H.oklab2rgb = function(lab)
  local L, A, B = lab.l, lab.a, lab.b

  local l_ = L + 0.3963377774 * A + 0.2158037573 * B
  local m_ = L - 0.1055613458 * A - 0.0638541728 * B
  local s_ = L - 0.0894841775 * A - 1.2914855480 * B

  local l = l_ * l_ * l_
  local m = m_ * m_ * m_
  local s = s_ * s_ * s_

  --stylua: ignore
  local r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
  local g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
  local b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

  return { r = H.correct_channel_inv(r), g = H.correct_channel_inv(g), b = H.correct_channel_inv(b) }
end

-- Oklab<-> Oklch
H.oklab2oklch = function(lab)
  local c = math.sqrt(lab.a ^ 2 + lab.b ^ 2)
  local h = H.rad2degree(math.atan2(lab.b, lab.a))
  return { l = lab.l, c = c, h = h }
end

H.oklch2oklab = function(lch)
  local a = lch.c * math.cos(H.degree2rad(lch.h))
  local b = lch.c * math.sin(H.degree2rad(lch.h))
  return { l = lch.l, a = a, b = b }
end

-- Degree in [0; 360] <-> Radian in [0; 2*pi]
H.rad2degree = function(x) return (x % H.tau) * 360 / H.tau end

H.degree2rad = function(x) return (x % 360) * H.tau / 360 end

-- Functions for RGB channel correction. Assumes input in [0; 1] range
-- https://bottosson.github.io/posts/colorwrong/#what-can-we-do%3F
H.correct_channel = function(x)
  x = H.clip(x, 0, 1)
  return 0.04045 < x and math.pow((x + 0.055) / 1.055, 2.4) or (x / 12.92)
end

H.correct_channel_inv = function(x)
  x = H.clip(x, 0, 1)
  return (0.0031308 >= x) and (12.92 * x) or (1.055 * math.pow(x, 0.416666667) - 0.055)
end

-- Functions for lightness correction. Assumes input is in [0; 100] range
-- https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab
H.correct_lightness = function(x)
  x = 0.01 * x
  local k1, k2 = 0.206, 0.03
  local k3 = (1 + k1) / (1 + k2)

  local res = 0.5 * (k3 * x - k1 + math.sqrt((k3 * x - k1) ^ 2 + 4 * k2 * k3 * x))
  return 100 * res
end

H.correct_lightness_inv = function(x)
  x = 0.01 * x
  local k1, k2 = 0.206, 0.03
  local k3 = (1 + k1) / (1 + k2)
  local res = (x / k3) * (x + k1) / (x + k2)
  return 100 * res
end

-- Get gamut ranges for Lch point. They are computed for its hue leaf as
-- segments of triangle in (c, l) coordinates ((0, 0), (0, 100), cusp).
-- Equations for triangle parts:
-- - Lower segment ((0; 0) to cusp): y * c_cusp = x * L_cusp
-- - Upper segment ((0; 100) to cusp): (100 - y) * c_cusp = x * (100 - L_cusp)
-- NOTEs:
-- - It is **very important** that this triangle is computed for **not
--   corrected** lightness. Input should also have **not corrected** lightness.
-- - This approach is not entirely accurate and can results in ranges outside
--   of input `lch` for in-gamut point. Put it should be pretty rare: ~0.5%
--   cases for most saturated colors.
H.get_gamut_points = function(lch)
  local l, c = lch.l, lch.c
  local cusp = H.cusps[math.floor(lch.h % 360)]

  -- Range of allowed lightness is computed based on current chroma:
  -- - Lower is from segment between (0, 0) and cusp.
  -- - Upper is from segment between (0, 100) and cusp.
  local l_lower, l_upper
  if c < 0 then
    l_lower, l_upper = 0, 100
  elseif cusp[1] < c then
    l_lower, l_upper = cusp[2], cusp[2]
  else
    local saturation = c / cusp[1]
    l_lower = saturation * cusp[2]
    l_upper = saturation * (cusp[2] - 100) + 100
  end

  -- Maximum allowed chroma is computed based on currnet lightness and depends
  -- on whether `l` is below or above cusp's `l`:
  -- - If below, then it is from lower triangle segment.
  -- - If above - from upper segment.
  local c_lower, c_upper = 0, nil
  if l < 0 or 100 < l then
    c_upper = 0
  else
    c_upper = l <= cusp[2] and (cusp[1] * l / cusp[2]) or (cusp[1] * (100 - l) / (100 - cusp[2]))
  end

  return { l_lower = l_lower, l_upper = l_upper, c_lower = c_lower, c_upper = c_upper }
end

H.clip_to_gamut = function(lch, clip_method)
  -- `lch` should have not corrected lightness
  local res = vim.deepcopy(lch)
  local gamut_points = H.get_gamut_points(lch)

  local is_inside_gamut = gamut_points.l_lower <= lch.l
    and lch.l <= gamut_points.l_upper
    and gamut_points.c_lower <= lch.c
    and lch.c <= gamut_points.c_upper

  if is_inside_gamut then return res end

  if clip_method == 'chroma' then
    -- Preserve lightness by clipping chroma
    res.c = H.clip(res.c, gamut_points.c_lower, gamut_points.c_upper)
  end

  if clip_method == 'lightness' then
    -- Preserve chroma by clipping lightness
    res.l = H.clip(res.l, gamut_points.l_lower, gamut_points.l_upper)
  end

  return res
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.colors) %s', msg), 0) end

H.round = function(x) return math.floor(x + 0.5) end

H.clip = function(x, from, to) return math.min(math.max(x, from), to) end

H.cuberoot = function(x) return math.pow(x, 0.333333) end

H.sign = function(x) return x == 0 and 0 or (x < 0 and -1 or 1) end

H.get_quadrant = function(degree) return math.floor((degree % 360) / 90) + 1 end

H.convex_point = function(x, y, coef) return (1 - coef) * x + coef * y end

H.doubleconvex_point = function(x, min, max, coef)
  if coef < 0 then return H.convex_point(x, min, -coef) end
  return H.convex_point(x, max, coef)
end

return MiniColors
