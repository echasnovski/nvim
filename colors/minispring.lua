-- "Blooming spring"
-- Dark  (OKLch): bg=15-3-135 and fg=85-1-265
-- Light (OKLch): bg=90-1-135 and fg=20-1-265
-- Foreground hues are intentionally different temperature (for better
-- legibility) and tweaked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#1c2617' or '#e0e4de'
local fg = is_dark and '#d2d5db' or '#2c2e33'

-- Have "green" accent only for bg (distinctive statusline), but not for fg.
-- This is better usability with diff colors (`MiniDiffSignAdd` uses green).
local hues = require('mini.hues')
local p = hues.make_palette({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'bg',
})
p.accent_bg = p.green_bg
hues.apply_palette(p)

vim.g.colors_name = 'minispring'
