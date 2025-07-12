-- "Icy winter"
-- Dark  (OKLch): bg=15-3-225 and fg=85-1-80
-- Light (OKLch): bg=90-1-225 and fg=20-1-80
-- Foreground hues are intentionally different temperature (for better
-- legibility) and tweaked to maximize palette's bg colors visibility
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#11262d' or '#dce4e8'
local fg = is_dark and '#d8d4cd' or '#312e29'

local hues = require('mini.hues')
local p = hues.make_palette({
  background = bg,
  foreground = fg,
  -- Have less saturated foreground for "cool" period
  saturation = is_dark and 'lowmedium' or 'mediumhigh',
  accent = 'azure',
})

-- Have more saturated background colors for more legible diffs
local p_bg = hues.make_palette({
  background = bg,
  foreground = fg,
  saturation = is_dark and 'medium' or 'high',
  accent = 'azure',
})
for color, hex in pairs(p_bg) do
  if vim.endswith(color, '_bg') then p[color] = hex end
end

hues.apply_palette(p)
vim.g.colors_name = 'miniwinter'
