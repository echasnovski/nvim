local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('align', config) end
local unload_module = function() child.mini_unload('align') end
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

local validate_step = function(var_name, step_name)
  eq(child.lua_get(('type(%s)'):format(var_name)), 'table')

  local keys = child.lua_get(('vim.tbl_keys(%s)'):format(var_name))
  table.sort(keys)
  eq(keys, { 'action', 'name' })

  eq(child.lua_get(('type(%s.name)'):format(var_name)), 'string')
  if step_name ~= nil then eq(child.lua_get(('%s.name'):format(var_name)), step_name) end

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
  expect_config('options', {})
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
  expect_config_error({ options = 'a' }, 'options', 'table')
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

local validate_align_strings = function(input_strings, steps, ref_strings, opts)
  local output = child.lua_get('MiniAlign.align_strings(...)', { input_strings, steps, opts })
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

  -- Is called with `opts`
  step_str = [[MiniAlign.as_step('tmp', function(strings, opts) strings[1] = opts.tmp end)]]
  cmd = string.format(
    [[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, { pre_split = { %s }, split = '=' }, { tmp = 'xxx' })]],
    step_str
  )
  eq(child.lua_get(cmd), { 'xxx', 'aa=b' })
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

  -- Is called with `opts`
  step_str = [[MiniAlign.as_step('tmp', function(strings, opts) return MiniAlign.as_parts(opts.tmp) end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { split = %s }, { tmp = { { 'xxx' } } })]], step_str)
  eq(child.lua_get(cmd), { 'xxx' })
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

  -- Is called with `opts`
  step_str = [[MiniAlign.as_step('tmp', function(parts, opts) parts[1][1] = opts.tmp end)]]
  cmd = string.format(
    [[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, { pre_justify = { %s }, split = '=' }, { tmp = 'xxx' })]],
    step_str
  )
  eq(child.lua_get(cmd), { 'xxx=b', 'aa =b' })
end

T['align_strings()']['respects `steps.justify` argument'] = function()
  local step_str, cmd

  -- Single string
  --stylua: ignore start
  validate_align_strings({ 'a=b', 'aaa=b' }, { split = '=', justify = 'left' },   { 'a  =b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { split = '=', justify = 'center' }, { ' a =b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { split = '=', justify = 'right' },  { '  a=b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { split = '=', justify = 'none' },   { 'a=b',   'aaa=b' })
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
  if child.fn.has('nvim-0.6.0') == 0 then MiniTest.skip('Neovim is <=0.5') end

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

  -- Is called with `opts`
  step_str = [[MiniAlign.as_step('tmp', function(parts, opts) parts[1][1] = opts.tmp end)]]
  cmd = string.format(
    [[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { justify = %s, split = '=' }, { tmp = 'xxx' })]],
    step_str
  )
  eq(child.lua_get(cmd), { 'xxx=b', 'aa=b' })
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

  -- Is called with `opts`
  step_str = [[MiniAlign.as_step('tmp', function(parts, opts) parts[1][1] = opts.tmp end)]]
  cmd = string.format(
    [[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, { pre_merge = { %s }, split = '=' }, { tmp = 'xxx' })]],
    step_str
  )
  eq(child.lua_get(cmd), { 'xxx=b', 'aa =b' })
end

T['align_strings()']['respects `steps.merge` argument'] = function()
  local step_str, cmd

  -- Single string
  validate_align_strings({ 'a=b' }, { split = '=', merge = '-' }, { 'a-=-b' })

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
  if child.fn.has('nvim-0.6.0') == 0 then MiniTest.skip('Neovim is <=0.5') end

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

  -- Is called with `opts`
  step_str = [[MiniAlign.as_step('tmp', function(parts, opts) return { opts.tmp } end)]]
  cmd = string.format(
    [[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { merge = %s, split = '=' }, { tmp = 'xxx' })]],
    step_str
  )
  eq(child.lua_get(cmd), { 'xxx' })
end

T['align_strings()']['respects `opts` argument'] = function()
  -- Its usage is explicitly tested inside every test step

  -- Should take default values from `MiniAlign.config.options`
  child.lua([[MiniAlign.config.options.test = 'xxx']])
  child.lua([[ MiniAlign.config.steps.pre_split = {
    MiniAlign.as_step('test', function(strings, opts) strings[1] = opts.test end)
  }]])
  eq(child.lua_get([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { split = '=' }, {})]]), { 'xxx', 'aa=b' })
end

T['align_strings()']['works with multibyte characters'] = function()
  validate_align_strings(
    { 'ыффццц', 'ыыыффц' },
    { split = 'ф', justify = 'center', merge = 'ю' },
    { ' ы юфюфюццц', 'ыыыюфюфю ц' }
  )
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
  local err_pattern

  -- `direction`
  err_pattern = '`direction` should be one of "both", "left", "none", "right"'
  expect.error(function() child.lua([[parts.trim(1)]]) end, err_pattern)
  expect.error(function() child.lua([[parts.trim('a')]]) end, err_pattern)

  -- `indent`
  err_pattern = '`indent` should be one of "keep", "max", "min", "remove"'
  expect.error(function() child.lua([[parts.trim('both', 1)]]) end, err_pattern)
  expect.error(function() child.lua([[parts.trim('both', 'a')]]) end, err_pattern)
