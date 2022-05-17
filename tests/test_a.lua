local child = MiniTest.new_child_neovim()
local new_set = MiniTest.new_testset

local T = new_set({
  hooks = { pre_case = child.restart, post_once = child.stop },
  user = { tag = "Global 'test_a.lua'" },
})

T['a'] = new_set({ user = { tag = [[Test 'a']] } })

T['a']['works'] = function()
  child.lua('_G.n = 0; _G.n = _G.n + 2')
  if child.lua_get('_G.n') ~= 1 then
    error('`_G.n` is not equal to 1')
  end
end

T['a']['works again'] = function()
  child.lua('_G.n = 100')
  if child.lua_get('_G.n') ~= 100 then
    error()
  end
end

T['a']['and again'] = function()
  child.lua('_G.n = 101')
  if child.lua_get('_G.n') ~= 100 then
    error('`_G.n` is not equal to 100')
  end
end

return T
