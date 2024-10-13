-- "Dark, cold, and gloomy" vibe
-- Reference hue is 265 for "cold blue" and not 270 for proper cyan in diff
-- Chroma values are 3 for bg and 1 for fg
-- Lightness is darker for 'dark' (10+80) and
-- purposefully lighter for 'light' (90+20)
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#101624' or '#bdc7db'
local fg = is_dark and '#c3c7ce' or '#14161b'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  -- Make it "gloomy"
  saturation = is_dark and 'lowmedium' or 'mediumhigh',
  accent = 'azure',
})

vim.g.colors_name = 'miniwinter'
