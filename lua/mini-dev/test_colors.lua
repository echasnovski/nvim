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
--stylua: ignore end

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

T['get_colorscheme()']['works'] = function() MiniTest.skip() end

T['interactive()'] = new_set()

T['interactive()']['works'] = function() MiniTest.skip() end

T['animate()'] = new_set()

T['animate()']['works'] = function() MiniTest.skip() end

T['convert()'] = new_set()

local convert = function(...) return child.lua_get('MiniColors.convert(...)', { ... }) end

T['convert()']['converts to HEX'] = function()
  local validate = function(x, ref) eq(convert(x, 'hex'), ref) end

  local hex_ref = '#012345'
  validate(hex_ref, hex_ref)
  validate({ r = 1, g = 35, b = 69 }, hex_ref)
  validate({ l = 15.126, a = -2.294, b = -7.095 }, hex_ref)
  validate({ l = 15.126, c = 7.456, h = 252 }, hex_ref)
  validate({ l = 15.126, s = 95, h = 252 }, hex_ref)

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

  local rgb_ref = { r = 1, g = 35, b = 69 }
  validate('#012345', rgb_ref)
  validate(rgb_ref, rgb_ref)
  validate({ l = 15.12563, a = -2.29431, b = -7.09467 }, rgb_ref, 1e-3)
  validate({ l = 15.12563, c = 7.45642, h = 252.0795 }, rgb_ref, 1e-3)
  validate({ l = 15.12563, s = 95.0342, h = 252.0795 }, rgb_ref, 1e-3)

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

  local oklab_ref = { l = 15.12563, a = -2.29431, b = -7.09467 }
  validate('#012345', oklab_ref, 1e-3)
  validate({ r = 1, g = 35, b = 69 }, oklab_ref, 1e-3)
  validate(oklab_ref, oklab_ref, 1e-6)
  validate({ l = 15.12563, c = 7.45642, h = 252.0795 }, oklab_ref, 1e-3)
  validate({ l = 15.12563, s = 95.0342, h = 252.0795 }, oklab_ref, 1e-3)

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

  local oklch_ref = { l = 15.12563, c = 7.45642, h = 252.0795 }
  validate('#012345', oklch_ref, 1e-3)
  validate({ r = 1, g = 35, b = 69 }, oklch_ref, 1e-3)
  validate({ l = 15.12563, a = -2.29431, b = -7.09467 }, oklch_ref, 1e-3)
  validate(oklch_ref, oklch_ref, 1e-6)
  validate({ l = 15.12563, s = 95.0342, h = 252.0795 }, oklch_ref, 1e-3)

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

  local oklsh_ref = { l = 15.12563, s = 95.0342, h = 252.0795 }
  validate('#012345', oklsh_ref, 1e-3)
  validate({ r = 1, g = 35, b = 69 }, oklsh_ref, 1e-3)
  validate({ l = 15.12563, a = -2.29431, b = -7.09467 }, oklsh_ref, 1e-3)
  validate({ l = 15.12563, c = 7.45642, h = 252.0795 }, oklsh_ref, 1e-3)
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
