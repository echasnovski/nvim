local base2 = require('mini-dev.base2')
local config = base2.random_config({ saturation = vim.o.background == 'dark' and 'medium' or 'high', accent = 'bg' })
base2.setup(config)

vim.g.colors_name = 'minirandom'
