-- "Blue-yellow" color scheme
--
-- Palette is mostly hand crafted leveraging OKLch color space.
-- Hues are chosen to look pretty while being far enough from one another.
--
-- Bg and Fg sets are computed with `require('mini.hues').make_palette()`.
--
-- All actual colors have have the same L and c, with varying h.
-- Hex colors are computed with 'mini.colors' and `gamut_clip='cusp'`.
-- Background colors are meant to be visible and distinctive.

local palette

--stylua: ignore
if vim.o.background == 'dark' then
  palette = {
    -- Main background: L=10, c=3, h=240
    bg_edge2 = '#000812', bg_edge = '#020f19', bg = '#081823', bg_mid = '#253642', bg_mid2 = '#435562',
    -- Main foreground: L=85, c=3, h=110
    fg_edge2 = '#f1f3dc', fg_edge = '#e3e5ce', fg = '#d5d7c0', fg_mid = '#b3b59f', fg_mid2 = '#91937d',

    --     L=85, c=8              L=10, c=8
    red    = '#ffc0c4', red_bg    = '#32000a', -- h= 15
    orange = '#fcc9a0', orange_bg = '#422100', -- h= 60
    yellow = '#e0d699', yellow_bg = '#3b3300', -- h=100
    green  = '#b4e3b5', green_bg  = '#002805', -- h=145
    cyan   = '#94e6e5', cyan_bg   = '#004748', -- h=195
    azure  = '#a1ddff', azure_bg  = '#00334a', -- h=235
    blue   = '#c8cdff', blue_bg   = '#110e39', -- h=280
    purple = '#f0c3f2', purple_bg = '#27042a', -- h=325

    accent = '#a1ddff', accent_bg = '#00334a', -- h=235
  }
else
  palette = {
    -- Main background: L=95, c=3, h=90
    bg_edge2 = '#fff7e3', bg_edge = '#fef5e0', bg = '#f9f0db', bg_mid = '#d6cdb9', bg_mid2 = '#b3aa97',
    -- Main foreground: L=20, c=3, h=270
    fg_edge2 = '#080d1a', fg_edge = '#191e2d', fg = '#282e3e', fg_mid = '#454b5d', fg_mid2 = '#636b7d',

    --     L=20, c=16             L=95, c=6
    red    = '#700021', red_bg    = '#ffd8da', -- h= 15
    orange = '#804500', orange_bg = '#ffe0c6', -- h= 60
    yellow = '#746600', yellow_bg = '#faf3c4', -- h=100
    green  = '#005c14', green_bg  = '#d9fcd9', -- h=145
    cyan   = '#008283', cyan_bg   = '#c2fefd', -- h=195
    azure  = '#006189', azure_bg  = '#c5eaff', -- h=235
    blue   = '#27127a', blue_bg   = '#d9ddff', -- h=280
    purple = '#56015c', purple_bg = '#ffe0ff', -- h=325

    accent = '#746600', accent_bg = '#faf3c4', -- h=100
  }
end

require('mini.hues').apply_palette(palette)
vim.g.colors_name = 'minischeme2'
