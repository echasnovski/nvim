local helpers = dofile('lua/mini-dev/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq, eq_approx = helpers.expect, helpers.expect.equality, helpers.expect.equality_approx
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('colors', config) end
local unload_module = function() child.mini_unload('colors') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local poke_eventloop = function() child.api.nvim_eval('1') end
local sleep = function(ms) vim.loop.sleep(ms); poke_eventloop() end
--stylua: ignore end

-- Mock test color scheme
local mock_test_cs = function() child.cmd('set rtp+=lua/mini-dev') end

-- Output test set ============================================================
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
  eq(child.lua_get('type(_G.MiniColors)'), 'table')

  -- `Colorscheme` command
  eq(child.fn.exists(':Colorscheme'), 2)
end

T['setup()']['creates `config` field'] = function() eq(child.lua_get('type(_G.MiniColors.config)'), 'table') end

T['as_colorscheme()'] = new_set()

T['as_colorscheme()']['works'] = function() MiniTest.skip() end

T['as_colorscheme()']['fields'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods'] = new_set()

T['as_colorscheme()']['methods']['apply()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['chan_add()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['chan_invert()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['chan_modify()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['chan_multiply()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['chan_repel()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['chan_set()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['color_modify()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['compress()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['ensure_cterm()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['make_transparent()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['simulate_cvd()'] = function() MiniTest.skip() end

T['as_colorscheme()']['methods']['write()'] = function() MiniTest.skip() end

T['get_colorscheme()'] = new_set()

local validate_test_cs = function(cs_var)
  -- Fields
  local validate_field = function(field, value) eq(child.lua_get(cs_var .. '.' .. field), value) end

  validate_field('groups.Normal', { fg = '#5f87af', bg = '#080808' })
  validate_field('groups.TestNormalCterm', { ctermfg = 67, ctermbg = 232 })
  validate_field('groups.TestComment', { fg = '#5f87af', bg = '#080808' })
  validate_field('groups.TestSpecial', { sp = '#00ff00', underline = true })
  validate_field('groups.TestBlend', { bg = '#121212', blend = 0 })

  validate_field('name', 'test_cs')

  validate_field('terminal[0]', '#010101')
  validate_field('terminal[7]', '#fefefe')

  -- Methods
  local validate_method = function(method)
    local lua_cmd = string.format('type(%s.%s)', cs_var, method)
    eq(child.lua_get(lua_cmd), 'function')
  end

  validate_method('apply')
  validate_method('chan_add')
  validate_method('chan_invert')
  validate_method('chan_modify')
  validate_method('chan_multiply')
  validate_method('chan_repel')
  validate_method('chan_set')
  validate_method('color_modify')
  validate_method('compress')
  validate_method('ensure_cterm')
  validate_method('make_transparent')
  validate_method('simulate_cvd')
  validate_method('write')
end

T['get_colorscheme()']['works for current color scheme'] = function()
  mock_test_cs()
  child.cmd('colorscheme test_cs')

  child.lua('_G.cs = MiniColors.get_colorscheme()')
  validate_test_cs('_G.cs')
end

T['get_colorscheme()']['works for some color scheme'] = function()
  mock_test_cs()
  child.lua([[_G.cs = MiniColors.get_colorscheme('test_cs')]])
  validate_test_cs('_G.cs')
end

T['get_colorscheme()']['validates arguments'] = function()
  expect.error(function() child.lua_get('MiniColors.get_colorscheme(111)') end, '`name`.*string')
  expect.error(function() child.lua_get([[MiniColors.get_colorscheme('aaa')]]) end, 'No color scheme')
end

T['get_colorscheme()']['has no side effects'] = function()
  -- Update current color scheme
  child.g.color_name = 'aaa'
  child.cmd('hi AAA guifg=#aaaaaa')

  mock_test_cs()
  child.lua([[_G.cs = MiniColors.get_colorscheme('test_cs')]])

  eq(child.g.color_name, 'aaa')
  expect.match(child.cmd_capture('hi AAA'), 'AAA.*guifg=#aaaaaa')
end

T['interactive()'] = new_set()

T['interactive()']['works'] = function() MiniTest.skip() end

T['animate()'] = new_set({
  hooks = {
    pre_case = function()
      -- Create two color scheme objects
      child.lua([[_G.cs_1 = MiniColors.as_colorscheme({
        name = 'cs_1',
        groups = {
          Normal      = { fg = '#190000', bg = '#001900' },
          TestSpecial = { sp = '#000019', blend = 0 },
          TestLink    = { link = 'Title' },
          TestSingle  = { fg = '#ffffff', bg = '#000000', sp = '#aaaaaa', underline = true },

          TestBold          = { fg = '#000000', bold          = true },
          TestItalic        = { fg = '#000000', italic        = true },
          TestNocombine     = { fg = '#000000', nocombine     = true },
          TestReverse       = { fg = '#000000', reverse       = true },
          TestStandout      = { fg = '#000000', standout      = true },
          TestStrikethrough = { fg = '#000000', strikethrough = true },
          TestUndercurl     = { fg = '#000000', undercurl     = true },
          TestUnderdashed   = { fg = '#000000', underdashed   = true },
          TestUnderdotted   = { fg = '#000000', underdotted   = true },
          TestUnderdouble   = { fg = '#000000', underdouble   = true },
          TestUnderline     = { fg = '#000000', underline     = true },
        },
        terminal = { [0] = '#190000', [7] = '#001900' }
      })]])

      child.lua([[_G.cs_2 = MiniColors.as_colorscheme({
        name = 'cs_2',
        groups = {
          Normal      = { fg = '#000000', bg = '#000000' },
          TestSpecial = { sp = '#000000', blend = 25 },
          TestLink    = { link = 'Comment' },
          -- No other highlight groups on purpose

          TestBold          = { fg = '#000000', bold          = false },
          TestItalic        = { fg = '#000000', italic        = false },
          TestNocombine     = { fg = '#000000', nocombine     = false },
          TestReverse       = { fg = '#000000', reverse       = false },
          TestStandout      = { fg = '#000000', standout      = false },
          TestStrikethrough = { fg = '#000000', strikethrough = false },
          TestUndercurl     = { fg = '#000000', undercurl     = false },
          TestUnderdashed   = { fg = '#000000', underdashed   = false },
          TestUnderdotted   = { fg = '#000000', underdotted   = false },
          TestUnderdouble   = { fg = '#000000', underdouble   = false },
          TestUnderline     = { fg = '#000000', underline     = false },
        },
        terminal = { [7] = '#000000', [15] = '#000000' }
      })]])

      -- Create function to get relevant data
      child.lua([[_G.get_relevant_cs_data = function()
        cur_cs = MiniColors.get_colorscheme()

        return {
          name = cur_cs.name,
          groups = {
            Normal            = cur_cs.groups.Normal,
            TestSpecial       = cur_cs.groups.TestSpecial,
            TestLink          = cur_cs.groups.TestLink,
            TestSingle        = cur_cs.groups.TestSingle,
            TestBold          = cur_cs.groups.TestBold,
            TestItalic        = cur_cs.groups.TestItalic,
            TestNocombine     = cur_cs.groups.TestNocombine,
            TestReverse       = cur_cs.groups.TestReverse,
            TestStandout      = cur_cs.groups.TestStandout,
            TestStrikethrough = cur_cs.groups.TestStrikethrough,
            TestUndercurl     = cur_cs.groups.TestUndercurl,
            TestUnderdashed   = cur_cs.groups.TestUnderdashed,
            TestUnderdotted   = cur_cs.groups.TestUnderdotted,
            TestUnderdouble   = cur_cs.groups.TestUnderdouble,
            TestUnderline     = cur_cs.groups.TestUnderline,
          },
          terminal = {
            { 0, vim.g.terminal_color_0},
            { 7, vim.g.terminal_color_7},
            { 15, vim.g.terminal_color_15},
          }
        }
      end]])
    end,
  },
})

--stylua: ignore
T['animate()']['works'] = function()
  -- Test only on Neovim>=0.8 as there were changes in highlight attributes
  -- See https://github.com/neovim/neovim/pull/19159
  -- TODO: Remove when support for Neovim=0.7 is dropped
  if child.fn.has('nvim-0.8') == 0 then MiniTest.skip('Needs Neovim=0.8 for easier testing.') end

  local validate_init = function()
    local cur_cs = child.lua_get('_G.get_relevant_cs_data()')
    eq(cur_cs.name, 'cs_2')
    eq(cur_cs.groups.Normal, child.lua_get('_G.cs_2.groups.Normal'))
    eq(cur_cs.groups.TestSpecial, child.lua_get('_G.cs_2.groups.TestSpecial'))
    eq(cur_cs.groups.TestLink, child.lua_get('_G.cs_2.groups.TestLink'))
    eq(child.g.terminal_color_0, vim.NIL)
    eq(child.g.terminal_color_7, '#000000')
    eq(child.g.terminal_color_15, '#000000')
  end

  child.lua('_G.cs_2:apply()')
  validate_init()

  -- It should animate transition from current color scheme to first in array,
  -- then to second, and so on
  child.lua([[MiniColors.animate({ _G.cs_1, _G.cs_2 })]])

  -- Check slightly before half-way
  local validate_before_half = function(single_hl_created)
    local test_single_hl = nil
    if single_hl_created then test_single_hl = {} end
    eq(
      child.lua_get('_G.get_relevant_cs_data()'),
      {
        name = 'transition_step',
        groups = {
          Normal      = { fg = '#050000', bg = '#030801' },
          TestSpecial = { sp = '#000003', blend = 13 },
          TestLink    = { link = 'Comment' },
          TestSingle  = test_single_hl,

          TestBold          = { fg = '#000000' },
          TestItalic        = { fg = '#000000' },
          TestNocombine     = { fg = '#000000' },
          TestReverse       = { fg = '#000000' },
          TestStandout      = { fg = '#000000' },
          TestStrikethrough = { fg = '#000000' },
          TestUndercurl     = { fg = '#000000' },
          TestUnderdashed   = { fg = '#000000' },
          TestUnderdotted   = { fg = '#000000' },
          TestUnderdouble   = { fg = '#000000' },
          TestUnderline     = { fg = '#000000' },
        },
        terminal = { { 0 }, { 7, '#030801' }, { 15, '#000000' } },
      }
    )
  end

  sleep(500 - 20)
  validate_before_half(false)

  -- Check slightly after half-way
  local validate_after_half = function()
    eq(
      child.lua_get('_G.get_relevant_cs_data()'),
      {
        name = 'transition_step',
        groups = {
          Normal      = { fg = '#090201', bg = '#000901' },
          TestSpecial = { sp = '#000003', blend = 12 },
          TestLink    = { link = 'Title' },
          TestSingle  = { bg = '#000000', fg = '#ffffff', sp = '#aaaaaa', underline = true },

          TestBold          = { fg = '#000000', bold          = true },
          TestItalic        = { fg = '#000000', italic        = true },
          TestNocombine     = { fg = '#000000', nocombine     = true },
          TestReverse       = { fg = '#000000', reverse       = true },
          TestStandout      = { fg = '#000000', standout      = true },
          TestStrikethrough = { fg = '#000000', strikethrough = true },
          TestUndercurl     = { fg = '#000000', undercurl     = true },
          TestUnderdashed   = { fg = '#000000', underdashed   = true },
          TestUnderdotted   = { fg = '#000000', underdotted   = true },
          TestUnderdouble   = { fg = '#000000', underdouble   = true },
          TestUnderline     = { fg = '#000000', underline     = true },
        },
        terminal = { { 0, '#190000' }, { 7, '#000901' }, { 15 } },
      }
    )
  end

  sleep(2 * 20)
  validate_after_half()

  -- After first transition end it should show intermediate step for 1 second
  local validate_intermediate = function()
    local cur_cs = child.lua_get('_G.get_relevant_cs_data()')
    eq(cur_cs.name, 'cs_1')
    eq(cur_cs.groups.Normal, child.lua_get('_G.cs_1.groups.Normal'))
    eq(cur_cs.groups.TestSpecial, child.lua_get('_G.cs_1.groups.TestSpecial'))
    eq(cur_cs.groups.TestLink, child.lua_get('_G.cs_1.groups.TestLink'))
    eq(child.g.terminal_color_0, '#190000')
    eq(child.g.terminal_color_7, '#001900')
    eq(child.g.terminal_color_15, vim.NIL)
  end

  sleep(500 - 20)
  validate_intermediate()

  sleep(1000 - 10)
  validate_intermediate()

  -- After showing period it should start transition back to first one (as it
  -- was specially designed command)
  sleep(500 - 20)
  validate_after_half()

  sleep(2 * 20)
  validate_before_half(true)

  sleep(500 - 20)
  validate_init()
end

T['animate()']['respects `opts.transition_steps`'] = function() end

T['animate()']['respects `opts.transition_duration`'] = function() MiniTest.skip() end

T['animate()']['respects `opts.show_duration`'] = function() MiniTest.skip() end

T['convert()'] = new_set()

local convert = function(...) return child.lua_get('MiniColors.convert(...)', { ... }) end

T['convert()']['converts to 8bit'] = function()
  local validate = function(x, ref) eq(convert(x, '8bit'), ref) end

  local bit_ref = 67
  validate(bit_ref, bit_ref)
  validate('#5f87af', bit_ref)
  validate({ r = 95, g = 135, b = 175 }, bit_ref)
  validate({ l = 54.729, a = -2.692, b = -7.072 }, bit_ref)
  validate({ l = 54.729, c = 7.567, h = 249.16 }, bit_ref)
  validate({ l = 54.729, s = 44.01, h = 249.16 }, bit_ref)

  -- Handles grays
  local gray_ref = 240
  validate({ r = 88, g = 88, b = 88 }, gray_ref)
  validate({ l = 37.6, a = 0, b = 0 }, gray_ref)
  validate({ l = 37.6, c = 0 }, gray_ref)
  validate({ l = 37.6, c = 0, h = 180 }, gray_ref)
  validate({ l = 37.6, s = 0 }, gray_ref)
  validate({ l = 37.6, s = 0, h = 180 }, gray_ref)
end

T['convert()']['converts to HEX'] = function()
  local validate = function(x, ref) eq(convert(x, 'hex'), ref) end

  local hex_ref = '#5f87af'
  validate(67, hex_ref)
  validate(hex_ref, hex_ref)
  validate({ r = 95, g = 135, b = 175 }, hex_ref)
  validate({ l = 54.729, a = -2.692, b = -7.072 }, hex_ref)
  validate({ l = 54.729, c = 7.567, h = 249.16 }, hex_ref)
  validate({ l = 54.729, s = 44.01, h = 249.16 }, hex_ref)

  -- Handles grays
  local gray_ref = '#111111'
  validate({ r = 17, g = 17, b = 17 }, gray_ref)
  validate({ l = 8, a = 0, b = 0 }, gray_ref)
  validate({ l = 8, c = 0 }, gray_ref)
  validate({ l = 8, c = 0, h = 180 }, gray_ref)
  validate({ l = 8, s = 0 }, gray_ref)
  validate({ l = 8, s = 0, h = 180 }, gray_ref)

  -- Performs correct gamut clipping
  -- NOTE: this uses approximate linear model and not entirely correct
  -- Clipping should be correct below and above cusp lightness.
  -- Cusp for hue=0 is at c=26.23 and l=59.05
  eq(convert({ l = 15, c = 13, h = 0 }, 'hex'), convert({ l = 15, c = 10.266, h = 0 }, 'hex'))
  eq(convert({ l = 85, c = 13, h = 0 }, 'hex'), convert({ l = 85, c = 9.5856, h = 0 }, 'hex'))

  -- Clipping with 'chroma' method should clip chroma channel
  eq(
    convert({ l = 15, c = 13, h = 0 }, 'hex', { gamut_clip = 'chroma' }),
    convert({ l = 15, c = 10.266, h = 0 }, 'hex')
  )
  eq(
    convert({ l = 85, c = 13, h = 0 }, 'hex', { gamut_clip = 'chroma' }),
    convert({ l = 85, c = 9.5856, h = 0 }, 'hex')
  )

  -- Clipping with 'lightness' method should clip lightness channel
  eq(
    convert({ l = 15, c = 13, h = 0 }, 'hex', { gamut_clip = 'lightness' }),
    convert({ l = 22.07, c = 13, h = 0 }, 'hex')
  )
  eq(
    convert({ l = 85, c = 13, h = 0 }, 'hex', { gamut_clip = 'lightness' }),
    convert({ l = 79.66, c = 13, h = 0 }, 'hex')
  )

  -- Clipping with 'cusp' method should draw line towards c=c_cusp, l=0 in
  -- (c, l) coordinates (with **not corrected** `l`)
  eq(
    convert({ l = 15, c = 13, h = 0 }, 'hex', { gamut_clip = 'cusp' }),
    convert({ l = 18.84, c = 11.77, h = 0 }, 'hex')
  )
  eq(convert({ l = 85, c = 13, h = 0 }, 'hex', { gamut_clip = 'cusp' }), convert({ l = 82, c = 11.5, h = 0 }, 'hex'))
end

T['convert()']['converts to RGB'] = function()
  local validate = function(x, ref, tol) eq_approx(convert(x, 'rgb'), ref, tol or 0) end

  local rgb_ref = { r = 95, g = 135, b = 175 }
  validate(67, rgb_ref)
  validate('#5f87af', rgb_ref)
  validate(rgb_ref, rgb_ref)
  validate({ l = 54.729, a = -2.692, b = -7.072 }, rgb_ref, 0.01)
  validate({ l = 54.729, c = 7.567, h = 249.16 }, rgb_ref, 0.01)
  validate({ l = 54.729, s = 44.01, h = 249.16 }, rgb_ref, 0.01)

  -- Handles grays
  local gray_ref = { r = 17, g = 17, b = 17 }
  validate({ l = 8, a = 0, b = 0 }, gray_ref, 0.02)
  validate({ l = 8, c = 0 }, gray_ref, 0.02)
  validate({ l = 8, c = 0, h = 180 }, gray_ref, 0.02)
  validate({ l = 8, s = 0 }, gray_ref, 0.02)
  validate({ l = 8, s = 0, h = 180 }, gray_ref, 0.02)

  -- Performs correct gamut clipping
  -- NOTE: this uses approximate linear model and not entirely correct
  -- Clipping should be correct below and above cusp lightness.
  -- Cusp for hue=0 is at c=26.23 and l=59.05
  eq_approx(convert({ l = 15, c = 13, h = 0 }, 'rgb'), convert({ l = 15, c = 10.266, h = 0 }, 'rgb'), 1e-4)
  eq_approx(convert({ l = 85, c = 13, h = 0 }, 'rgb'), convert({ l = 85, c = 9.5856, h = 0 }, 'rgb'), 1e-4)

  -- Clipping with 'chroma' method should clip chroma channel
  eq_approx(
    convert({ l = 15, c = 13, h = 0 }, 'rgb', { gamut_clip = 'chroma' }),
    convert({ l = 15, c = 10.266, h = 0 }, 'rgb'),
    0.02
  )
  eq_approx(
    convert({ l = 85, c = 13, h = 0 }, 'rgb', { gamut_clip = 'chroma' }),
    convert({ l = 85, c = 9.5856, h = 0 }, 'rgb'),
    0.02
  )

  -- Clipping with 'lightness' method should clip lightness channel
  eq_approx(
    convert({ l = 15, c = 13, h = 0 }, 'rgb', { gamut_clip = 'lightness' }),
    convert({ l = 22.07, c = 13, h = 0 }, 'rgb'),
    0.02
  )
  eq_approx(
    convert({ l = 85, c = 13, h = 0 }, 'rgb', { gamut_clip = 'lightness' }),
    convert({ l = 79.66, c = 13, h = 0 }, 'rgb'),
    0.02
  )

  -- Clipping with 'cusp' method should draw line towards c=c_cusp, l=0 in
  -- (c, l) coordinates (with **not corrected** `l`)
  eq_approx(
    convert({ l = 15, c = 13, h = 0 }, 'rgb', { gamut_clip = 'cusp' }),
    convert({ l = 18.8397, c = 11.7727, h = 0 }, 'rgb'),
    0.02
  )
  eq_approx(
    convert({ l = 85, c = 13, h = 0 }, 'rgb', { gamut_clip = 'cusp' }),
    convert({ l = 82.003, c = 11.5003, h = 0 }, 'rgb'),
    0.02
  )
end

T['convert()']['converts to Oklab'] = function()
  local validate = function(x, ref, tol) eq_approx(convert(x, 'oklab'), ref, tol or 0) end

  local oklab_ref = { l = 54.7293, a = -2.6923, b = -7.0722 }
  validate(67, oklab_ref, 1e-3)
  validate('#5f87af', oklab_ref, 1e-3)
  validate({ r = 95, g = 135, b = 175 }, oklab_ref, 1e-3)
  validate(oklab_ref, oklab_ref, 1e-6)
  validate({ l = 54.7293, c = 7.5673, h = 249.1588 }, oklab_ref, 1e-3)
  validate({ l = 54.7293, s = 44.0189, h = 249.1588 }, oklab_ref, 1e-3)

  -- Handles grays
  local gray_ref = { l = 8, a = 0, b = 0 }
  validate(gray_ref, gray_ref)
  validate({ l = 8, c = 0 }, gray_ref)
  validate({ l = 8, c = 0, h = 180 }, gray_ref)
  validate({ l = 8, s = 0 }, gray_ref)
  validate({ l = 8, s = 0, h = 180 }, gray_ref)

  -- Normalization
  validate({ l = 110, a = 1, b = 1 }, { l = 100, a = 1, b = 1 }, 1e-6)
  validate({ l = -10, a = 1, b = 1 }, { l = 0, a = 1, b = 1 }, 1e-6)
end

T['convert()']['converts to Oklch'] = function()
  local validate = function(x, ref, tol) eq_approx(convert(x, 'oklch'), ref, tol or 0) end

  local oklch_ref = { l = 54.7293, c = 7.5673, h = 249.1588 }
  validate(67, oklch_ref, 1e-3)
  validate('#5f87af', oklch_ref, 1e-3)
  validate({ r = 95, g = 135, b = 175 }, oklch_ref, 1e-3)
  validate({ l = 54.7293, a = -2.6923, b = -7.0722 }, oklch_ref, 1e-3)
  validate(oklch_ref, oklch_ref, 1e-6)
  validate({ l = 54.7293, s = 44.0189, h = 249.1588 }, oklch_ref, 1e-3)

  -- Handles grays
  local gray_ref = { l = 8, c = 0 }
  validate({ l = 8, a = 0, b = 0 }, gray_ref)
  validate(gray_ref, gray_ref)
  validate({ l = 8, c = 0, h = 180 }, gray_ref)
  validate({ l = 8, s = 0 }, gray_ref)
  validate({ l = 8, s = 0, h = 180 }, gray_ref)

  -- Normalization
  validate({ l = 110, c = 10, h = 0 }, { l = 100, c = 10, h = 0 }, 1e-6)
  validate({ l = -10, c = 10, h = 0 }, { l = 0, c = 10, h = 0 }, 1e-6)

  validate({ l = 50, c = -10, h = 0 }, { l = 50, c = 0 }, 1e-6)

  validate({ l = 50, c = 10, h = -90 }, { l = 50, c = 10, h = 270 }, 1e-6)
  validate({ l = 50, c = 10, h = 450 }, { l = 50, c = 10, h = 90 }, 1e-6)
  validate({ l = 50, c = 10, h = 360 }, { l = 50, c = 10, h = 0 }, 1e-6)
end

T['convert()']['converts to Oklsh'] = function()
  local validate = function(x, ref, tol) eq_approx(convert(x, 'oklsh'), ref, tol or 0) end

  local oklsh_ref = { l = 54.7293, s = 44.0189, h = 249.1588 }
  validate(67, oklsh_ref, 1e-3)
  validate('#5f87af', oklsh_ref, 1e-3)
  validate({ r = 95, g = 135, b = 175 }, oklsh_ref, 1e-3)
  validate({ l = 54.7293, a = -2.6923, b = -7.0722 }, oklsh_ref, 1e-3)
  validate({ l = 54.7293, c = 7.5673, h = 249.1588 }, oklsh_ref, 1e-3)
  validate(oklsh_ref, oklsh_ref, 1e-6)

  -- Handles grays
  local gray_ref = { l = 8, s = 0 }
  validate({ l = 8, a = 0, b = 0 }, gray_ref)
  validate({ l = 8, c = 0 }, gray_ref)
  validate({ l = 8, c = 0, h = 180 }, gray_ref)
  validate(gray_ref, gray_ref)
  validate({ l = 8, s = 0, h = 180 }, gray_ref)

  -- Normalization
  validate({ l = 110, s = 10, h = 0 }, { l = 100, s = 0 }, 1e-6)
  validate({ l = -10, s = 10, h = 0 }, { l = 0, s = 0 }, 1e-6)

  validate({ l = 50, s = -10, h = 0 }, { l = 50, s = 0 }, 1e-6)

  validate({ l = 50, s = 10, h = -90 }, { l = 50, s = 10, h = 270 }, 1e-6)
  validate({ l = 50, s = 10, h = 450 }, { l = 50, s = 10, h = 90 }, 1e-6)
  validate({ l = 50, s = 10, h = 360 }, { l = 50, s = 10, h = 0 }, 1e-6)
end

T['convert()']['validates arguments'] = function()
  -- Input
  expect.error(function() convert('aaaaaa', 'rgb') end, 'Can not infer color space of "aaaaaa"')
  expect.error(function() convert({}, 'rgb') end, 'Can not infer color space of {}')

  -- - `nil` is allowed as input
  eq(child.lua_get([[MiniColors.convert(nil, 'hex')]]), vim.NIL)

  -- `to_space`
  expect.error(function() convert('#aaaaaa', 'AAA') end, 'one of')
end

T['simulate_cvd()'] = new_set()

local simulate_cvd = function(...) return child.lua_get('MiniColors.simulate_cvd(...)', { ... }) end

T['simulate_cvd()']['works for "protan"'] = function()
  local validate = function(x, severity, ref) eq(simulate_cvd(x, 'protan', severity), ref) end

  local hex = '#00ff00'
  validate(hex, 0.0, '#00ff00')
  validate(hex, 0.1, '#2ef400')
  validate(hex, 0.2, '#55ea00')
  validate(hex, 0.3, '#77e300')
  validate(hex, 0.4, '#94dd00')
  validate(hex, 0.5, '#add800')
  validate(hex, 0.6, '#c4d400')
  validate(hex, 0.7, '#d9d000')
  validate(hex, 0.8, '#ebcd00')
  validate(hex, 0.9, '#fdcb00')
  validate(hex, 1.0, '#ffc900')

  -- Works for non-hex input
  validate({ r = 0, g = 255, b = 0 }, 1, '#ffc900')
end

T['simulate_cvd()']['works for "deutan"'] = function()
  local validate = function(x, severity, ref) eq(simulate_cvd(x, 'deutan', severity), ref) end

  local hex = '#00ff00'
  validate(hex, 0.0, '#00ff00')
  validate(hex, 0.1, '#2def02')
  validate(hex, 0.2, '#51e303')
  validate(hex, 0.3, '#6fd805')
  validate(hex, 0.4, '#87cf06')
  validate(hex, 0.5, '#9bc707')
  validate(hex, 0.6, '#acc008')
  validate(hex, 0.7, '#bbba09')
  validate(hex, 0.8, '#c7b50a')
  validate(hex, 0.9, '#d2b00a')
  validate(hex, 1.0, '#dbab0b')

  -- Works for non-hex input
  validate({ r = 0, g = 255, b = 0 }, 1, '#dbab0b')
end

T['simulate_cvd()']['works for "tritan"'] = function()
  local validate = function(x, severity, ref) eq(simulate_cvd(x, 'tritan', severity), ref) end

  local hex = '#00ff00'
  validate(hex, 0.0, '#00ff00')
  validate(hex, 0.1, '#18f60e')
  validate(hex, 0.2, '#22f11b')
  validate(hex, 0.3, '#21f026')
  validate(hex, 0.4, '#17f131')
  validate(hex, 0.5, '#07f43f')
  validate(hex, 0.6, '#00f851')
  validate(hex, 0.7, '#00fa67')
  validate(hex, 0.8, '#00f980')
  validate(hex, 0.9, '#00f499')
  validate(hex, 1.0, '#00edb0')

  -- Works for non-hex input
  validate({ r = 0, g = 255, b = 0 }, 1, '#00edb0')
end

T['simulate_cvd()']['works for "mono"'] = function()
  local validate = function(lightness)
    local hex = convert({ l = lightness, c = 4, h = 0 }, 'hex')
    local ref_gray = convert({ l = convert(hex, 'oklch').l, c = 0 }, 'hex')
    eq(simulate_cvd(hex, 'mono'), ref_gray)
  end

  for i = 0, 10 do
    validate(10 * i)
  end

  -- Works for non-hex input
  eq(simulate_cvd({ r = 0, g = 255, b = 0 }, 'mono'), '#d3d3d3')
end

T['simulate_cvd()']['allows all values of `severity`'] = function()
  local validate = function(severity_1, severity_2)
    eq(simulate_cvd('#00ff00', 'protan', severity_1), simulate_cvd('#00ff00', 'protan', severity_2))
  end

  -- Not one of 0, 0.1, ..., 0.9, 1 is rounded towards closest one
  validate(0.54, 0.5)
  validate(0.56, 0.6)

  -- `nil` is allowed
  validate(nil, 1)

  -- Out of bounds values
  validate(100, 1)
  validate(-100, 0)
end

T['simulate_cvd()']['validates arguments'] = function()
  -- Input
  expect.error(function() simulate_cvd('aaaaaa', 'protan', 1) end, 'Can not infer color space of "aaaaaa"')
  expect.error(function() simulate_cvd({}, 'protan', 1) end, 'Can not infer color space of {}')

  -- - `nil` is allowed as input
  eq(child.lua_get([[MiniColors.simulate_cvd(nil, 'protan', 1)]]), vim.NIL)

  -- `cvd_type`
  expect.error(function() simulate_cvd('#aaaaaa', 'AAA', 1) end, 'one of')

  -- `severity`
  expect.error(function() simulate_cvd('#aaaaaa', 'protan', 'a') end, '`severity`.*number')
end

-- Integration tests ==========================================================
T[':Colorscheme'] = new_set()

T[':Colorscheme']['works'] = function() MiniTest.skip() end

T[':Colorscheme']['accepts several arguments'] = function() MiniTest.skip() end

T[':Colorscheme']['provides proper completion'] = function() MiniTest.skip() end

return T
