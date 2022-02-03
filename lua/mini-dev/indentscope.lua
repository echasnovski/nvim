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

--- Drawing of scope indicator
---
--- Draw of scope indicator is done as iterative animation. It has the
--- following design:
--- - Draw indicator on origin line (where cursor is at) immediately. Indicator
---   is visualized as `MiniIndentscope.config.symbol` placed to the right of
---   scope's outer indent. This creates a line from top to bottom scope edges.
--- - Draw upward and downward concurrently per one line. Progression by one
---   line in both direction is considered to be one step of animation.
--- - Before each step wait certain amount of time, which is decided by
---   "animation function". It takes next and total step numbers (both are one
---   or bigger) and return number of milliseconds to wait before drawing next
---   step. Comparing to a more popular "easing functions" in animation (input:
---   duration since animation start; output: percent of animation done), it is
---   a discrete inverse version of its derivative. Such interface proved to be
---   more appropriate for kind of task at hand.
---
--- Special cases~
---
--- - When scope to be drawn intersects (same indent, ranges overlap) currently
---   visible one (at process or finished drawing), drawing is done immediately
---   without animation. With most common example being typing new text, this
---   feels more natural.
--- - Scope for the whole is not drawn as it is isually redundant. Technically,
---   it can be thought as drawn at column 0 (because outer indent is -1) which
---   is not visible.
---@tag MiniIndentscope-drawing

---@alias __animation_duration number Total duration (in ms) of any animation. Default: 100.
---@alias __animation_type string Type of progression. One of:
---   - 'in': accelerating from zero speed.
---   - 'out': decelerating to zero speed.
---   - 'in-out': accelerating until halfway, then decelerating.
---@alias __animation_function function Animation function (see |MiniIndentscope-drawing|).

-- Notes about implementation:
-- - Scope - maximum set of consecutive lines which contains input line and
--   every member has indent not less than input "indent at column".
--   Technically: <buffer id> + <indents: outer (where visual line will be
--   drawn) and inner (which is used to compute range)> + <range of lines>.
-- - Tried and rejected features/optimizations:
--     - Gap at cursor. Intended to always show cursor at normal state. It
--       might be more visually pleasing and more convenient when start typing
--       over indicator. Couldn't properly do that because couldn't find an
--       appropriate (fast, non-blocking, without much code complexity,
--       low-flickering) way to do that. There was an idea of making draw
--       function not draw at cursor and update only cursor gap when it was
--       enough, but there was slight flickering and too much code complexity.
--     - Draw only inside current window view (from top visible line to bottom
--       one). Would decrease workload. Couldn't properly do that because there
--       is early screen redraw after `WinScrolled` which introduced flickering
--       when scrolling (so it was `WinScrolled` -> redraw with current
--       extmarks -> redraw with new extmarks).
-- - Manual tests to check proper behavior (not sure how to autotest this):
--     - Moving cursor faster than debounce delay should not initiate drawing.
--     - Extmark on cursor line should show right after debounce delay. Other
--       steps (if present) should use animation function.
--     - Usual typing on new line without decreasing indent should immediately
--       update scope without animation (although it is a different scope).
--     - Moving cursor within same scope when it is already drawing shouldn't
--       stop drawing.
--     - Fast consecutive scrolling within big scope (try `<C-d>` and `<Down>`)
--       shouldn't cause flicker.

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
---@text
--- Notes~
--- - Indent rules are designed to compute indent based on two equally possible
---   indent values. They matter only if values are different, all of them
---   return same result otherwise. Here is an illustration of how they work
---   when empty lines are present:
--- >
---                              |max|min|previous|next|
---   1|function foo()           | 0 | 0 |   0    | 0  |
---   2|                         | 4 | 0 |   0    | 4  |
---   3|    print('Hello world') | 4 | 4 |   4    | 4  |
---   4|                         | 4 | 2 |   4    | 2  |
---   5|  end                    | 2 | 2 |   2    | 2  |
--- <
---   So, for example, a scope at line 3 and right-most column has range
---   depending on `MiniIndentscope.config.rules.blank`: 2-4 for "max", 3-3 for
---   "min", 3-4 for "previous", and 2-3 for "next".
---   Also, when using "max" as indent rule for blank lines, outer indent of
---   scope is: 2 for "max", 0 for "min", 0 for "previous", and 2 for "next".
MiniIndentscope.config = {
  draw = {
    -- Delay (in ms) between event and start of drawing scope indicator
    delay = 100,

    -- Animation rule for scope's first drawing. A function which, given next and
    -- total step numbers, returns wait time (in ms). For builtin options
    -- |MiniIndentscope.animations|. To not use animation, supply
    -- `require('mini.indentscope').animations.none()`.
    --minidoc_replace_start animation = --<function: implements constant 5ms between steps>,
    animation = function(s, n)
      return 5
    end,
    --minidoc_replace_end
  },

  -- Rules by which indent is computed in ambiguous cases: when there are two
  -- conflicting indent values. Can be one of:
  -- 'min' (take minimum), 'max' (take maximum), 'next', 'previous'.
  rules = {
    -- Indent of blank line (empty or containing only whitespace). Two indent
    -- values (`:h indent()`) are from previous (`:h prevnonblank()`) and next
    -- (`:h nextnonblank()`) non-blank lines.
    blank = 'max',

    -- Outer indent of scope. Two indent values are from top and bottom lines
    -- with indent strictly less than current 'indent at column'.
    scope = 'max',
  },

  -- Which character to use for drawing scope indicator
  symbol = '╎',
}
--minidoc_afterlines_end

