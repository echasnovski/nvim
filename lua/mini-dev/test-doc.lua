--- This is a file to test 'mini-dev.doc'

local M = {}

--- Second block
---
---@param a `string` Some string. List of items:
---  - Item 1.
---  - Item 2.
---@param b `number` Number.
---@return boolean
function M.fun(a, b)
  return true
end

---@param x number
---@param y number
---@text Some text after parameters.
M.fun2 = function(x, y)
  return x + y
end

return M
