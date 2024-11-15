-- "Hot and bright summer" vibe
-- Reference hue is 85 for "hot yellow" and not 90 for proper cyan diff
-- Chroma values are 3 for bg and 1 for fg
-- Lightness is same for 'dark' and 'light' (20+90) to achieve "sunny" feeling
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#352d1d' or '#ece2cd'
local fg = is_dark and '#e6e2db' or '#302e29'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'orange',
})

vim.g.colors_name = 'minisummer'
