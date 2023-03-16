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
  return H.linrgb2oklab(H.rgb2linrgb(H.hex2rgb(hex)))
end

MiniColors.oklab2hex = function(oklab)
  if oklab == nil then return nil end
  return H.rgb2hex(H.linrgb2rgb(H.oklab2linrgb(oklab)))
end

MiniColors.hex2oklch = function(hex)
  if hex == nil then return nil end
  return H.oklab2oklch(MiniColors.hex2oklab(hex))
end

MiniColors.oklch2hex = function(oklch)
  if oklch == nil then return nil end
  return MiniColors.oklab2hex(H.oklch2oklab(oklch))
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
  local oklab = MiniColors.hex2oklab(hex)
  oklab.l = 1 - oklab.l
  return MiniColors.oklab2hex(oklab)
end

-- Oklab ----------------------------------------------------------------------
-- HEX <-> RGB
H.hex2rgb = function(hex)
  local dec = tonumber(hex:sub(2), 16)

  local b = math.fmod(dec, 256)
  local g = math.fmod((dec - b) / 256, 256)
  local r = math.floor(dec / 65536)

  return { r = r, g = g, b = b }
end

H.rgb2hex = function(rgb)
  local r = H.squash(H.round(rgb.r), 0, 255)
  local g = H.squash(H.round(rgb.g), 0, 255)
  local b = H.squash(H.round(rgb.b), 0, 255)

  return string.format('#%02x%02x%02x', r, g, b)
end

-- RGB <-> Linear RGB
-- https://bottosson.github.io/posts/colorwrong/#what-can-we-do%3F
H.rgb2linrgb = function(rgb)
  return vim.tbl_map(function(c)
    c = c / 255
    c = (0.04045 < c) and ((c + 0.055) / 1.055) ^ 2.4 or (c / 12.92)
    return c
  end, rgb)
end

H.linrgb2rgb = function(linrgb)
  return vim.tbl_map(function(c)
    c = (0.0031308 < c) and (1.055 * (c ^ 0.416666666667) - 0.055) or (12.92 * c)
    return 255 * c
  end, linrgb)
end

-- Linear RGB <-> Oklab
-- https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
-- https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab
H.linrgb2oklab = function(linrgb)
  local r, g, b = linrgb.r, linrgb.g, linrgb.b

  -- Basic convert
  local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
  local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
  local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

  local l_, m_, s_ = H.cuberoot(l), H.cuberoot(m), H.cuberoot(s)

  local o_l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
  local o_a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
  local o_b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

  -- Correct lightness
  local k_1, k_2 = 0.206, 0.03
  local k_3 = (1 + k_1) / (1 + k_2)

  local o_lr = 0.5 * (k_3 * o_l - k_1 + math.sqrt((k_3 * o_l - k_1) * (k_3 * o_l - k_1) + 4 * k_2 * k_3 * o_l))

  return { l = o_lr, a = o_a, b = o_b }
end

H.oklab2linrgb = function(oklab)
  local o_lr, o_a, o_b = oklab.l, oklab.a, oklab.b

  -- Decorrect lightness
  local k_1, k_2 = 0.206, 0.03
  local k_3 = (1 + k_1) / (1 + k_2)
  local o_l = (o_lr * o_lr + k_1 * o_lr) / (k_3 * (o_lr + k_2))

  -- Basic convert
  local l_ = o_l + 0.3963377774 * o_a + 0.2158037573 * o_b
  local m_ = o_l - 0.1055613458 * o_a - 0.0638541728 * o_b
  local s_ = o_l - 0.0894841775 * o_a - 1.2914855480 * o_b

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

-- Oklab <-> Oklch
-- https://bottosson.github.io/posts/oklab/#the-oklab-color-space
H.oklab2oklch = function(oklab)
  local a, b = oklab.a, oklab.b
  local c = math.sqrt(a * a + b * b)
  local h = c == 0 and 0 or math.atan2(b, a)
  return { l = 100 * oklab.l, c = 100 * c, h = (h % H.tau) * 360 / H.tau }
end

H.oklch2oklab = function(oklch)
  local c, angle = 0.01 * oklch.c, oklch.h * H.tau / 360
  return { l = 0.01 * oklch.l, a = c * math.cos(angle), b = c * math.sin(angle) }
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.colors) %s', msg), 0) end

H.round = function(x) return math.floor(x + 0.5) end

H.squash = function(x, from, to) return math.min(math.max(x, from), to) end

H.cuberoot = function(x) return math.pow(x, 0.333333) end

return MiniColors
