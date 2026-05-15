local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('input', config) end
local unload_module = function(config) child.mini_unload('input', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local forward_lua_notify = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_notify(lua_cmd, { ... }) end
end

local get = forward_lua_notify('MiniInput.get')
local get_history = forward_lua('MiniInput.get_history')

local get_state = function()
  return child.lua([[
    local state = MiniInput.get_state()
    if state == nil then return nil end
    -- Adjust function handlers to be able to pass through RPC
    for k, v in pairs(state.opts.handlers) do
      if vim.is_callable(v) then state.opts.handlers[k] = 'function' end
    end
    return state
  ]])
end

-- Common mocks
local mock_finished_input = function(input, prompt, scope)
  get({ prompt = prompt, scope = scope })
  type_keys(input, '<CR>')
end

local mock_state = function(incomplete_state)
  child.lua('_G.mock_state = ' .. vim.inspect(incomplete_state))
  child.lua([[
    _G.mock_state.input = _G.mock_state.input or ''
    _G.mock_state.caret = _G.mock_state.caret or (vim.fn.strchars(_G.mock_state.input) + 1)
    _G.mock_state.data = {}
    _G.mock_state.status = _G.mock_state.status or 'progress'

    local opts = _G.mock_state.opts or {}
    local default_handlers = {
      key = MiniInput.default_key,
      highlight = MiniInput.default_highlight,
      view = MiniInput.default_view,
      complete = MiniInput.default_complete,
    }
    opts.handlers = vim.tbl_extend('force', default_handlers, opts.handlers or {})
    if opts.hide == nil then opts.hide = false end
    opts.init_keys = opts.init_keys or {}
    opts.prompt = opts.prompt or 'Input'
    opts.scope = opts.scope or MiniInput.config.scope
    _G.mock_state.opts = opts
  ]])
end

-- Common validators
local validate_input = function(ref_input, ref_caret, ref_scope)
  local state = get_state()
  if state == vim.NIL then
    local msg = 'No active input.'
      .. string.format(' Expected input=%s, caret=%d, scope=%s', vim.inspect(ref_input), ref_caret, ref_scope)
    error(msg)
  end
  local ref = {
    input = ref_input or state.input,
    caret = ref_caret or state.caret,
    scope = ref_scope or state.opts.scope,
  }
  eq({ input = state.input, caret = state.caret, scope = state.opts.scope }, ref)
end

local validate_no_input = function()
  local state = get_state()
  if state == vim.NIL then return end
  local msg = string.format('There is active input: input=%s, caret=%d', vim.inspect(state.input), state.caret)
  error(msg)
end

local validate_log = function(name, ref, preserve)
  eq(child.lua_get(name), ref)
  if not preserve then child.lua(name .. ' = {}') end
end

local validate_default_handler = function(name, state, arg, ref_state_changes)
  child.lua([[
    _G.compute_changed_values = function(left, right)
      if not (type(left) == 'table' and type(right) == 'table') then
        if vim.deep_equal(left, right) then return nil end
        -- Use `vim.NIL` to indicate that the value was set to `nil`
        if right == nil then return vim.NIL end
        return right
      end

      local changed = {}
      for k, v in pairs(left) do
        changed[k] = _G.compute_changed_values(v, right[k])
        if type(changed[k]) == 'table' and vim.tbl_count(changed[k]) == 0 then changed[k] = nil end
      end
      for k, v in pairs(right) do
        if left[k] == nil then changed[k] = v end
      end
      return changed
    end
  ]])

  child.lua('_G.handler_name = ' .. vim.inspect(name))
  mock_state(state)
  child.lua('_G.arg = ' .. vim.inspect(arg))
  child.lua('_G.handler = MiniInput.default_' .. name)
  local state_changes = child.lua([[
    local old_state = vim.deepcopy(_G.mock_state)
    local new_state = _G.handler(_G.mock_state, _G.arg) or _G.mock_state
    return _G.compute_changed_values(old_state, new_state)
  ]])
  eq(state_changes, ref_state_changes)
end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()

      -- Make screenshots more robust
      child.set_size(10, 20)
      child.o.laststatus = 0
      child.o.showtabline = 0
      child.o.ruler = false
    end,
    post_once = child.stop,
    n_retry = helpers.get_n_retry(1),
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniInput)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniInput'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniInputAdded', 'links to DiagnosticFloatingOk')
  has_highlight('MiniInputBorder', 'links to FloatBorder')
  has_highlight('MiniInputCaret', 'links to MiniInputPrompt')
  has_highlight('MiniInputHide', 'links to DiagnosticFloatingWarn')
  has_highlight('MiniInputHint', 'links to DiagnosticFloatingHint')
  has_highlight('MiniInputNormal', 'links to NormalFloat')
  has_highlight('MiniInputPrompt', 'links to DiagnosticFloatingInfo')
  has_highlight('MiniInputSpecial', 'links to DiagnosticFloatingWarn')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniInput.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniInput.config.' .. field), value) end

  expect_config('handlers.complete', vim.NIL)
  expect_config('handlers.highlight', vim.NIL)
  expect_config('handlers.key', vim.NIL)
  expect_config('handlers.view', vim.NIL)
  expect_config('scope', 'editor')
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ handlers = 1 }, 'handlers', 'table')
  expect_config_error({ handlers = { complete = 1 } }, 'handlers.complete', 'function')
  expect_config_error({ handlers = { highlight = 1 } }, 'handlers.highlight', 'function')
  expect_config_error({ handlers = { key = 1 } }, 'handlers.key', 'function')
  expect_config_error({ handlers = { view = 1 } }, 'handlers.view', 'function')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniInputBorder'), 'links to FloatBorder')
end

