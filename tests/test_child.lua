local new_set, expect = MiniTest.new_testset, MiniTest.expect
local eq = expect.equality

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

T['child']['`get_screenshot()`'] = function()
  child.o.cmdheight = 3
  child.o.lines, child.o.columns = 10, 20
  child.cmd('set rtp+=~/.config/nvim/pack/plugins/opt/mini')
  child.cmd('colorscheme minischeme')
  child.api.nvim_buf_set_lines(0, 0, -1, true, { 'aaa' })
  expect.reference_screenshot(child.get_screenshot())
end

return T