-- Module data ================================================================
--- Builtin generators of animation functions
---
--- Each element is a function which returns an animation function (takes next
--- and total step numbers, returns wait time before next step).
--- Most of elements are analogues of some commonly used easing functions.
---
---@seealso |MiniIndentscope-drawing| for more information about how drawing is
---   done.
MiniIndentscope.animations = {}

--- No animation
---
---@return __animation_function
MiniIndentscope.animations.none = function()
  return function()
    return 0
  end
end

--- Animate with constant wait time between steps
---
---@param step_wait number Wait time (in ms) before every step. Default: 10.
---
---@return __animation_function
MiniIndentscope.animations.constant_step = function(step_wait)
  step_wait = step_wait or 10

  return function(s, n)
    return step_wait
  end
end

--- Animate with linear progression for fixed duration
---
--- Another description: wait time between steps is constant, such that total
--- duration is always `duration`.
---
---@param duration __animation_duration
---
---@return __animation_function
MiniIndentscope.animations.linear = function(duration)
  duration = duration or 100

  -- Every step is preceeded by constant waiting time
  return function(s, n)
    return (duration / n)
  end
end

--- Animate with quadratic progression for fixed duration
---
--- Another description: wait time between steps is decreasing/increasing
--- linearly, such that total duration is always `duration`.
---
---@param duration __animation_duration
---@param type __animation_type
---
---@return __animation_function
MiniIndentscope.animations.quadratic = function(duration, type)
  duration = duration or 100
  type = type or 'in-out'

  local make_delta = function(n_steps)
    local total = n_steps * (n_steps + 1) / 2
    return duration / total
  end

  return H.animation_arithmetic_powers(1, make_delta, type)
end

--- Animate with cubic progression for fixed duration
---
--- Another description: wait time between steps is decreasing/increasing
--- quadratically, such that total duration is always `duration`.
---
---@param duration __animation_duration
---@param type __animation_type
---
---@return __animation_function
MiniIndentscope.animations.cubic = function(duration, type)
  duration = duration or 100
  type = type or 'in-out'

  local make_delta = function(n_steps)
    local total = n_steps * (n_steps + 1) * (2 * n_steps + 1) / 6
    return duration / total
  end

  return H.animation_arithmetic_powers(2, make_delta, type)
end

--- Animate with quartic progression for fixed duration
---
--- Another description: wait time between steps is decreasing/increasing
--- cubically, such that total duration is always `duration`.
---
---@param duration __animation_duration
---@param type __animation_type
---
---@return __animation_function
MiniIndentscope.animations.quartic = function(duration, type)
  duration = duration or 100
  type = type or 'in-out'

  local make_delta = function(n_steps)
    local total = n_steps ^ 2 * (n_steps + 1) ^ 2 / 4
    return duration / total
  end

  return H.animation_arithmetic_powers(3, make_delta, type)
