-- My personal "Mint" theme
-- Derived from base16 (https://github.com/chriskempson/base16) and mini16
-- palette generator

-- Dark palette is a 'mini16' with background '#29303d' (HSL = 220-20-20) and
-- foreground '#e7f5a3' (HSL = 70-80-80)
local palette = {
  base00 = "#29303d",
  base01 = "#444f65",
  base02 = "#5e6e8c",
  base03 = "#8290ab",
  base04 = "#e7f5a3",
  base05 = "#dff283",
  base06 = "#d6ee63",
  base07 = "#ceeb42",
  base08 = "#f5b1a3",
  base09 = "#eb5e42",
  base0A = "#bef5a3",
  base0B = "#7aeb42",
  base0C = "#a3e7f5",
  base0D = "#42ceeb",
  base0E = "#daa3f5",
  base0F = "#b242eb"
}

require('mini.colors').base16(palette, 'Mint')

-- Make bright and bold color for operators and delimiters
local bright_color = '#ffffff'
if vim.o.background == 'light' then bright_color = '#000000' end

local hi_bright = function(group)
  vim.cmd(
    string.format([[hi %s guifg=%s gui=bold]], group, bright_color)
  )
end

hi_bright('Operator')
hi_bright('Delimiter')
hi_bright('TSPunctBracket')
hi_bright('TSPunctDelimiter')
hi_bright('TSPunctSpecial')
hi_bright('TSOperator')