end

T['as_parts()']['`trim()` method']['respects `direction` argument'] = function()
  local validate = function(direction, output)
    child.lua([[parts = MiniAlign.as_parts({ { ' a ', ' b ', ' c', 'd ', 'e' }, { '  f ' } })]])
    child.lua(([[parts.trim('%s')]]):format(direction))
    eq(child.lua_get('parts'), output)
  end

  --stylua: ignore start
  validate('both',  { { ' a',  'b',   'c',  'd',  'e' }, { '  f' } })
  validate('left',  { { ' a ', 'b ',  'c',  'd ', 'e' }, { '  f ' } })
  validate('right', { { ' a',  ' b',  ' c', 'd',  'e' }, { '  f' } })
  validate('none',  { { ' a ', ' b ', ' c', 'd ', 'e' }, { '  f ' } })
  --stylua: ignore end
end

T['as_parts()']['`trim()` method']['respects `indent` argument'] = function()
  local validate = function(indent, output)
    child.lua([[parts = MiniAlign.as_parts({ { ' a ', ' b ' }, { '  c ', ' d ' } })]])
    child.lua(([[parts.trim('both', '%s')]]):format(indent))
    eq(child.lua_get('parts'), output)
  end

  --stylua: ignore start
  validate('keep',   { { ' a',  'b' }, { '  c', 'd' } })
  validate('min',    { { ' a',  'b' }, { ' c',  'd' } })
  validate('max',    { { '  a', 'b' }, { '  c', 'd' } })
  validate('remove', { { 'a',   'b' }, { 'c',   'd' } })
  --stylua: ignore end
end

T['as_step()'] = new_set()

T['as_step()']['works'] = function()
  child.lua([[step = MiniAlign.as_step('aaa', function() end)]])
  validate_step('step', 'aaa')

  -- Allows callable table as action
  child.lua([[action = setmetatable({}, { __call = function() end })]])
  child.lua([[step = MiniAlign.as_step('aaa', action)]])
  validate_step('step', 'aaa')
end

T['as_step()']['validates arguments'] = function()
  local validate = function(args_str, err_pattern)
    expect.error(function() child.lua('MiniAlign.as_step(' .. args_str .. ')') end, err_pattern)
  end

  validate([[1]], 'Step name should be string')
  validate([['aaa', 1]], 'Step action should be callable')
end

T['gen_step'] = new_set()

local set_default_split = function(pattern)
  set_config_steps({ split = ([[MiniAlign.gen_step.default_split(%s)]]):format(vim.inspect(pattern)) })
end

T['gen_step']['default_split()'] = new_set()

T['gen_step']['default_split()']['works'] = function()
  -- Returns proper step
  child.lua([[step = MiniAlign.gen_step.default_split(',')]])
  validate_step('step', [[","]])

  -- Single string
  set_default_split(',')
  validate_align_strings({ 'a,b', 'aa,b' }, {}, { 'a ,b', 'aa,b' })

  -- Array of strings (should be recycled)
  set_default_split({ ',' })
  validate_align_strings({ 'a,b', 'aa,b' }, {}, { 'a ,b', 'aa,b' })

  set_default_split({ ',', '=' })
  validate_align_strings({ 'a,b=c,d=e,', 'aa,bb=cc,dd=ee,' }, {}, { 'a ,b =c ,d =e ,', 'aa,bb=cc,dd=ee,' })
end

T['gen_step']['default_split()']['validates input'] = function()
  expect.error(
    function() child.lua('MiniAlign.gen_step.default_split(1)') end,
    'Split `pattern` should be string or array of strings'
  )
end

T['gen_step']['default_split()']['sets proper step name'] = function()
  local validate = function(pattern, ref_name)
    local cmd = ('MiniAlign.gen_step.default_split(%s).name'):format(pattern)
    eq(child.lua_get(cmd), ref_name)
  end

  validate([[',']], vim.inspect(','))
  validate([[{ ',' }]], vim.inspect({ ',' }))
  validate([[{ ',', '=' }]], vim.inspect({ ',', '=' }))
end

T['gen_step']['default_split()']['allows Lua pattern'] = function()
  set_config_steps({ split = [[MiniAlign.gen_step.default_split('%s*=%s*')]], merge = [['-']] })
  validate_align_strings({ 'a=b  =c=  d  =  e' }, {}, { 'a-=-b-  =-c-=  -d-  =  -e' })
end

T['gen_step']['default_split()']['works with different number of output parts'] = function()
  set_config_steps({ split = [[MiniAlign.gen_step.default_split(',')]], merge = [['-']] })
  validate_align_strings({ 'a', 'b,', 'c,d' }, {}, { 'a', 'b-,', 'c-,-d' })
end

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
  set_default_split('')
  validate_align_strings({ 'a=b', 'a=bbb' }, {}, { 'a=b', 'a=bbb' })

  -- Treat `'.'` as any character is a split
  set_default_split('.')
  validate_align_strings({ 'a=b', 'a=bbb' }, {}, { 'a-=-b', 'a-=-b-b-b' })

  -- Works with `^`
  set_default_split('^.')
  validate_align_strings({ 'a=b', 'a=bbb' }, {}, { 'a-=b', 'a-=bbb' })

  -- Works with `$`
  set_default_split('.$')
  validate_align_strings({ 'a=b', 'a=bbb' }, {}, { 'a=  -b', 'a=bb-b' })
