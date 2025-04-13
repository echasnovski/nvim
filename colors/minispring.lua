-- "Blooming spring"
-- Dark  (OKLch): bg=15-3-135 and fg=85-2-178
-- Light (OKLch): bg=90-1-135 and fg=20-2-178
-- Foreground hues are picked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#1c2617' or '#e0e4de'
local fg = is_dark and '#c8d9d4' or '#23322e'

-- Use background shade of green as foreground accent for better usability with
-- diff colors (for example, "MiniDiffSignAdd" uses green).
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
