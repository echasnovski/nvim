-- "Cooling red autumn" vibe
-- Dark  (OKLch): bg=10-2-315 and fg=80-2-0
-- Light (OKLch): bg=85-2-315 and fg=15-2-0
-- Foreground hues are picked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#1a141d' or '#dad1de'
local fg = is_dark and '#d3c2c6' or '#2b1e22'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'red',
})

vim.g.colors_name = 'miniautumn'
