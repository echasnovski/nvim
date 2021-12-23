--- This is a file to test 'mini-dev.doc'

local M = {}

---@title Second block
---
---@param a `string` Some string. List of items:
---   - Item 1.
---   - Item 2.
---@param b `number` Number.
---
---@return boolean
---
---@usage `M.fun(1, 2)`
function M.fun(a, b)
  return true
end

---@title Title for `fun2`
--- Can be multiline!
---@text
--- This illustrates some code:
--- >
---   require('mini.doc').setup()
--- <
---@param x number
---@param y number
---@text Some text after parameters.
M.fun2 = function(x, y)
  return x + y
end

return M
