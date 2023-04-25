local genscheme = require('mini-dev.genscheme')

-- Generate random config with initialized random seed (otherwise it won't be
-- random during startup)
math.randomseed(vim.loop.hrtime())
local config =
  genscheme.random_config({ saturation = vim.o.background == 'dark' and 'medium' or 'high', accent = 'bg' })

genscheme.setup(config)

vim.g.colors_name = 'minirandom'
