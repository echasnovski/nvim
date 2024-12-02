-- "Gloomy blue winter" vibe
-- Dark  (OKLch): bg=15-3-225 and fg=85-2-270
-- Light (OKLch): bg=90-2-225 and fg=20-2-270
-- Foreground hue is hand picked for good bg colors
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#11262d' or '#d5e6ed'
local fg = is_dark and '#cfd4e2' or '#2a2e39'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'lowmedium' or 'mediumhigh',
  accent = 'azure',
})

vim.g.colors_name = 'miniwinter'
