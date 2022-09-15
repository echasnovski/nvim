local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('align', config) end
local unload_module = function() child.mini_unload('align') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

local set_config_steps = function(tbl)
  for key, value in pairs(tbl) do
    child.lua('MiniAlign.config.steps.' .. key .. ' = ' .. value)
  end
end

local validate_step = function(var_name)
  eq(child.lua_get(('type(%s)'):format(var_name)), 'table')

  local keys = child.lua_get(('vim.tbl_keys(%s)'):format(var_name))
  table.sort(keys)
  eq(keys, { 'action', 'name' })

  eq(child.lua_get(('type(%s.name)'):format(var_name)), 'string')
  eq(child.lua_get(('vim.is_callable(%s.action)'):format(var_name)), true)
end

local get_latest_message = function() return child.cmd_capture('1messages') end

local get_mode = function() return child.api.nvim_get_mode()['mode'] end

-- Output test set
T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniAlign)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniAlign.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniAlign.config.' .. field), value) end
  local expect_config_type =
    function(field, type_val) eq(child.lua_get('type(MiniAlign.config.' .. field .. ')'), type_val) end

  -- Check default values
  expect_config('mappings.start', 'ga')
  expect_config('mappings.start_with_preview', 'gA')
  expect_config_type('modifiers.s', 'function')
  expect_config_type('modifiers.j', 'function')
  expect_config_type('modifiers.m', 'function')
  expect_config_type('modifiers.f', 'function')
  expect_config_type('modifiers.t', 'function')
  expect_config_type('modifiers.p', 'function')
  expect_config_type(
    string.format('modifiers["%s"]', child.api.nvim_replace_termcodes('<BS>', true, true, true)),
    'function'
  )
  expect_config_type('modifiers["="]', 'function')
  expect_config_type('modifiers[","]', 'function')
  expect_config_type('modifiers[" "]', 'function')
  expect_config_type('modifiers["|"]', 'function')
  expect_config('steps.pre_split', {})
  expect_config('steps.split', vim.NIL)
  expect_config('steps.pre_justify', {})
  expect_config('steps.justify', 'left')
  expect_config('steps.pre_merge', {})
  expect_config('steps.merge', '')
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ steps = { justify = 'center' } })
  eq(child.lua_get('MiniAlign.config.steps.justify'), 'center')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { start = 1 } }, 'mappings.start', 'string')
  expect_config_error({ mappings = { start_with_preview = 1 } }, 'mappings.start_with_preview', 'string')
  expect_config_error({ modifiers = 'a' }, 'modifiers', 'table')
  expect_config_error({ modifiers = { x = 1 } }, 'modifiers["x"]', 'function')
  expect_config_error({ steps = { pre_split = 1 } }, 'steps.pre_split', 'array of steps')
  expect_config_error({ steps = { split = 1 } }, 'steps.split', 'string, array of strings, or step')
  expect_config_error({ steps = { pre_justify = 1 } }, 'steps.pre_justify', 'array of steps')
  expect_config_error({ steps = { justify = 1 } }, 'steps.justify', 'one of')
  expect_config_error({ steps = { pre_merge = 1 } }, 'steps.pre_merge', 'array of steps')
  expect_config_error({ steps = { merge = 1 } }, 'steps.merge', 'string, array of strings, or step')
end

T['setup()']['properly handles `config.mappings`'] = function()
  local has_map = function(lhs) return child.cmd_capture('xmap ' .. lhs):find('MiniAlign') ~= nil end
  eq(has_map('ga'), true)

  unload_module()
  child.api.nvim_del_keymap('x', 'ga')

  -- Supplying empty string should mean "don't create keymap"
  load_module({ mappings = { start = '' } })
  eq(has_map('ga'), false)
end

local validate_align_strings = function(input_strings, steps, ref_strings)
  local output = child.lua_get('MiniAlign.align_strings(...)', { input_strings, steps })
  eq(output, ref_strings)
end

T['align_strings()'] = new_set()

T['align_strings()']['works'] =
  function() validate_align_strings({ 'a=b', 'aa=b' }, { split = '=' }, { 'a =b', 'aa=b' }) end

