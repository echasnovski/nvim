-- "Cooling autumn"
-- Dark  (OKLch): bg=15-2-315 and fg=85-2-336
-- Light (OKLch): bg=90-1-315 and fg=20-2-336
-- Foreground hues are picked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#262029' or '#e5e1e7'
local fg = is_dark and '#ded0da' or '#352a32'

-- Use background shade of red as foreground accent for better usability with
-- diff colors (for example, "MiniDiffSignDelete" uses red).
local hues = require('mini.hues')
local p = hues.make_palette({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'lowmedium' or 'mediumhigh',
  accent = 'bg',
})
p.accent_bg = p.red_bg
hues.apply_palette(p)

vim.g.colors_name = 'miniautumn'
