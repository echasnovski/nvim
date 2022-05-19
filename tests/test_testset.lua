local new_set = MiniTest.new_testset

local T = new_set()

-- Hooks ----------------------------------------------------------------------
local erroring = function(x)
  return function()
    error(x, 0)
  end
end

T['hooks'] = new_set()

T['hooks']['order'] = new_set({
  hooks = {
    pre_once = erroring('pre_once_1'),
    pre_case = erroring('pre_case_1'),
    post_case = erroring('post_case_1'),
    post_once = erroring('post_once_1'),
  },
})

T['hooks']['order']['first level'] = erroring('First level test')

T['hooks']['order']['nested'] = new_set({
  hooks = {
    pre_once = erroring('pre_once_2'),
    pre_case = erroring('pre_case_2'),
    post_case = erroring('post_case_2'),
    post_once = erroring('post_once_2'),
  },
})

T['hooks']['order']['nested']['first'] = erroring('Nested #1')
T['hooks']['order']['nested']['second'] = erroring('Nested #2')

-- Ensure that this will be called even if represented by the same function.
-- Use this in several `_once` hooks and see that they all got executed.
local f = erroring('Same function')
T['hooks']['same `*_once` hooks'] = new_set({ hooks = { pre_once = f, post_once = f } })
T['hooks']['same `*_once` hooks']['nested'] = as_set({ erroring('Test') }, { hooks = { pre_once = f, post_once = f } })

-- Parametrize ----------------------------------------------------------------
local error2 = function(x, y)
  error(vim.inspect(x) .. ' ' .. vim.inspect(y))
end

T['parametrize'] = new_set({ parametrize = { { '1' }, { '2' } } })

T['parametrize']['first level'] = error2

T['parametrize']['nested'] = new_set({ parametrize = { { 1 }, { 2 } } })

T['parametrize']['nested']['test'] = error2

-- User data ------------------------------------------------------------------
local error_user = function()
  error(vim.inspect(MiniTest.current.testcase.user), 0)
end

T['user'] = new_set({ user = { a = 1, b = 2 } })

T['user']['first level'] = error_user

T['user']['nested'] = new_set({ user = { a = 10, c = 30 } })

T['user']['nested']['should override'] = error_user

return T