T['setup()']['clears history'] = function()
  get()
  type_keys('one', '<CR>')
  eq(#get_history(), 1)

  load_module()
  eq(#get_history(), 0)
end

T['setup()']['sets `vim.ui.input`'] = function()
  child.lua_notify('vim.ui.input({}, function() end)')
  validate_input('', 1, 'editor')
end

T['setup()']['adjusts `vim.paste`'] = function()
  child.setup()

  child.lua([[
    _G.notify_log = {}
    vim.notify = function(...) table.insert(_G.notify_log, { ... }) end

    _G.paste_log = {}
    vim.paste = function(lines, phase) table.insert(_G.paste_log, { lines, phase }) end
  ]])

  load_module()
  child.lua([[
    _G.key_log = {}
    MiniInput.config.handlers.key = function(state, key)
      table.insert(_G.key_log, key)
      return MiniInput.default_key(state, key)
    end
  ]])
  get()

  -- Not streaming input should be inserted as is respecting custom key handler
  child.api.nvim_paste('Clipboard', false, -1)
  validate_input('Clipboard', 10)
  validate_log('paste_log', {})
  validate_log('key_log', { 'Clipboard' })

  -- Streaming paste is not supported and should fall back to what was before
  child.api.nvim_paste('Not supported', false, 1)
  validate_input('Clipboard', 10)
  validate_log('paste_log', { { { 'Not supported' }, 1 } })
  validate_log('key_log', {})
  validate_log('notify_log', { { '(mini.input) There is no streaming paste support. Use `<C-r>+` or `<C-r>*`.' } })
end

T['setup()']['hard-codes special default scopes'] = function()
  child.restart()
  child.lua([[
    _G.rename_log = {}
    local append = function(...) table.insert(_G.rename_log, { ... }) end
    vim.lsp.buf.rename = function(new_name, _)
      if new_name ~= nil then return append('direct', new_name) end
      vim.ui.input({ prompt = 'New name: ' }, function(inp) append('ui.input', inp) end)
    end
  ]])
  load_module()

  -- `vim.lsp.buf.rename()`
  child.lua_notify('vim.lsp.buf.rename()')
  validate_input('', 1, 'cursor')
  type_keys('Hello', '<CR>')
  validate_log('rename_log', { { 'ui.input', 'Hello' } })

  child.lua('vim.lsp.buf.rename("World")')
  validate_no_input()
  validate_log('rename_log', { { 'direct', 'World' } })

  -- - Should be possible to override via a key handler
  child.lua([[
    MiniInput.config.handlers.key = function(state, key)
      if state.opts.prompt == 'New name: ' then state.opts.scope = 'window' end
      return MiniInput.default_key(state, key)
    end
  ]])

  child.lua_notify('vim.lsp.buf.rename()')
  validate_input('', 1, 'window')
  type_keys('New one', '<CR>')
  validate_log('rename_log', { { 'ui.input', 'New one' } })
end

T['get()'] = new_set()

T['get()']['works'] = function() MiniTest.skip() end

T['get()']['adds to history'] = function()
  get()
  type_keys('Regular', '<CR>')
  eq(#get_history(), 1)

  -- Canceled input should not be added
  get()
  type_keys('x', '<C-c>')
  eq(#get_history(), 1)

  -- Hidden input should not be added
  get({ hide = true })
  type_keys('Hidden', '<CR>')
  eq(#get_history(), 1)

  -- - Even if hidden is set interactively
  get({ hide = false })
  type_keys('Another', '<C-x>', '<CR>')
  eq(#get_history(), 1)

  -- Empty should be accepted
  get()
  type_keys('x', '<C-u>', '<CR>')
  eq(#get_history(), 2)
end

T['get()']['reacts to `VimResized`'] = function()
  -- Should refresh on resize
  child.lua([[
    _G.handlers_log = {}
    MiniInput.config.handlers.key = function(state, key)
      table.insert(_G.handlers_log, { 'key', key == nil and 0 or key, state.status })
    end
    MiniInput.config.handlers.highlight = function(state) table.insert(_G.handlers_log, { 'highlight' }) end
    MiniInput.config.handlers.view = function(state) table.insert(_G.handlers_log, { 'view' }) end
  ]])

  get()
  validate_log('handlers_log', { { 'key', 0, 'start' }, { 'highlight' }, { 'view' } })

  child.o.lines = 20
  validate_log('handlers_log', { { 'key', 0, 'progress' }, { 'highlight' }, { 'view' } })
end

T['get()']['works with non-copyable `data`'] = function() MiniTest.skip() end

T['ui_input()'] = new_set()

T['ui_input()']['works'] = function()
  child.lua([[
    _G.choice_log = {}
    _G.on_choice = function(...) table.insert(_G.choice_log, { ... }) end
  ]])

  child.lua_notify('MiniInput.ui_input(nil, _G.on_choice)')
  validate_input('', 1, 'editor')
  type_keys('x', '<CR>')
  validate_log('choice_log', { { 'x' } })

  child.lua_notify([[
    MiniInput.ui_input({ prompt = 'Hello?', default = 'World', completion = 'cmdline' }, _G.on_choice)
  ]])
  local state = get_state()
  eq(state.opts.prompt, 'Hello?')
  eq(state.opts.init_keys, { 'World' })
  eq(state.opts.completion, 'cmdline')
end

T['ui_input()']['converts `opts.highlight` to highlight handler'] = function() MiniTest.skip() end

T['get_state()'] = new_set()

T['get_state()']['works'] = function()
  get()

  -- Should return correct structure
  local state = get_state()
  eq(type(state), 'table')
  local keys = vim.tbl_keys(state)
  table.sort(keys)
  eq(keys, { 'caret', 'data', 'input', 'opts', 'status' })

  eq(state.caret, 1)
  eq(type(state.data), 'table')
  eq(state.input, '')
  local ref_opts = { completion = '', hide = false, init_keys = {}, prompt = 'Input', scope = 'editor' }
  ref_opts.handlers = { complete = 'function', highlight = 'function', key = 'function', view = 'function' }
  eq(state.opts, ref_opts)
  eq(state.status, 'progress')

  -- Should return up to date information
  type_keys('x')
  state = get_state()
  eq({ input = state.input, caret = state.caret }, { input = 'x', caret = 2 })

  type_keys('<Left>')
  state = get_state()
  eq({ input = state.input, caret = state.caret }, { input = 'x', caret = 1 })

  type_keys('<C-x>', '<C-o>')
  state = get_state()
  eq({ hide = state.opts.hide, scope = state.opts.scope }, { hide = true, scope = 'project' })
end

T['get_state()']['returns copy'] = function()
  get()
  local res = child.lua([[
    local state = MiniInput.get_state()
    state.status = 'cancel'
    return MiniInput.get_state().status == 'progress'
  ]])
  eq(res, true)
end

T['get_state()']['respect `opts.hide`'] = function()
  get({ hide = true })
  local state = get_state()
  eq({ input = state.input, caret = state.caret }, {})
end

T['get_state()']['works with non-copyable `data`'] = function() MiniTest.skip() end

T['get_history()'] = new_set()

T['get_history()']['works'] = function()
  local cwd = child.fn.getcwd()

  eq(get_history(), {})

  mock_finished_input('World', 'Hello?', 'cursor')
  local ref_1 = { cwd = cwd, input = 'World', prompt = 'Hello?', scope = 'cursor' }
  eq(get_history(), { ref_1 })

  -- Should append new entries
  child.lua('MiniInput.config.scope = "window"')
  get({ prompt = 'Two' })
  type_keys('x', '<C-u>', '<CR>')
  local ref_2 = { cwd = cwd, input = '', prompt = 'Two', scope = 'window' }
  eq(get_history(), { ref_1, ref_2 })
end

T['get_history()']['returns copy'] = function()
  mock_finished_input('one')
  local res = child.lua([[
    local history = MiniInput.get_history()
    history[1] = 'a'
    return type(MiniInput.get_history()[1]) == 'table'
  ]])
  eq(res, true)
end

T['set_history()'] = new_set()

local set_history = forward_lua('MiniInput.set_history')

T['set_history()']['works'] = function()
  local history = { { cwd = child.fn.getcwd(), input = 'World', prompt = 'Hello?', scope = 'cursor' } }
  set_history(history)
  eq(get_history(), history)
end

T['set_history()']['uses copy'] = function()
  local res = child.lua([[
    local history = { { cwd = vim.fn.getcwd(), input = 'World', prompt = 'Hello?', scope = 'cursor' } }
    MiniInput.set_history(history)
    history[1].input = 'New one'
    return MiniInput.get_history()[1].input == 'World'
  ]])
  eq(res, true)
end

T['set_history()']['validates input'] = function()
  local validate = function(arg, pattern)
    expect.error(function() set_history(arg) end, pattern)
  end

  validate('a', '`history`.*array')
  validate({ 'a' }, '`history`.*item.*table')
  validate({ { cwd = 1, input = '', prompt = 'Input', scope = 'cursor' } }, '`history%[1%]%.cwd`.*string')
  validate({ { cwd = 'a', input = 1, prompt = 'Input', scope = 'cursor' } }, '`history%[1%]%.input`.*string')
  validate({ { cwd = 'a', input = '', prompt = 1, scope = 'cursor' } }, '`history%[1%]%.prompt`.*string')
  validate({ { cwd = 'a', input = '', prompt = 'Input', scope = 'xxx' } }, '`history%[1%]%.scope`.*one of')
end

T['refresh()'] = new_set()

local refresh = forward_lua('MiniInput.refresh')

T['refresh()']['works'] = function()
  child.lua([[
    _G.handlers_log = {}
    local key_n = 0
    MiniInput.config.handlers.key = function(state, key)
      table.insert(_G.handlers_log, { 'key', key == nil and 0 or key, state.status, _G.track })
      key_n = key_n + 1
      if key_n < 3 then return end
      state.status = 'cancel'
    end
    MiniInput.config.handlers.highlight = function(state) table.insert(_G.handlers_log, { 'highlight' }) end
    MiniInput.config.handlers.view = function(state) table.insert(_G.handlers_log, { 'view' }) end
  ]])

  -- Should work without active input
  expect.no_error(refresh)

  get()
  validate_log('handlers_log', { { 'key', 0, 'start' }, { 'highlight' }, { 'view' } })

  -- Should call all handlers with `key=nil`
  child.lua('_G.track = true')
  refresh()
  validate_log('handlers_log', { { 'key', 0, 'progress', true }, { 'highlight' }, { 'view' } })

  -- Should react to ending the input
  child.lua('_G.track = nil')
  refresh()
  validate_no_input()
  --stylua: ignore
  local ref_log = {
    { 'key', 0, 'progress' }, { 'highlight' }, { 'view' },
    { 'key', 0, 'cancel' },   { 'highlight' }, { 'view' },
  }
  validate_log('handlers_log', ref_log)
end

T['gen_highlight'] = new_set()

T['gen_highlight']['treesitter()'] = new_set()

T['gen_highlight']['treesitter()']['works'] = function() MiniTest.skip() end

T['gen_view'] = new_set()

T['gen_view']['floatwin'] = new_set()

T['gen_view']['floatwin']['works'] = function() MiniTest.skip() end

T['gen_view']['uiline'] = new_set()

T['gen_view']['uiline']['works'] = function() MiniTest.skip() end

T['gen_view']['virtual'] = new_set()

T['gen_view']['virtual']['works'] = function() MiniTest.skip() end

T['default_key()'] = new_set()

local validate_key = function(state, key, state_change)
  -- Treat `key` as not escaped for easier to read test code
  if key ~= nil then key = child.api.nvim_replace_termcodes(key, true, true, true) end
  validate_default_handler('key', state, key, state_change)
end

T['default_key()']['works'] = function()
  -- Should insert at caret any non-special key
  validate_key({ input = 'ab', caret = 3 }, 'c', { input = 'abc', caret = 4 })
  validate_key({ input = 'ab', caret = 2 }, 'c', { input = 'acb', caret = 3 })
  validate_key({ input = 'ab', caret = 1 }, 'c', { input = 'cab', caret = 2 })

  -- Should do nothing if no key or state is ending
  local validate_no_action = function(status, key) validate_key({ input = 'ab', caret = 3, status = status }, key, {}) end
  validate_no_action('start', nil)
  validate_no_action('progress', nil)
  validate_no_action('accept', nil)
  validate_no_action('cancel', nil)

  validate_no_action('accept', 'c')
  validate_no_action('cancel', 'c')
end

T['default_key()']['can accept and cancel'] = function()
  local validate_status_change = function(key, ref_status)
    validate_key({ status = 'start' }, key, { status = ref_status })
    validate_key({ status = 'progress' }, key, { status = ref_status })
    -- When the state is already ending, nothing should be done
    validate_key({ status = 'accept' }, key, {})
    validate_key({ status = 'cancel' }, key, {})
  end

  validate_status_change('<CR>', 'accept')
  validate_status_change('<Esc>', 'cancel')
  validate_status_change('<C-c>', 'cancel')
end

T['default_key()']['can move caret'] = function()
  local validate_move = function(input, key, caret, ref_caret)
    validate_key({ input = input, caret = caret }, key, { caret = ref_caret ~= caret and ref_caret or nil })
  end

  -- Left/right
  validate_move('ab', '<Left>', 3, 2)
  validate_move('ab', '<Left>', 2, 1)
  validate_move('ab', '<Left>', 1, 1)
  validate_move('ab', '<M-h>', 3, 2)
  validate_move('ab', '<M-h>', 2, 1)
  validate_move('ab', '<M-h>', 1, 1)

  validate_move('ab', '<Right>', 3, 3)
  validate_move('ab', '<Right>', 2, 3)
  validate_move('ab', '<Right>', 1, 2)
  validate_move('ab', '<M-l>', 3, 3)
  validate_move('ab', '<M-l>', 2, 3)
  validate_move('ab', '<M-l>', 1, 2)

  -- Left/right by word. Should jump over all consecutive keyword and non
  -- keyword characters. Here keyword characters are 'a' and 'b'.
  child.o.iskeyword = '97-98'

  validate_move('axabxxab', '<S-Left>', 1, 1)
  validate_move('axabxxab', '<S-Left>', 2, 1)
  validate_move('axabxxab', '<S-Left>', 3, 2)
  validate_move('axabxxab', '<S-Left>', 7, 5)
  validate_move('axabxxab', '<S-Left>', 4, 3)
  validate_move('axabxxab', '<S-Left>', 5, 3)
  validate_move('axabxxab', '<S-Left>', 6, 5)
  validate_move('axabxxab', '<S-Left>', 8, 7)
  validate_move('axabxxab', '<S-Left>', 9, 7)

  validate_move('axabxxab', '<S-Right>', 1, 2)
  validate_move('axabxxab', '<S-Right>', 2, 3)
  validate_move('axabxxab', '<S-Right>', 3, 5)
  validate_move('axabxxab', '<S-Right>', 4, 5)
  validate_move('axabxxab', '<S-Right>', 5, 7)
  validate_move('axabxxab', '<S-Right>', 6, 7)
  if child.fn.has('nvim-0.10') == 1 then
    validate_move('axabxxab', '<S-Right>', 7, 9)
    validate_move('axabxxab', '<S-Right>', 8, 9)
    validate_move('axabxxab', '<S-Right>', 9, 9)
  end

  -- - Can work with multibyte characters
  child.cmd('set iskeyword&')
  validate_move('фя  фtя  ', '<S-Left>', 2, 1)
  validate_move('фя  фtя  ', '<S-Left>', 3, 1)
  validate_move('фя  фtя  ', '<S-Left>', 5, 3)
  validate_move('фя  фtя  ', '<S-Left>', 6, 5)
  validate_move('фя  фtя  ', '<S-Left>', 7, 5)
  validate_move('фя  фtя  ', '<S-Left>', 8, 5)
  validate_move('фя  фtя  ', '<S-Left>', 10, 8)

  validate_move('фя  фtя  ', '<S-Right>', 1, 3)
  validate_move('фя  фtя  ', '<S-Right>', 2, 3)
  validate_move('фя  фtя  ', '<S-Right>', 3, 5)
  validate_move('фя  фtя  ', '<S-Right>', 4, 5)
  validate_move('фя  фtя  ', '<S-Right>', 5, 8)
  validate_move('фя  фtя  ', '<S-Right>', 6, 8)
  validate_move('фя  фtя  ', '<S-Right>', 7, 8)

  -- Home/End
  validate_move('ab', '<Home>', 1, 1)
  validate_move('ab', '<Home>', 2, 1)
  validate_move('ab', '<Home>', 3, 1)
  validate_move('ab', '<C-b>', 1, 1)
  validate_move('ab', '<C-b>', 2, 1)
  validate_move('ab', '<C-b>', 3, 1)

  validate_move('ab', '<End>', 1, 3)
  validate_move('ab', '<End>', 2, 3)
  validate_move('ab', '<End>', 3, 3)
  validate_move('ab', '<C-e>', 1, 3)
  validate_move('ab', '<C-e>', 2, 3)
  validate_move('ab', '<C-e>', 3, 3)
end

T['default_key()']['can delete'] = function() MiniTest.skip() end

T['default_key()']['supports <C-k>'] = function() MiniTest.skip() end

T['default_key()']['supports <C-r>'] = function() MiniTest.skip() end

T['default_key()']['supports <C-v>/<C-q>'] = function() MiniTest.skip() end

T['default_key()']['can complete with state method'] = function()
  -- Regular

  -- Should preserve changes to `state.data` made by complete handler
  MiniTest.skip()
end

T['default_key()']['can complete history'] = function()
  -- Regular

  -- Should preserve changes to `state.data` made by complete handler
  MiniTest.skip()
end

T['default_key()']['can change input scope'] = function() MiniTest.skip() end

T['default_key()']['can change view style'] = function() MiniTest.skip() end

T['default_key()']['can toggle hidden'] = function() MiniTest.skip() end

T['default_key()']['works with special keys'] = function()
  -- Should ignore combos, mouse click, mouse scroll wheel

  -- Should allow any whitespace, like <Space>, <C-j>, and <C-l>

  -- Should allow more than one character
  MiniTest.skip()
end

T['default_key()']['respects `opts.autopair`'] = function() MiniTest.skip() end

T['default_highlight()'] = new_set()

T['default_highlight()']['works'] = function() MiniTest.skip() end

T['default_view()'] = new_set()

T['default_view()']['works'] = function() MiniTest.skip() end

T['default_complete()'] = new_set()

T['default_complete()']['works'] = function() MiniTest.skip() end

T['default_complete()']['correctly computes base'] = function()
  -- Method 'cmdline':
  -- `:e /path/to/` should be usable
  MiniTest.skip()
end

T['state_to_chunks()'] = new_set()

local state_to_chunks = function(state, max_width, opts)
  mock_state(state)
  child.lua('_G.max_width = ' .. vim.inspect(max_width))
  child.lua('_G.opts = ' .. vim.inspect(opts))
  return child.lua_get('MiniInput.state_to_chunks(_G.mock_state, _G.max_width, _G.opts)')
end

local with_prompt_chunks = function(chunks, prompt)
  return vim.list_extend({ { prompt or 'Input', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' } }, chunks)
end

local caret_ch = { '▏', 'MiniInputCaret' }

T['state_to_chunks()']['works'] = function()
  local validate = function(input, caret, ref)
    eq(state_to_chunks({ input = input, caret = caret }), with_prompt_chunks(ref))
  end

  validate('', 1, { caret_ch })
  validate('a', 2, { { 'a', 'MiniInputNormal' }, caret_ch })
  validate('a', 1, { caret_ch, { 'a', 'MiniInputNormal' } })
  validate('ab', 3, { { 'ab', 'MiniInputNormal' }, caret_ch })
  validate('ab', 2, { { 'a', 'MiniInputNormal' }, caret_ch, { 'b', 'MiniInputNormal' } })
  validate('ab', 1, { caret_ch, { 'ab', 'MiniInputNormal' } })

  -- Multibyte characters
  validate('ф🬗', 3, { { 'ф🬗', 'MiniInputNormal' }, caret_ch })
  validate('ф🬗', 2, { { 'ф', 'MiniInputNormal' }, caret_ch, { '🬗', 'MiniInputNormal' } })
  validate('ф🬗', 1, { caret_ch, { 'ф🬗', 'MiniInputNormal' } })

  -- Double-width characters
  validate('「」', 3, { { '「」', 'MiniInputNormal' }, caret_ch })
  validate('「」', 2, { { '「', 'MiniInputNormal' }, caret_ch, { '」', 'MiniInputNormal' } })
  validate('「」', 1, { caret_ch, { '「」', 'MiniInputNormal' } })

  -- Should not include empty prompt
  eq(state_to_chunks({ input = '', caret = 1, opts = { prompt = '' } }), { caret_ch })
end

T['state_to_chunks()']['works with hidden input'] = function()
  local validate = function(input, caret, ref)
    eq(state_to_chunks({ input = input, caret = caret, opts = { hide = true } }), ref)
  end

  validate('', 1, { { 'Input', 'MiniInputHide' }, { ' ', 'MiniInputNormal' }, caret_ch })
  validate('a', 2, { { 'Input', 'MiniInputHide' }, { ' ', 'MiniInputNormal' }, { '•', 'MiniInputNormal' }, caret_ch })
  validate('a', 1, { { 'Input', 'MiniInputHide' }, { ' ', 'MiniInputNormal' }, caret_ch, { '•', 'MiniInputNormal' } })
end

T['state_to_chunks()']['works with `state.highlight`'] = function()
  local validate = function(ranges, caret, ref)
    local highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, ranges)
    eq(state_to_chunks({ input = 'abcdefghij', caret = caret, highlight = highlight }), with_prompt_chunks(ref))
  end

  local ref = { { 'a', 'AA' }, { 'bcdefghij', 'MiniInputNormal' }, caret_ch }
  validate({ { 1, 1, 'AA' } }, nil, ref)

  ref = { { 'a', 'AA' }, { 'bc', 'BB' }, { 'de', 'CC' }, { 'fghij', 'MiniInputNormal' }, caret_ch }
  validate({ { 1, 1, 'AA' }, { 2, 3, 'BB' }, { 4, 5, 'CC' } }, nil, ref)
  validate({ { 2, 3, 'BB' }, { 4, 5, 'CC' }, { 1, 1, 'AA' } }, nil, ref)
  validate({ { 4, 5, 'CC' }, { 2, 3, 'BB' }, { 1, 1, 'AA' } }, nil, ref)

  -- Should work with inside caret
  validate({ { 1, 1, 'AA' } }, 1, { caret_ch, { 'a', 'AA' }, { 'bcdefghij', 'MiniInputNormal' } })
  validate({ { 1, 2, 'AA' } }, 1, { caret_ch, { 'ab', 'AA' }, { 'cdefghij', 'MiniInputNormal' } })

  ref = { { 'a', 'AA' }, caret_ch, { 'b', 'AA' }, { 'cdefghij', 'MiniInputNormal' } }
  validate({ { 1, 2, 'AA' } }, 2, ref)
  ref = { { 'ab', 'AA' }, caret_ch, { 'cdefghij', 'MiniInputNormal' } }
  validate({ { 1, 2, 'AA' } }, 3, ref)

  ref = { { 'ab', 'AA' }, caret_ch, { 'cd', 'BB' }, { 'efghij', 'MiniInputNormal' } }
  validate({ { 1, 2, 'AA' }, { 3, 4, 'BB' } }, 3, ref)
  ref = { { 'ab', 'AA' }, { 'c', 'BB' }, caret_ch, { 'd', 'BB' }, { 'efghij', 'MiniInputNormal' } }
  validate({ { 1, 2, 'AA' }, { 3, 4, 'BB' } }, 4, ref)
  ref = { { 'ab', 'AA' }, { 'cd', 'BB' }, caret_ch, { 'efghij', 'MiniInputNormal' } }
  validate({ { 1, 2, 'AA' }, { 3, 4, 'BB' } }, 5, ref)

  -- Gaps from not full coverage should be filled with 'MiniInputNormal'
  --stylua: ignore
  ref = {
    { 'a', 'MiniInputNormal' }, { 'bc', 'AA' }, { 'de', 'MiniInputNormal' }, { 'f', 'BB' },
    { 'ghij', 'MiniInputNormal' },
    caret_ch,
  }
  validate({ { 2, 3, 'AA' }, { 6, 6, 'BB' } }, nil, ref)

  -- Should allow `to = math.huge`
  mock_state({ input = 'abc', caret = 4 })
  -- NOTE: Set `math.huge` explicitly as `vim.inpsect()` translates it into `info`
  child.lua('_G.mock_state.highlight = { { from = 2, to = math.huge, hl = "AA" } }')
  ref = with_prompt_chunks({ { 'a', 'MiniInputNormal' }, { 'bc', 'AA' }, caret_ch })
  eq(child.lua_get('MiniInput.state_to_chunks(_G.mock_state)'), ref)
end

T['state_to_chunks()']['handles highlight overlap'] = function()
  -- All combinations of overlapping ranges should work
  -- Later chunks should be applied "on top" on the normalized previous ones
  local validate_overlap = function(ranges, ref_ranges)
    local input = 'abcdefghij'
    local ref_chunks, max_to = {}, 0
    for i, r in ipairs(ref_ranges) do
      ref_chunks[i] = { input:sub(r[1], r[2]), r[3] }
      max_to = math.max(max_to, r[2])
    end
    local rest = string.sub(input, max_to + 1)
    if rest ~= '' then table.insert(ref_chunks, { rest, 'MiniInputNormal' }) end
    vim.list_extend(ref_chunks, { caret_ch })
    ref_chunks = with_prompt_chunks(ref_chunks)

    local highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, ranges)
    eq(state_to_chunks({ input = input, caret = 11, highlight = highlight }), ref_chunks)
  end

  -- - Intersect
  validate_overlap(
    { { 1, 4, 'AA' }, { 3, 6, 'BB' }, { 5, 7, 'CC' } },
    { { 1, 2, 'AA' }, { 3, 4, 'BB' }, { 5, 7, 'CC' } }
  )
  validate_overlap(
    { { 1, 2, 'AA' }, { 2, 3, 'BB' }, { 3, 4, 'CC' } },
    { { 1, 1, 'AA' }, { 2, 2, 'BB' }, { 3, 4, 'CC' } }
  )

  -- - Split
  validate_overlap({ { 1, 4, 'AA' }, { 2, 3, 'BB' } }, { { 1, 1, 'AA' }, { 2, 3, 'BB' }, { 4, 4, 'AA' } })
  validate_overlap({ { 1, 4, 'AA' }, { 1, 3, 'BB' } }, { { 1, 3, 'BB' }, { 4, 4, 'AA' } })
  validate_overlap({ { 1, 4, 'AA' }, { 2, 4, 'BB' } }, { { 1, 1, 'AA' }, { 2, 4, 'BB' } })
  validate_overlap({ { 1, 4, 'AA' }, { 1, 4, 'BB' } }, { { 1, 4, 'BB' } })

  validate_overlap({ { 1, 3, 'AA' }, { 2, 2, 'BB' } }, { { 1, 1, 'AA' }, { 2, 2, 'BB' }, { 3, 3, 'AA' } })
  validate_overlap({ { 1, 3, 'AA' }, { 1, 1, 'BB' } }, { { 1, 1, 'BB' }, { 2, 3, 'AA' } })
  validate_overlap({ { 1, 3, 'AA' }, { 3, 3, 'BB' } }, { { 1, 2, 'AA' }, { 3, 3, 'BB' } })
  validate_overlap({ { 1, 1, 'AA' }, { 1, 1, 'BB' } }, { { 1, 1, 'BB' } })

  -- - Cover
  validate_overlap({ { 2, 3, 'AA' }, { 1, 4, 'BB' } }, { { 1, 4, 'BB' } })

  -- - Mix
  validate_overlap(
    { { 1, 2, 'AA' }, { 1, 3, 'BB' }, { 2, 4, 'CC' }, { 3, 5, 'DD' }, { 5, 5, 'EE' } },
    { { 1, 1, 'BB' }, { 2, 2, 'CC' }, { 3, 4, 'DD' }, { 5, 5, 'EE' } }
  )
  validate_overlap(
    { { 1, 6, 'AA' }, { 3, 8, 'BB' }, { 5, 9, 'CC' } },
    { { 1, 2, 'AA' }, { 3, 4, 'BB' }, { 5, 9, 'CC' } }
  )
end

T['state_to_chunks()']['works with `state.highlight` and multibyte input'] = function()
  local validate_one = function(input, ranges, caret, ref)
    local highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, ranges)
    eq(state_to_chunks({ input = input, caret = caret, highlight = highlight }), with_prompt_chunks(ref))
  end

  local validate = function(char_1, char_2)
    local input = char_1 .. char_2
    validate_one(input, { { 1, 2, 'AA' } }, 3, { { input, 'AA' }, caret_ch })
    validate_one(input, { { 1, 2, 'AA' } }, 2, { { char_1, 'AA' }, caret_ch, { char_2, 'AA' } })
    validate_one(input, { { 1, 2, 'AA' } }, 1, { caret_ch, { input, 'AA' } })

    validate_one(input, { { 1, 1, 'AA' }, { 2, 2, 'BB' } }, 3, { { char_1, 'AA' }, { char_2, 'BB' }, caret_ch })
    validate_one(input, { { 1, 1, 'AA' }, { 2, 2, 'BB' } }, 2, { { char_1, 'AA' }, caret_ch, { char_2, 'BB' } })
    validate_one(input, { { 1, 1, 'AA' }, { 2, 2, 'BB' } }, 1, { caret_ch, { char_1, 'AA' }, { char_2, 'BB' } })

    validate_one(input, { { 1, 1, 'AA' } }, 3, { { char_1, 'AA' }, { char_2, 'MiniInputNormal' }, caret_ch })
    validate_one(input, { { 2, 2, 'AA' } }, 3, { { char_1, 'MiniInputNormal' }, { char_2, 'AA' }, caret_ch })
    validate_one(input, { { 2, 2, 'AA' } }, 2, { { char_1, 'MiniInputNormal' }, caret_ch, { char_2, 'AA' } })
    validate_one(input, { { 2, 2, 'AA' } }, 1, { caret_ch, { char_1, 'MiniInputNormal' }, { char_2, 'AA' } })
  end

  -- Multibyte characters
  validate('ф', '🬗')

  -- Double-width characters
  validate('「', '」')
end

T['state_to_chunks()']['normalizes highlight ranges'] = function()
  local validate = function(ranges, ref)
    local highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, ranges)
    ref = with_prompt_chunks(ref)
    table.insert(ref, caret_ch)
    eq(state_to_chunks({ input = 'abcd', caret = 5, highlight = highlight }), ref)
  end

  -- Ranges completely outside should be ignored
  validate({ { -2, 0, 'UU' }, { 1, 2, 'AA' }, { 5, 10, 'VV' } }, { { 'ab', 'AA' }, { 'cd', 'MiniInputNormal' } })

  -- Ranges partially outside should be clamped to edges
  validate({ { -2, 1, 'AA' }, { 4, 10, 'BB' } }, { { 'a', 'AA' }, { 'bc', 'MiniInputNormal' }, { 'd', 'BB' } })
  validate({ { -2, 2, 'AA' }, { 3, 10, 'BB' } }, { { 'ab', 'AA' }, { 'cd', 'BB' } })
end

T['state_to_chunks()']['works with `state.complete`'] = function()
  local validate = function(id, caret, ref)
    local complete = { base = 'cd', items = { 'cdu', 'cdv' }, id = id, method = '' }
    eq(state_to_chunks({ input = 'abcd', caret = caret, complete = complete }), with_prompt_chunks(ref))
  end

  validate(0, 5, { { 'abcd', 'MiniInputNormal' }, caret_ch, { '(0/2)', 'MiniInputHint' } })
  validate(1, 5, { { 'abcd', 'MiniInputNormal' }, caret_ch, { '(1/2)', 'MiniInputHint' } })
  validate(2, 5, { { 'abcd', 'MiniInputNormal' }, caret_ch, { '(2/2)', 'MiniInputHint' } })

  validate(0, 4, { { 'abc', 'MiniInputNormal' }, caret_ch, { '(0/2)', 'MiniInputHint' }, { 'd', 'MiniInputNormal' } })
  validate(1, 4, { { 'abc', 'MiniInputNormal' }, caret_ch, { '(1/2)', 'MiniInputHint' }, { 'd', 'MiniInputNormal' } })
  validate(0, 1, { caret_ch, { '(0/2)', 'MiniInputHint' }, { 'abcd', 'MiniInputNormal' } })
  validate(1, 1, { caret_ch, { '(1/2)', 'MiniInputHint' }, { 'abcd', 'MiniInputNormal' } })

  -- Method should not matter
  local complete = { base = 'cd', items = { 'cdu', 'cdv' }, id = 0, method = 'custom' }
  local ref = { { 'abcd', 'MiniInputNormal' }, caret_ch, { '(0/2)', 'MiniInputHint' } }
  eq(state_to_chunks({ input = 'abcd', complete = complete }), with_prompt_chunks(ref))
end

T['state_to_chunks()']['works with `state.highlight` and `state.complete`'] = function()
  local validate = function(ranges, caret, ref)
    local complete = { base = 'cd', items = { 'cdu', 'cdv' }, id = 1, method = '' }
    local highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, ranges)

    local state = { input = 'abcdu', caret = caret, complete = complete, highlight = highlight }
    eq(state_to_chunks(state), with_prompt_chunks(ref))
  end

  validate({ { 1, 5, 'AA' } }, 6, { { 'abcdu', 'AA' }, caret_ch, { '(1/2)', 'MiniInputHint' } })
  validate({ { 1, 5, 'AA' } }, 5, { { 'abcd', 'AA' }, caret_ch, { '(1/2)', 'MiniInputHint' }, { 'u', 'AA' } })
  validate({ { 1, 5, 'AA' } }, 1, { caret_ch, { '(1/2)', 'MiniInputHint' }, { 'abcdu', 'AA' } })

  local ref = { { 'abcd', 'MiniInputNormal' }, { 'u', 'AA' }, caret_ch, { '(1/2)', 'MiniInputHint' } }
  validate({ { 5, 5, 'AA' } }, 6, ref)
  ref = { { 'abcd', 'MiniInputNormal' }, caret_ch, { '(1/2)', 'MiniInputHint' }, { 'u', 'AA' } }
  validate({ { 5, 5, 'AA' } }, 5, ref)

  -- Complex highlight
  ref = { { 'a', 'BB' }, { 'b', 'CC' }, caret_ch, { '(1/2)', 'MiniInputHint' }, { 'cd', 'CC' }, { 'u', 'AA' } }
  validate({ { 1, 5, 'AA' }, { 1, 3, 'BB' }, { 2, 4, 'CC' } }, 3, ref)
end

T['state_to_chunks()']['respects `max_width`'] = function()
  local validate = function(max_width, ref)
    eq(state_to_chunks({ input = 'def', opts = { prompt = 'ABC' } }, max_width), ref)
  end

  validate(8, { { 'ABC', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'def', 'MiniInputNormal' }, caret_ch })
  validate(7, { { 'BC', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'def', 'MiniInputNormal' }, caret_ch })
  validate(6, { { 'C', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'def', 'MiniInputNormal' }, caret_ch })
  validate(5, { { ' ', 'MiniInputNormal' }, { 'def', 'MiniInputNormal' }, caret_ch })
  validate(4, { { 'def', 'MiniInputNormal' }, caret_ch })
  validate(3, { { 'ef', 'MiniInputNormal' }, caret_ch })
  validate(2, { { 'f', 'MiniInputNormal' }, caret_ch })
  validate(1, { caret_ch })

  -- Can be big values
  local full = { { 'ABC', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'def', 'MiniInputNormal' }, caret_ch }
  validate(100, full)

  mock_state({ input = 'def', opts = { prompt = 'ABC' } })
  eq(child.lua_get('MiniInput.state_to_chunks(_G.mock_state, math.huge)'), full)
end

T['state_to_chunks()']['truncates with centered caret'] = function()
  local validate = function(caret, ref)
    eq(state_to_chunks({ input = 'bcdefg', caret = caret, opts = { prompt = 'A' } }, 5), ref)
  end

  validate(7, { { 'defg', 'MiniInputNormal' }, caret_ch })
  validate(6, { { 'def', 'MiniInputNormal' }, caret_ch, { 'g', 'MiniInputNormal' } })
  validate(5, { { 'de', 'MiniInputNormal' }, caret_ch, { 'fg', 'MiniInputNormal' } })
  validate(4, { { 'cd', 'MiniInputNormal' }, caret_ch, { 'ef', 'MiniInputNormal' } })
  validate(3, { { 'bc', 'MiniInputNormal' }, caret_ch, { 'de', 'MiniInputNormal' } })
  validate(2, { { ' ', 'MiniInputNormal' }, { 'b', 'MiniInputNormal' }, caret_ch, { 'cd', 'MiniInputNormal' } })
  validate(1, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { 'bc', 'MiniInputNormal' } })

  -- Works with even maximum width
  validate = function(caret, ref)
    eq(state_to_chunks({ input = 'bcdefg', caret = caret, opts = { prompt = 'A' } }, 6), ref)
  end

  validate(7, { { 'cdefg', 'MiniInputNormal' }, caret_ch })
  validate(6, { { 'cdef', 'MiniInputNormal' }, caret_ch, { 'g', 'MiniInputNormal' } })
  validate(5, { { 'cde', 'MiniInputNormal' }, caret_ch, { 'fg', 'MiniInputNormal' } })
  validate(4, { { 'cd', 'MiniInputNormal' }, caret_ch, { 'efg', 'MiniInputNormal' } })
  validate(3, { { 'bc', 'MiniInputNormal' }, caret_ch, { 'def', 'MiniInputNormal' } })
  validate(2, { { ' ', 'MiniInputNormal' }, { 'b', 'MiniInputNormal' }, caret_ch, { 'cde', 'MiniInputNormal' } })
  validate(1, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { 'bcd', 'MiniInputNormal' } })
end

T['state_to_chunks()']['truncates with multibyte characters'] = function()
  local validate = function(caret, ref)
    eq(state_to_chunks({ input = 'xф「🬗」', caret = caret, opts = { prompt = 'A' } }, 3), ref)
  end

  validate(6, { { '🬗」', 'MiniInputNormal' }, caret_ch })
  validate(5, { { '🬗', 'MiniInputNormal' }, caret_ch, { '」', 'MiniInputNormal' } })
  validate(4, { { '「', 'MiniInputNormal' }, caret_ch, { '🬗', 'MiniInputNormal' } })
  validate(3, { { 'ф', 'MiniInputNormal' }, caret_ch, { '「', 'MiniInputNormal' } })
  validate(2, { { 'x', 'MiniInputNormal' }, caret_ch, { 'ф', 'MiniInputNormal' } })
  validate(1, { { ' ', 'MiniInputNormal' }, caret_ch, { 'x', 'MiniInputNormal' } })
end

T['state_to_chunks()']['truncates to with `state.highlight` and `state.complete`'] = function()
  local state = {}
  local validate = function(caret, max_width, ref)
    local st = vim.deepcopy(state)
    st.caret = caret
    eq(state_to_chunks(st, max_width), ref)
  end

  -- With `state.highlight`
  state = { input = 'bcd', opts = { prompt = 'A' } }
  state.highlight = { { from = 1, to = 2, hl = 'AA' }, { from = 3, to = 3, hl = 'BB' } }

  validate(4, 6, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'bc', 'AA' }, { 'd', 'BB' }, caret_ch })
  validate(3, 6, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'bc', 'AA' }, caret_ch, { 'd', 'BB' } })
  --stylua: ignore
  validate(2, 6, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'b', 'AA' }, caret_ch, { 'c', 'AA' }, { 'd', 'BB' } })
  validate(1, 6, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { 'bc', 'AA' }, { 'd', 'BB' } })

  validate(4, 4, { { 'bc', 'AA' }, { 'd', 'BB' }, caret_ch })
  validate(4, 3, { { 'c', 'AA' }, { 'd', 'BB' }, caret_ch })
  validate(4, 2, { { 'd', 'BB' }, caret_ch })
  validate(4, 1, { caret_ch })

  validate(3, 4, { { 'bc', 'AA' }, caret_ch, { 'd', 'BB' } })
  validate(3, 3, { { 'c', 'AA' }, caret_ch, { 'd', 'BB' } })
  validate(3, 2, { caret_ch, { 'd', 'BB' } })
  validate(3, 1, { caret_ch })

  validate(2, 4, { { 'b', 'AA' }, caret_ch, { 'c', 'AA' }, { 'd', 'BB' } })
  validate(2, 3, { { 'b', 'AA' }, caret_ch, { 'c', 'AA' } })
  validate(2, 2, { caret_ch, { 'c', 'AA' } })
  validate(2, 1, { caret_ch })

  validate(1, 4, { { ' ', 'MiniInputNormal' }, caret_ch, { 'bc', 'AA' } })
  validate(1, 3, { { ' ', 'MiniInputNormal' }, caret_ch, { 'b', 'AA' } })
  validate(1, 2, { caret_ch, { 'b', 'AA' } })
  validate(1, 1, { caret_ch })

  -- With `state.complete`
  state = { input = 'bcd', opts = { prompt = 'A' } }
  state.complete = { base = '', items = { 'u' }, id = 0, method = '' }

  validate(4, 10, { { ' ', 'MiniInputNormal' }, { 'bcd', 'MiniInputNormal' }, caret_ch, { '(0/1)', 'MiniInputHint' } })
  --stylua: ignore
  validate(3, 10, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'bc', 'MiniInputNormal' }, caret_ch, { '(0/1)', 'MiniInputHint' } })
  --stylua: ignore
  validate(2, 10, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'b', 'MiniInputNormal' }, caret_ch, { '(0/1)', 'MiniInputHint' }, { 'c', 'MiniInputNormal' } })
  --stylua: ignore
  validate(1, 10, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { '(0/1)', 'MiniInputHint' }, { 'bc', 'MiniInputNormal' }, })

  validate(4, 9, { { ' ', 'MiniInputNormal' }, { 'bcd', 'MiniInputNormal' }, caret_ch, { '(0/1', 'MiniInputHint' } })
  validate(4, 8, { { 'bcd', 'MiniInputNormal' }, caret_ch, { '(0/1', 'MiniInputHint' } })
  validate(4, 7, { { 'bcd', 'MiniInputNormal' }, caret_ch, { '(0/', 'MiniInputHint' } })
  validate(4, 6, { { 'cd', 'MiniInputNormal' }, caret_ch, { '(0/', 'MiniInputHint' } })
  validate(4, 5, { { 'cd', 'MiniInputNormal' }, caret_ch, { '(0', 'MiniInputHint' } })
  validate(4, 4, { { 'd', 'MiniInputNormal' }, caret_ch, { '(0', 'MiniInputHint' } })
  validate(4, 3, { { 'd', 'MiniInputNormal' }, caret_ch, { '(', 'MiniInputHint' } })
  validate(4, 2, { caret_ch, { '(', 'MiniInputHint' } })
  validate(4, 1, { caret_ch })

  validate(3, 5, { { 'bc', 'MiniInputNormal' }, caret_ch, { '(0', 'MiniInputHint' } })
  validate(2, 5, { { ' ', 'MiniInputNormal' }, { 'b', 'MiniInputNormal' }, caret_ch, { '(0', 'MiniInputHint' } })
  validate(1, 5, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { '(0', 'MiniInputHint' } })

  -- With both `state.highlight` and `state.complete`
  state = { input = 'bcd', opts = { prompt = 'A' } }
  state.highlight = { { from = 1, to = 2, hl = 'AA' }, { from = 3, to = 3, hl = 'BB' } }
  state.complete = { base = '', items = { 'u' }, id = 0, method = '' }
  validate(2, 3, { { 'b', 'AA' }, caret_ch, { '(', 'MiniInputHint' } })
