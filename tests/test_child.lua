local new_set, expect = MiniTest.new_set, MiniTest.expect
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

T['child']['prevent hanging'] = new_set()

T['child']['prevent hanging']['helper wrappers'] = new_set(
  { parametrize = { { 'lua' }, { 'lua_get' }, { 'cmd' }, { 'cmd_capture' }, { 'get_screenshot' } } },
  {
    function(method)
      child.type_keys('di')
      child[method]('1 + 1')
    end,
  }
)

T['child']['prevent hanging']['builtin wrappers'] = new_set({
  parametrize = { { 'loop', 'hrtime' }, { 'fn', 'mode' }, { 'b', 'aaa' }, { 'bo', 'filetype' } },
})

T['child']['prevent hanging']['builtin wrappers']['metatbl_index'] = function(tbl_name, key)
  child.type_keys('di')
  child[tbl_name][key]('1 + 1')
end

T['child']['prevent hanging']['builtin wrappers']['metatbl_newindex'] = function(tbl_name, key)
  child.type_keys('di')
  child[tbl_name][key] = 1
end

T['child']['`get_screenshot()`'] = function()
  child.o.cmdheight = 3
  child.o.lines, child.o.columns = 10, 20
  child.cmd('colorscheme blue')
  child.api.nvim_buf_set_lines(0, 0, -1, true, { 'aaa' })
  expect.reference_screenshot(child.get_screenshot())
end

return T