T['align_strings()']['validates `strings` argument'] = function()
  expect.error(function() child.lua([[MiniAlign.align_strings({'a', 1})]]) end, 'string')
  expect.error(function() child.lua([[MiniAlign.align_strings('a')]]) end, 'array')
end

T['align_strings()']['respects `strings` argument'] =
  function() validate_align_strings({ 'aaa=b', 'aa=b' }, { split = '=' }, { 'aaa=b', 'aa =b' }) end

T['align_strings()']['validates `steps` argument'] = function()
  -- `config.split` is `nil` by default but it is needed for `align_strings()`
  set_config_steps({ split = [['=']] })

  local validate = function(steps_str, error_pattern)
    expect.error(function()
      local cmd = string.format([[MiniAlign.align_strings({'a=b', 'aa=b'}, %s)]], steps_str)
      child.lua(cmd)
    end, error_pattern)
  end

  validate([[{ pre_split = 1 }]], 'pre_split.*array of steps')
  validate([[{ pre_split = { function() end } }]], 'pre_split.*array of steps')

  child.lua([[MiniAlign.config.steps.split = nil]])
  validate([[{ split = nil }]], 'split.*string.*array of strings.*step')
  validate([[{ split = 1 }]], 'split.*string.*array of strings.*step')
  validate([[{ split = function() end }]], 'split.*string.*array of strings.*step')
  set_config_steps({ split = [['=']] })

  validate([[{ pre_justify = 1 }]], 'pre_justify.*array of steps')
  validate([[{ pre_justify = { function() end } }]], 'pre_justify.*array of steps')

  validate([[{ justify = 1 }]], 'justify.*one of.*array of.*step')
  validate([[{ justify = 'aaa' }]], 'justify.*one of.*array of.*step')
  validate([[{ justify = function() end }]], 'justify.*one of.*array of.*step')

  validate([[{ pre_merge = 1 }]], 'pre_merge.*array of steps')
  validate([[{ pre_merge = { function() end } }]], 'pre_merge.*array of steps')

  validate([[{ merge = 1 }]], 'merge.*string.*array of strings.*step')
  validate([[{ merge = function() end }]], 'merge.*string.*array of strings.*step')
end

T['align_strings()']['respects `steps.pre_split` argument'] = function()
  local step_str, cmd

  -- Array of steps
  step_str = [[MiniAlign.as_step('tmp', function(strings) strings[1] = 'a=b' end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, { pre_split = { %s }, split = '=' })]], step_str)
  eq(child.lua_get(cmd), { 'a =b', 'aa=b' })

  -- Should validate that step correctly modified in place
  step_str = [[MiniAlign.as_step('tmp', function(strings) strings[1] = 1 end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { pre_split = { %s }, split = '=' })]], step_str)
  expect.error(child.lua, 'Step `tmp` of `pre_split` should modify `strings` in place and preserve its structure.', cmd)

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({ pre_split = [[{ MiniAlign.as_step('tmp', function(strings) strings[1] = 'a=b' end) }]] })
  validate_align_strings({ 'aaa=b', 'aa=b' }, { split = '=' }, { 'a =b', 'aa=b' })
end

T['align_strings()']['respects `steps.split` argument'] = function()
  local step_str, cmd

  -- Single string
  validate_align_strings({ 'a,b', 'aa,b' }, { split = ',' }, { 'a ,b', 'aa,b' })

  -- Array of strings (should be recycled)
  validate_align_strings(
    { 'a,b=c,d=e,', 'aa,bb=cc,dd=ee,' },
    { split = { ',', '=' } },
    { 'a ,b =c ,d =e ,', 'aa,bb=cc,dd=ee,' }
  )

  -- Step. Action output should be parts or convertable to it.
  step_str = [[MiniAlign.as_step('tmp', function(strings) return { { 'a', 'b' }, {'aa', 'b'} } end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { split = %s })]], step_str)
  eq(child.lua_get(cmd), { 'a b', 'aab' })

  step_str =
    [[MiniAlign.as_step('tmp', function(strings) return MiniAlign.as_parts({ { 'a', 'b' }, {'aa', 'b'} }) end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { split = %s })]], step_str)
  eq(child.lua_get(cmd), { 'a b', 'aab' })

  -- Should validate that step's output is convertable to parts
  step_str = [[MiniAlign.as_step('tmp', function(strings) return { { 'a', 1 }, {'aa', 'b'} } end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { split = %s })]], step_str)
  expect.error(child.lua, 'convertable to parts', cmd)

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({ split = [[',']] })
  validate_align_strings({ 'a,b', 'aa,b' }, {}, { 'a ,b', 'aa,b' })
