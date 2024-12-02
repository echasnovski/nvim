-- "Cooling red autumn" vibe
-- Dark  (OKLch): bg=15-2-315 and fg=85-2-336
-- Light (OKLch): bg=90-2-315 and fg=20-2-336
-- Foreground hues are picked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#262029' or '#e8dfec'
local fg = is_dark and '#ded0da' or '#352a32'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'lowmedium' or 'mediumhigh',
  accent = 'red',
})

vim.g.colors_name = 'miniautumn'
