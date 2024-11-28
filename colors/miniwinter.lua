-- "Cold dark winter" vibe
-- Dark  (OKLch): bg=10-3-225 and fg=80-2-269
-- Light (OKLch): bg=85-2-225 and fg=15-2-269
-- Foreground hue is hand picked for good bg colors
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#051920' or '#c7d8df'
local fg = is_dark and '#c1c6d4' or '#1e222c'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'azure',
})

vim.g.colors_name = 'miniwinter'