end

T['align_strings()']['respects `steps.pre_justify` argument'] = function()
  local step_str, cmd

  -- Array of steps
  step_str = [[MiniAlign.as_step('tmp', function(parts) parts[1][1] = 'xxx' end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, { pre_justify = { %s }, split = '=' })]], step_str)
  eq(child.lua_get(cmd), { 'xxx=b', 'aa =b' })

  -- Should validate that step correctly modified in place
  step_str = [[MiniAlign.as_step('tmp', function(parts) parts[1][1] = 1 end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { pre_justify = { %s }, split = '=' })]], step_str)
  expect.error(
    child.lua,
    vim.pesc(
      'Step `tmp` of `pre_justify` should modify `parts` in place '
        .. 'and preserve its structure. See `:h MiniAlign.as_parts()`.'
    ),
    cmd
  )

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({ pre_justify = [[{ MiniAlign.as_step('tmp', function(parts) parts[1][1] = 'xxx' end) }]] })
  validate_align_strings({ 'aaa=b', 'aa=b' }, { split = '=' }, { 'xxx=b', 'aa =b' })
end

T['align_strings()']['respects `steps.justify` argument'] = function()
  local step_str, cmd

  -- Single string
  --stylua: ignore start
  validate_align_strings({ 'a=b', 'aaa=b' }, { split = '=', justify = 'left' },   { 'a  =b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { split = '=', justify = 'center' }, { ' a =b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { split = '=', justify = 'right' },  { '  a=b', 'aaa=b' })
  --stylua: ignore end

  -- Array of strings (should be recycled)
  validate_align_strings(
    { 'a=b=c=d=e', 'aaa  =bbb  =ccc  =ddd  =eee' },
    { split = '%s*=', justify = { 'left', 'center', 'right' } },
    -- Part resulted from separator is treated the same as any other part
    { 'a   =   b=   c   =d   =   e', 'aaa  =bbb  =ccc  =ddd  =eee' }
  )

  -- The `vim.tbl_deep_extend()` in Neovim<0.6 failes here because `justify` is
  -- table while by default it is string.
  -- TODO: Remove this after dropping support for Neovim<=0.5
  if child.fn.has('nvim-0.6.0') == 0 then return end

  -- Step. Action should modify parts in place.
  step_str = [[MiniAlign.as_step('tmp', function(parts) parts[1][1] = 'xxx' end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { justify = %s, split = '=' })]], step_str)
  eq(child.lua_get(cmd), { 'xxx=b', 'aa=b' })

  -- Should validate that step correctly modified in place
  step_str = [[MiniAlign.as_step('tmp', function(parts) parts[1][1] = 1 end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { justify = %s, split = '=' })]], step_str)
  expect.error(
    child.lua,
    vim.pesc(
      'Step `tmp` of `justify` should modify `parts` in place '
        .. 'and preserve its structure. See `:h MiniAlign.as_parts()`.'
    ),
    cmd
  )

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({ justify = [['center']] })
  validate_align_strings({ 'a=b', 'aaa=b' }, { split = '=' }, { ' a =b', 'aaa=b' })
end

T['align_strings()']['respects `steps.pre_merge` argument'] = function()
  local step_str, cmd

  -- Array of steps
  step_str = [[MiniAlign.as_step('tmp', function(parts) parts[1][1] = 'xxx' end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, { pre_merge = { %s }, split = '=' })]], step_str)
  eq(child.lua_get(cmd), { 'xxx=b', 'aa =b' })

  -- Should validate that step correctly modified in place
  step_str = [[MiniAlign.as_step('tmp', function(parts) parts[1][1] = 1 end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { pre_merge = { %s }, split = '=' })]], step_str)
  expect.error(
    child.lua,
    vim.pesc(
      'Step `tmp` of `pre_merge` should modify `parts` in place '
        .. 'and preserve its structure. See `:h MiniAlign.as_parts()`.'
    ),
    cmd
  )

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({ pre_merge = [[{ MiniAlign.as_step('tmp', function(parts) parts[1][1] = 'xxx' end) }]] })
  validate_align_strings({ 'aaa=b', 'aa=b' }, { split = '=' }, { 'xxx=b', 'aa =b' })
