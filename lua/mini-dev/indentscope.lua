-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- Documentation ==============================================================
--- Work with indent scope.
---
--- # Setup~
---
--- This module needs a setup with `require('mini.indentscope').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniIndentscope` which you can use for scripting or manually (with `:lua
--- MiniIndentscope.*`). See |MiniIndentscope.config| for available config
--- settings.
---
--- # Disabling~
---
--- To disable, set `g:miniindentscope_disable` (globally) or
--- `b:miniindentscope_disable` (for a buffer) to `v:true`.
---@tag MiniIndentscope mini.indentscope

-- Notes about implementation:
-- - Scope - (buffer id) + (indent) + (range of lines).
-- - Indicator - optimized visual representation of scope in current window
--   view.
-- - Checking for new indicator being equal to current one in order to optimize
--   drawing is dangerous: text change can move extmark from their initial
--   place (for example, like during comment-uncomment). Also there might be
--   gap at cursor, which is not really a part of indicator. All in all, this
--   showed to introduce severe complexity when current "make async full update
--   all the time" works in vast majority of situations (it might lack when
--   cursor travels fast on indicator and during fast scroll by screen sizes
--   within same scope).

-- Module definition ==========================================================
local MiniIndentscope = {}
H = {}

--- Module setup
---
---@param config table Module config table. See |MiniIndentscope.config|.
---
---@usage `require('mini.indentscope').setup({})` (replace `{}` with your `config` table)
function MiniIndentscope.setup(config)
  -- Export module
  _G.MiniIndentscope = MiniIndentscope

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Module behavior
  vim.api.nvim_exec(
    [[augroup MiniIndentscope
        au!
        au CursorMoved,CursorMovedI             * lua MiniIndentscope.auto_draw({ lazy = true })
        au TextChanged,TextChangedI,WinScrolled * lua MiniIndentscope.auto_draw()
      augroup END]],
    false
  )

  -- Create highlighting
  vim.api.nvim_exec(
    [[hi default link MiniIndentscopeSymbol Delimiter
      hi MiniIndentscopePrefix guifg=NONE guibg=NONE gui=nocombine]],
    false
  )
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniIndentscope.config = {
  -- Delay (in ms) between event and start of drawing scope indicator
  draw_delay = 100,

  -- Animation rule for scope's first drawing. Follows the inverted idea of
  -- common easing function: given current and total number of steps, compute
  -- duration at which current step should end. For builtin options and more
  -- information see |MiniIndentscope.animations|. To not use animation, supply
  -- `require('mini.indentscope').animations.none()`.
  --minidoc_replace_start draw_animation = --<function: implements constant 5ms between steps>,
  draw_animation = function(s, n)
    return 5 * s
  end,
  --minidoc_replace_end

  -- Rules by which indent is computed in ambiguous cases: when there are two
  -- conflicting indent values. Can be one of:
  -- 'min' (take minimum), 'max' (take maximum), 'next', 'previous'.
  rules = {
    -- Indent of blank line (empty or containing only whitespace). Two indent
    -- values (`:h indent()`) are from previous (`:h prevnonblank()`) and next
    -- (`:h nextnonblank()`) non-blank lines.
    blank = 'max',

    -- Outer indent of outer scope. Two indent values are from top and bottom
    -- lines with indent strictly less than current 'indent at cursor'.
    scope = 'max',
  },

  -- Which character to use for drawing scope indicator
  symbol = '╎',
}
--minidoc_afterlines_end

-- Module data ================================================================
MiniIndentscope.animations = {
  none = function()
    return function()
      return 0
    end
  end,
  constant_step = function(step_duration)
    return function(s, n)
      return step_duration * s
    end
  end,
  constant_duration = function(duration)
    return function(s, n)
      return (duration / n) * s
    end
  end,
  quadratic = function(duration, type)
    return H.make_inverted_easing(function(d)
      return math.sqrt(d)
    end, duration, type)
  end,
  cubic = function(duration, type)
    return H.make_inverted_easing(function(d)
      return math.pow(d, 0.33)
    end, duration, type)
  end,
  exponential = function(duration, type)
    return H.make_inverted_easing(function(d)
      if d < math.pow(2, -10) then
        return 0
      end
      return 0.1 * math.log(d, 2) + 1
    end, duration, type)
  end,
}

