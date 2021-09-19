-- 'Minischeme' color scheme
-- Derived from base16 (https://github.com/chriskempson/base16) and
-- mini_palette palette generator
local use_cterm, palette

-- Dark palette is an output of 'MiniBase16.mini_palette':
-- - Background '#112641' (LCh(uv) = 15-20-250)
-- - Foreground '#e2eb66' (Lch(uv) = 90-80-90)
-- - Accent chroma 80
if vim.o.background == 'dark' then
  palette = {
    base00 = '#112641',
    base01 = '#3a475e',
    base02 = '#606b81',
    base03 = '#8791a7',
    base04 = '#d5de55',
    base05 = '#e2eb66',
    base06 = '#eff876',
    base07 = '#fbff85',
    base08 = '#ffce9b',
    base09 = '#cf7c3e',
    base0A = '#3fa52b',
    base0B = '#9af98f',
    base0C = '#ce6ad3',
    base0D = '#0cf8ff',
    base0E = '#ffc1ff',
    base0F = '#00a6c9',
  }
  use_cterm = {
    base00 = 235,
    base01 = 238,
    base02 = 60,
    base03 = 103,
    base04 = 185,
    base05 = 185,
    base06 = 228,
    base07 = 228,
    base08 = 222,
    base09 = 173,
    base0A = 70,
    base0B = 120,
    base0C = 170,
    base0D = 14,
    base0E = 219,
    base0F = 38,
  }
end

-- Dark palette is an 'inverted dark', output of 'MiniBase16.mini_palette':
-- - Background '#e2e5ca' (LCh(uv) = 90-20-90)
-- - Foreground '#0031ce' (Lch(uv) = 15-80-250)
-- - Accent chroma 80
if vim.o.background == 'light' then
  palette = {
    base00 = '#e2e5ca',
    base01 = '#c1c4a9',
    base02 = '#a1a489',
    base03 = '#82856a',
    base04 = '#505fe1',
    base05 = '#0031ce',
    base06 = '#876900',
    base07 = '#070500',
    base08 = '#793800',
    base09 = '#ba7200',
    base0A = '#00992b',
    base0B = '#005d00',
    base0C = '#c657be',
    base0D = '#005f8b',
    base0E = '#900088',
    base0F = '#0096c2',
  }
  use_cterm = {
    base00 = 254,
    base01 = 250,
    base02 = 144,
    base03 = 101,
    base04 = 62,
    base05 = 26,
    base06 = 94,
    base07 = 0,
    base08 = 94,
    base09 = 130,
    base0A = 28,
    base0B = 22,
    base0C = 169,
    base0D = 24,
    base0E = 90,
    base0F = 31,
  }
end

if palette then
  require('mini.base16').apply(palette, 'minischeme', use_cterm)
end
