-- 'Minischeme' color scheme
-- Derived from base16 (https://github.com/chriskempson/base16) and mini16
-- palette generator
local use_cterm, palette

-- Dark palette is an output of 'MiniBase16.mini_palette':
-- - Background '#1e2634' (LCh(uv) = 15-10-250);
-- - Foreground '#e2ea7c' (Lch(uv) = 90-70-90)
if vim.o.background == 'dark' then
  palette = {
    base00 = '#1e2634',
    base01 = '#414753',
    base02 = '#656b76',
    base03 = '#8c919c',
    base04 = '#d5dd6e',
    base05 = '#e2ea7c',
    base06 = '#eff78a',
    base07 = '#fcff98',
    base08 = '#ffd1a5',
    base09 = '#c97f4d',
    base0A = '#4da340',
    base0B = '#a4f69b',
    base0C = '#c671cb',
    base0D = '#5bf5ff',
    base0E = '#ffc6ff',
    base0F = '#00a3c2'
  }
  use_cterm = {
    base00 = 235,
    base01 = 238,
    base02 = 242,
    base03 = 246,
    base04 = 185,
    base05 = 186,
    base06 = 228,
    base07 = 228,
    base08 = 223,
    base09 = 173,
    base0A = 71,
    base0B = 156,
    base0C = 170,
    base0D = 87,
    base0E = 225,
    base0F = 37
  }
end

-- Dark palette is an output of 'MiniBase16.mini_palette':
-- - Background '#ecf1fc' (LCh(uv) = 95-10-250);
-- - Foreground '#525900' (Lch(uv) = 25-70-90)
if vim.o.background == 'light' then
  palette = {
    base00 = '#ecf1fc',
    base01 = '#cbd0da',
    base02 = '#aaafba',
    base03 = '#8b909a',
    base04 = '#7d8446',
    base05 = '#525900',
    base06 = '#2b3200',
    base07 = '#030600',
    base08 = '#764a2c',
    base09 = '#b3856d',
    base0A = '#6c9b69',
    base0B = '#2b5f27',
    base0C = '#af80b1',
    base0D = '#005f72',
    base0E = '#754276',
    base0F = '#4d9aad'
  }
  use_cterm = {
    base00 = 255,
    base01 = 252,
    base02 = 145,
    base03 = 246,
    base04 = 101,
    base05 = 58,
    base06 = 235,
    base07 = 0,
    base08 = 239,
    base09 = 137,
    base0A = 65,
    base0B = 236,
    base0C = 139,
    base0D = 23,
    base0E = 243,
    base0F = 67
  }
end

if palette then
  require('mini.base16').apply(palette, 'minischeme', use_cterm)
end
