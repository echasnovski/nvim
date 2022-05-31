local new_set, expect = MiniTest.new_testset, MiniTest.expect

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

--stylua: ignore
T['traceback'] = function()
  local h = dofile('tests/helpers.lua').h
  local g = function() h(1, 2) end
  g()
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
