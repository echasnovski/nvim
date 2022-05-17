local new_set = MiniTest.new_testset

local T = new_set({ parametrize = { { 'a' }, { 'b' } } })

T['b'] = new_set()

T['b']['works'] = new_set({ parametrize = { { 1 }, { 2 } } })

T['b']['works']['first time'] = function(x, y)
  print('Test b|works|first time', x, y)
end

T['b']['works']['second time'] = function(x, y)
  print(x, y)
  error('Test b|works|second time')
end

return T
