-- "Icy winter"
-- Dark  (OKLch): bg=15-3-225 and fg=85-2-270
-- Light (OKLch): bg=90-1-225 and fg=20-2-270
-- Foreground hues are picked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#11262d' or '#dce4e8'
local fg = is_dark and '#cfd4e2' or '#2a2e39'

require('mini.hues').setup({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'lowmedium' or 'mediumhigh',
  accent = 'azure',
})

vim.g.colors_name = 'miniwinter'
