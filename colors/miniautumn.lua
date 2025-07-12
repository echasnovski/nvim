-- "Cooling autumn"
-- Dark  (OKLch): bg=15-2-315 and fg=85-1-100
-- Light (OKLch): bg=90-1-315 and fg=20-1-100
-- Foreground hues are intentionally different temperature (for better
-- legibility) and tweaked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#262029' or '#e5e1e7'
local fg = is_dark and '#d7d5cd' or '#2f2e29'

-- Have "red" accent only for bg (distinctive statusline), but not for fg.
-- This is better usability with diff colors (`MiniDiffSignAdd` uses red).
local hues = require('mini.hues')
local p = hues.make_palette({
  background = bg,
  foreground = fg,
  -- Have less saturated foreground for "cool" period
  saturation = is_dark and 'lowmedium' or 'mediumhigh',
  accent = 'bg',
})

-- Have more saturated background colors for more legible diffs
local p_bg = hues.make_palette({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'bg',
})
for color, hex in pairs(p_bg) do
  if vim.endswith(color, '_bg') then p[color] = hex end
end
p.accent_bg = p.red_bg

hues.apply_palette(p)
vim.g.colors_name = 'miniautumn'
