-- "Red autumn leaves" vibe
-- Reference hue is 355 for "vibrant red" and not 0 for proper cyan diff
-- Chroma values are 3 for bg and 1 for fg
-- Lightness levels are same for 'dark' and 'light' (15+85) and are "medium"
-- TODO: Consider changing to 90+20 for 'light'
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#2e1c23' or '#e6cdd5'
local fg = is_dark and '#dad2d5' or '#272023'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'purple',
})

vim.g.colors_name = 'miniautumn'