end

T['align_strings()']['respects `steps.merge` argument'] = function()
  local step_str, cmd

  -- Single string
  --stylua: ignore start
  validate_align_strings({ 'a=b' }, { split = '=', merge = '-' },   { 'a-=-b' })
  --stylua: ignore end

  -- Array of strings (should be recycled)
  validate_align_strings(
    { 'a=b=c=' },
    { split = '=', merge = { '-', '!' } },
    -- Part resulted from separator is treated the same as any other part
    { 'a-=!b-=!c-=' }
  )

  -- The `vim.tbl_deep_extend()` in Neovim<0.6 failes here because `justify` is
  -- table while by default it is string.
  -- TODO: Remove this after dropping support for Neovim<=0.5
  if child.fn.has('nvim-0.6.0') == 0 then return end

  -- Step. Action should return array of strings.
  step_str = [[MiniAlign.as_step('tmp', function(parts) return { 'xxx' } end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { merge = %s, split = '=' })]], step_str)
  eq(child.lua_get(cmd), { 'xxx' })

  -- Should validate that output is an array of strings
  step_str = [[MiniAlign.as_step('tmp', function(parts) return { 'a', 1 } end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { merge = %s, split = '=' })]], step_str)
  expect.error(child.lua, vim.pesc('Output of `merge` step should be array of strings.'), cmd)

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({ merge = [['-']] })
  validate_align_strings({ 'a=b' }, { split = '=' }, { 'a-=-b' })
end

T['align_strings()']['respects `vim.b.minialign_config`'] = function()
  child.b.minialign_config = { steps = { split = '=' } }
  validate_align_strings({ 'a=b', 'aa=b' }, {}, { 'a =b', 'aa=b' })

  -- Shoudl take precedence over global cofnfig
  set_config_steps({ split = [[',']] })
  validate_align_strings({ 'a=b', 'aa=b' }, {}, { 'a =b', 'aa=b' })
end

local is_parts = function(var_name)
  local cmd = string.format('getmetatable(%s).class', var_name)
  eq(child.lua_get(cmd), 'parts')
end

T['as_parts()'] = new_set()

