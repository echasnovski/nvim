vim.cmd('set rtp+=.')

require('mini-dev.test').setup()

MiniTest.run()

vim.cmd('0cquit!')
