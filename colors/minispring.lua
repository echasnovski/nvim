-- "Cold green scenery with blossoming" vibe
-- Reference hue is 175 for "cold green" and not 180 for proper cyan diff
-- Chroma values are 3 for bg and 1 for fg
-- Lightness levels are same for 'dark' and 'light' (15+85) and are "medium"
-- TODO: Consider changing to 90+20 for 'light'
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#122722' or '#c1dbd3'
local fg = is_dark and '#ced7d4' or '#1e2422'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'green',
})

vim.g.colors_name = 'minispring'