T['as_parts()']['works'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a', 'b' }, { 'c' } })]])
  eq(child.lua_get('type(parts.get_dims)'), 'function')
end

T['as_parts()']['validates arguments'] = function()
  local validate = function(input_str, err_pattern)
    expect.error(function() child.lua('MiniAlign.as_parts(' .. input_str .. ')') end, err_pattern)
  end

  validate('', 'Input of `as_parts%(%)` should be table')
  validate('1', 'table')
  validate([[{ 'a' }]], 'Input of `as_parts%(%)` values should be an array of strings')
  validate([[{ { 1 } }]], 'array of strings')
  validate([[{ { 'a' }, 'a' }]], 'array of strings')
end

T['as_parts()']['works with empty table'] = function()
  -- Empty parts
  child.lua('empty = MiniAlign.as_parts({})')
  is_parts('empty')

  -- All methods should work
  local validate_method = function(method_call, output, ...)
    child.lua('empty = MiniAlign.as_parts({})')
    local cmd = string.format('empty.%s', method_call)
    if output ~= nil then
      eq(child.lua_get(cmd, { ... }), output)
    else
      child.lua(cmd, { ... })
      eq(child.lua_get('empty'), {})
    end
  end

  validate_method([[apply_inplace(function(s) return 'a' end)]])
  validate_method('group()')
  validate_method('pair()')
  validate_method('trim()')

  validate_method('apply(function(s) return 1 end)', {})
  validate_method('get_dims()', { row = 0, col = 0 })
  validate_method('slice_col(1)', {})
  validate_method('slice_row(1)', {})
end

T['as_parts()']['`apply()` method'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a', 'b' }, { 'c' } })]])
  eq(
    child.lua_get('parts.apply(function(x, data) return x .. data.row .. data.col end)'),
    { { 'a11', 'b12' }, { 'c21' } }
  )
end

T['as_parts()']['`apply_inplace()` method'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a', 'b' }, { 'c' } })]])
  child.lua('parts.apply_inplace(function(x, data) return x .. data.row .. data.col end)')
  eq(child.lua_get('parts'), { { 'a11', 'b12' }, { 'c21' } })
end

T['as_parts()']['`get_dims()` method'] = function()
  local validate = function(arr2d_str, dims)
    local cmd = string.format('MiniAlign.as_parts(%s).get_dims()', arr2d_str)
    eq(child.lua_get(cmd), dims)
  end

  validate([[{ { 'a' } }]], { row = 1, col = 1 })
  validate([[{ { 'a', 'b' } }]], { row = 1, col = 2 })
  validate([[{ { 'a', 'b' }, { 'c' } }]], { row = 2, col = 2 })
  validate([[{ { 'a', 'b' }, { 'c', 'd', 'e' } }]], { row = 2, col = 3 })
  validate([[{}]], { row = 0, col = 0 })
end

local validate_parts_group = function(arr2d_str, mask_str, output, direction)
  child.lua(('parts = MiniAlign.as_parts(%s)'):format(arr2d_str))
  direction = direction == nil and '' or (', ' .. vim.inspect(direction))
  child.lua(('parts.group(%s%s)'):format(mask_str, direction))
  eq(child.lua_get('parts'), output)
end

T['as_parts()']['`group()` method'] = new_set()

T['as_parts()']['`group()` method']['works'] = function()
  validate_parts_group(
    [[{ { 'a', 'b', 'c' }, { 'd' } }]],
    '{ { false, false, true }, { true } }',
    { { 'abc' }, { 'd' } }
  )
end

T['as_parts()']['`group()` method']['respects `mask` argument'] = function()
  local arr2d_str

  arr2d_str = [[{ { 'a', 'b' } }]]
  validate_parts_group(arr2d_str, '{ { false, false } }', { { 'ab' } })
  validate_parts_group(arr2d_str, '{ { false, true } }', { { 'ab' } })
  validate_parts_group(arr2d_str, '{ { true, false } }', { { 'a', 'b' } })
  validate_parts_group(arr2d_str, '{ { true, true } }', { { 'a', 'b' } })

  arr2d_str = [[{ { 'a', 'b' }, { 'c', 'd', 'e' } }]]
  validate_parts_group(arr2d_str, '{ { false, true }, { true, false, true } }', { { 'ab' }, { 'c', 'de' } })

  -- Default direction is 'left'
  arr2d_str = [[{ { 'a', 'b', 'c', 'd' } }]]
  validate_parts_group(arr2d_str, '{ { false, true, false, false } }', { { 'ab', 'cd' } })
end

T['as_parts()']['`group()` method']['respects `direction` argument'] = function()
  local validate = function(...)
    local dots = { ... }
    table.insert(dots, 'right')
    validate_parts_group(unpack(dots))
  end

  local arr2d_str

  arr2d_str = [[{ { 'a', 'b' } }]]
  validate(arr2d_str, '{ { false, false } }', { { 'ab' } })
  validate(arr2d_str, '{ { false, true } }', { { 'a', 'b' } })
  validate(arr2d_str, '{ { true, false } }', { { 'ab' } })
  validate(arr2d_str, '{ { true, true } }', { { 'a', 'b' } })

  arr2d_str = [[{ { 'a', 'b' }, { 'c', 'd', 'e' } }]]
  validate(arr2d_str, '{ { false, true }, { true, false, true } }', { { 'a', 'b' }, { 'cd', 'e' } })

  -- Should differ from default 'left' direction
  arr2d_str = [[{ { 'a', 'b', 'c', 'd' } }]]
  validate(arr2d_str, '{ { false, true, false, false } }', { { 'a', 'bcd' } })
end

T['as_parts()']['`pair()` method'] = new_set()

T['as_parts()']['`pair()` method']['works'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a' }, { 'b', 'c' }, { 'd', 'e', 'f' } })]])
  child.lua('parts.pair()')
  eq(child.lua_get('parts'), { { 'a' }, { 'bc' }, { 'de', 'f' } })
end

T['as_parts()']['`pair()` method']['respects `direction` argument'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a' }, { 'b', 'c' }, { 'd', 'e', 'f' } })]])
  child.lua([[parts.pair('right')]])
  eq(child.lua_get('parts'), { { 'a' }, { 'bc' }, { 'd', 'ef' } })
end

T['as_parts()']['`slice_col()` method'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a' }, { 'b', 'c' }, { 'd' } })]])

  eq(child.lua_get('parts.slice_col(0)'), {})
  eq(child.lua_get('parts.slice_col(1)'), { 'a', 'b', 'd' })
  -- `slice_col()` may not return array (table with only 1, ..., n keys)
  eq(child.lua_get([[vim.deep_equal(parts.slice_col(2), { [2] = 'c' })]]), true)
  eq(child.lua_get('parts.slice_col(3)'), {})
end

T['as_parts()']['`slice_row()` method'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a' }, { 'b', 'c' } })]])

  eq(child.lua_get('parts.slice_row(0)'), {})
  eq(child.lua_get('parts.slice_row(1)'), { 'a' })
  eq(child.lua_get('parts.slice_row(2)'), { 'b', 'c' })
  eq(child.lua_get('parts.slice_col(3)'), {})
end

T['as_parts()']['`trim()` method'] = new_set()

T['as_parts()']['`trim()` method']['works'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { ' a ', ' b ', ' c', 'd ', 'e' }, { '  f ' } })]])
  child.lua('parts.trim()')
  -- By default trims from both directions and keeps indentation (left
  -- whitespace of every first row string)
  eq(child.lua_get('parts'), { { ' a', 'b', 'c', 'd', 'e' }, { '  f' } })
end

T['as_parts()']['`trim()` method']['validates arguments'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { ' a ' } })]])

  -- `direction`
  expect.error(function() child.lua([[parts.trim(1)]]) end, '`direction` should be one of "both", "left", "right"')
  expect.error(function() child.lua([[parts.trim('a')]]) end, '`direction` should be one of "both", "left", "right"')

  -- `indent`
  expect.error(
    function() child.lua([[parts.trim('both', 1)]]) end,
    '`indent` should be one of "keep", "max", "min", "none"'
  )
  expect.error(
    function() child.lua([[parts.trim('both', 'a')]]) end,
    '`indent` should be one of "keep", "max", "min", "none"'
  )
