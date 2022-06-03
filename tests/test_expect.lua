local new_set, expect = MiniTest.new_set, MiniTest.expect
local eq, not_eq = expect.equality, expect.no_equality

local T = new_set()

-- equal() --------------------------------------------------------------------
T['`equal()`'] = new_set()

local f = function() end
local tmp_tbl = {}
T['`equal()`']['not errors when equal'] = new_set({
  parametrize = {
    { 1, 1 },
    { f, f },
    -- Tables are compared "deeply per elements"
    { tmp_tbl, tmp_tbl },
    { tmp_tbl, {} },
    { { 1 }, { 1 } },
    { { a = 1 }, { a = 1 } },
  },
}, { eq })

T['`equal()`']['errors when not equal'] = new_set({
  parametrize = {
    { 1, 2 },
    { f, function() end },
    { { 1 }, { 2 } },
    { { a = 1 }, { b = 1 } },
    { { a = 1 }, { a = 2 } },
  },
}, {
  function(x, y)
    expect.error(eq, 'equality.*Left:.*Right:', x, y)
  end,
})

-- not_equal() ----------------------------------------------------------------
T['`not_equal()`'] = new_set()
T['`not_equal()`']['works'] = function()
  expect.no_error(not_eq, 1, 2)
  expect.error(not_eq, '%*no%* equality.*Object:', 1, 1)
end

-- Errors ---------------------------------------------------------------------
T['Errors'] = new_set()

--stylua: ignore
T['Errors']['work'] = function()
  expect.no_error(function()
    expect.error(function() error() end)
  end)
  expect.error(function()
    expect.no_error(function() error() end)
  end)
end

T['Errors']['allow extra arguments'] = function() end

local has_match = function(str, pattern)
  if str:find(pattern) == nil then
    error(([[String '%s' does not match pattern '%s']]):format(str, pattern), 0)
  end
end

T['Errors']['`error()` fails with appropriate message'] = function()
  local err

  -- No error, no `match`
  _, err = pcall(function()
    expect.error(function() end)
  end)
  has_match(err, 'error.*Observed no error')

  -- No error, with `match`
  _, err = pcall(function()
    expect.error(function() end, 'aaa')
  end)
  has_match(err, 'error with match "aaa".*Observed no error')

  -- Error, with `match`
  _, err = pcall(function()
    expect.error(function()
      error('aaa')
    end, 'bbb')
  end)
  has_match(err, 'error with match "bbb".*Observed error:.*aaa')
end

T['Errors']['`error()` validates `match`'] = function()
  local _, err = pcall(function()
    expect.error(function() end, 1)
  end)
  has_match(err, 'match.*string')
end

return T