-- Module functionality =======================================================
---@param line number Line number (starts from 1).
---@param col number Column number (starts from 1).
---@private
function MiniIndentscope.get_scope(line, col)
  local buf_id = vim.api.nvim_get_current_buf()
  local curpos = (not line or not col) and vim.fn.getcurpos() or {}
  -- Use `curpos[5]` (`curswant`, see `:h getcurpos()`) to account for blank
  -- and empty lines.
  line, col = line or curpos[2], col or curpos[5]

  -- Compute "indent at column"
  local indent = math.min(col, H.get_line_indent(line))

  -- Make early return
  if indent <= 0 then
    return {
      buf_id = buf_id,
      indent = { outer = indent - 1, inner = indent },
      input = { line = line, column = col },
      range = { top = 1, bottom = vim.fn.line('$') },
    }
  end

  -- Compute scope
  local top, top_indent = H.cast_ray(line, indent, 'up')
  local bottom, bottom_indent = H.cast_ray(line, indent, 'down')

  local scope_rule = H.indent_rules[MiniIndentscope.config.rules.scope]
  return {
    buf_id = buf_id,
    indent = { outer = scope_rule(top_indent, bottom_indent), inner = indent },
    input = { line = line, column = col },
    range = { top = top, bottom = bottom },
  }
end

function MiniIndentscope.auto_draw(opts)
  if H.is_disabled() then
    H.undraw_indicator()
    return
  end

  local local_event_id = H.current.event_id + 1
  H.current.event_id = local_event_id

  opts = opts or {}
  local scope = MiniIndentscope.get_scope()
  local draw_opts = H.make_draw_opts(opts, scope)

  if draw_opts.type == 'none' then
    return
  end

  if draw_opts.delay > 0 then
    H.undraw_indicator(draw_opts)
  end

  -- Use `defer_fn()` even if `delay` is 0 to draw line only after all events
  -- are processed (stops flickering)
  vim.defer_fn(function()
    if H.current.event_id ~= local_event_id then
      return
    end

    local indicator = H.indicator_compute(scope)
    H.current.scope = scope

    H.undraw_indicator(draw_opts)
    H.draw_indicator(indicator, draw_opts)
  end, draw_opts.delay)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniIndentscope.config

-- Namespace for drawing vertical line
H.ns_id = vim.api.nvim_create_namespace('MiniIndentscope')

-- Timer for doing animation
H.timer = vim.loop.new_timer()

-- Table with current relevalnt data:
-- - `event_id` - counter for events.
-- - `scope` - latest drawn scope.
-- - `draw_status` - status of current drawing.
H.current = { event_id = 0, scope = {}, draw_status = 'none' }

-- Functions to compute indent of blank line based on `edge_blank`
H.indent_rules = {
  ['min'] = function(prev_indent, next_indent)
    return math.min(prev_indent, next_indent)
  end,
  ['max'] = function(prev_indent, next_indent)
    return math.max(prev_indent, next_indent)
  end,
  ['previous'] = function(prev_indent, next_indent)
    return prev_indent
  end,
  ['next'] = function(prev_indent, next_indent)
    return next_indent
  end,
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    draw_delay = { config.draw_delay, 'number' },
    draw_animation = { config.draw_animation, 'function' },

    rules = { config.rules, 'table' },
    ['rules.blank'] = { config.rules.blank, 'string' },
    ['rules.scope'] = { config.rules.scope, 'string' },

    symbol = { config.symbol, 'string' },
  })
  return config
end

function H.apply_config(config)
  MiniIndentscope.config = config
end

function H.is_disabled()
  return vim.g.miniindentscope_disable == true or vim.b.miniindentscope_disable == true
end

-- Scope ======================================================================
-- Line indent:
-- - Equals output of `vim.fn.indent()` in case of non-blank line.
-- - Depends on `MiniIndentscope.config.rules.blank` in such way so as to
--   satisfy its definition.
function H.get_line_indent(line)
  local prev_nonblank = vim.fn.prevnonblank(line)
  local res = vim.fn.indent(prev_nonblank)

  -- Compute indent of blank line depending on `rules.blank` values
  if line ~= prev_nonblank then
    local next_indent = vim.fn.indent(vim.fn.nextnonblank(line))
    local blank_rule = H.indent_rules[MiniIndentscope.config.rules.blank]
    res = blank_rule(res, next_indent)
  end

  return res
end

function H.cast_ray(line, indent, direction)
  local final_line, increment = 1, -1
  if direction == 'down' then
    final_line, increment = vim.fn.line('$'), 1
  end

  for l = line, final_line, increment do
    local new_indent = H.get_line_indent(l + increment)
    if new_indent < indent then
      return l, new_indent
    end
  end

  return final_line, -1
end

function H.scope_is_equal(scope_1, scope_2)
  if type(scope_1) ~= 'table' or type(scope_2) ~= 'table' then
    return false
  end

  return scope_1.buf_id == scope_2.buf_id
    and scope_1.indent.outer == scope_2.indent.outer
    and scope_1.range.top == scope_2.range.top
    and scope_1.range.bottom == scope_2.range.bottom
