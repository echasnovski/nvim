local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local slash = helpers.is_windows() and '\\' or '/'

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('statuscolumn', config) end
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

-- Common validators
local validate_log = function(name, ref, preserve)
  eq(child.lua_get(name), ref)
  if not preserve then child.lua(name .. ' = {}') end
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
      child.o.winwidth = 1
      child.o.winminwidth = 1
    end,
    post_once = child.stop,
    n_retry = helpers.get_n_retry(1),
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniStatuscolumn)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniStatuscolumn'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  child.api.nvim_set_hl(0, 'LineNr', { fg = '#AAAAAA', bg = '#111111' })
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniStatuscolumnDim', 'guifg=#4b4b4b guibg=#111111')
  has_highlight('MiniStatuscolumnDimCursor', 'links to MiniStatuscolumnDim')
  has_highlight('MiniStatuscolumnSep', 'links to LineNr')
  has_highlight('MiniStatuscolumnSepCursor', 'links to CursorLineNr')

  -- Sets custom 'statuscolumn'
  expect.no_equality(child.o.statuscolumn, '')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniStatuscolumn.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniStatuscolumn.config.' .. field), value) end

  expect_config('content', {})
  expect_config('dim_inactive', true)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ content = 1 }, 'content', 'table')
  expect_config_error({ content = { active = 1 } }, 'content.active', 'function')
  expect_config_error({ content = { inactive = 1 } }, 'content.inactive', 'function')
  expect_config_error({ dim_inactive = 1 }, 'dim_inactive', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniStatuscolumnSep'), 'links to LineNr')
end

--stylua: ignore
T['setup()']['correctly computes dimmed highlight attributes'] = function()
  -- Should make effective foreground closer to the effective background.
  -- Should prefer attribute from `LineNr` with possible fall back to `Normal`.
  -- When not enough attribute info, should fall back to linkining to `LineNr`
  local validate = function(hl_linenr, hl_normal, hl_ref)
    child.cmd('hi clear')
    child.api.nvim_set_hl(0, 'LineNr', hl_linenr)
    child.api.nvim_set_hl(0, 'Normal', hl_normal)
    load_module()

    local ref = child.api.nvim_get_hl(0, { name = 'MiniStatuscolumnDim', link = true })
    if ref.fg then ref.fg = string.format('#%06x', ref.fg) end
    if ref.bg then ref.bg = string.format('#%06x', ref.bg) end
    eq(ref, hl_ref)
  end

  validate({ fg = '#656667', bg = '#010203' }, { fg = '#757677', bg = '#111213' }, { fg = '#272829', bg = '#010203' })
  validate({ fg = '#656667', bg = '#010203' }, { fg = '#757677',                }, { fg = '#272829', bg = '#010203' })
  validate({ fg = '#656667', bg = '#010203' }, {                 bg = '#111213' }, { fg = '#272829', bg = '#010203' })
  validate({ fg = '#656667', bg = '#010203' }, {                                }, { fg = '#272829', bg = '#010203' })

  validate({                 bg = '#010203' }, { fg = '#757677', bg = '#111213' }, { fg = '#2d2e2f', bg = '#010203' })
  validate({                 bg = '#010203' }, { fg = '#757677',                }, { fg = '#2d2e2f', bg = '#010203' })
  validate({                 bg = '#010203' }, {                 bg = '#111213' }, { link = 'LineNr' })
  validate({                 bg = '#010203' }, {                                }, { link = 'LineNr' })

  validate({ fg = '#656667',                }, { fg = '#757677', bg = '#111213' }, { fg = '#313233', bg = '#111213' })
  validate({ fg = '#656667',                }, { fg = '#757677',                }, { link = 'LineNr' })
  validate({ fg = '#656667',                }, {                 bg = '#111213' }, { fg = '#313233', bg = '#111213' })
  validate({ fg = '#656667',                }, {                                }, { link = 'LineNr' })

  validate({                                }, { fg = '#757677', bg = '#111213' }, { fg = '#373839', bg = '#111213' })
  validate({                                }, { fg = '#757677',                }, { link = 'LineNr' })
  validate({                                }, {                 bg = '#111213' }, { link = 'LineNr' })
  validate({                                }, {                                }, { link = 'LineNr' })

  -- Should recompute after changing color scheme
  child.cmd('hi clear')
  child.api.nvim_set_hl(0, 'LineNr', { fg = '#656565', bg = '#010101' })
  expect.match(child.cmd_capture('hi MiniStatuscolumnDim'), 'cleared')
  child.cmd('doautocmd ColorScheme')
  expect.match(child.cmd_capture('hi MiniStatuscolumnDim'), 'guifg=#272727 guibg=#010101')
end

T['gen_content'] = new_set()

T['gen_content']['main()'] = new_set()

T['gen_content']['main()']['works'] = function() MiniTest.skip() end

T['default_click()'] = new_set()

T['default_click()']['works'] = function() MiniTest.skip() end

-- Integration tests ==========================================================
local mock_dim_test_content = function()
  child.lua([[
    local make_content = function(win_type)
      return function()
        local is_cur = vim.v.relnum == 0
        local cur_lnum = vim.api.nvim_win_get_cursor(0)[1]

        local win = win_type == 'active' and 'a' or 'i'
        local pos = is_cur and 'c' or (vim.v.lnum < cur_lnum and 'a' or 'b')
        local ltype = vim.v.virtnum == 0 and 't' or (vim.v.virtnum < 0 and 'v' or 'w')

        local fold_hl = is_cur and 'CursorLineFold' or 'FoldColumn'
        local line_hl = is_cur and 'CursorLineNr' or (vim.v.lnum > 3 and 'LineNr' or (pos == 'a' and 'LineNrAbove' or 'LineNrBelow'))
        local sign_hl = is_cur and 'CursorLineSign' or 'SignColumn'
        local sep_hl  = is_cur and 'MiniStatuscolumnSepCursor' or 'MiniStatuscolumnSep'

        return string.format('%%#%s#%s%%#%s#%s%%#%s#%s%%#%s#|', fold_hl, win, line_hl, pos, sign_hl, ltype, sep_hl)
      end
    end
    require('mini-dev.statuscolumn').setup({
      content = {
        active = make_content('active'),
        inactive = make_content('inactive'),
      },
    })
  ]])
end

T['Dim'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(10, 39)
      mock_dim_test_content()

      -- Prepare main buffer to show. Add reference highlight to check that the
      -- correct highlight group is used when dimming.
      set_lines({ 'uuu', 'vvv', 'www', 'xxxxxxxxx' })
      local ns_id = child.api.nvim_create_namespace('test')
      local dim_hl, dim_cur_hl = 'MiniStatuscolumnDim', 'MiniStatuscolumnDimCursor'
      child.api.nvim_buf_set_extmark(0, ns_id, 0, 0, { end_row = 1, end_col = 0, hl_group = dim_hl })
      child.api.nvim_buf_set_extmark(0, ns_id, 1, 0, { end_row = 2, end_col = 0, hl_group = dim_cur_hl })
      child.api.nvim_buf_set_extmark(0, ns_id, 2, 0, { virt_lines = { { { 'VIR', 'String' } } } })

      -- Ensure visually distinctive highlight groups that are getting dimmed
      local n = 0
      local ensure_different_attr = function(hl_group)
        n = n + 1
        child.api.nvim_set_hl(0, hl_group, { fg = string.format('#%06x', n) })
      end

      ensure_different_attr('MiniStatuscolumnDim')
      ensure_different_attr('MiniStatuscolumnDimCursor')

      ensure_different_attr('CursorLineFold')
      ensure_different_attr('CursorLineNr')
      ensure_different_attr('CursorLineSign')
      ensure_different_attr('FoldColumn')
      ensure_different_attr('LineNr')
      ensure_different_attr('LineNrAbove')
      ensure_different_attr('LineNrBelow')
      ensure_different_attr('SignColumn')
      ensure_different_attr('MiniStatuscolumnSep')
      ensure_different_attr('MiniStatuscolumnSepCursor')
    end,
  },
})

