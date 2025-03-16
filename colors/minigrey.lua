-- "Less colors" vibe
-- Lightness levels are 15+85 for 'dark' and 90+20 for 'light'. Picked by hand.
-- There is no reference hue and chroma. Instead, tweak reference grey colors
-- (with chroma 0 and reference lightness values) in such a way so that:
-- - Background and accent color is azure.
-- - Diff's cyan is closer to cyan.
local is_dark = vim.o.background == 'dark'
local bg = is_dark and '#212223' or '#e1e2e3'
local fg = is_dark and '#d3d4d5' or '#2d2e2f'

-- Alternative with precisely manipulated colors to reduce their usage while
-- retaining usability
local hues = require('mini.hues')
local p = hues.make_palette({
  background = bg,
  foreground = fg,
  -- Make it "less colors"
  saturation = is_dark and 'lowmedium' or 'mediumhigh',
  accent = 'bg',
})

local less_p = vim.deepcopy(p)
less_p.orange, less_p.orange_bg = fg, bg
less_p.blue, less_p.blue_bg = fg, bg

hues.apply_palette(less_p)
vim.g.colors_name = 'minigrey'

-- Tweak highlight groups for general usability (acounting for removed colors)
local hi = function(group, data) vim.api.nvim_set_hl(0, group, data) end

hi('DiagnosticInfo', { fg = less_p.azure })
hi('DiagnosticUnderlineInfo', { sp = less_p.azure, underline = true })
hi('DiagnosticFloatingInfo', { fg = less_p.azure, bg = less_p.bg_edge })

hi('MiniHipatternsTodo', { fg = less_p.bg, bg = p.azure, bold = true })
hi('MiniIconsBlue', { fg = less_p.azure })
hi('MiniIconsOrange', { fg = less_p.yellow })

hi('@keyword.return', { fg = less_p.accent, bold = true })
hi('Delimiter', { fg = less_p.fg_edge2 })
hi('@markup.heading.1', { fg = less_p.accent, bold = true })
