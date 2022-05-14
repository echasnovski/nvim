local child = MiniTest.new_child_neovim()
local new_set = MiniTest.new_test_set

local T = new_set({ user = { "Global 'test_a.lua'" } })

T['a'] = new_set({ user = { [[Test 'a']] } })

T['a']['works'] = function()
  child.lua('_G.n = 0; _G.n = _G.n + 1')
  if child.lua_get('_G.n') ~= 1 then
    error()
  end
end

T['a']['works again'] = function()
  child.lua('_G.n = 100')
  if child.lua_get('_G.n') ~= 100 then
    error()
  end
end

child.stop()

return T
