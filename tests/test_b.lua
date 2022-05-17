local new_set = MiniTest.new_testset

MiniTest.log = {}
local logging = function(x)
  return function()
    table.insert(MiniTest.log, x)
    -- print(x)
  end
end

-- -- Ensure that this will be called even if represented by the same function.
-- -- Use this in several `_once` hooks and see that they all got executed.
-- local f = logging('f')

local T = MiniTest.new_testset({
  hooks = {
    pre_once = logging('pre_once_1'),
    pre_case = logging('pre_case_1'),
    post_case = logging('post_case_1'),
    post_once = logging('post_once_1'),
  },
})

T['a'] = function()
  table.insert(MiniTest.log, [[Test of 'a']])
end

T['b'] = MiniTest.new_testset({
  hooks = {
    pre_once = logging('pre_once_2'),
    pre_case = logging('pre_case_2'),
    post_case = logging('post_case_2'),
    post_once = logging('post_once_2'),
  },
})

T['b']['works'] = new_set()

T['b']['works']['first time'] = function()
  table.insert(MiniTest.log, 'Test b|works|first time')
end

T['b']['works']['second time'] = function()
  table.insert(MiniTest.log, 'Test b|works|second time')
end

return T
