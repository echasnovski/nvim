local hues = require('mini-dev.hues')

-- Generate random config with initialized random seed (otherwise it won't be
-- random during startup)
math.randomseed(vim.loop.hrtime())
local config = hues.random_config({ saturation = vim.o.background == 'dark' and 'medium' or 'high', accent = 'bg' })

hues.setup(config)

vim.g.colors_name = 'randomhue'
