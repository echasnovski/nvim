-- TODO:
--
-- Code:
-- - Explore possibility of making `animate_transition()` function. Ideally should
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
--     - `color_cut(channel, from, to, predicate, opts)` - exclude regions in
--       channel. `opts.action` decides what action to perform:
--         - "rescale" to rescale all colors (usefult to create color-blind
--           friendly scheme when cutting hue). All colors are affected.
--         - "clip" to clip to nearest value. Only colors inside cut region are
--           affected.
--       NOTE: this only allows for a single cut region; having several can be
--       useful, so maybe some other API?.
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
--     - Temperature - circular distance from current hue angle to 270 hue angle.
--       Ranges from 0 (cool) to 180 (hot) anchored at 270 (blue) and 90
--       (yellow) hue degrees. Similar to `b` channel but tries to preserve chroma.
--     - Pressure - circular distance from current hue angle to 180 hue angle.
--       Ranges from 0 to 180 anchored at 180 (greenish) and 0 (redish) hue degrees.
--       Similar to `a` channel but tries to preserve chroma. NOTE: not a wide
--       used term; coined to be similar to temperature.
--     - a - `a` component of Oklab.
--     - b - `b` component of Oklab.
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
--
-- - General idea of gamut clipping usefulness.
--
-- - Most Oklab/Oklch inversions are not exactly invertable.: applying it twice
--   might lead to slightly different colors depending on clip method (like
--   smaller chroma with default "chroma" clip method).

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

  -- Create user command
  vim.api.nvim_create_user_command('Colorscheme', function(input)
    local from_cs = MiniColors.get_current_colorscheme()

    -- Currently there is a brief redraw even with `lazyredraw`.
    -- Find a way to avoid it.
    local cache_lazyredraw = vim.o.lazyredraw
    vim.o.lazyredraw = true

    local ok, _ = pcall(vim.cmd, 'colorscheme ' .. input.args)
    if ok then
      local to_cs = MiniColors.get_current_colorscheme()
      MiniColors.animate_transition(from_cs, to_cs)
    end

    vim.o.lazyredraw = cache_lazyredraw
  end, { nargs = 1, complete = 'color' })
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniColors.config = {
  gamut_clip = 'cusp',
}
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
  res.color_cut = H.cs_color_cut
  res.color_invert = H.cs_color_invert
  res.color_map = H.cs_color_map
  res.color_shift = H.cs_color_shift
  res.compress = H.cs_compress
  res.ensure_cterm = H.cs_ensure_cterm
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

MiniColors.interactive = function(opts)
  opts = vim.tbl_deep_extend(
    'force',
    { colorscheme = nil, mappings = { Apply = '<M-a>', Reset = '<M-r>', Quit = '<M-q>', Write = '<M-w>' } },
    opts or {}
  )
  local maps = opts.mappings

  -- Prepare
  local init_cs = vim.deepcopy(opts.colorscheme) or MiniColors.get_current_colorscheme()
  local buf_id = vim.api.nvim_create_buf(true, true)

  -- Write header lines
  local delimiter = '----------'
  local header_lines = {
    [[Experiment with color scheme by 'mini.colors']],
    '',
    'Non-blank lines after `' .. delimiter .. '` are treated as calls to color scheme methods',
    'For more information see `:h MiniColors.interactive()`',
    '',
    'Current initial color scheme: ' .. init_cs.name,
    'Current buffer-local mappings (Normal mode):',
    '  Apply: ' .. maps.Apply,
    '  Reset: ' .. maps.Reset,
    '  Quit:  ' .. maps.Quit,
    '  Write: ' .. maps.Write,
    '',
    delimiter,
    '',
    '',
  }
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, header_lines)

  -- Add highlight
  local hi = function(group, from, to) vim.highlight.range(buf_id, H.ns_id.interactive, group, from, to, {}) end
  --stylua: ignore start
  hi('Title',   { 0,  0 },  { 1,  0 })
  hi('Special', { 5,  30 }, { 6,  0 })
  hi('Special', { 7,  9 },  { 8,  0 })
  hi('Special', { 8,  9 },  { 9,  0 })
  hi('Special', { 9,  9 },  { 10, 0 })
  hi('Special', { 10, 9 },  { 11, 0 })
  --stylua: ignore end

  -- Make local mappings
  local m = function(action, rhs) vim.keymap.set('n', maps[action], rhs, { desc = action, buffer = buf_id }) end

  m('Apply', function()
    local new_cs = H.apply_interactive_buffer(buf_id, init_cs, delimiter)
    new_cs:apply()
  end)
  m('Reset', function() init_cs:apply() end)
  m('Quit', function() vim.api.nvim_buf_delete(buf_id, { force = true }) end)
  m('Write', function()
    vim.ui.input(
      { prompt = [[Write to 'colors/' of your config under this name: ]], default = init_cs.name },
      function(input)
        if input == nil then return end
        local new_cs = H.apply_interactive_buffer(buf_id, init_cs, delimiter)
        new_cs:write({ name = input })
      end
    )
  end)

  -- Make current
  vim.api.nvim_set_current_buf(buf_id)
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf_id), 0 })
end

