local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('icons', config) end
local unload_module = function() child.mini_unload('icons') end
--stylua: ignore end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local get = function(...) return child.lua_get('{ MiniIcons.get(...) }', { ... }) end

-- Output test set ============================================================
local T = new_set({
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
  eq(child.lua_get('type(_G.MiniIcons)'), 'table')

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniIconsAzure', 'links to Function')
  has_highlight('MiniIconsBlue', 'links to DiagnosticInfo')
  has_highlight('MiniIconsCyan', 'links to DiagnosticHint')
  has_highlight('MiniIconsGreen', 'links to DiagnosticOk')
  has_highlight('MiniIconsGrey', 'cleared')
  has_highlight('MiniIconsOrange', 'links to DiagnosticWarn')
  has_highlight('MiniIconsPurple', 'links to Constant')
  has_highlight('MiniIconsRed', 'links to DiagnosticError')
  has_highlight('MiniIconsYellow', 'links to DiagnosticWarn')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniIcons.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniIcons.config.' .. field), value) end

  expect_config('style', 'glyph')

  expect_config('default', {})
  expect_config('directory', {})
  expect_config('extension', {})
  expect_config('file', {})
  expect_config('filetype', {})
  expect_config('lsp', {})
  expect_config('os', {})
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ style = 'ascii' })
  eq(child.lua_get('MiniIcons.config.style'), 'ascii')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ style = 1 }, 'style', 'string')
  expect_config_error({ default = 1 }, 'default', 'table')
  expect_config_error({ directory = 1 }, 'directory', 'table')
  expect_config_error({ extension = 1 }, 'extension', 'table')
  expect_config_error({ file = 1 }, 'file', 'table')
  expect_config_error({ filetype = 1 }, 'filetype', 'table')
  expect_config_error({ lsp = 1 }, 'lsp', 'table')
  expect_config_error({ os = 1 }, 'os', 'table')
end

T['setup()']['can customize icons'] = function()
  -- Both override existing and provide new ones
  load_module({
    default = {
      -- Can provide only customized attributes
      extension = { glyph = 'E' },
      file = { hl = 'AAA' },
    },
    directory = {
      my_dir = { glyph = 'D', hl = 'Directory' },
    },
  })

  eq(get('default', 'extension')[1], 'E')
  eq(get('default', 'file')[2], 'AAA')
  eq(get('directory', 'my_dir'), { 'D', 'Directory' })
end

T['setup()']['respects `config.style` when customizing icons'] = function()
  load_module({
    style = 'ascii',
    extension = { ext = { glyph = '󰻲', hl = 'MiniIconsRed' } },
  })

  eq(get('extension', 'ext'), { 'E', 'MiniIconsRed' })
end

T['setup()']['clears cache'] = function() MiniTest.skip() end

T['get()'] = new_set()

T['get()']['works with "default" category'] = function()
  eq(get('default', 'default'), { '󰟢', 'MiniIconsGrey' })
  eq(get('default', 'directory'), { '󰉋', 'MiniIconsAzure' })
  eq(get('default', 'extension'), { '󰈔', 'MiniIconsGrey' })
  eq(get('default', 'file'), { '󰈔', 'MiniIconsGrey' })
  eq(get('default', 'filetype'), { '󰈔', 'MiniIconsGrey' })
  eq(get('default', 'lsp'), { '󰞋', 'MiniIconsRed' })
  eq(get('default', 'os'), { '󰟀', 'MiniIconsPurple' })

  -- Can be customized
  load_module({
    default = {
      file = { glyph = '󱁂', hl = 'Comment' },
    },
  })
  eq(get('default', 'file'), { '󱁂', 'Comment' })

  -- Validates not supported category
  expect.error(function() get('default', 'aaa') end, 'aaa.*not.*category')
  MiniTest.skip()
end

T['get()']['works with "directory" category'] = function()
  -- Works

  -- Falls back to category default
  MiniTest.skip()
end

T['get()']['works with "extension" category'] = function()
  -- Works

  -- Can reuse "filetype" customization

  -- Falls back to category default
  MiniTest.skip()
end

T['get()']['works with "file" category'] = function()
  load_module({
    file = {
      myfile = { glyph = '󱁂', hl = 'AA' },
    },
    extension = {
      lua = { glyph = '', hl = 'LUA' },
      ['my.ext'] = { glyph = '󰻲', hl = 'MiniIconsRed' },
    },
  })

  -- Works

  -- Can reuse "extension" customization

  -- Can reuse complex "extension"

  -- Can reuse "filetype" customization

  -- Falls back to category default
  MiniTest.skip()
end

T['get()']['works with "filetype" category'] = function()
  -- Works

  -- Falls back to category default
  MiniTest.skip()
end

T['get()']['works with "lsp" category'] = function()
  -- Works

  -- Falls back to category default
  MiniTest.skip()
end

T['get()']['works with "os" category'] = function()
  -- Works

  -- Falls back to category default
  MiniTest.skip()
end

T['get()']['caches output'] = function() MiniTest.skip() end

T['get()']['respects `config.style`'] = function() MiniTest.skip() end

T['get()']['respects customizations in config'] = function() MiniTest.skip() end

T['get()']['validates arguments'] = function()
  expect.error(function() get(1, 'lua') end, 'category.*string')
  expect.error(function() get('file', 1) end, 'name.*string')

  expect.error(function() get('aaa', 'lua') end, 'aaa.*not.*category')
end

return T