end

--- Animate with exponential progression for fixed duration
---
--- Another description: wait time between steps is decreasing/increasing
--- geometrically, such that total duration is always `duration`.
---
---@param duration __animation_duration
---@param type __animation_type
---
---@return __animation_function
MiniIndentscope.animations.exponential = function(duration, type)
  duration = duration or 100
  type = type or 'in-out'

  local make_delta = function(n_steps)
    return math.pow(duration + 1, 1 / n_steps)
  end

  -- Every step is preceeded by waiting time decreasing/increasing in geometric
  -- progression fashion (`d` is 'delta', ensures total duration time):
  -- - 'in':  (d-1)*d^(n-1); (d-1)*d^(n-2); ...; (d-1)*d^1;     (d-1)*d^0
  -- - 'out': (d-1)*d^0;     (d-1)*d^1;     ...; (d-1)*d^(n-2); (d-1)*d^(n-1)
  -- - 'in-out': 'in' until 0.5*n, 'out' afterwards
  return ({
    ['in'] = function(s, n)
      local delta = make_delta(n)
      return (delta - 1) * delta ^ (n - s)
    end,
    ['out'] = function(s, n)
      local delta = make_delta(n)
      return (delta - 1) * delta ^ (s - 1)
    end,
    ['in-out'] = function(s, n)
      local n_half = math.floor(0.5 * n + 0.5)
      -- Possibly use `0.5` because `make_delta` ensures total duration time
      -- within its input number steps.
      local coef = n_half <= 1 and 1 or 0.5

      if s <= n_half then
        local delta = make_delta(n_half)
        return coef * (delta - 1) * delta ^ (n_half - s)
      end
      local delta = make_delta(n - n_half)
      return coef * (delta - 1) * delta ^ (s - n_half - 1)
    end,
  })[type]
end

-- Module functionality =======================================================
--- Compute indent scope
---
--- Indent scope (or just "scope") is a maximum set of consecutive lines which
--- contains input line and every member has indent not less than input "indent
--- at column". Here "indent at column" means minimum between column value and
--- indent of input line. When using cursor column, this allows for a useful
--- interactive view of nested indent scopes by making horizontal movements.
---
--- Algorithm overview~
---
--- - Compute reference "indent at column".
--- - Process upwards and downwards from input line to search for line with
---   indent (see next section) strictly less than reference one. This is like
---   casting rays up and down from input line and reference indent until
---   meeting "a wall" (non-whitespace character or buffer edge). Latest line
---   before that meeting is a respective range end of scope. It always exists
---   because input line is a such one.
--- - Based on top and bottom lines with strictly lower indent, compute scope's
---   "outer" indent. The way it is computed is decided based on
---   `MiniIndentscope.config.rules.scope` (see |MiniIndentscope.config| for
---   more information).
---
--- Indent computation~
---
--- For every line indent is intended to be computed unambiguously:
--- - For "normal" lines indent is an output of |indent()|.
--- - Indent is `-1` for imaginary lines 0 and past last line.
--- - For blank and empty lines indent is computed based on previous
---   (|prevnonblank()|) and next (|nextnonblank()|) non-blank lines. The way
---   it is computed is decided based on `MiniIndentscope.config.rules.blank`
---   (see |MiniIndentscope.config| for more information).
---
---@param line number Line number (starts from 1). Default: cursor line.
---@param col number Column number (starts from 1). Default: cursor column from
---   `curswant` of |getcurpos()|. This allows for more natural behavior on
---   empty lines.
---
---@return table Table with scope information:
---   - <buf_id> - identifier of current buffer.
---   - <indent> - table with <inner> (indent for computing scope) and <outer>
---     (computed indent of outer lines) keys.
---   - <range> - table with <top> (top line of scope, inclusive) and <bottom>
---     (bottom line of scope, inclusive) keys. Line numbers start at 1.
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
      indent = { inner = indent, outer = indent - 1 },
      range = { top = 1, bottom = vim.fn.line('$') },
    }
  end

  -- Compute scope
  local top, top_indent = H.cast_ray(line, indent, 'up')
  local bottom, bottom_indent = H.cast_ray(line, indent, 'down')

  local scope_rule = H.indent_rules[MiniIndentscope.config.rules.scope]
  return {
    buf_id = buf_id,
    indent = { inner = indent, outer = scope_rule(top_indent, bottom_indent) },
    range = { top = top, bottom = bottom },
  }