MiniColors.animate_transition = function(from_colorscheme, to_colorscheme, opts)
  opts = opts or {}
  local n_steps = math.max(opts.n_steps or 40, 1)
  local step_duration = math.max(opts.step_duration or 25, 1)

  -- Pre-compute common data
  local from_edge = H.cs_hex_to_oklab(vim.deepcopy(from_colorscheme:compress()))
  local to_edge = H.cs_hex_to_oklab(vim.deepcopy(to_colorscheme:compress()))
  local all_group_names = H.union(vim.tbl_keys(from_edge.groups), vim.tbl_keys(to_edge.groups))

  -- Start animation
  local step = 0
  local timer = vim.loop.new_timer()

  local draw_step
  draw_step = vim.schedule_wrap(function()
    local cs_step = H.compute_animate_step(from_edge, to_edge, step / n_steps, all_group_names)
    MiniColors.as_colorscheme(H.cs_oklab_to_hex(cs_step)):apply()
    vim.cmd('redraw')

    step = step + 1

    if n_steps <= step then
      timer:stop()
      to_colorscheme:apply()
      return
    end

    timer:again()
  end)

  -- Start repeating timer without callback execution
  timer:start(10000000, step_duration, draw_step)

  -- Execute initial step (apply `from` color scheme) immediately
  draw_step()
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
  opts = vim.tbl_deep_extend('force', H.get_config(), { corrected_l = true }, opts or {})

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
  opts = vim.tbl_deep_extend('force', H.get_config(), { corrected_l = true }, opts or {})

  -- Make effort to have point inside gamut. NOTE: not always precise, i.e. not
  -- always results into point in gamut, but sufficiently close.
  lch.h = lch.h % 360
  local lch_in_gamut = H.clip_to_gamut(lch, opts.gamut_clip)

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
--stylua: ignore
---@diagnostic disable-next-line
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

H.allowed_channels = { 'lightness', 'chroma', 'hue', 'temperature', 'pressure', 'a', 'b', 'red', 'green', 'blue' }

H.ns_id = { interactive = vim.api.nvim_create_namespace('MiniColorsInteractive') }

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

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniColors.config, vim.b.minicolors_config or {}, config or {})
end

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

  return self
end

H.cs_color_adjust = function(self, channel, coef, predicate)
  channel = H.normalize_channel(channel)
  coef = H.normalize_number(coef or 1, 'coef')
  predicate = H.normalize_predicate(predicate)

  if coef == 1 then return self end

  local adjust_channel = H.color_adjusters[channel]

  local f = function(hex, data)
    if not predicate(hex, data) then return hex end
    return adjust_channel(hex, coef)
  end

  return self:color_map(f)
end

H.cs_color_cut = function(self, channel, from, to, predicate)
  channel = H.normalize_channel(channel)
  from, to = H.normalize_from_to(from, to)
  predicate = H.normalize_predicate(predicate)

  local cut_channel = H.color_cutters[channel]

  local f = function(hex, data)
    if not predicate(hex, data) then return hex end
    return cut_channel(hex, from, to)
  end

  return self:color_map(f)
end

H.cs_color_invert = function(self, channel, predicate)
  channel = H.normalize_channel(channel)
  predicate = H.normalize_predicate(predicate)

  local invert_channel = H.color_inverters[channel]

  local f = function(hex, data)
    if not predicate(hex, data) then return hex end
    return invert_channel(hex)
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

