require('mini.comment').setup()
require('mini.cursorword').setup()
require('mini.pairs').setup({
  settings = {modes = {"c", "i", "t"}, map_cr = false}
})
require('mini.statusline').setup()
require('mini.surround').setup()
require('mini.tabline').setup()
require('mini.trailspace').setup()