T['Dim']['works'] = function()
  -- Prepare windows to show various combinations of lines
  set_cursor(4, 0)
  child.cmd('vsplit')
  set_cursor(3, 0)
  child.cmd('vsplit')
  set_cursor(2, 0)
  child.cmd('vsplit')
  set_cursor(1, 0)
  -- NOTE: force redraw since statuscolumn is not re-computed on cursor move
  child.cmd('redraw!')

  -- Should properly dim only inside inactive windows
  child.expect_screenshot()
  child.cmd('wincmd l')
  child.expect_screenshot()
  child.cmd('wincmd l')
  child.expect_screenshot()
  child.cmd('wincmd l')
  child.expect_screenshot()
end

T['Dim']['works when switching tabpage'] = function()
  child.cmd('vsplit | tabnew | vsplit')
  child.expect_screenshot()
  child.cmd('tabprev')
  child.expect_screenshot()
end

T['Dim']['works when showing buffer in inactive window'] = function()
  child.o.laststatus = 2
  child.o.statusline = '%{%nvim_get_current_win()==#g:actual_curwin ? "active" : "inactive"%}'
  local win_id_other = child.api.nvim_get_current_win()
  child.cmd('vsplit')

  local buf_id_other = child.api.nvim_create_buf(false, true)
  child.api.nvim_buf_set_lines(buf_id_other, 0, -1, false, { 'other', 'buf' })
  child.api.nvim_win_set_buf(0, buf_id_other)
  child.api.nvim_win_set_buf(win_id_other, buf_id_other)
  child.expect_screenshot()
end

T['Content'] = new_set()

T['Content']['works'] = function() MiniTest.skip() end

return T
