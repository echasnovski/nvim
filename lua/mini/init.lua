require('mini.comment').setup()
require('mini.completion').setup({delay = {signature = 50}})
require('mini.cursorword').setup()
require('mini.pairs').setup({modes = {insert = true, command = true, terminal = true}})
require('mini.statusline').setup()
require('mini.surround').setup()
require('mini.tabline').setup()
require('mini.trailspace').setup()

-- Define custom highlightings (from Gruvbox color palette)
vim.api.nvim_exec([[
  hi MiniTablineCurrent         guibg=#8797AB guifg=#E0E4C8 gui=bold ctermbg=15 ctermfg=0
  hi MiniTablineActive          guibg=#343E4B guifg=#E0E4C8 gui=bold ctermbg=7  ctermfg=0
  hi MiniTablineHidden          guibg=#343E4B guifg=#D2D9B0          ctermbg=8  ctermfg=7

  hi MiniTablineModifiedCurrent guibg=#8CD0F2 guifg=#E0E4C8 gui=bold ctermbg=14 ctermfg=0
  hi MiniTablineModifiedActive  guibg=#19A1E6 guifg=#E0E4C8 gui=bold ctermbg=6  ctermfg=0
  hi MiniTablineModifiedHidden  guibg=#19A1E6 guifg=#D2D9B0          ctermbg=6  ctermfg=0

  hi MiniTablineFill NONE

  hi MiniStatuslineModeNormal  guibg=#D2D9B0 guifg=#1F252D gui=bold ctermbg=7 ctermfg=0
  hi MiniStatuslineModeInsert  guibg=#8CD0F2 guifg=#1F252D gui=bold ctermbg=4 ctermfg=0
  hi MiniStatuslineModeVisual  guibg=#8CF28C guifg=#1F252D gui=bold ctermbg=2 ctermfg=0
  hi MiniStatuslineModeReplace guibg=#F28CF2 guifg=#1F252D gui=bold ctermbg=1 ctermfg=0
  hi MiniStatuslineModeCommand guibg=#F2BF8C guifg=#1F252D gui=bold ctermbg=3 ctermfg=0
  hi MiniStatuslineModeOther   guibg=#8797AB guifg=#1F252D gui=bold ctermbg=6 ctermfg=0
]], false)
