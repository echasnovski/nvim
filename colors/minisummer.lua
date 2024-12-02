-- "Hot yellow summer" vibe
-- Dark  (OKLch): bg=15-2-45 and fg=85-2-70
-- Light (OKLch): bg=90-2-45 and fg=20-2-70
-- Foreground hues are picked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#2b201a' or '#efdfd8'
local fg = is_dark and '#ded3c7' or '#352d23'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'yellow',
})

vim.g.colors_name = 'minisummer'
