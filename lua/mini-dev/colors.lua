-- TODO:
--
-- Code:
-- - Probably, implement OKHSL for (hopefuly) better handling of saturation.
--
-- - Experiment with inversion. Maybe differntiate how dark->light and
--   light->dark is done.
--
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
--     - `terminal_colors` (see `:h terminal-config`)
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
  res.terminal_colors = res.terminal_colors or {}

  -- Methods
  res.apply = H.cs_apply
  res.compress = H.cs_compress
  res.invert = H.cs_invert
  res.map_colors = H.cs_map_colors
  res.write = H.cs_write

  return res
end

MiniColors.get_current_colorscheme = function(opts)
  opts = vim.tbl_deep_extend('force', { new_name = nil }, opts or {})

  return MiniColors.as_colorscheme({
    name = opts.new_name or vim.g.colors_name,
    groups = H.get_current_groups(),
    terminal_colors = H.get_current_terminal_colors(),
  })
end

MiniColors.hex2oklab = function(hex)
  if hex == nil then return nil end
  return H.rgb2oklab(H.hex2rgb(hex))
end

MiniColors.oklab2hex = function(oklab)
  if oklab == nil then return nil end
  return H.rgb2hex(H.oklab2rgb(oklab))
end

MiniColors.hex2okhsl = function(hex)
  if hex == nil then return nil end
  return H.rgb2okhsl(H.hex2rgb(hex))
end

MiniColors.okhsl2hex = function(okhsl)
  if okhsl == nil then return nil end
  return H.rgb2hex(H.okhsl2rgb(okhsl))
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniColors.config

-- Color conversion constants
H.tau = 2 * math.pi

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
  for i, val in pairs(self.terminal_colors) do
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

  return MiniColors.as_colorscheme({ name = self.name, groups = new_groups, terminal_colors = self.terminal_colors })
end

H.cs_map_colors = function(self, f)
  local res = vim.deepcopy(self)

  -- Highlight groups
  for name, spec in pairs(res.groups) do
    if spec.fg ~= nil then spec.fg = f(spec.fg, { part = 'fg', group = name }) end
    if spec.bg ~= nil then spec.bg = f(spec.bg, { part = 'bg', group = name }) end
    if spec.sp ~= nil then spec.sp = f(spec.sp, { part = 'sp', group = name }) end
  end

  -- Terminal colors
  for i, hex in pairs(res.terminal_colors) do
    res.terminal_colors[i] = f(hex, { terminal_color = i })
  end

  return res
end

H.cs_invert = function(self) return self:map_colors(H.invert_color) end

H.cs_write = function(self, opts)
  opts = vim.tbl_extend('force', { directory = (vim.fn.stdpath('config') .. '/colors'), name = nil }, opts or {})

  local name = opts.name or H.make_file_basename(self.name)

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

H.get_current_terminal_colors = function()
  local res = {}
  for i = 0, 255 do
    local col = vim.g['terminal_color_' .. i]
    -- Use only defined colors with proper HEX values (ignores color names)
    if type(col) == 'string' and col:find('^#%x%x%x%x%x%x$') ~= nil then res[i] = col end
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

-- Color manipulation ---------------------------------------------------------
H.invert_color = function(hex, _)
  -- Using OKHSL
  local okhsl = MiniColors.hex2okhsl(hex)
  okhsl.l = 1 - okhsl.l

  -- local s = okhsl.s
  -- okhsl.s = okhsl.l < 0.5 and math.pow(s, 1 / 4) or math.pow(s, 4)

  -- okhsl.h = (okhsl.h + 180) % 360

  return MiniColors.okhsl2hex(okhsl)

  -- TODO: Explore idea of inverting lightness while preserving chroma:
  -- - For current chroma find maximum and minimum lightness (by utilizing
  --   `H.find_cusp()` and assuming it forms triangle).
  -- - Invert lightness **inside** this segment. So for `l` in `[l_min, l_max]`
  --   the output is `l_min + (l_max - l)`.

  -- -- Using Oklab
  -- local oklab = MiniColors.hex2oklab(hex)
  -- local l, a, b = oklab.l, oklab.a, oklab.b
  -- local c = math.sqrt(a * a + b * b)
  -- local h = math.atan2(b, a)
  --
  -- local new_l = 1 - l
  -- oklab.l = new_l
  --
  -- local new_c = new_l < 0.5 and math.pow(c, 1 / 2) or math.pow(c, 2)
  -- oklab.a, oklab.b = new_c * math.cos(h), new_c * math.sin(h)
  --
  -- -- local new_h = (h + 0.5 * H.tau) % H.tau
  -- -- oklab.a, oklab.b = c * math.cos(new_h), c * math.sin(new_h)
  --
  -- return MiniColors.oklab2hex(oklab)