end

local set_default_justify = function(side)
  set_config_steps({ justify = ([[MiniAlign.gen_step.default_justify(%s)]]):format(vim.inspect(side)) })
end

T['gen_step']['default_justify()'] = new_set()

T['gen_step']['default_justify()']['works'] = function()
  -- Single string
  set_config_steps({ split = [['=']] })

  --stylua: ignore start
  set_default_justify('left')
  validate_align_strings({ 'a=b', 'aaa=b' }, {}, { 'a  =b', 'aaa=b' })

  set_default_justify('center')
  validate_align_strings({ 'a=b', 'aaa=b' }, {}, { ' a =b', 'aaa=b' })

  set_default_justify('right')
  validate_align_strings({ 'a=b', 'aaa=b' }, {}, { '  a=b', 'aaa=b' })

  set_default_justify('none')
  validate_align_strings({ 'a=b', 'aaa=b' }, {}, { 'a=b', 'aaa=b' })
  --stylua: ignore end

  -- Array of strings (should be recycled)
  set_config_steps({ split = [['%s*=']] })
  set_default_justify({ 'left', 'center', 'right' })
  validate_align_strings(
    { 'a=b=c=d=e', 'aaa  =bbb  =ccc  =ddd  =eee' },
    {},
    -- Part resulted from separator is treated the same as any other part
    { 'a   =   b=   c   =d   =   e', 'aaa  =bbb  =ccc  =ddd  =eee' }
  )
end

T['gen_step']['default_justify()']['validates input'] = function()
  expect.error(
    function() child.lua('MiniAlign.gen_step.default_justify(1)') end,
    [[Justify `side` should one of 'left', 'center', 'right', 'none', or array of those]]
  )
end

T['gen_step']['default_justify()']['sets proper step name'] = function()
  local validate = function(pattern, ref_name)
    local cmd = ('MiniAlign.gen_step.default_justify(%s).name'):format(pattern)
    eq(child.lua_get(cmd), ref_name)
  end

  validate([['left']], vim.inspect('left'))
  validate([[{ 'center' }]], vim.inspect({ 'center' }))
  validate([[{ 'right', 'left' }]], vim.inspect({ 'right', 'left' }))
end

T['gen_step']['default_justify()']['works with multibyte characters'] = function()
  set_config_steps({ split = [['=']] })

  set_default_justify('left')
  validate_align_strings({ 'ы=ю', 'ыыы=ююю' }, {}, { 'ы  =ю', 'ыыы=ююю' })

  set_default_justify('center')
  validate_align_strings({ 'ы=ю', 'ыыы=ююю' }, {}, { ' ы = ю', 'ыыы=ююю' })

  set_default_justify('right')
  validate_align_strings({ 'ы=ю', 'ыыы=ююю' }, {}, { '  ы=  ю', 'ыыы=ююю' })

  set_default_justify('none')
  validate_align_strings({ 'ы=ю', 'ыыы=ююю' }, {}, { 'ы=ю', 'ыыы=ююю' })
end

T['gen_step']['default_justify()']['does not add trailing whitespace'] = function()
  set_config_steps({ split = [['=']] })

  set_default_justify('left')
  validate_align_strings({ 'a=b', '', 'a=bbb' }, {}, { 'a=b', '', 'a=bbb' })

  set_default_justify('center')
  validate_align_strings({ 'a=b', '', 'a=bbb' }, {}, { 'a= b', '', 'a=bbb' })

  set_default_justify('right')
  validate_align_strings({ 'a=b', '', 'a=bbb' }, {}, { 'a=  b', '', 'a=bbb' })

  set_default_justify('none')
  validate_align_strings({ 'a=b', '', 'a=bbb' }, {}, { 'a=b', '', 'a=bbb' })
end

T['gen_step']['default_justify()']['last row element width is ignored for left `justify`'] = function()
  set_config_steps({ split = [['=']], justify = [[MiniAlign.gen_step.default_justify('left')]] })

  -- It won't be padded so shouldn't contribute to column width
  validate_align_strings({ 'a=b', 'aa=b', 'aaaaa' }, {}, { 'a =b', 'aa=b', 'aaaaa' })
  validate_align_strings({ 'a=b=c', 'a=bb=c', 'a=bbbbb' }, {}, { 'a=b =c', 'a=bb=c', 'a=bbbbb' })
end

T['gen_step']['default_justify()']['prefers padding left for center `justify`'] = function()
  set_config_steps({ split = [['=']], justify = [[MiniAlign.gen_step.default_justify('center')]] })

  validate_align_strings({ 'a=b', 'aaaa=b' }, {}, { '  a =b', 'aaaa=b' })
end

T['gen_step']['default_justify()']['output step uses `opts.offsets`'] = function()
  set_config_steps({ split = [['=']], justify = [[MiniAlign.gen_step.default_justify('left')]] })

  -- Using `opts.offsets` allows to respect string prefixes but without
  -- processing them. So in this case output should be the same as with
  -- `{ '   a=b', '  a=b', 'a=b' }` and equal offsets (but without indents).
  validate_align_strings({ 'a=b', 'a=b', 'a=b' }, {}, { 'a=b', 'a =b', 'a   =b' }, { offsets = { 3, 2, 0 } })
