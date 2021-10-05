-- This option is required for a plugin to work
vim.opt.termguicolors = true

require('colorizer').setup({
  '*',
  css = { rgb_fn = true }, -- Enable parsing rgb(...) functions in css
}, {
  names = false, -- Don't color plain names
  RRGGBBAA = true, -- Color 'RRGGBBAA' codes
})