end

-- Oklab/OKHSL ----------------------------------------------------------------
-- Sources:
-- https://github.com/bottosson/bottosson.github.io/blob/master/misc/colorpicker/colorconversion.js
-- https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
-- https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab

-- HEX <-> RGB in [0;1]
H.hex2rgb = function(hex)
  local dec = tonumber(hex:sub(2), 16)

  local b = math.fmod(dec, 256)
  local g = math.fmod((dec - b) / 256, 256)
  local r = math.floor(dec / 65536)

  return { r = r / 255, g = g / 255, b = b / 255 }
end

H.rgb2hex = function(rgb)
  local r = H.clamp(H.round(255 * rgb.r), 0, 255)
  local g = H.clamp(H.round(255 * rgb.g), 0, 255)
  local b = H.clamp(H.round(255 * rgb.b), 0, 255)

  return string.format('#%02x%02x%02x', r, g, b)
end

-- RGB in [0;1] <-> OKHSL
H.okhsl2rgb = function(okhsl)
  local h, s, l = okhsl.h, okhsl.s, okhsl.l
  h = H.degree2rad(h)

  if 1 <= l then return { r = 1, g = 1, b = 1 } end
  if l <= 0 then return { r = 0, g = 0, b = 0 } end

  local a_ = math.cos(h)
  local b_ = math.sin(h)
  local L = H.toe_inv(l)

  local C_0, C_mid, C_max = H.get_Cs(L, a_, b_)

  local t, k_0, k_1, k_2
  if s < 0.8 then
    t = 1.25 * s
    k_0 = 0
    k_1 = 0.8 * C_0
    k_2 = (1 - k_1 / C_mid)
  else
    t = 5 * (s - 0.8)
    k_0 = C_mid
    k_1 = 0.2 * C_mid * C_mid * 1.25 * 1.25 / C_0
    k_2 = (1 - k_1 / (C_max - C_mid))
  end

  local C = k_0 + t * k_1 / (1 - k_2 * t)

  local rgb = H.oklab2linrgb(L, C * a_, C * b_)
  return {
    r = H.rgb_transfer(rgb.r),
    g = H.rgb_transfer(rgb.g),
    b = H.rgb_transfer(rgb.b),
  }
end

H.rgb2okhsl = function(rgb)
  local lab = H.linrgb2oklab(H.rgb_transfer_inv(rgb.r), H.rgb_transfer_inv(rgb.g), H.rgb_transfer_inv(rgb.b))

  local C = math.sqrt(lab.a * lab.a + lab.b * lab.b)
  local a_ = lab.a / C
  local b_ = lab.b / C

  local L = lab.l
  local h = 0.5 * H.tau + math.atan2(-lab.b, -lab.a)
  h = H.rad2degree(h)

  local C_0, C_mid, C_max = H.get_Cs(L, a_, b_)

  local s
  if C < C_mid then
    local k_0 = 0
    local k_1 = 0.8 * C_0
    local k_2 = (1 - k_1 / C_mid)

    local t = (C - k_0) / (k_1 + k_2 * (C - k_0))
    s = t * 0.8
  else
    local k_0 = C_mid
    local k_1 = 0.2 * C_mid * C_mid * 1.25 * 1.25 / C_0
    local k_2 = (1 - k_1 / (C_max - C_mid))

    local t = (C - k_0) / (k_1 + k_2 * (C - k_0))
    s = 0.8 + 0.2 * t
  end

  local l = H.toe(L)
  return { h = h, s = s, l = l }