end

T['gen_step']['default_merge()'] = new_set()

T['gen_step']['default_merge()']['works'] = function()
  set_config_steps({ split = [['=']] })

  -- Single string
  set_config_steps({ merge = [[MiniAlign.gen_step.default_merge('-')]] })
  validate_align_strings({ 'a=b' }, {}, { 'a-=-b' })

  -- Array of strings (should be recycled)
  set_config_steps({ merge = [[MiniAlign.gen_step.default_merge({ '-', '!' })]] })
  validate_align_strings(
    { 'a=b=c=' },
    {},
    -- Part resulted from separator is treated the same as any other part
    { 'a-=!b-=!c-=' }
  )
end

T['gen_step']['default_merge()']['validates input'] = function()
  expect.error(
    function() child.lua('MiniAlign.gen_step.default_merge(1)') end,
    'Merge `delimiter` should be string or array of strings'
  )
end

T['gen_step']['default_merge()']['sets proper step name'] = function()
  local validate = function(pattern, ref_name)
    local cmd = ('MiniAlign.gen_step.default_merge(%s).name'):format(pattern)
    eq(child.lua_get(cmd), ref_name)
  end

  validate([['']], vim.inspect(''))
  validate([[{ '' }]], vim.inspect({ '' }))
  validate([[{ '', ' ' }]], vim.inspect({ '', ' ' }))
end

T['gen_step']['default_merge()']['does not merge empty strings in parts'] = function()
  set_config_steps({ split = [['=']] })

  -- Shouldn't result into adding extra merge
  set_config_steps({ merge = [[MiniAlign.gen_step.default_merge('-')]] })
  validate_align_strings({ 'a===b' }, {}, { 'a-=-=-=-b' })
  validate_align_strings({ '=a' }, {}, { '=-a' })
end

T['gen_step']['trim()'] = new_set()

T['gen_step']['trim()']['works'] = function()
  set_config_steps({ split = [[' = ']], pre_justify = [[{ MiniAlign.gen_step.trim() }]] })
  eq(child.lua_get('MiniAlign.config.steps.pre_justify[1].name'), 'trim')

  validate_align_strings({ ' a  = b  =  c = d', '  e = ' }, {}, { ' a =b=c=d', '  e=' })
end

T['gen_step']['trim()']['respects `direction` argument'] = function()
  set_config_steps({ split = [['=']] })
  local set = function(direction)
    set_config_steps({ pre_justify = ([[{ MiniAlign.gen_step.trim(%s) }]]):format(vim.inspect(direction)) })
  end

  set('both')
  validate_align_strings({ ' a =b = c=d' }, {}, { ' a=b=c=d' })

  set('left')
  validate_align_strings({ ' a =b = c=d' }, {}, { ' a =b =c=d' })

  set('right')
  validate_align_strings({ ' a =b = c=d' }, {}, { ' a=b= c=d' })
end

T['gen_step']['trim()']['respects `indent` argument'] = function()
  set_config_steps({ split = [['=']] })
  local set = function(indent)
    set_config_steps({ pre_justify = ([[{ MiniAlign.gen_step.trim('both', %s) }]]):format(vim.inspect(indent)) })
  end

  set('keep')
  validate_align_strings({ ' a ', '  b ' }, {}, { ' a', '  b' })

  set('min')
  validate_align_strings({ ' a ', '  b ' }, {}, { ' a', ' b' })

  set('max')
  validate_align_strings({ ' a ', '  b ' }, {}, { '  a', '  b' })

  set('remove')
  validate_align_strings({ ' a ', '  b ' }, {}, { 'a', 'b' })
end

T['gen_step']['pair()'] = new_set()

T['gen_step']['pair()']['works'] = function()
  set_config_steps({ split = [[',']], pre_justify = [[{ MiniAlign.gen_step.pair() }]], justify = [['center']] })
  eq(child.lua_get('MiniAlign.config.steps.pre_justify[1].name'), 'pair')

  validate_align_strings({ 'a,b,c', 'aaa,bbb,c' }, {}, { ' a,  b, c', 'aaa,bbb,c' })
end

T['gen_step']['pair()']['respects `direction` argument'] = function()
  set_config_steps({ split = [[',']], justify = [['center']] })

  set_config_steps({ pre_justify = [[{ MiniAlign.gen_step.pair('left') }]] })
  validate_align_strings({ 'a,b,c', 'aaa,bbb,c' }, {}, { ' a,  b, c', 'aaa,bbb,c' })

  set_config_steps({ pre_justify = [[{ MiniAlign.gen_step.pair('right') }]] })
  validate_align_strings({ 'a,b,c', 'aaa,bbb,c' }, {}, { ' a  ,b ,c', 'aaa,bbb,c' })
end

T['gen_step']['filter()'] = new_set()

T['gen_step']['filter()']['works'] = function()
  set_config_steps({ split = [['=']], justify = [['center']] })

  set_config_steps({ pre_justify = [[{ MiniAlign.gen_step.filter('n == 1') }]] })
  validate_align_strings({ 'a=b=c', 'aaa=bbb=ccc' }, {}, { ' a =  b=c', 'aaa=bbb=ccc' })

  -- `nil` allowed as input
  eq(child.lua_get('MiniAlign.gen_step.filter()'), vim.NIL)
