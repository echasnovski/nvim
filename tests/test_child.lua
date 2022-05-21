local new_set, expect = MiniTest.new_testset, MiniTest.expect
local eq = expect.equal

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = { pre_case = child.restart, post_once = child.stop },
})

T['child'] = new_set()

T['child']['works'] = function()
  child.lua('_G.n = 0; _G.n = _G.n + 2')
  eq(child.lua_get('_G.n'), 1)
end

T['child']['works again'] = function()
  child.lua('_G.n = 100')
  eq(child.lua_get('_G.n'), 100)
end

T['child']['and again'] = function()
  child.lua('_G.n = 101')
  eq(child.lua_get('_G.n'), 100)
end

T['child']['`get_screen()`'] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, true, { 'aaa', 'bbb' })
  expect.equal_to_dump(child.get_screen())
end

return T