end

T['state_to_chunks()']['truncates to width in special cases'] = function()
  local state = {}
  local validate = function(caret, max_width, ref)
    local st = vim.deepcopy(state)
    st.caret = caret
    eq(state_to_chunks(st, max_width), ref)
  end

  -- With translated special keys
  state = { input = '\n\ra\t\f\3', opts = { prompt = 'A' } }

  validate(7, 9, { { '-L><C-C>', 'MiniInputSpecial' }, caret_ch })
  validate(6, 9, { { 'C-L>', 'MiniInputSpecial' }, caret_ch, { '<C-C', 'MiniInputSpecial' } })
  validate(5, 9, { { 'Tab>', 'MiniInputSpecial' }, caret_ch, { '<C-L', 'MiniInputSpecial' } })
  --stylua: ignore
  validate(4, 9, { { 'CR>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, caret_ch, { '<Tab', 'MiniInputSpecial' } })
  --stylua: ignore
  validate(3, 9, { { '<CR>', 'MiniInputSpecial' }, caret_ch, { 'a', 'MiniInputNormal' }, { '<Ta', 'MiniInputSpecial' } })
  validate(2, 9, { { '<NL>', 'MiniInputSpecial' }, caret_ch, { '<CR>', 'MiniInputSpecial' } })
  --stylua: ignore
  validate(1, 9, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { '<NL><C', 'MiniInputSpecial' }, })

  validate(4, 8, { { 'R>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, caret_ch, { '<Tab', 'MiniInputSpecial' } })
  validate(4, 7, { { 'R>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, caret_ch, { '<Ta', 'MiniInputSpecial' } })
  validate(4, 6, { { '>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, caret_ch, { '<Ta', 'MiniInputSpecial' } })
  validate(4, 5, { { '>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, caret_ch, { '<T', 'MiniInputSpecial' } })
  validate(4, 4, { { 'a', 'MiniInputNormal' }, caret_ch, { '<T', 'MiniInputSpecial' } })
  validate(4, 3, { { 'a', 'MiniInputNormal' }, caret_ch, { '<', 'MiniInputSpecial' } })
  validate(4, 2, { caret_ch, { '<', 'MiniInputSpecial' } })
  validate(4, 1, { caret_ch })

  -- Empty prompt
  state = { input = 'bc', opts = { prompt = '' } }
  validate(3, 3, { { 'bc', 'MiniInputNormal' }, caret_ch })
  validate(2, 3, { { 'b', 'MiniInputNormal' }, caret_ch, { 'c', 'MiniInputNormal' } })
  validate(1, 3, { caret_ch, { 'bc', 'MiniInputNormal' } })

  state.input = ''
  validate(1, 3, { caret_ch })

  -- Multicharacter caret symbol
  local validate_multichar_caret = function(max_width, ref)
    eq(state_to_chunks(state, max_width, { symbol_caret = 'UVW' }), ref)
  end

  state = { input = 'bcd', caret = 4, opts = { prompt = 'A' } }
  local ref = { { 'bcd', 'MiniInputNormal' }, { 'UVW', 'MiniInputCaret' } }
  validate_multichar_caret(10, with_prompt_chunks(ref, 'A'))

  validate_multichar_caret(4, { { 'd', 'MiniInputNormal' }, { 'UVW', 'MiniInputCaret' } })
  validate_multichar_caret(3, { { 'UVW', 'MiniInputCaret' } })
  validate_multichar_caret(2, { { 'VW', 'MiniInputCaret' } })
  validate_multichar_caret(1, { { 'W', 'MiniInputCaret' } })

  state.caret = 3
  ref = { { 'bc', 'MiniInputNormal' }, { 'UVW', 'MiniInputCaret' }, { 'd', 'MiniInputNormal' } }
  validate_multichar_caret(10, with_prompt_chunks(ref, 'A'))

  ref = { { 'c', 'MiniInputNormal' }, { 'UVW', 'MiniInputCaret' }, { 'd', 'MiniInputNormal' } }
  validate_multichar_caret(5, ref)
  validate_multichar_caret(4, { { 'UVW', 'MiniInputCaret' }, { 'd', 'MiniInputNormal' } })
  validate_multichar_caret(3, { { 'VW', 'MiniInputCaret' }, { 'd', 'MiniInputNormal' } })
  validate_multichar_caret(2, { { 'W', 'MiniInputCaret' }, { 'd', 'MiniInputNormal' } })
  validate_multichar_caret(1, { { 'W', 'MiniInputCaret' } })
end

T['state_to_chunks()']['respects `opts.keytrans`'] = function()
  local validate = function(input, caret, ref) eq(state_to_chunks({ input = input, caret = caret }), ref) end

  -- Should translate special control characters
  local ref = with_prompt_chunks({ { '<NL><CR><Tab><C-C><C-V>', 'MiniInputSpecial' }, caret_ch })
  validate('\n\r\t\3\22', 6, ref)

  -- Should place caret between translated characters
  validate('\n\r\t', 4, with_prompt_chunks({ { '<NL><CR><Tab>', 'MiniInputSpecial' }, caret_ch }))
  ref = with_prompt_chunks({ { '<NL><CR>', 'MiniInputSpecial' }, caret_ch, { '<Tab>', 'MiniInputSpecial' } })
  validate('\n\r\t', 3, ref)
  ref = with_prompt_chunks({ { '<NL>', 'MiniInputSpecial' }, caret_ch, { '<CR><Tab>', 'MiniInputSpecial' } })
  validate('\n\r\t', 2, ref)
  validate('\n\r\t', 1, with_prompt_chunks({ caret_ch, { '<NL><CR><Tab>', 'MiniInputSpecial' } }))

  -- Should properly detect control characters
  ref = { { 'a', 'MiniInputNormal' }, { '<Tab>', 'MiniInputSpecial' }, { 'b', 'MiniInputNormal' }, caret_ch }
  validate('a\tb', 4, with_prompt_chunks(ref))
  ref = { { '<CR>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, { '<NL>', 'MiniInputSpecial' }, caret_ch }
  validate('\ra\n', 4, with_prompt_chunks(ref))
end

T['state_to_chunks()']['respects `opts.include_prompt`'] = function()
  eq(state_to_chunks({}, nil, { include_prompt = false }), { caret_ch })
  eq(state_to_chunks({ input = 'abc' }, nil, { include_prompt = false }), { { 'abc', 'MiniInputNormal' }, caret_ch })
end

T['state_to_chunks()']['respects `opts.include_hint`'] = function()
  local state = { complete = { base = '', items = { 'a', 'b' }, id = 0, method = '' } }
  eq(state_to_chunks(state, nil, { include_hint = false }), with_prompt_chunks({ caret_ch }))
end

T['state_to_chunks()']['respects `opts.symbol_caret`'] = function()
  local state = { input = 'ab', caret = 2 }
  local validate = function(symbol_caret)
    local ref = { { 'a', 'MiniInputNormal' }, { symbol_caret, 'MiniInputCaret' }, { 'b', 'MiniInputNormal' } }
    eq(state_to_chunks(state, nil, { symbol_caret = symbol_caret }), with_prompt_chunks(ref))
  end

  -- Regular
  validate('_')
  validate('│')

  -- Double-width
  validate('「')

  -- Multicharacter
  validate('!@#')

  -- Empty
  local ref = with_prompt_chunks({ { 'a', 'MiniInputNormal' }, { 'b', 'MiniInputNormal' } })
  eq(state_to_chunks(state, nil, { symbol_caret = '' }), ref)
end

T['state_to_chunks()']['respects `opts.symbol_hide`'] = function()
  local validate_one = function(caret, symbol_hide, ref)
    local state = { input = 'ab', caret = caret, opts = { hide = true } }
    eq(state_to_chunks(state, nil, { symbol_hide = symbol_hide }), ref)
  end

  local validate = function(symbol_hide)
    local prompt, pad = { 'Input', 'MiniInputHide' }, { ' ', 'MiniInputNormal' }
    validate_one(3, symbol_hide, { prompt, pad, { symbol_hide .. symbol_hide, 'MiniInputNormal' }, caret_ch })
    --stylua: ignore
    local ref = { prompt, pad, { symbol_hide, 'MiniInputNormal' }, caret_ch, { symbol_hide, 'MiniInputNormal' } }
    validate_one(2, symbol_hide, ref)
    validate_one(1, symbol_hide, { prompt, pad, caret_ch, { symbol_hide .. symbol_hide, 'MiniInputNormal' } })
  end

  -- Regular
  validate('_')

  -- Double-width
  validate('「')

  -- Multicharacter
  validate('!@#')

  -- Empty
  local validate_empty = function(caret)
    local prompt, pad = { 'Input', 'MiniInputHide' }, { ' ', 'MiniInputNormal' }
    validate_one(caret, '', { prompt, pad, caret_ch })
  end

  validate_empty(3)
  validate_empty(2)
  validate_empty(1)
end

T['state_to_chunks()']['validates input'] = function()
  expect.error(function() child.lua('MiniInput.state_to_chunks(1)') end, '`state`.*table')

  mock_state({})
  expect.error(function() child.lua('MiniInput.state_to_chunks(_G.mock_state, "a")') end, '`max_width`.*number')

  local validate_opts = function(bad_opts, pattern)
    expect.error(function() state_to_chunks({}, nil, bad_opts) end, pattern)
  end

  validate_opts({ keytrans = 1 }, '`opts.keytrans`.*boolean')
  validate_opts({ include_prompt = 1 }, '`opts.include_prompt`.*boolean')
  validate_opts({ include_hint = 1 }, '`opts.include_hint`.*boolean')
  validate_opts({ symbol_caret = 1 }, '`opts.symbol_caret`.*string')
  validate_opts({ symbol_hide = 1 }, '`opts.symbol_hide`.*string')
end

return T