end

T['gen_step']['filter()']['validates input'] = function()
  expect.error(
    function() child.lua([[MiniAlign.gen_step.filter('(')]]) end,
    [[%(mini%.align%) "%(" is not a valid filter expression]]
  )
end

T['gen_step']['filter()']['handles special input'] = function()
  -- `nil`
  eq(child.lua_get('MiniAlign.gen_step.filter()'), vim.NIL)

  -- `''` (treated as `true`, i.e. nothing is filtered out)
  set_config_steps({ split = [['=']], pre_justify = [[{ MiniAlign.gen_step.filter('') }]] })
  validate_align_strings({ 'a=b=c', 'aaa=bbb=ccc' }, {}, { 'a  =b  =c', 'aaa=bbb=ccc' })
end

T['gen_step']['filter()']['allows special variables'] = function()
  set_config_steps({ split = [['=']] })
  local set = function(expr)
    set_config_steps({ pre_justify = ([[{ MiniAlign.gen_step.filter(%s) }]]):format(vim.inspect(expr)) })
  end

  --stylua:ignore start
  set('row == 2 or row == 3')
  validate_align_strings({ 'a=b=c', 'aa=bb=cc', 'aaa=bbb=ccc' }, {}, { 'a=b=c', 'aa =bb =cc', 'aaa=bbb=ccc' })

  set('row ~= ROW')
  validate_align_strings({ 'a=b=c', 'aa=bb=cc', 'aaa=bbb=ccc' }, {}, { 'a =b =c', 'aa=bb=cc', 'aaa=bbb=ccc' })

  set('col > 1')
  validate_align_strings({ 'a=b=c', 'aa=bb=cc', 'aaa=bbb=ccc' }, {}, { 'a=  b  =c', 'aa= bb =cc', 'aaa=bbb=ccc' })

  set('col >= COL - 1')
  validate_align_strings({ 'a=b=c', 'aa=bb=cc', 'aaa=bbb=ccc' }, {}, { 'a=b=    c', 'aa=bb=  cc', 'aaa=bbb=ccc' })
  --stylua:ignore end
end

T['gen_step']['filter()']['allows usage of global objects'] = function()
  set_config_steps({ split = [['=']], pre_justify = [[{ MiniAlign.gen_step.filter('row ~= first_row') }]] })
  child.lua('_G.first_row = 1')
  validate_align_strings({ 'a=b=c', 'aa=bb=cc', 'aaa=bbb=ccc' }, {}, { 'a=b=c', 'aa =bb =cc', 'aaa=bbb=ccc' })
end

-- Integration tests ==========================================================
local validate_keys = function(input_lines, keys, output_lines)
  set_lines(input_lines)
  set_cursor(1, 0)
  type_keys(keys)
  eq(get_lines(), output_lines)
end

-- NOTEs:
-- - In Neovim=0.5 some textobjects in Operator-pending mode don't set linewise
--   mode (like `ip`). However in Visual mode they do. So if Neovim=0.5 support
--   is needed, write tests with explicit forcing of linewise selection.

T['Align'] = new_set()

T['Align']['works'] = function()
  -- Use neutral split pattern to avoid testing builtin modifiers
  validate_keys({ 'a_b', 'aaa_b' }, { 'Vj', 'ga', '_' }, { 'a  _b', 'aaa_b' })

  -- Allows non-split related modifiers
  validate_keys({ 'a_b', 'aaa_b' }, { 'V1j', 'ga', 'jc', '_' }, { ' a _b', 'aaa_b' })
end

T['Align']['works in Normal mode'] = function()
  -- Should accept any textobject or motion
  validate_keys({ 'a_b', 'aaa_b', '', 'aaaaa_b' }, { 'ga', 'Vip', '_' }, { 'a  _b', 'aaa_b', '', 'aaaaa_b' })
  eq(get_cursor(), { 1, 0 })

  validate_keys({ 'a_b', 'aaa_c' }, { 'ga', [[/_\zsc<CR>]], '_' }, { 'a  _b', 'aaa_c' })
end

T['Align']['allows dot-repeat'] = function()
  set_lines({ 'a_b', 'aaa_b', '', 'aaaaa_b', 'a_b' })
  set_cursor(1, 0)
  type_keys('ga', 'Vip', '_')
  eq(get_lines(), { 'a  _b', 'aaa_b', '', 'aaaaa_b', 'a_b' })

  set_cursor(4, 0)
  type_keys('.')
  eq(get_lines(), { 'a  _b', 'aaa_b', '', 'aaaaa_b', 'a    _b' })
end

T['Align']['works in Visual charwise mode'] = function()
  -- Should use visual selection to extract strings and correctly place result
  -- Should return to Normal mode after finish
  validate_keys({ 'a_b', 'aaa_b' }, { 'v', '1j4l', 'ga', '_' }, { 'a  _b', 'aaa_b' })
  eq(get_cursor(), { 2, 4 })
  eq(get_mode(), 'n')

  -- Respects offset of first line
  set_lines({ 'xx_xxa_b', 'a_b' })
  set_cursor(1, 5)
  type_keys('vj', 'ga', '_')
  eq(get_lines(), { 'xx_xxa_b', 'a     _b' })

  -- Allows using non-split related modifiers
  validate_keys({ 'a_b', 'aaa_b' }, { 'v', '1j4l', 'ga', 'jc', '_' }, { ' a _b', 'aaa_b' })

  -- Should align for second `_` because it is not inside selection
  validate_keys({ 'a_b_c', 'aaa_bbb_ccc' }, { 'v', '/bb_<CR>', 'ga', '_' }, { 'a  _b_c', 'aaa_bbb_ccc' })

  -- Can use `$` without `end_col out of bounds`
  validate_keys({ 'a_b', 'aaa_b' }, { 'v', '1j$', 'ga', '_' }, { 'a  _b', 'aaa_b' })
