-- Model flaky test
math.randomseed(vim.loop.hrtime())

local T = MiniTest.new_set()

T['flaky'] = function()
  local x = math.random()
  if x <= 0.5 then error('Random number ' .. x .. ' is less than 0.5.') end
end

return T