H.cs_color_shift = function(self, channel, by, predicate)
  channel = H.normalize_channel(channel)
  by = H.normalize_number(by or 0, 'by')
  predicate = H.normalize_predicate(predicate)

  if by == 0 then return self end

  local shift_channel = H.color_shifters[channel]

  local f = function(hex, data)
    if not predicate(hex, data) then return hex end
    return shift_channel(hex, by)
  end

  return self:color_map(f)
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

H.cs_ensure_cterm = function(self, opts)
  opts = vim.tbl_deep_extend('force', { force = true }, opts or {})

  -- Compute Oklab coordinates of terminal colors for better approximation
  local term_oklab = H.compute_term_oklab()

  local force = opts.force
  for _, gr in pairs(self.groups) do
    if gr.fg and (force or not gr.ctermfg) then gr.ctermfg = H.approx_term_color(gr.fg, term_oklab) end
    if gr.bg and (force or not gr.ctermbg) then gr.ctermbg = H.approx_term_color(gr.bg, term_oklab) end
  end

  return self
end

H.cs_write = function(self, opts)
  opts = vim.tbl_extend(
    'force',
    { compress = true, name = nil, directory = (vim.fn.stdpath('config') .. '/colors') },
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

  return self
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

H.normalize_number = function(x, arg_name)
  if type(x) ~= 'number' then H.error('Argument `' .. arg_name .. '` should be a number.') end
  return x
end

H.normalize_from_to = function(from, to)
  if type(from) ~= 'number' then H.error('Argument `from` should be a number.') end
  if type(to) ~= 'number' then H.error('Argument `to` should be a number.') end
  if to < from then H.error('Argument `from` should not be greater than `to`.') end
  return from, to
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

-- Terminal colors ------------------------------------------------------------
H.compute_term_oklab = function()
  -- Use cached values if they are already computed
  if H.term_oklab ~= nil then return H.term_oklab end

  local res = {}

  -- Main colors. Don't use 0-15 because they are terminal dependent
  local cterm_basis = { 0, 95, 135, 175, 215, 255 }
  for i = 16, 231 do
    local j = i - 16
    local r = cterm_basis[math.floor(j / 36) % 6 + 1]
    local g = cterm_basis[math.floor(j / 6) % 6 + 1]
    local b = cterm_basis[j % 6 + 1]
    res[i] = H.rgb2oklab({ r = r, g = g, b = b })
  end

  -- Grays
  for i = 232, 255 do
    local c = 8 + (i - 232) * 10
    res[i] = H.rgb2oklab({ r = c, g = c, b = c })
  end

  H.term_oklab = res
  return res
end

H.approx_term_color = function(hex, term_oklab)
  local ref_lab = H.rgb2oklab(H.hex2rgb(hex))

  local best_id, best_dist = nil, math.huge
  for id, lab in pairs(term_oklab) do
    local dist = math.abs(ref_lab.l - lab.l) + math.abs(ref_lab.a - lab.a) + math.abs(ref_lab.b - lab.b)
    if dist < best_dist then
      best_id, best_dist = id, dist
    end
  end

  return best_id
end

-- Animation ------------------------------------------------------------------
H.cs_hex_to_oklab = function(cs)
  cs.groups = vim.tbl_map(function(gr)
    gr.fg = MiniColors.hex2oklab(gr.fg)
    gr.bg = MiniColors.hex2oklab(gr.bg)
    gr.sp = MiniColors.hex2oklab(gr.sp)
    return gr
  end, cs.groups)

  cs.terminal = vim.tbl_map(MiniColors.hex2oklab, cs.terminal)

  return cs
end

H.cs_oklab_to_hex = function(cs)
  -- Using 'chroma' clipping method preserves lightness which results into
  -- smoother transitions
  local oklab2hex = function(lab) return MiniColors.oklab2hex(lab, { gamut_clip = 'chroma' }) end
  cs.groups = vim.tbl_map(function(gr)
    gr.fg = oklab2hex(gr.fg)
    gr.bg = oklab2hex(gr.bg)
    gr.sp = oklab2hex(gr.sp)
    return gr
  end, cs.groups)

  cs.terminal = vim.tbl_map(oklab2hex, cs.terminal)

  return cs
end

H.compute_animate_step = function(from, to, coef, all_group_names)
  local groups = {}
  for _, name in ipairs(all_group_names) do
    groups[name] = H.convex_hl_group(from.groups[name], to.groups[name], coef)
  end

  local terminal = {}
  for i = 0, 15 do
    terminal[i] = H.convex_lab(from.terminal[i], to.terminal[i], coef)
  end

  return MiniColors.as_colorscheme({ name = 'transition_step', groups = groups, terminal = terminal })
end

H.convex_hl_group = function(from, to, coef)
  if from == nil or to == nil or from.link ~= nil or to.link ~= nil then return H.convex_discrete(from, to, coef) end

  --stylua: ignore
  return {
    fg = H.convex_lab(from.fg, to.fg, coef),
    bg = H.convex_lab(from.bg, to.bg, coef),
    sp = H.convex_lab(from.sp, to.sp, coef),

    blend = H.round(H.convex_continuous(from.blend, to.blend, coef)),

    bold          = H.convex_discrete(from.bold,          to.bold,          coef),
    italic        = H.convex_discrete(from.italic,        to.italic,        coef),
    nocombine     = H.convex_discrete(from.nocombine,     to.nocombine,     coef),
    reverse       = H.convex_discrete(from.reverse,       to.reverse,       coef),
    standout      = H.convex_discrete(from.standout,      to.standout,      coef),
    strikethrough = H.convex_discrete(from.strikethrough, to.strikethrough, coef),
    undercurl     = H.convex_discrete(from.undercurl,     to.undercurl,     coef),
    underdashed   = H.convex_discrete(from.underdashed,   to.underdashed,   coef),
    underdotted   = H.convex_discrete(from.underdotted,   to.underdotted,   coef),
    underdouble   = H.convex_discrete(from.underdouble,   to.underdouble,   coef),
    underline     = H.convex_discrete(from.underline,     to.underline,     coef),
  }
end

H.convex_lab = function(from_lab, to_lab, coef)
  if from_lab == nil or to_lab == nil then return H.convex_discrete(from_lab, to_lab, coef) end
  return {
    l = H.convex_continuous(from_lab.l, to_lab.l, coef),
    a = H.convex_continuous(from_lab.a, to_lab.a, coef),
    b = H.convex_continuous(from_lab.b, to_lab.b, coef),
  }
end

-- Channel modifiers ----------------------------------------------------------
H.modify_lightness = function(hex, f)
  local lch = MiniColors.hex2oklch(hex, { corrected_l = true })
  lch.l = H.clip(f(lch.l), 0, 100)
  return MiniColors.oklch2hex(lch, { corrected_l = true })
end

H.modify_chroma = function(hex, f)
  local lch = MiniColors.hex2oklch(hex)
  lch.c = H.clip(f(lch.c), 0, math.huge)
  return MiniColors.oklch2hex(lch)
end

H.modify_hue = function(hex, f)
  local lch = MiniColors.hex2oklch(hex)
  lch.h = f(lch.h) % 360
  return MiniColors.oklch2hex(lch)
end

H.modify_temperature = function(hex, f)
  local lch = MiniColors.hex2oklch(hex)

  -- Temperature is a circular distance to 270 hue degrees
  -- Output value will lie in the same vertical half plane
  local is_left = 90 <= lch.h and lch.h <= 270
  local temp = (is_left and (270 - lch.h) or (lch.h + 90)) % 360
  local new_temp = H.clip(f(temp), 0, 180)
  lch.h = (is_left and (270 - new_temp) or (new_temp - 90)) % 360

  return MiniColors.oklch2hex(lch)
end

H.modify_pressure = function(hex, f)
  local lch = MiniColors.hex2oklch(hex)

  -- Pressure is a circular distance to 180 hue degrees
  -- Output value will lie in the same horizontal half plane
  local is_up = 0 <= lch.h and lch.h <= 180
  local press = is_up and (180 - lch.h) or (lch.h - 180)
  local new_press = H.clip(f(press), 0, 180)
  lch.h = is_up and (180 - new_press) or (new_press + 180)

  return MiniColors.oklch2hex(lch)
end

H.modify_a = function(hex, f)
  local lab = MiniColors.hex2oklab(hex)
  lab.a = f(lab.a)
  return MiniColors.oklab2hex(lab)
end

H.modify_b = function(hex, f)
  local lab = MiniColors.hex2oklab(hex)
  lab.b = f(lab.b)
  return MiniColors.oklab2hex(lab)
end

H.modify_red = function(hex, f)
  local rgb = H.hex2rgb(hex)
  rgb.r = H.clip(f(rgb.r), 0, 255)
  return H.rgb2hex(rgb)
end

H.modify_green = function(hex, f)
  local rgb = H.hex2rgb(hex)
  rgb.g = H.clip(f(rgb.g), 0, 255)
  return H.rgb2hex(rgb)
end

H.modify_blue = function(hex, f)
  local rgb = H.hex2rgb(hex)
  rgb.b = H.clip(f(rgb.b), 0, 255)
  return H.rgb2hex(rgb)
end

-- Color adjust ---------------------------------------------------------------
H.make_adjuster = function(modifier)
  return function(hex, coef)
    return modifier(hex, function(x) return coef * x end)
  end
end

--stylua: ignore
H.color_adjusters = {
  lightness   = H.make_adjuster(H.modify_lightness),
  chroma      = H.make_adjuster(H.modify_chroma),
  hue         = H.make_adjuster(H.modify_hue),
  temperature = H.make_adjuster(H.modify_temperature),
  pressure    = H.make_adjuster(H.modify_pressure),
  a           = H.make_adjuster(H.modify_a),
  b           = H.make_adjuster(H.modify_b),
  red         = H.make_adjuster(H.modify_red),
  green       = H.make_adjuster(H.modify_green),
  blue        = H.make_adjuster(H.modify_blue),
}

-- Color cut ------------------------------------------------------------------
H.cut = function(x, from, to)
  -- If value is in [from; to], return closest edge. Otherwise return input.
  if x <= from or to <= x then return x end
  return ((x - from) <= (to - x)) and from or to
end

H.cut_circular = function(x, from, to)
  --  Segment to cut out is assumed to be from `from` counter clockwise to `to`
  -- Normalize `from` and `to` to be in [0; 360)
  from, to = from % 360, to % 360

  -- Act only on points inside segment which can be either:
  -- - Usual like [90, 180].
  -- - Covering zero like [180, 90], which is union of [180; 360) and [0; 90].
  if from <= to and not (from <= x and x <= to) then return x end
  if to < from and not (from <= x or x <= to) then return x end

  -- Return closest edge for points inside segment
  return H.dist_circle(x, from) <= H.dist_circle(x, to) and from or to
end

H.make_cutter = function(modifier)
  return function(hex, from, to)
    return modifier(hex, function(x) return H.cut(x, from, to) end)
  end
end

--stylua: ignore
H.color_cutters = {
  lightness   = H.make_cutter(H.modify_lightness),
  chroma      = H.make_cutter(H.modify_chroma),
  hue = function(hex, from, to)
    return H.modify_hue(hex, function(x) return H.cut_circular(x, from, to) end)
  end,
  temperature = H.make_cutter(H.modify_temperature),
  pressure    = H.make_cutter(H.modify_pressure),
  a           = H.make_cutter(H.modify_a),
  b           = H.make_cutter(H.modify_b),
  red         = H.make_cutter(H.modify_red),
  green       = H.make_cutter(H.modify_green),
  blue        = H.make_cutter(H.modify_blue),
}

-- Color inversion ------------------------------------------------------------
H.negate = function(x) return -x end

H.negate_lightness = function(x) return 100 - x end

H.negate_rgb = function(x) return 255 - x end

H.color_inverters = {
  lightness = function(hex) return H.modify_lightness(hex, H.negate_lightness) end,

  chroma = function(hex)
    local lch = MiniColors.hex2oklch(hex, { corrected_l = false })

    -- Don't invert achromatic colors (black, greys, white)
    if lch.c == 0 then return hex end

    local gamut_points = H.get_gamut_points(lch)
    lch.c = gamut_points.c_upper - lch.c
    return MiniColors.oklch2hex(lch, { corrected_l = false })
  end,

  hue = function(hex) return H.modify_hue(hex, H.negate) end,

  -- Using `b` channel is a simpler approach of inverting temperature
  temperature = function(hex) return H.modify_b(hex, H.negate) end,

  -- Using `a` channel is a simpler approach of inverting temperature
  pressure = function(hex) return H.modify_a(hex, H.negate) end,

  a = function(hex) return H.modify_a(hex, H.negate) end,

  b = function(hex) return H.modify_b(hex, H.negate) end,

  red = function(hex) return H.modify_red(hex, H.negate_rgb) end,

  green = function(hex) return H.modify_green(hex, H.negate_rgb) end,

  blue = function(hex) return H.modify_blue(hex, H.negate_rgb) end,
}

-- Color shift ----------------------------------------------------------------
H.make_shifter = function(modifier)
  return function(hex, by)
    return modifier(hex, function(x) return x + by end)
  end
end

--stylua: ignore
H.color_shifters = {
  lightness   = H.make_shifter(H.modify_lightness),
  chroma      = H.make_shifter(H.modify_chroma),
  hue         = H.make_shifter(H.modify_hue),
  temperature = H.make_shifter(H.modify_temperature),
  pressure    = H.make_shifter(H.modify_pressure),
  a           = H.make_shifter(H.modify_a),
  b           = H.make_shifter(H.modify_b),
  red         = H.make_shifter(H.modify_red),
  green       = H.make_shifter(H.modify_green),
  blue        = H.make_shifter(H.modify_blue),
}

-- Oklab/Oklch ----------------------------------------------------------------
-- Sources:
-- https://github.com/bottosson/bottosson.github.io/blob/master/misc/colorpicker/colorconversion.js
-- https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab

-- HEX <-> RGB in [0;255]
H.hex2rgb = function(hex)
  local dec = tonumber(hex:sub(2), 16)

  local b = math.fmod(dec, 256)
  local g = math.fmod((dec - b) / 256, 256)
  local r = math.floor(dec / 65536)

  return { r = r, g = g, b = b }
end

H.rgb2hex = function(rgb)
  -- Use straightforward clipping to [0; 255] here to ensure correctness.
  -- Modify `rgb` prior to this to ensure only a small distortion.
  local r = H.clip(H.round(rgb.r), 0, 255)
  local g = H.clip(H.round(rgb.g), 0, 255)
  local b = H.clip(H.round(rgb.b), 0, 255)

  return string.format('#%02x%02x%02x', r, g, b)
end

-- RGB in [0; 255] <-> Oklab in [0; 1]
-- https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
H.rgb2oklab = function(rgb)
  -- Convert to linear RGB
  local r, g, b = H.correct_channel(rgb.r / 255), H.correct_channel(rgb.g / 255), H.correct_channel(rgb.b / 255)

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

  return { r = 255 * H.correct_channel_inv(r), g = 255 * H.correct_channel_inv(g), b = 255 * H.correct_channel_inv(b) }
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
  local c, l = lch.c, lch.l
  local cusp = H.cusps[math.floor(lch.h % 360)]
  local c_cusp, l_cusp = cusp[1], cusp[2]

  -- Range of allowed lightness is computed based on current chroma:
  -- - Lower is from segment between (0, 0) and cusp.
  -- - Upper is from segment between (0, 100) and cusp.
  local l_lower, l_upper
  if c < 0 then
    l_lower, l_upper = 0, 100
  elseif c_cusp < c then
    l_lower, l_upper = l_cusp, l_cusp
  else
    local saturation = c / c_cusp
    l_lower = saturation * l_cusp
    l_upper = saturation * (l_cusp - 100) + 100
  end

  -- Maximum allowed chroma is computed based on currnet lightness and depends
  -- on whether `l` is below or above cusp's `l`:
  -- - If below, then it is from lower triangle segment.
  -- - If above - from upper segment.
  local c_lower, c_upper = 0, nil
  if l < 0 or 100 < l then
    c_upper = 0
  else
    c_upper = l <= l_cusp and (c_cusp * l / l_cusp) or (c_cusp * (100 - l) / (100 - l_cusp))
  end

  -- Intersection of segment between (c, l) and (0, l_cusp) with gamut boundary
  local c_cusp_clip, l_cusp_clip
  if c <= 0 then
    c_cusp_clip, l_cusp_clip = c, l
  elseif l <= l_cusp then
    -- Intersection with lower segment
    local prop = 1 - l / l_cusp
    c_cusp_clip = c_cusp * c / (c_cusp * prop + c)
    l_cusp_clip = l_cusp * c_cusp_clip / c_cusp
  else
    -- Intersection with upper segment
    local prop = 1 - (l - 100) / (l_cusp - 100)
    c_cusp_clip = c_cusp * c / (c_cusp * prop + c)
    l_cusp_clip = 100 + c_cusp_clip * (l_cusp - 100) / c_cusp
  end

  return {
    l_lower = l_lower,
    l_upper = l_upper,
    c_lower = c_lower,
    c_upper = c_upper,
    l_cusp_clip = l_cusp_clip,
    c_cusp_clip = c_cusp_clip,
  }
end

H.clip_to_gamut = function(lch, gamut_clip)
  -- `lch` should have not corrected lightness
  local res = vim.deepcopy(lch)
  local gamut_points = H.get_gamut_points(lch)

  local is_inside_gamut = gamut_points.c_lower <= lch.c and lch.c <= gamut_points.c_upper
  if is_inside_gamut then return res end

  -- Clip by going towards (0, l_cusp) until in gamut. This approach proved to
  -- be the best because of reasonable compromise between chroma and lightness.
  -- In particular when inverting lightness of dark color schemes:
  -- - Clipping by reducing chroma with constant lightness leads to a dark
  --   foreground with hardly distinguishable colors.
  -- - Clipping by adjusting lightness with constant chroma leads to very low
  --   contrast on a particularly saturated foreground colors.
  if gamut_clip == 'cusp' then
    res.l, res.c = gamut_points.l_cusp_clip, gamut_points.c_cusp_clip
  end

  -- Preserve lightness by clipping chroma
  if gamut_clip == 'chroma' then res.c = H.clip(res.c, gamut_points.c_lower, gamut_points.c_upper) end

  -- Preserve chroma by clipping lightness
  if gamut_clip == 'lightness' then res.l = H.clip(res.l, gamut_points.l_lower, gamut_points.l_upper) end

  return res
end

-- Interactive ----------------------------------------------------------------
H.apply_interactive_buffer = function(buf_id, init_cs, delimiter)
  -- Create temporart color scheme
  MiniColors._interactive_cs = vim.deepcopy(init_cs)

  local is_past_delimiter = false
  local process_line = function(l)
    if l == delimiter then
      is_past_delimiter = true
      return
    end

    l = vim.trim(l)
    if not is_past_delimiter or l == '' then return end

    local ok, out = pcall(vim.cmd, 'lua MiniColors._interactive_cs = MiniColors._interactive_cs:' .. l)
    if not ok then
      MiniColors._interactive_cs = nil
      H.error('There was error executing content of interactive buffer: ' .. out)
    end
  end

  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, true)
  for _, l in ipairs(lines) do
    process_line(l)
  end

  local res = MiniColors._interactive_cs
  MiniColors._interactive_cs = nil
  return res
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.colors) %s', msg), 0) end

H.round = function(x)
  if x == nil then return nil end
  return math.floor(x + 0.5)
end

H.clip = function(x, from, to) return math.min(math.max(x, from), to) end

H.cuberoot = function(x) return math.pow(x, 0.333333) end

H.dist_circle = function(x, y)
  local d = math.abs(x - y)
  return math.min(d, 360 - d)
end

H.convex_continuous = function(x, y, coef)
  if x == nil or y == nil then return H.convex_discrete(x, y, coef) end
  return H.round((1 - coef) * x + coef * y)
end

H.convex_discrete = function(x, y, coef)
  if coef < 0.5 then return x end
  return y
end

H.union = function(arr1, arr2)
  local value_is_present = {}
  for _, x in ipairs(arr1) do
    value_is_present[x] = true
  end
  for _, x in ipairs(arr2) do
    value_is_present[x] = true
  end
  return vim.tbl_keys(value_is_present)
end

return MiniColors