end

T['Align']['works in Visual linewise mode'] = function()
  validate_keys({ 'a_b_c', 'aaa_bbb_ccc' }, { 'V', 'ip', 'ga', '_' }, { 'a  _b  _c', 'aaa_bbb_ccc' })
  eq(get_mode(), 'n')

  -- Allows using non-split related modifiers
  validate_keys({ 'a_b', 'aaa_b' }, { 'V', '1j', 'ga', 'jc', '_' }, { ' a _b', 'aaa_b' })
end

T['Align']['works in Visual blockwise mode'] = function()
  validate_keys({ 'a_b_c', 'aaa_bbb_c' }, { '<C-v>', '1j3l', 'ga', '_' }, { 'a  _b_c', 'aaa_bbb_c' })
  eq(get_mode(), 'n')

  child.o.virtualedit = 'block'

  -- Selection goes over empty line (at start/middle/end of selection)
  validate_keys({ '', 'a_b_c', 'aaa_bbb_c' }, { '<C-v>', '2j3l', 'ga', '_' }, { '', 'a  _b_c', 'aaa_bbb_c' })
  validate_keys({ 'a_b_c', '', 'aaa_bbb_c' }, { '<C-v>', '2j3l', 'ga', '_' }, { 'a  _b_c', '', 'aaa_bbb_c' })
  validate_keys({ 'a_b_c', 'aaa_bbb_c', '' }, { '<C-v>', '2j3l', 'ga', '_' }, { 'a  _b_c', 'aaa_bbb_c', '' })

  -- Works when selection goes past the line (only right column, both columns)
  validate_keys({ 'a_b', 'aa_b', 'aaa_b' }, { '1l', '<C-v>', '2j2l', 'ga', '_' }, { 'a  _b', 'aa _b', 'aaa_b' })
  validate_keys({ 'a_b', 'aaa_b', 'aaaa_b' }, { '2j3l', '<C-v>', '2k2l', 'ga', '_' }, { 'a_b', 'aaa _b', 'aaaa_b' })

  -- Correctly works in presence of multibyte characters
  validate_keys({ 'ыы_ф', 'ыыы_ф' }, { '1l', '<C-v>', '1j3l', 'ga', '_' }, { 'ыы _ф', 'ыыы_ф' })
end

T['Align']['registers visual selection'] = function()
  set_lines({ 'a_b', 'aa_b', 'vvv', 'vvv' })

  -- Make preceding visual selection
  set_cursor(3, 0)
  type_keys('V', 'j', 'u')

  -- Align in Visual mode
  set_cursor(1, 0)
  type_keys('V', 'j', 'ga', '_')
  eq(get_lines(), { 'a _b', 'aa_b', 'vvv', 'vvv' })

  -- Verify that Visual selection got updated
  type_keys('gv')
  eq(get_mode(), 'V')
  eq(child.fn.getpos('v'), { 0, 1, 1, 0 })
end

T['Align']['works with differnt mapping'] = function()
  unload_module()
  child.api.nvim_del_keymap('n', 'ga')
  child.api.nvim_del_keymap('x', 'ga')
  load_module({ mappings = { start = 'gl' } })

  validate_keys({ 'a_b', 'aaa_b' }, { 'gl', 'Vj', '_' }, { 'a  _b', 'aaa_b' })
  validate_keys({ 'a_b', 'aaa_b' }, { 'Vj', 'gl', '_' }, { 'a  _b', 'aaa_b' })
end

T['Align']['works with multibyte characters'] = function()
  validate_keys(
    { 'ыффцццф', 'ыыыффцф' },
    { 'Vj', 'ga', 'ф' },
    { 'ы  ффцццф', 'ыыыффц  ф' }
  )
end

T['Align']['does not ask for modifier if `split` is set'] = function()
  set_config_steps({ split = [['_']] })
  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)
  type_keys('Vj', 'ga')
  eq(get_lines(), { 'a _b', 'aa_b' })
end

T['Align']['treats non-config modifier as explicit split pattern'] = function()
  validate_keys({ 'a.b', 'aaa.b' }, { 'ga', 'Vj', '.' }, { 'a  .b', 'aaa.b' })
  validate_keys({ 'a(b', 'aaa(b' }, { 'ga', 'Vj', '(' }, { 'a  (b', 'aaa(b' })
end

T['Align']['stops on `<Esc>` and `<C-c>`'] = function()
  for _, stop_key in ipairs({ '<Esc>', '<C-c>' }) do
    validate_keys({ 'a_b', 'aa_b' }, { 'Vj', 'ga', stop_key }, { 'a_b', 'aa_b' })
    eq(get_mode(), 'n')
  end
end