end

T['as_parts()']['`trim()` method']['respects `direction` argument'] = function()
  local validate = function(direction, output)
    child.lua([[parts = MiniAlign.as_parts({ { ' a ', ' b ', ' c', 'd ', 'e' }, { '  f ' } })]])
    child.lua(([[parts.trim('%s')]]):format(direction))
    eq(child.lua_get('parts'), output)
  end

  --stylua: ignore start
  validate('both',  { { ' a',  'b',  'c',  'd',  'e' }, { '  f' } })
  validate('left',  { { ' a ', 'b ', 'c',  'd ', 'e' }, { '  f ' } })
  validate('right', { { ' a',  ' b', ' c', 'd',  'e' }, { '  f' } })
  --stylua: ignore end
end

T['as_parts()']['`trim()` method']['respects `indent` argument'] = function()
  local validate = function(indent, output)
    child.lua([[parts = MiniAlign.as_parts({ { ' a ', ' b ' }, { '  c ', ' d ' } })]])
    child.lua(([[parts.trim('both', '%s')]]):format(indent))
    eq(child.lua_get('parts'), output)
  end

  --stylua: ignore start
  validate('keep', { { ' a',  'b' }, { '  c', 'd' } })
  validate('min',  { { ' a',  'b' }, { ' c',  'd' } })
  validate('max',  { { '  a', 'b' }, { '  c', 'd' } })
  validate('none', { { 'a',   'b' }, { 'c',   'd' } })
  --stylua: ignore end
end

T['as_step()'] = new_set()

