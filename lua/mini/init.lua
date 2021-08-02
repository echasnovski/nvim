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
  hi MiniTablineCurrent         guibg=#7C6F64 guifg=#EBDBB2 gui=bold ctermbg=15 ctermfg=0
  hi MiniTablineActive          guibg=#3C3836 guifg=#EBDBB2 gui=bold ctermbg=7  ctermfg=0
  hi MiniTablineHidden          guifg=#A89984 guibg=#3C3836          ctermbg=8  ctermfg=7

  hi MiniTablineModifiedCurrent guibg=#458588 guifg=#EBDBB2 gui=bold ctermbg=14 ctermfg=0
  hi MiniTablineModifiedActive  guibg=#076678 guifg=#EBDBB2 gui=bold ctermbg=6  ctermfg=0
  hi MiniTablineModifiedHidden  guibg=#076678 guifg=#BDAE93          ctermbg=6  ctermfg=0

  hi MiniTablineFill NONE

  hi MiniStatuslineModeNormal  guibg=#BDAE93 guifg=#1D2021 gui=bold ctermbg=7 ctermfg=0
  hi MiniStatuslineModeInsert  guibg=#83A598 guifg=#1D2021 gui=bold ctermbg=4 ctermfg=0
  hi MiniStatuslineModeVisual  guibg=#B8BB26 guifg=#1D2021 gui=bold ctermbg=2 ctermfg=0
  hi MiniStatuslineModeReplace guibg=#FB4934 guifg=#1D2021 gui=bold ctermbg=1 ctermfg=0
  hi MiniStatuslineModeCommand guibg=#FABD2F guifg=#1D2021 gui=bold ctermbg=3 ctermfg=0
  hi MiniStatuslineModeOther   guibg=#8EC07C guifg=#1D2021 gui=bold ctermbg=6 ctermfg=0
]], false)
