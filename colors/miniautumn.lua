-- "Cold autumn with red leaves" vibe
-- Reference hue is 355 for "vibrant red" and not 0 for proper cyan diff
-- Chroma levels are 3 for bg and 1 for fg
-- Lightness levels are 10+80 for 'dark' and 90+20 for 'light'
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#211017' or '#f4dbe4'
local fg = is_dark and '#ccc4c7' or '#332c2e'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'purple',
})

vim.g.colors_name = 'miniautumn'