end

function H.scope_has_intersect(scope_1, scope_2)
  if type(scope_1) ~= 'table' or type(scope_2) ~= 'table' then
    return false
  end
  if (scope_1.buf_id ~= scope_2.buf_id) or (scope_1.indent.outer ~= scope_2.indent.outer) then
    return false
  end

  local range_1, range_2 = scope_1.range, scope_2.range
  return (range_2.top <= range_1.top and range_1.top <= range_2.bottom)
    or (range_1.top <= range_2.top and range_2.top <= range_1.bottom)
end

-- Indicator ==================================================================
--- Compute indicator of scope to be displayed
---
--- Here 'indicator' means all the data necessary to visually represent scope
--- in current window.
---
---@return table|nil Table with hash info or `nil` in case line shouldn't be drawn.
---@private
function H.indicator_compute(scope)
  scope = scope or H.current.scope
  local outer_indent = scope.indent.outer

  -- Don't draw indicator that should be outside of screen. This condition is
  -- (perpusfully) "responsible" for not drawing indicator spanning whole file.
  if outer_indent < 0 then
    return {}
  end

  -- Extmarks will be located at column zero but show indented text:
  -- - This allows showing line even on empty lines.
  -- - Text indentation should depend on current window view because extmarks
  --   can't scroll to be past left window side. Sources:
  --     - Neovim issue: https://github.com/neovim/neovim/issues/14050
  --     - Used fix: https://github.com/lukas-reineke/indent-blankline.nvim/pull/155
  local leftcol = vim.fn.winsaveview().leftcol
  if outer_indent < leftcol then
    return {}
  end

  -- Usage separate highlight groups for prefix and symbol allows cursor to be
  -- "natural" when on the left of indicator line (like on empty lines)
  local virt_text = { { MiniIndentscope.config.symbol, 'MiniIndentscopeSymbol' } }
  local prefix = string.rep(' ', outer_indent - leftcol)
  -- Currently Neovim doesn't work when text for extmark is empty string
  if prefix:len() > 0 then
    table.insert(virt_text, 1, { prefix, 'MiniIndentscopePrefix' })
  end

  -- These lines can be updated to result into drawing line only inside current
  -- window view. Like this:
  --   local top = math.max(scope.range.top, vim.fn.line('w0'))
  --   local bottom = math.min(scope.range.bottom, vim.fn.line('w$'))
  -- However, this is a compromize optimization (because currently there is a
  -- screen redraw after window scroll but before showing indicator):
  -- - On plus side, it reduces workload.
  -- - On minus side, it introduces visible flickering when scrolling window
  --   within same scope. If cursor is on the indicator, it also flickers
  --   (because there is no gap at cursor).
  -- - On the neutral side, it applies animation function not to the whole
  --   scope, but only to its currently visible part.
  local top = scope.range.top
  local bottom = scope.range.bottom

  return { buf_id = vim.api.nvim_get_current_buf(), virt_text = virt_text, top = top, bottom = bottom }
end

-- Drawing --------------------------------------------------------------------
-- TODO: remove duraction tracking
_G.draw_durations = {}
function H.draw_indicator(indicator, opts)
  local start_time = vim.loop.hrtime()

  indicator = indicator or {}
  opts = opts or {}

  -- Don't draw anything if nothing to be displayed
  if indicator.virt_text == nil or #indicator.virt_text == 0 then
    H.current.draw_status = 'finished'
    return
  end

  -- Make drawing function
  local draw_fun = H.make_draw_function(indicator, opts)

  -- Perform drawing
  H.current.draw_status = 'drawing'
  H.draw_indicator_animation(indicator, opts, draw_fun)

  local end_time = vim.loop.hrtime()
  table.insert(_G.draw_durations, 0.000001 * (end_time - start_time))
end

