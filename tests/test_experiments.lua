local new_set, expect = MiniTest.new_testset, MiniTest.expect

local sleeping = function(ms)
  return function()
    vim.loop.sleep(ms)
  end
end

local T = new_set({
  hooks = { pre_once = sleeping(250), pre_case = sleeping(250), post_case = sleeping(250), post_once = sleeping(250) },
})

T['first'] = sleeping(250)
T['second'] = sleeping(250)

return T
