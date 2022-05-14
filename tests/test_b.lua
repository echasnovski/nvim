local new_set = MiniTest.new_test_set
local printing = function(x)
  return function()
    print(x)
  end
end

local T = MiniTest.new_test_set({
  hooks = {
    -- pre_first = printing('1'),
    -- pre_node = printing('2'),
    pre_case = printing('3'),
    post_case = printing('4'),
    -- post_node = printing('5'),
    -- post_last = printing('6'),
  },
})

T['a'] = function()
  error('Does not work')
end

T['b'] = MiniTest.new_test_set({
  hooks = {
    -- pre_first = printing('b1'),
    -- pre_node = printing('b2'),
    pre_case = printing('b3'),
    post_case = printing('b4'),
    -- post_node = printing('b5'),
    -- post_last = printing('b6'),
  },
})

T['b']['works'] = new_set()

T['b']['works']['first time'] = function()
  print('Test b|works|first time')
end

T['b']['works']['second time'] = function()
  error('Test b|works|second time')
end

return T
