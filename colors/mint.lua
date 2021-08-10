-- My personal "Mint" theme
-- Derived from base16 (https://github.com/chriskempson/base16) and
-- mini16 palette with background '#1f242e' and foreground '#e1f28c'
local palette = {
  base00 = "#1f242e",
  base01 = "#333c4c",
  base02 = "#48546b",
  base03 = "#5c6b89",
  base04 = "#e1f28c",
  base05 = "#d5ed5e",
  base06 = "#c9e831",
  base07 = "#b0ce17",
  base08 = "#f29d8c",
  base09 = "#ce3617",
  base0A = "#aef28c",
  base0B = "#54ce17",
  base0C = "#8ce1f2",
  base0D = "#17b0ce",
  base0E = "#d08cf2",
  base0F = "#9117ce"
}

require("mini.colors").base16(palette, 'Mint')
vim.o.background = 'dark'

-- Brighten comments
vim.cmd([[hi Comment guifg=#8693ac]])

-- Make bright and bold color for operators and delimiters
local bright_color = '#FFFFFF'

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