function H.draw_indicator_animation(indicator, opts, draw_fun)
  -- Draw from origin (cursor line but wihtin indicator range)
  local top, bottom = indicator.top, indicator.bottom
  local origin = math.min(math.max(vim.fn.line('.'), top), bottom)

  local step = 1
  local n_steps = math.max(origin - top, bottom - origin) + 1

  local animation_fun = opts.animation_fun
  local progress = animation_fun(step, n_steps)
  local wait_time = progress - animation_fun(0, n_steps)

  local draw_step
  draw_step = vim.schedule_wrap(function()
    -- Check for not drawing outside of interval is done inside `draw_fun`
    local success = draw_fun(origin - step + 1)
    if step > 1 then
      success = success and draw_fun(origin + step - 1)
    end

    if not success or step == n_steps then
      H.current.draw_status = step == n_steps and 'finished' or H.current.draw_status
      H.timer:stop()
      return
    end

    step = step + 1
    local progress_new = animation_fun(step, n_steps)
    wait_time = progress_new - progress
    progress = progress_new
    -- Repeat value of `timer` seems to be rounded down to milliseconds. This
    -- means that values less than 1 will lead to timer stop repeating. Instead
    -- call next step function directly.
    if wait_time < 1 then
      H.timer:set_repeat(0)
      draw_step()
    else
      H.timer:set_repeat(wait_time)
      -- Usage of `again()` is needed to overcome the fact that it is called
      -- inside callback. Mainly this is needed only in case of transition from
      -- 'non-repeating' timer to 'repeating' one in case of complex animation
      -- functions. See https://docs.libuv.org/en/v1.x/timer.html#api
      H.timer:again()
    end
  end)

  H.timer:start(0, 0, draw_step)

  if wait_time < 1 then
    draw_step()
  else
    H.timer:set_repeat(wait_time)
  end
end

function H.undraw_indicator(opts)
  opts = opts or {}

  -- Don't operate outside of current event if able to verify
  if opts.event_id and opts.event_id ~= H.current.event_id then
    return
  end

  pcall(vim.api.nvim_buf_clear_namespace, H.current.scope.buf_id or 0, H.ns_id, 0, -1)

  H.current.draw_status = 'none'
end

function H.make_draw_opts(opts, scope)
  if opts.lazy and H.current.draw_status == 'finished' and H.scope_is_equal(scope, H.current.scope) then
    return { type = 'none' }
  end

  local res = {
    event_id = H.current.event_id,
    type = 'animation',
    delay = MiniIndentscope.config.draw_delay,
    animation_fun = MiniIndentscope.config.draw_animation,
    -- This is currently not used to reduce flickering, but can be brought back
    cursor_gap_line = (scope.indent.outer + 1) == vim.fn.virtcol('.') and vim.fn.line('.') or nil,
  }

  if H.current.draw_status == 'none' then
    return res
  end

  -- Draw immediately scope which intersects (same indent, overlapping ranges)
  -- currently drawn or finished. This is more natural when typing text.
  if H.scope_has_intersect(scope, H.current.scope) then
    res.type = 'immediate'
    res.delay = 0
    res.animation_fun = MiniIndentscope.animations.none()
    return res
  end

  return res
end

function H.make_draw_function(indicator, opts)
  local extmark_opts = {
    hl_mode = 'combine',
    priority = 2,
    right_gravity = false,
    virt_text = indicator.virt_text,
    virt_text_pos = 'overlay',
  }

  local current_event_id = opts.event_id
  -- local cursor_gap_line = opts.cursor_gap_line

  return function(l)
    -- Don't draw if outdated
    if H.current.event_id ~= current_event_id then
      return false
    end

    -- This is not used to reduce flickering, but can be brought back
    -- -- Don't put extmark if it will conflict with cursor
    -- if l == cursor_gap_line then
    --   return true
    -- end

    -- Don't put extmark outside of indicator range
    if not (indicator.top <= l and l <= indicator.bottom) then
      return true
    end

    return pcall(vim.api.nvim_buf_set_extmark, indicator.buf_id, H.ns_id, l - 1, 0, extmark_opts)
  end
end

-- Animations =================================================================
-- Reference: https://github.com/rxi/flux/blob/master/flux.lua
-- Example (`duration` - total desired duration):
-- - `basis = function(x) return x*x end`
--   Its inverse is `inverted_basis = function(y) return math.sqrt(y) end`
-- - Easing 'in' (input - 'current' duration `d`, output - 'current' step `s`):
--   `s = n_steps * basis(d / duration)`
--   Inverted easing is obtained by solving this equation assuming
--   `inverted_basis = basis^{-1}(d)` is given
-- - Same goes for easing 'out' and 'in-out'.
function H.make_inverted_easing(inverted_basis, duration, type)
  duration = duration or 100
  type = type or 'in-out'
  return ({
    ['in'] = function(s, n)
      return duration * inverted_basis(s / n)
    end,
    ['out'] = function(s, n)
      return duration * (1 - inverted_basis(1 - s / n))
    end,
    ['in-out'] = function(s, n)
      s = 2 * s / n
      if s < 1 then
        return duration * (0.5 * inverted_basis(s))
      end
      return duration * (1 - 0.5 * inverted_basis(2 - s))
    end,
  })[type]
end

-- Utilities ------------------------------------------------------------------
function H.notify(msg)
  vim.notify(('(mini.indentscope) %s'):format(msg))
end

return MiniIndentscope
