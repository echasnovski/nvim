-- "Hot summer"
-- Dark  (OKLch): bg=15-1-45 and fg=85-2-70
-- Light (OKLch): bg=90-1-45 and fg=20-2-70
-- Foreground hues are picked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#27211e' or '#e9e1dd'
local fg = is_dark and '#ded3c7' or '#352d23'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'yellow',
})

vim.g.colors_name = 'minisummer'
