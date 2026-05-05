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

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
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

T['setup()']['set `vim.ui.input`'] = function() MiniTest.skip() end

T['setup()']['adjusts `vim.paste`'] = function() MiniTest.skip() end

T['setup()']['hard-codes some default scope'] = function()
  -- `vim.lsp.buf.rename()`

  -- Should be possible to override with explicit `opts.scope` or via a key
  -- handler
  MiniTest.skip()
end

T['get()'] = new_set()

T['get()']['works'] = function() MiniTest.skip() end

T['get()']['reacts to `VimResized`'] = function() MiniTest.skip() end

T['ui_input()'] = new_set()

T['ui_input()']['works'] = function() MiniTest.skip() end

T['get_state()'] = new_set()

T['get_state()']['works'] = function() MiniTest.skip() end

T['get_history()'] = new_set()

T['get_history()']['works'] = function() MiniTest.skip() end

T['set_history()'] = new_set()

T['set_history()']['works'] = function() MiniTest.skip() end

T['refresh()'] = new_set()

T['refresh()']['works'] = function() MiniTest.skip() end

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

T['default_key()']['works'] = function() MiniTest.skip() end

T['default_highlight()'] = new_set()

T['default_highlight()']['works'] = function() MiniTest.skip() end

T['default_view()'] = new_set()

T['default_view()']['works'] = function() MiniTest.skip() end

T['default_complete()'] = new_set()

T['default_complete()']['works'] = function() MiniTest.skip() end

T['state_to_chunks()'] = new_set()

T['state_to_chunks()']['works'] = function() MiniTest.skip() end

return T
