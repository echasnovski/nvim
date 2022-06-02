local new_set, expect = MiniTest.new_testset, MiniTest.expect
local eq = expect.equality

local sleep_ms = 0

local f = function()
  vim.loop.sleep(sleep_ms)
  return true
end

--stylua: ignore
local T = new_set({
  hooks = {
    pre_case = function() vim.loop.sleep(sleep_ms) end,
    post_case = function() vim.loop.sleep(sleep_ms) end,
  },
})

table.insert(T, function()
  error('This should be collected at the end.')
end)

--stylua: ignore
T['traceback'] = function()
  local h = dofile('tests/helpers.lua').h
  local g = function() h(1, 2) end
  g()
end

T['skip'] = function()
  MiniTest.skip('This is skipped')
  error('This should not be executed')
end

T['finally'] = new_set()
T['finally']['use `finally()` with error'] = function()
  MiniTest.finally(function()
    _G.was_inside_finally_error = true
  end)
  error('Generic error')
end
T['finally']['verify `finally()` with error'] = function()
  eq(_G.was_inside_finally_error, true)
end

T['finally']['use `finally()` without error'] = function()
  MiniTest.finally(function()
    _G.was_inside_finally_no_error = true
  end)
  eq(1, 1)
end
T['finally']['verify `finally()` without error'] = function()
  eq(_G.was_inside_finally_no_error, true)
end

T['first'] = new_set()
T['first']['a'] = new_set()
T['first']['a']['aa'] = f
T['first']['a']['ab'] = f
T['first']['a']['ac'] = f
T['first']['b'] = new_set()
T['first']['b']['ba'] = f
T['first']['b']['bb'] = f
T['first']['c'] = f

--stylua: ignore start
T['second'] = new_set()
T['second']['a'] = new_set()
T['second']['a']['aa'] = function() table.insert(MiniTest.current.case.exec.notes, 'Hello note!'); error('Hello') end
T['second']['a']['ab'] = function() error('Hello') end
T['second']['a']['ac'] = function() table.insert(MiniTest.current.case.exec.notes, 'Hello note!') end
T['second']['a']['ad'] = f
T['second']['b'] = new_set()
T['second']['b']['ba'] = f
T['second']['b']['bb'] = f
T['second']['c'] = f
--stylua: ignore end

return T
