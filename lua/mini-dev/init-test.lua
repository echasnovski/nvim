vim.cmd('set rtp+=.')

require('mini-dev.test').setup()
-- require('mini-dev.test').setup({
--   execute = {
--     reporter = {
--       update = function(case_num)
--         local case = MiniTest.current.all_cases[case_num]
--
--         local desc = table.concat(case.desc, ' | ')
--         local with_args = ''
--         if #case.args > 0 then
--           with_args = string.format(' with args %s', vim.inspect(case.args, { newline = '', indent = '' }))
--         end
--         local state = tostring(case.exec.state)
--
--         local out = string.format('%s%s: %s\n', desc, with_args, state)
--         io.stdout:write(out)
--       end,
--       finish = function()
--         vim.cmd('quit')
--       end,
--     },
--   },
-- })

MiniTest.run()