end

--- Auto draw scope indicator based on movement events
---
--- Designed to be used with |autocmd|. No need to use it directly, everything
--- is setup in |MiniIndentscope.setup|.
---
---@param opts table Options.
function MiniIndentscope.auto_draw(opts)
  if H.is_disabled() then
    H.undraw_scope()
    return
  end

  opts = opts or {}
  local scope = MiniIndentscope.get_scope()

  -- Make early return if nothing has to be done. Doing this before updating
  -- event id allows to not interrupt ongoing animation.
  if opts.lazy and H.current.draw_status ~= 'none' and H.scope_is_equal(scope, H.current.scope) then
    return
  end

  -- Account for current event
  local local_event_id = H.current.event_id + 1
  H.current.event_id = local_event_id

  -- Compute drawing options for current event
  local draw_opts = H.make_autodraw_opts(scope)

  -- Allow delay
  if draw_opts.delay > 0 then
    H.undraw_scope(draw_opts)
  end

  -- Use `defer_fn()` even if `delay` is 0 to draw indicator only after all
  -- events are processed (stops flickering)
  vim.defer_fn(function()
    if H.current.event_id ~= local_event_id then
      return
    end

    H.undraw_scope(draw_opts)

    H.current.scope = scope
    H.draw_scope(scope, draw_opts)
  end, draw_opts.delay)
end

--- Draw scope manually
---
---@param scope table Scope. Default: output of |MiniIndentscope.get_scope|
---   with default arguments.
---@param opts table Options. Currently supported:
---    - <animation_fun> - animation function for drawing. See
---      |MiniIndentscope-drawing| and |MiniIndentscope.animations|.
function MiniIndentscope.draw(scope, opts)
  scope = scope or MiniIndentscope.get_scope()
  local draw_opts = vim.tbl_deep_extend('force', { animation_fun = MiniIndentscope.config.draw.animation }, opts or {})

  H.undraw_scope()

  H.current.scope = scope
  H.draw_scope(scope, draw_opts)
end

