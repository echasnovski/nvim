-- "Hot summer"
-- Dark  (OKLch): bg=15-1-45 and fg=85-1-270
-- Light (OKLch): bg=90-1-45 and fg=20-1-270
-- Foreground hues are intentionally different temperature (for better
-- legibility) and tweaked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#27211e' or '#e9e1dd'
local fg = is_dark and '#d2d4db' or '#2c2e33'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'yellow',
})

vim.g.colors_name = 'minisummer'