T['Align']['has guard against infinite loop'] = function()
  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)
  type_keys('Vj', 'ga')
  eq(get_mode(), 'V')

  for _ = 1, 1001 do
    type_keys('m', ' ', '<CR>')
  end
  eq(get_mode(), 'n')
  eq(get_latest_message(), '(mini.align) Too many modifiers typed.')
end

T['Align']['does not stop on error during modifier execution'] = function()
  child.lua([[MiniAlign.config.modifiers.e = function() error('Bad modifier') end]])

  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)

  -- Error in modifier execution should lead to a pause to make message visible
  local before_time = vim.loop.hrtime()
  type_keys('Vj', 'ga', 'e')
  local duration = 0.000001 * (vim.loop.hrtime() - before_time)
  eq(500 <= duration and duration <= 510, true)
  expect.match(get_latest_message(), '^%(mini.align%) Modifier "e" should be properly callable%. Reason:')
end

T['Align']['validates steps after each modifier'] = function()
  child.lua([[MiniAlign.config.modifiers.e = function(steps) steps.pre_split = 1 end]])
  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)
  type_keys('Vj', 'ga')
  expect.error(type_keys, 'pre_split.*array of steps', { 'e', '_' })
end

T['Align']['prompts helper message after one idle second'] = new_set({
  parametrize = { { 'Normal' }, { 'Visual' } },
}, {
  test = function(test_mode)
    child.set_size(12, 20)
    child.o.cmdheight = 5

    -- Prompts message in debounce-style fashion
    set_lines({ 'a_b', 'aa_b' })
    set_cursor(1, 0)
    local keys = test_mode == 'Normal' and { 'ga', 'Vip' } or { 'Vip', 'ga' }
    type_keys(unpack(keys))

    sleep(1000 - 15)
    -- Should show no message
    child.expect_screenshot()
    type_keys('j', 'r')
    -- Should show result of modifier 'j'
    child.expect_screenshot()
    sleep(1000 - 15)
    -- Should still show result of modifier 'j'
    child.expect_screenshot()
    sleep(15 + 15)
    -- Should now show helper message
    child.expect_screenshot()

    -- Shows message immediately if it was already shown
    type_keys('j', 'c')
    child.expect_screenshot()
  end,
})

T['Align']['helper message does not cause hit-enter-prompt'] = function()
  child.set_size(6, 20)
  child.o.cmdheight = 2
  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)

  type_keys('ga', 'Vj')
  sleep(1000)
  child.expect_screenshot()
end

--stylua: ignore
T['Align']["respects 'selection=exclusive'"] = function()
  child.o.selection = 'exclusive'

  -- Normal mode charwise
  validate_keys({ 'a_b_c', 'aa_bb_cc' }, { 'ga', 'v', [[/bb\zs_<CR>]], '_' }, { 'a _b_c', 'aa_bb_cc' })
  validate_keys({ 'ы_ю_я', 'ыы_юю_яя' }, { 'ga', 'v', [[/юю\zs_<CR>]], '_' }, { 'ы _ю_я', 'ыы_юю_яя' })

  -- Normal mode blockwise
  validate_keys({ 'a_b_c', 'aa_bb_cc' }, { 'ga', '<C-v>', [[/bb\zs_<CR>]], '_' }, { 'a _b_c', 'aa_bb_cc' })
  validate_keys({ 'ы_ю_я', 'ыы_юю_яя' }, { 'ga', '<C-v>', [[/юю\zs_<CR>]], '_' }, { 'ы _ю_я', 'ыы_юю_яя' })

  -- Visual mode
  validate_keys({ 'a_b_c', 'aa_bb_cc' }, { 'v1j5l', 'ga', '_' }, { 'a _b_c', 'aa_bb_cc' })
  validate_keys({ 'ы_ю_я', 'ыы_юю_яя' }, { 'v1j5l', 'ga', '_' }, { 'ы _ю_я', 'ыы_юю_яя' })

  -- Visual mode blockwise
  validate_keys({ 'a_b_c', 'aa_bb_cc' }, { '<C-v>', '1j5l', 'ga', '_' }, { 'a _b_c', 'aa_bb_cc' })
  validate_keys({ 'ы_ю_я', 'ыы_юю_яя' }, { '<C-v>', '1j5l', 'ga', '_' }, { 'ы _ю_я', 'ыы_юю_яя' })
end

T['Align']['does not affect marks'] = function()
  local validate = function(start_keys)
    set_lines({ 'a_b', 'aa_b', 'aaa_b' })
    child.fn.setpos("'a", { 0, 1, 1, 0 })
    child.fn.setpos("'b", { 0, 3, 1, 0 })
    set_cursor(1, 0)

    type_keys(start_keys, '_')
    eq(get_lines(), { 'a _b', 'aa_b', 'aaa_b' })
    eq(child.api.nvim_buf_get_mark(0, 'a'), { 1, 0 })
    eq(child.api.nvim_buf_get_mark(0, 'b'), { 3, 0 })
  end

  -- Normal mode
  validate({ 'ga', 'v', [[2/_\zsb]], '<CR>' })
  validate({ 'ga', 'V', 'j' })
  validate({ 'ga', '<C-v>', [[2/_\zsb]], '<CR>' })

  -- Visual mode
  validate({ 'v', [[2/_\zsb]], '<CR>', 'ga' })
  validate({ 'V', 'j', 'ga' })
  validate({ '<C-v>', [[2/_\zsb]], '<CR>', 'ga' })