end

-- RGB in [0;1] <-> Oklab
H.rgb2oklab = function(rgb)
  return H.linrgb2oklab(H.rgb_transfer_inv(rgb.r), H.rgb_transfer_inv(rgb.g), H.rgb_transfer_inv(rgb.b))
end

H.oklab2rgb = function(oklab)
  local rgb = H.oklab2linrgb(oklab.l, oklab.a, oklab.b)
  return {
    r = H.rgb_transfer(rgb.r),
    g = H.rgb_transfer(rgb.g),
    b = H.rgb_transfer(rgb.b),
  }
end

-- RGB in [0;1] <-> Linear RGB
-- https://bottosson.github.io/posts/colorwrong/#what-can-we-do%3F
H.rgb_transfer = function(x) return (0.0031308 >= x) and (12.92 * x) or (1.055 * math.pow(x, 0.416666667) - 0.055) end

H.rgb_transfer_inv = function(x) return 0.04045 < x and math.pow((x + 0.055) / 1.055, 2.4) or (x / 12.92) end

-- Linear RGB <-> Oklab
-- https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
-- https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab
H.linrgb2oklab = function(r, g, b)
  local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
  local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
  local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

  local l_, m_, s_ = H.cuberoot(l), H.cuberoot(m), H.cuberoot(s)

  local o_l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
  local o_a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
  local o_b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

  return { l = o_l, a = o_a, b = o_b }
end

H.oklab2linrgb = function(L, a, b)
  local l_ = L + 0.3963377774 * a + 0.2158037573 * b
  local m_ = L - 0.1055613458 * a - 0.0638541728 * b
  local s_ = L - 0.0894841775 * a - 1.2914855480 * b

  local l = l_ * l_ * l_
  local m = m_ * m_ * m_
  local s = s_ * s_ * s_

  --stylua: ignore
  return {
    r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  }
end

-- Functions for lightness correction
H.toe = function(x)
  local k_1, k_2 = 0.206, 0.03
  local k_3 = (1 + k_1) / (1 + k_2)

  return 0.5 * (k_3 * x - k_1 + math.sqrt((k_3 * x - k_1) * (k_3 * x - k_1) + 4 * k_2 * k_3 * x))
end

H.toe_inv = function(x)
  local k_1, k_2 = 0.206, 0.03
  local k_3 = (1 + k_1) / (1 + k_2)
  return (x * x + k_1 * x) / (k_3 * (x + k_2))
end

