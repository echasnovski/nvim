-- "Hot yellow summer" vibe
-- Dark  (OKLch): bg=15-2-45 and fg=85-2-68
-- Light (OKLch): bg=90-2-45 and fg=20-2-68
-- Foreground hues are picked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#2b1f1a' or '#efdfd8'
local fg = is_dark and '#ded2c7' or '#352c24'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'yellow',
})

vim.g.colors_name = 'minisummer'