end

T['Align']['respects `vim.{g,b}.minialign_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minialign_disable = true

    validate_keys({ 'a_b', 'aa_b' }, { 'Vj', 'ga', '_' }, { 'a_b', 'aa_b' })
  end,
})

-- Test mostly "preview" part. Hope that other is covered in 'Align' tests.
T['Align with preview'] =
  new_set({ hooks = {
    pre_case = function()
      child.set_size(12, 30)
      child.o.cmdheight = 5
    end,
  } })

T['Align with preview']['works'] = new_set({
  parametrize = {
    { 'Normal-char' },
    { 'Normal-line' },
    { 'Normal-block' },
    { 'Visual-char' },
    { 'Visual-line' },
    { 'Visual-block' },
  },
}, {
  test = function(test_mode)
    set_lines({ 'a_b_c', 'aaa_bbb_ccc' })
    set_cursor(1, 0)
    child.fn.setpos("'a", { 0, 2, 5, 0 })

    local init_keys = ({
      ['Normal-char'] = { 'gA', 'v', '`a' },
      ['Normal-line'] = { 'gA', 'V', 'j' },
      ['Normal-block'] = { 'gA', '<C-v>', '`a' },
      ['Visual-char'] = { 'v', '`a', 'gA' },
      ['Visual-line'] = { 'V', 'j', 'gA' },
      ['Visual-block'] = { '<C-v>', '`a', 'gA' },
    })[test_mode]
    type_keys(init_keys)

    -- Should show helper message immediately
    child.expect_screenshot()

    -- Should show result and not stop preview
    type_keys('_')
    child.expect_screenshot()

    type_keys('j', 'r')
    child.expect_screenshot()

    type_keys('m', '-', '<CR>')
    child.expect_screenshot()

    -- Hitting `<CR>` accepts current result
    type_keys('<CR>')
    -- This should start Insert mode and not right justify by 'a'
    type_keys('a')
    child.expect_screenshot()
  end,
})

T['Align with preview']['stops preview after `<Esc>` and `<C-c>`'] = function()
  -- Don't show mode because it causes hit-enter-prompt with Visual selection
  child.o.showmode = false
  local validate = function(init_keys, stop_key)
    child.ensure_normal_mode()

    local lines = { 'a_b', 'aa_b' }
    set_lines(lines)
    set_cursor(1, 0)
    type_keys(init_keys, '_')
    -- Justify to right side
    type_keys('jr')
    eq(get_lines(), { ' a_b', 'aa_b' })

    -- Should reset text to its initial form
    type_keys(stop_key)
    eq(get_mode(), 'n')
    eq(get_lines(), lines)
    -- This should start Insert mode and not right justify by 'a'
    type_keys('a')
    eq(get_mode(), 'i')
  end

  -- Normal mode
  validate({ 'gA', 'Vj' }, '<Esc>')
  validate({ 'gA', 'Vj' }, '<C-c>')

  -- Visual mode
  validate({ 'Vj', 'gA' }, '<Esc>')
  validate({ 'Vj', 'gA' }, '<C-c>')
end

T['Align with preview']['correctly restores visual selection'] = new_set(
  { parametrize = { { 'Visual-char' }, { 'Visual-line' }, { 'Visual-block' } } },
  {
    test = function(test_mode)
      set_lines({ 'a_b_c', 'aaa_bbb_ccc', '', 'previous selection' })
      child.fn.setpos("'a", { 0, 2, 5, 0 })

      -- Make "previous selection" to complicate setup
      set_cursor(4, 9)
      type_keys('v', '8l', '<Esc>')

      set_cursor(1, 0)
      local init_keys = ({
        ['Visual-char'] = { 'v', '`a', 'gA' },
        ['Visual-line'] = { 'V', 'j', 'gA' },
        ['Visual-block'] = { '<C-v>', '`a', 'gA' },
      })[test_mode]
      type_keys(init_keys, '_')
      child.expect_screenshot()

      -- Make undo of current result and redo alignment
      type_keys('jr')
      child.expect_screenshot()
    end,
  }
)

T['Align with preview']['respects `vim.{g,b}.minialign_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minialign_disable = true

    local lines = { 'a_b', 'aa_b' }
    set_lines(lines)
    set_cursor(1, 0)
    type_keys('Vj', 'gA', '_', '<CR>')
    eq(get_lines(), lines)
  end,
})

T['Modifiers'] = new_set()

T['Modifiers']['s'] = function() MiniTest.skip() end
T['Modifiers']['j'] = function() MiniTest.skip() end
T['Modifiers']['m'] = function() MiniTest.skip() end
T['Modifiers']['f'] = function() MiniTest.skip() end
T['Modifiers']['t'] = function() MiniTest.skip() end
T['Modifiers']['p'] = function() MiniTest.skip() end
T['Modifiers']['<BS>'] = function() MiniTest.skip() end
T['Modifiers']['='] = function() MiniTest.skip() end
T['Modifiers'][','] = function() MiniTest.skip() end
T['Modifiers'][' '] = function() MiniTest.skip() end
T['Modifiers']['|'] = function() MiniTest.skip() end

return T