T['as_step()']['works'] = function()
  child.lua([[step = MiniAlign.as_step('aaa', function() end)]])
  validate_step('step')

  -- Allows callable table as action
  child.lua([[action = setmetatable({}, { __call = function() end })]])
  child.lua([[step = MiniAlign.as_step('aaa', action)]])
  validate_step('step')
end

T['as_step()']['validates arguments'] = function()
  local validate = function(args_str, err_pattern)
    expect.error(function() child.lua('MiniAlign.as_step(' .. args_str .. ')') end, err_pattern)
  end

  validate([[1]], 'Step name should be string')
  validate([['aaa', 1]], 'Step action should be callable')
end

T['gen_step'] = new_set()

T['gen_step']['default_split()'] = new_set()

T['gen_step']['default_split()']['works'] = function() MiniTest.skip() end

T['gen_step']['default_split()']['works with no split pattern found'] = function()
  set_config_steps({ split = [[MiniAlign.gen_step.default_split(',')]], merge = [['-']] })

  -- In some lines
  validate_align_strings({ 'a,b', 'a=b' }, { justify = 'center' }, { ' a -,-b', 'a=b' })

  -- In all lines
  validate_align_strings({ 'a=b', 'a=bb' }, {}, { 'a=b', 'a=bb' })
end

T['gen_step']['default_split()']['works with special split patterns'] = function()
  set_config_steps({ merge = [['-']] })

  -- Treat `''` as no split pattern is found
  set_config_steps({ split = [[MiniAlign.gen_step.default_split('')]] })
  validate_align_strings({ 'a=b', 'a=bbb' }, {}, { 'a=b', 'a=bbb' })

  -- Treat `'.'` as any character is a split
  set_config_steps({ split = [[MiniAlign.gen_step.default_split('.')]] })
  validate_align_strings({ 'a=b', 'a=bbb' }, {}, { 'a-=-b', 'a-=-b-b-b' })
end

T['gen_step']['default_justify()'] = new_set()

T['gen_step']['default_justify()']['works'] = function() MiniTest.skip() end

T['gen_step']['default_justify()']['does not add trailing whitespace'] = function()
  set_config_steps({ split = [['=']] })

  set_config_steps({ justify = [[MiniAlign.gen_step.default_justify('left')]] })
  validate_align_strings({ 'a=b', '', 'a=bbb' }, {}, { 'a=b', '', 'a=bbb' })

  set_config_steps({ justify = [[MiniAlign.gen_step.default_justify('center')]] })
  validate_align_strings({ 'a=b', '', 'a=bbb' }, {}, { 'a= b', '', 'a=bbb' })

  set_config_steps({ justify = [[MiniAlign.gen_step.default_justify('right')]] })
  validate_align_strings({ 'a=b', '', 'a=bbb' }, {}, { 'a=  b', '', 'a=bbb' })
end

T['gen_step']['default_justify()']['last row column does not affect column width for left justification'] = function()
  set_config_steps({ split = [['=']], justify = [['left']] })

  -- It won't be padded so shouldn't contribute to column width
  validate_align_strings({ 'a=b', 'aa=b', 'aaaaa' }, {}, { 'a =b', 'aa=b', 'aaaaa' })
  validate_align_strings({ 'a=b=c', 'a=bb=c', 'a=bbbbb' }, {}, { 'a=b =c', 'a=bb=c', 'a=bbbbb' })
end

T['gen_step']['default_merge()'] = new_set()

T['gen_step']['default_merge()']['works'] = function() MiniTest.skip() end

T['gen_step']['default_merge()']['does not merge empty strings in parts'] = function()
  set_config_steps({ split = [['=']] })

  -- Shouldn't result into adding extra merge
  set_config_steps({ merge = [[MiniAlign.gen_step.default_merge('-')]] })
  validate_align_strings({ 'a===b' }, {}, { 'a-=-=-=-b' })
end

-- Integration tests ==========================================================
T['Align'] = new_set()

T['Align']['respects `vim.{g,b}.minialign_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type) MiniTest.skip() end,
})

T['Align with preview'] = new_set()

T['Align with preview']['respects `vim.{g,b}.minialign_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type) MiniTest.skip() end,
})

T['Modifiers'] = new_set()

return T