--stylua: ignore
-- Find maximum possible saturation for a given hue that fits in sRGB
-- Saturation here is defined as S = C/L
-- a and b must be normalized so a^2 + b^2 == 1
H.compute_max_saturation = function(a, b)
  -- Max saturation will be when one of r, g or b goes below zero

  -- Select different coefficients depending on which component goes below zero first
  local k0, k1, k2, k3, k4, wl, wm, ws

  if (-1.88170328 * a - 0.80936493 * b > 1) then
      -- Red component
      k0, k1, k2, k3, k4 = 1.19086277, 1.76576728, 0.59662641, 0.75515197, 0.56771245
      wl, wm, ws =  4.0767416621, -3.3077115913,  0.2309699292
  elseif (1.81444104 * a - 1.19445276 * b > 1) then
      -- Green component
      k0, k1, k2, k3, k4 = 0.73956515, -0.45954404,  0.08285427,  0.12541070,  0.14503204
      wl, wm, ws = -1.2684380046,  2.6097574011, -0.3413193965
  else
      -- Blue component
      k0, k1, k2, k3, k4 = 1.35733652, -0.00915799, -1.15130210, -0.50559606,  0.00692167
      wl, wm, ws = -0.0041960863, -0.7034186147,  1.7076147010
  end

  -- Approximate max saturation using a polynomial:
  local S = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b

  -- Do one step Halley's method to get closer
  -- this gives an error less than 10e6, except for some blue hues where the dS/dh is close to infinite
  -- this should be sufficient for most applications, otherwise do two/three steps
  local k_l =  0.3963377774 * a + 0.2158037573 * b
  local k_m = -0.1055613458 * a - 0.0638541728 * b
  local k_s = -0.0894841775 * a - 1.2914855480 * b

  local l_ = 1 + S * k_l
  local m_ = 1 + S * k_m
  local s_ = 1 + S * k_s

  local l = l_ * l_ * l_
  local m = m_ * m_ * m_
  local s = s_ * s_ * s_

  local l_dS = 3 * k_l * l_ * l_
  local m_dS = 3 * k_m * m_ * m_
  local s_dS = 3 * k_s * s_ * s_

  local l_dS2 = 6 * k_l * k_l * l_
  local m_dS2 = 6 * k_m * k_m * m_
  local s_dS2 = 6 * k_s * k_s * s_

  local f  = wl * l     + wm * m     + ws * s
  local f1 = wl * l_dS  + wm * m_dS  + ws * s_dS
  local f2 = wl * l_dS2 + wm * m_dS2 + ws * s_dS2

  S = S - f * f1 / (f1*f1 - 0.5 * f * f2)

  return S
end

H.find_cusp = function(a, b)
  -- First, find the maximum saturation (saturation S = C/L)
  local S_cusp = H.compute_max_saturation(a, b)

  -- Convert to linear sRGB to find the first point where at least one of r,g or b >= 1:
  local rgb_at_max = H.oklab2linrgb(1, S_cusp * a, S_cusp * b)
  local L_cusp = H.cuberoot(1 / math.max(rgb_at_max.r, rgb_at_max.g, rgb_at_max.b))
  local C_cusp = L_cusp * S_cusp

  return { L = L_cusp, C = C_cusp }
end

--stylua: ignore
-- Finds intersection of the line defined by
-- L = L0 * (1 - t) + t * L1
-- C = t * C1
-- a and b must be normalized so a^2 + b^2 == 1
H.find_gamut_intersection = function(a, b, L1, C1, L0, cusp)
  -- Find the cusp of the gamut triangle
  cusp = cusp or H.find_cusp(a, b)

  -- Find the intersection for upper and lower half seprately

  -- Lower half
  local is_lower_half = ((L1 - L0) * cusp.C - (cusp.L - L0) * C1) <= 0
  if is_lower_half then return cusp.C * L0 / (C1 * cusp.L + cusp.C * (L0 - L1)) end

  -- Upper half. First intersect with triangle.
  local t = cusp.C * (L0 - 1) / (C1 * (cusp.L - 1) + cusp.C * (L0 - L1))

  -- Then one step Halley's method
  local dL = L1 - L0
  local dC = C1

  local k_l =  0.3963377774 * a + 0.2158037573 * b
  local k_m = -0.1055613458 * a - 0.0638541728 * b
  local k_s = -0.0894841775 * a - 1.2914855480 * b

  local l_dt = dL + dC * k_l
  local m_dt = dL + dC * k_m
  local s_dt = dL + dC * k_s

  -- If higher accuracy is required, 2 or 3 iterations of the following block can be used:
  local L = L0 * (1 - t) + t * L1
  local C = t * C1

  local l_ = L + C * k_l
  local m_ = L + C * k_m
  local s_ = L + C * k_s

  local l = l_ * l_ * l_
  local m = m_ * m_ * m_
  local s = s_ * s_ * s_

  local ldt = 3 * l_dt * l_ * l_
  local mdt = 3 * m_dt * m_ * m_
  local sdt = 3 * s_dt * s_ * s_

  local ldt2 = 6 * l_dt * l_dt * l_
  local mdt2 = 6 * m_dt * m_dt * m_
  local sdt2 = 6 * s_dt * s_dt * s_

  local r  = 4.0767416621 * l    - 3.3077115913 * m    + 0.2309699292 * s - 1
  local r1 = 4.0767416621 * ldt  - 3.3077115913 * mdt  + 0.2309699292 * sdt
  local r2 = 4.0767416621 * ldt2 - 3.3077115913 * mdt2 + 0.2309699292 * sdt2

  local u_r = r1 / (r1 * r1 - 0.5 * r * r2)
  local t_r = -r * u_r

  local g  = -1.2684380046 * l    + 2.6097574011 * m    - 0.3413193965 * s - 1
  local g1 = -1.2684380046 * ldt  + 2.6097574011 * mdt  - 0.3413193965 * sdt
  local g2 = -1.2684380046 * ldt2 + 2.6097574011 * mdt2 - 0.3413193965 * sdt2

  local u_g = g1 / (g1 * g1 - 0.5 * g * g2)
  local t_g = -g * u_g

  local b  = -0.0041960863 * l    - 0.7034186147 * m    + 1.7076147010 * s - 1
  local b1 = -0.0041960863 * ldt  - 0.7034186147 * mdt  + 1.7076147010 * sdt
  local b2 = -0.0041960863 * ldt2 - 0.7034186147 * mdt2 + 1.7076147010 * sdt2

  local u_b = b1 / (b1 * b1 - 0.5 * b * b2)
  local t_b = -b * u_b

  t_r = u_r >= 0 and t_r or 10e5
  t_g = u_g >= 0 and t_g or 10e5
  t_b = u_b >= 0 and t_b or 10e5

  t = t + math.min(t_r, t_g, t_b)

  return t
