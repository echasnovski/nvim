-- "Dark, cold, and gloomy" vibe
-- Reference hue is 265 for "cold blue" and not 270 for proper cyan in diff
-- Chroma levels are 3 for bg and 1 for fg
-- Lightness levels are 10+80 for 'dark' and 85+15 for 'light'
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#101624' or '#cbd5e9'
local fg = is_dark and '#c3c7ce' or '#202227'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  -- Make it "gloomy"
  saturation = is_dark and 'lowmedium' or 'mediumhigh',
  accent = 'azure',
})

vim.g.colors_name = 'miniwinter'