--- Undraw currently visible scope manually
function MiniIndentscope.undraw()
  H.undraw_scope()
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
    draw = { config.draw, 'table' },
    ['draw.delay'] = { config.draw.delay, 'number' },
    ['draw.animation'] = { config.draw.animation, 'function' },

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
--- Indicator is visual representation of scope in current window view using
--- extmarks. Currently only needed because Neovim can't correctly process
--- horizontal window scroll (Neovim issue:
--- https://github.com/neovim/neovim/issues/14050)
---
---@return table|nil Table with indicator info or empty one in case indicator
---   shouldn't be drawn.
---@private
function H.indicator_compute(scope)
  scope = scope or H.current.scope
  local outer_indent = (scope.indent or {}).outer

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

  local top = scope.range.top
  local bottom = scope.range.bottom

  return { buf_id = vim.api.nvim_get_current_buf(), virt_text = virt_text, top = top, bottom = bottom }
end

-- Drawing --------------------------------------------------------------------
function H.draw_scope(scope, opts)
  scope = scope or {}
  opts = opts or {}

  local indicator = H.indicator_compute(scope)

  -- Don't draw anything if nothing to be displayed
  if indicator.virt_text == nil or #indicator.virt_text == 0 then
    H.current.draw_status = 'finished'
    return
  end

  -- Make drawing function
  local draw_fun = H.make_draw_function(indicator, opts)

  -- Perform drawing
  H.current.draw_status = 'drawing'
  H.draw_indicator_animation(indicator, draw_fun, opts.animation_fun)
end

function H.draw_indicator_animation(indicator, draw_fun, animation_fun)
  -- Draw from origin (cursor line but wihtin indicator range)
  local top, bottom = indicator.top, indicator.bottom
  local origin = math.min(math.max(vim.fn.line('.'), top), bottom)

  local step = 0
  local n_steps = math.max(origin - top, bottom - origin)
  local wait_time = 0

  local draw_step
  draw_step = vim.schedule_wrap(function()
    -- Check for not drawing outside of interval is done inside `draw_fun`
    local success = draw_fun(origin - step)
    if step > 0 then
      success = success and draw_fun(origin + step)
    end

    if not success or step == n_steps then
      H.current.draw_status = step == n_steps and 'finished' or H.current.draw_status
      H.timer:stop()
      return
    end

    step = step + 1
    wait_time = wait_time + animation_fun(step, n_steps)

    -- Repeat value of `timer` seems to be rounded down to milliseconds. This
    -- means that values less than 1 will lead to timer stop repeating. Instead
    -- call next step function directly.
    if wait_time < 1 then
      H.timer:set_repeat(0)
      draw_step()
    else
      H.timer:set_repeat(wait_time)

      -- Restart `wait_time` only if it is actually used
      wait_time = 0

      -- Usage of `again()` is needed to overcome the fact that it is called
      -- inside callback and to restart initial timer. Mainly this is needed
      -- only in case of transition from 'non-repeating' timer to 'repeating'
      -- one in case of complex animation functions. See
      -- https://docs.libuv.org/en/v1.x/timer.html#api
      H.timer:again()
    end
  end)

  -- Start non-repeating timer without callback execution. This shouldn't be
  -- `timer:start(0, 0, draw_step)` because it will execute `draw_step` on the
  -- next redraw (flickers on window scroll).
  H.timer:start(10000000, 0, draw_step)

  -- Draw step zero (at origin) immediately
  draw_step()
end

function H.undraw_scope(opts)
  opts = opts or {}

  -- Don't operate outside of current event if able to verify
  if opts.event_id and opts.event_id ~= H.current.event_id then
    return
  end

  pcall(vim.api.nvim_buf_clear_namespace, H.current.scope.buf_id or 0, H.ns_id, 0, -1)

  H.current.draw_status = 'none'
  H.current.scope = {}
end

function H.make_autodraw_opts(scope)
  local res = {
    event_id = H.current.event_id,
    type = 'animation',
    delay = MiniIndentscope.config.draw.delay,
    animation_fun = MiniIndentscope.config.draw.animation,
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

  return function(l)
    -- Don't draw if outdated
    if H.current.event_id ~= current_event_id and current_event_id ~= nil then
      return false
    end

    -- Don't put extmark outside of indicator range
    if not (indicator.top <= l and l <= indicator.bottom) then
      return true
    end

    return pcall(vim.api.nvim_buf_set_extmark, indicator.buf_id, H.ns_id, l - 1, 0, extmark_opts)
  end
end

-- Animations =================================================================
--- Imitate common power easing function
---
--- Every step is preceeded by waiting time decreasing/increasing in power
--- series fashion (`d` is 'delta', ensures total duration time):
--- - 'in':  d*n^p; d*(n-1)^p; ... ; d*2^p;     d*1^p
--- - 'out': d*1^p; d*2^p;     ... ; d*(n-1)^p; d*n^p
--- - 'in-out': 'in' until 0.5*n, 'out' afterwards
---
--- This way it imitates `power + 1` common easing function because animation
--- progression behaves as sum of `power` elements.
---
---@param power number Power of series.
---@param make_delta function Function which computes common delta so that
---   overall duration will have desired value.
---@param type __animation_type
---@private
function H.animation_arithmetic_powers(power, make_delta, type)
  return ({
    ['in'] = function(s, n)
      return make_delta(n) * (n - s + 1) ^ power
    end,
    ['out'] = function(s, n)
      return make_delta(n) * s ^ power
    end,
    ['in-out'] = function(s, n)
      local n_half = math.floor(0.5 * n + 0.5)
      -- Possibly use `0.5` because `make_delta` ensures total duration time
      -- within its input number steps.
      local coef = n_half <= 1 and 1 or 0.5

      if s <= n_half then
        return coef * make_delta(n_half) * (n_half - s + 1) ^ power
      end
      return coef * make_delta(n - n_half) * (s - n_half) ^ power
    end,
  })[type]
end

-- Utilities ------------------------------------------------------------------
function H.notify(msg)
  vim.notify(('(mini.indentscope) %s'):format(msg))
end

return MiniIndentscope