end

H.get_ST_max = function(a_, b_, cusp)
  cusp = cusp or H.find_cusp(a_, b_)

  local L, C = cusp.L, cusp.C
  return C / L, C / (1 - L)
end

-- stylua: ignore
H.get_ST_mid = function(a_, b_)
  local S = 0.11516993 + 1 / (
    7.44778970 + 4.15901240 * b_ + a_ * (
      -2.19557347 + 1.75198401 * b_ + a_ * (
        -2.13704948 - 10.02301043 * b_ + a_ * (
          -4.24894561 + 5.38770819 * b_ + 4.69891013 * a_
        )
      )
    )
  )

  local T = 0.11239642 + 1 / (
    1.61320320 - 0.68124379 * b_ + a_ * (
      0.40370612 + 0.90148123 * b_ + a_ * (
        -0.27087943 + 0.61223990 * b_ + a_ * (
          0.00299215 - 0.45399568 * b_ - 0.14661872 * a_
        )
      )
    )
  )

  return  S, T
end

H.get_Cs = function(L, a_, b_)
  local cusp = H.find_cusp(a_, b_)

  local S_mid, T_mid = H.get_ST_mid(a_, b_)
  local S_max, T_max = H.get_ST_max(a_, b_, cusp)

  local C_max = H.find_gamut_intersection(a_, b_, L, 1, L, cusp)

  local k = C_max / math.min((L * S_max), (1 - L) * T_max)

  local C_a, C_b

  C_a, C_b = L * S_mid, (1 - L) * T_mid
  local C_mid = 0.9 * k * math.sqrt(math.sqrt(1 / (1 / (C_a * C_a * C_a * C_a) + 1 / (C_b * C_b * C_b * C_b))))

  C_a, C_b = L * 0.4, (1 - L) * 0.8
  local C_0 = math.sqrt(1 / (1 / (C_a * C_a) + 1 / (C_b * C_b)))

  return C_0, C_mid, C_max
end

H.rad2degree = function(x) return (x % H.tau) * 360 / H.tau end

H.degree2rad = function(x) return (x % 360) * H.tau / 360 end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.colors) %s', msg), 0) end

H.round = function(x) return math.floor(x + 0.5) end

H.clamp = function(x, from, to) return math.min(math.max(x, from), to) end

H.cuberoot = function(x) return math.pow(x, 0.333333) end

return MiniColors
