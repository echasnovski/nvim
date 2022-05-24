vim.cmd('set rtp+=.')

require('mini-dev.test').setup()

-- io.stdout:write('\27[1000E\27[6n')

MiniTest.run()

-- for n_lines = 1, 60 do
--   -- Write lines
--   for i = 1, n_lines do
--     local out = string.format('\r\27[2KHello%s\n', i)
--     io.stdout:write(out)
--   end
--
--   -- Go back to beginning
--   io.stdout:write(('\27[%sF'):format(n_lines))
--   -- io.stdout:write(('\27[%sT'):format(n_lines))
--
--   -- Show lines
--   io.stdout:flush()
--
--   vim.loop.sleep(200)
-- end
--
-- vim.cmd('0cquit!')
