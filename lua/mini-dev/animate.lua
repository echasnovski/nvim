-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO:
-- Code:
-- - Create appropriate tracking and autocommands to animate automatically.
--   Should take into account:
--     - Folds?  Probably not with reasoning to make "animation of absoulte
--       cursor movement within buffer".
--     - Visualizing only inside current view? Probably not with reasoning to
--       make "animation of absoulte cursor movement within buffer".
-- - Scroll:
--     - Deal with back-to-back scrolls.
--     - Quantify severity of CPU loads.
--
-- Tests:
-- - Cursor move:
--     - All timing and path generators.
--     - Mark placing inside/outside line width.
--     - Multibyte characters.
--     - Folds.
--     - Window view.
--     - Simultenous animations.
--
-- Documentation:
--

-- Documentation ==============================================================
--- Animate common Neovim actions
---
--- Features:
--- - Animate cursor movement within same buffer. Cursor path is configurable.
--- - Animate window scrolling.
--- - Customizable animation rule.
---
--- # Setup~
---
--- This module needs a setup with `require('mini.animate').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniAnimate`
--- which you can use for scripting or manually (with `:lua MiniAnimate.*`).
---
--- See |MiniAnimate.config| for available config settings.
---
--- You can override runtime config settings (like `config.modifiers`) locally
--- to buffer inside `vim.b.minianimate_config` which should have same structure
--- as `MiniAnimate.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons~
--- - Neovide:
--- - '???/neoscroll.nvim':
--- - '???/specs.nvim':
---
--- # Highlight groups~
---
--- * `MiniAnimateCursorMove` - highlight of cursor during its animated movement.
--- * `MiniAnimateCursorMovePrefix` - highlight of space between line end and
---   cursor animation mark.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling~
---
--- To disable, set `g:minianimate_disable` (globally) or `b:minianimate_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.animate
---@tag MiniAnimate

---@diagnostic disable:undefined-field

-- Module definition ==========================================================
-- TODO: make local before release.
MiniAnimate = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniAnimate.config|.
---
---@usage `require('mini.animate').setup({})` (replace `{}` with your `config` table)
MiniAnimate.setup = function(config)
  -- Export module
  _G.MiniAnimate = MiniAnimate

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Module behavior
  vim.api.nvim_exec(
    [[augroup MiniAnimate
        au!
        au CursorMoved * lua MiniAnimate.on_cursor_moved()
        au WinScrolled * noautocmd lua MiniAnimate.on_win_scrolled()
        au WinEnter    * noautocmd lua MiniAnimate.on_win_enter()
      augroup END]],
    false
  )
  -- Create highlighting
  vim.api.nvim_exec(
    [[hi default MiniAnimateCursorMove gui=reverse,nocombine
      hi MiniAnimateCursorMovePrefix guifg=NONE guibg=NONE gui=nocombine]],
    false
  )
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Options ~
---
MiniAnimate.config = {
  -- Path of cursor movement within same buffer
  cursor_move = {
    enable = true,
    timing = function(_, n) return math.min(10, 250 / n) end,
    path = function(destination) return H.path_line(destination, H.path_default_predicate) end,
  },

  -- Window vertical scroll
  scroll = {
    enable = true,
    timing = function(_, n) return math.min(10, 250 / n) end,
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Generate animation rule
MiniAnimate.gen_timing = {}

MiniAnimate.gen_timing.none = function()
  return function() return 0 end
end

MiniAnimate.gen_timing.linear = function(opts) return H.timing_arithmetic(0, H.normalize_timing_opts(opts)) end

MiniAnimate.gen_timing.quadratic = function(opts) return H.timing_arithmetic(1, H.normalize_timing_opts(opts)) end

MiniAnimate.gen_timing.cubic = function(opts) return H.timing_arithmetic(2, H.normalize_timing_opts(opts)) end

MiniAnimate.gen_timing.quartic = function(opts) return H.timing_arithmetic(3, H.normalize_timing_opts(opts)) end

MiniAnimate.gen_timing.exponential = function(opts) return H.timing_geometrical(H.normalize_timing_opts(opts)) end

--- Generate animation path
---
--- Animation path - callable which takes `destination` argument (2d integer
--- point) and return array of relative to (0, 0) places for animation to
--- visit.
MiniAnimate.gen_path = {}

MiniAnimate.gen_path.line = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.path_default_predicate

  return function(destination) return H.path_line(destination, predicate) end
end

MiniAnimate.gen_path.angle = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.path_default_predicate
  local first_direction = opts.first_direction or 'horizontal'

  local append_horizontal = function(res, dest_col, const_line)
    local step = H.make_step(dest_col)
    if step == 0 then return end
    for i = 0, dest_col - step, step do
      table.insert(res, { const_line, i })
    end
  end

  local append_vertical = function(res, dest_line, const_col)
    local step = H.make_step(dest_line)
    if step == 0 then return end
    for i = 0, dest_line - step, step do
      table.insert(res, { i, const_col })
    end
  end

  return function(destination)
    -- Don't animate in case of false predicate
    if not predicate(destination) then return {} end

    -- Travel along horizontal/vertical lines
    local res = {}
    if first_direction == 'horizontal' then
      append_horizontal(res, destination[2], 0)
      append_vertical(res, destination[1], destination[2])
    else
      append_vertical(res, destination[1], 0)
      append_horizontal(res, destination[2], destination[1])
    end

    return res
  end
end

MiniAnimate.on_cursor_moved = function()
  if H.cache.is_inside_animate_scroll then return end

  local cursor_move_config = H.get_config().cursor_move

  -- Use character column to allow tracking outside of linw width
  local curpos = vim.fn.getcursorcharpos()
  local new_tracking = { buf_id = vim.api.nvim_get_current_buf(), pos = { curpos[2], curpos[3] + curpos[4] } }

  local prev_tracking = H.cache.cursor_tracking
  local should_animate = cursor_move_config.enable
    and not H.is_disabled()
    and new_tracking.buf_id == prev_tracking.buf_id

  if should_animate then
    local animate_step = H.make_cursor_move_step(prev_tracking, new_tracking, cursor_move_config)
    if animate_step ~= nil then H.animate(animate_step.step_action, animate_step.step_timing) end
  end

  H.cache.cursor_tracking = new_tracking
end

MiniAnimate.on_win_scrolled = function()
  if H.cache.is_inside_animate_scroll then return end

  local scroll_config = H.get_config().scroll

  local new_tracking =
    { buf_id = vim.api.nvim_get_current_buf(), win_id = vim.api.nvim_get_current_win(), view = vim.fn.winsaveview() }

  local prev_tracking = H.cache.scroll_tracking
  local should_animate = scroll_config.enable
    and not H.is_disabled()
    and new_tracking.buf_id == prev_tracking.buf_id
    and new_tracking.win_id == prev_tracking.win_id
    and new_tracking.view.topline ~= prev_tracking.view.topline

  if should_animate then
    local animate_step = H.make_scroll_step(prev_tracking, new_tracking, scroll_config)
    if animate_step ~= nil then
      -- Start animating from previous view
      vim.fn.winrestview(prev_tracking.view)
      H.cache.is_inside_animate_scroll = true
      H.animate(animate_step.step_action, animate_step.step_timing)
    end
  end

  H.cache.scroll_tracking = new_tracking
end

MiniAnimate.on_win_enter = function()
  H.cache.scroll_tracking =
    { buf_id = vim.api.nvim_get_current_buf(), win_id = vim.api.nvim_get_current_win(), view = vim.fn.winsaveview() }
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniAnimate.config

-- Cache for various operations
H.cache = {
  -- Cursor move animation data
  cursor_tracking = {},
  cursor_mark_id = 1,

  -- Scroll animation data
  scroll_tracking = {},
  is_inside_animate_scroll = false,
}

H.ns_id = {
  cursor_move = vim.api.nvim_create_namespace('MiniAnimateCursorMove'),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    cursor_move = { config.cursor_move, H.is_config_cursor_move },
    scroll = { config.cursor_move, H.is_config_scroll },
  })

  return config
end

H.apply_config = function(config) MiniAnimate.config = config end

H.is_disabled = function() return vim.g.minianimate_disable == true or vim.b.minianimate_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniAnimate.config, vim.b.minianimate_config or {}, config or {})
end

-- Animation ------------------------------------------------------------------
H.animate = function(step_action, step_timing)
  -- Using explicit buffer id allows for animation
  local step = 1
  local timer, wait_time = vim.loop.new_timer(), 0

  local draw_step
  draw_step = vim.schedule_wrap(function()
    local ok, should_continue = pcall(step_action, step)
    if not (ok and should_continue) then
      timer:stop()
      return
    end

    step = step + 1
    wait_time = wait_time + step_timing(step)

    -- Repeat value of `timer` seems to be rounded down to milliseconds. This
    -- means that values less than 1 will lead to timer stop repeating. Instead
    -- call next step function directly.
    if wait_time < 1 then
      timer:set_repeat(0)
      -- Use `return` to make this proper "tail call"
      return draw_step()
    else
      timer:set_repeat(wait_time)
      wait_time = 0
      timer:again()
    end
  end)

  -- Start non-repeating timer without callback execution
  timer:start(10000000, 0, draw_step)

  -- Draw step zero (at origin) immediately
  draw_step()
end

-- Cursor movement ------------------------------------------------------------
H.make_cursor_move_step = function(data_from, data_to, opts)
  local pos_from, pos_to = data_from.pos, data_to.pos
  local destination = { pos_to[1] - pos_from[1], pos_to[2] - pos_from[2] }
  local path = opts.path(destination)
  if #path == 0 then return end

  local n_steps = #path
  local timing = opts.timing

  -- Using explicit buffer id allows correct animation stop after buffer switch
  local draw_opts = { buf_id = data_from.buf_id, mark_id = H.cache.cursor_mark_id }
  H.cache.cursor_mark_id = draw_opts.mark_id + 1

  return {
    step_action = function(step)
      H.undraw_cursor_mark(draw_opts)

      -- Don't draw outside of prescribed number of steps or not inside current buffer
      if n_steps < step or vim.api.nvim_get_current_buf() ~= draw_opts.buf_id then return false end

      local pos = path[step]
      H.draw_cursor_mark(pos_from[1] + pos[1], pos_from[2] + pos[2], draw_opts)
      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.draw_cursor_mark = function(line, virt_col, opts)
  local extmark_opts = {
    id = opts.mark_id,
    hl_mode = 'combine',
    priority = 1000,
    right_gravity = false,
    virt_text = { { ' ', 'MiniAnimateCursorMove' } },
    virt_text_pos = 'overlay',
  }

  -- Allow drawing mark outside of '$' mark of line (its width plus one)
  local n_past_line = virt_col - vim.fn.virtcol({ line, '$' })
  if n_past_line > 0 then
    virt_col = virt_col - n_past_line
    extmark_opts.virt_text =
      { { string.rep(' ', n_past_line), 'MiniAnimateCursorMovePrefix' }, { ' ', 'MiniAnimateCursorMove' } }
  end

  local mark_col = H.virtcol2col(0, line, virt_col - 1)
  pcall(vim.api.nvim_buf_set_extmark, opts.buf_id, H.ns_id.cursor_move, line - 1, mark_col, extmark_opts)
end

H.undraw_cursor_mark =
  function(opts) pcall(vim.api.nvim_buf_del_extmark, opts.buf_id, H.ns_id.cursor_move, opts.mark_id) end

-- Scroll ---------------------------------------------------------------------
H.make_scroll_step = function(data_from, data_to, opts)
  local from_line, to_line = data_from.view.topline, data_to.view.topline
  local n_steps = H.get_scroll_n_steps(from_line, to_line)
  -- Don't animate if scrolling only single line
  if n_steps <= 1 then return end

  local scroll_once = from_line < to_line and H.scroll_down or H.scroll_up

  local buf_id, win_id, timing = data_from.buf_id, data_from.win_id, opts.timing
  local stop_scrolling = function(restore_end_view)
    if restore_end_view then vim.fn.winrestview(data_to.view) end
    H.cache.is_inside_animate_scroll = false
    return false
  end

  return {
    step_action = function(step)
      local is_same_win_buf = vim.api.nvim_get_current_buf() == buf_id and vim.api.nvim_get_current_win() == win_id
      if not is_same_win_buf then return stop_scrolling(false) end

      if n_steps < step then return stop_scrolling(true) end

      local ok, _ = pcall(scroll_once)
      if not ok then return stop_scrolling(true) end

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

-- Key '\25' is escaped '<C-Y>'
H.scroll_up = function() vim.cmd('noautocmd normal! \25') end

-- Key '\5' is escaped '<C-E>'
H.scroll_down = function() vim.cmd('noautocmd normal! \5') end

H.get_scroll_n_steps = function(from_line, to_line)
  local min_line, max_line = math.min(from_line, to_line), math.max(from_line, to_line)

  -- If `max_line` is inside fold, scrol should stop on the fold (not after)
  local max_line_fold_start = vim.fn.foldclosed(max_line)
  local target_line = max_line_fold_start == -1 and max_line or max_line_fold_start

  local i, res = min_line, 0
  while i < target_line do
    res = res + 1
    local end_fold_line = vim.fn.foldclosedend(i)
    i = (end_fold_line == -1 and i or end_fold_line) + 1
  end
  return res
end

-- Animation timings ----------------------------------------------------------
H.normalize_timing_opts = function(x)
  x = vim.tbl_deep_extend('force', H.get_config(), { duration = 100, easing = 'in-out', unit = 'total' }, x or {})
  H.validate_if(H.is_valid_timing_opts, x, 'opts')
  return x
end

H.is_valid_timing_opts = function(x)
  if type(x.duration) ~= 'number' or x.duration < 0 then
    return false, [[In `gen_animation()` option `duration` should be a positive number.]]
  end

  if not vim.tbl_contains({ 'in', 'out', 'in-out' }, x.easing) then
    return false, [[In `gen_animation()` option `easing` should be one of 'in', 'out', or 'in-out'.]]
  end

  if not vim.tbl_contains({ 'total', 'step' }, x.unit) then
    return false, [[In `gen_animation()` option `unit` should be one of 'step' or 'total'.]]
  end

  return true
end

--- Imitate common power easing function
---
--- Every step is preceeded by waiting time decreasing/increasing in power
--- series fashion (`d` is "delta", ensures total duration time):
--- - "in":  d*n^p; d*(n-1)^p; ... ; d*2^p;     d*1^p
--- - "out": d*1^p; d*2^p;     ... ; d*(n-1)^p; d*n^p
--- - "in-out": "in" until 0.5*n, "out" afterwards
---
--- This way it imitates `power + 1` common easing function because animation
--- progression behaves as sum of `power` elements.
---
---@param power number Power of series.
---@param opts table Options from `MiniMap.gen_animation` entry.
---@private
H.timing_arithmetic = function(power, opts)
  -- Sum of first `n_steps` natural numbers raised to `power`
  local arith_power_sum = ({
    [0] = function(n_steps) return n_steps end,
    [1] = function(n_steps) return n_steps * (n_steps + 1) / 2 end,
    [2] = function(n_steps) return n_steps * (n_steps + 1) * (2 * n_steps + 1) / 6 end,
    [3] = function(n_steps) return n_steps ^ 2 * (n_steps + 1) ^ 2 / 4 end,
  })[power]

  -- Function which computes common delta so that overall duration will have
  -- desired value (based on supplied `opts`)
  local duration_unit, duration_value = opts.unit, opts.duration
  local make_delta = function(n_steps, is_in_out)
    local total_time = duration_unit == 'total' and duration_value or (duration_value * n_steps)
    local total_parts
    if is_in_out then
      -- Examples:
      -- - n_steps=5: 3^d, 2^d, 1^d, 2^d, 3^d
      -- - n_steps=6: 3^d, 2^d, 1^d, 1^d, 2^d, 3^d
      total_parts = 2 * arith_power_sum(math.ceil(0.5 * n_steps)) - (n_steps % 2 == 1 and 1 or 0)
    else
      total_parts = arith_power_sum(n_steps)
    end
    return total_time / total_parts
  end

  return ({
    ['in'] = function(s, n) return make_delta(n) * (n - s + 1) ^ power end,
    ['out'] = function(s, n) return make_delta(n) * s ^ power end,
    ['in-out'] = function(s, n)
      local n_half = math.ceil(0.5 * n)
      local s_halved
      if n % 2 == 0 then
        s_halved = s <= n_half and (n_half - s + 1) or (s - n_half)
      else
        s_halved = s < n_half and (n_half - s + 1) or (s - n_half + 1)
      end
      return make_delta(n, true) * s_halved ^ power
    end,
  })[opts.easing]
end

--- Imitate common exponential easing function
---
--- Every step is preceeded by waiting time decreasing/increasing in geometric
--- progression fashion (`d` is 'delta', ensures total duration time):
--- - 'in':  (d-1)*d^(n-1); (d-1)*d^(n-2); ...; (d-1)*d^1;     (d-1)*d^0
--- - 'out': (d-1)*d^0;     (d-1)*d^1;     ...; (d-1)*d^(n-2); (d-1)*d^(n-1)
--- - 'in-out': 'in' until 0.5*n, 'out' afterwards
---
---@param opts table Options from `MiniMap.gen_animation` entry.
---@private
H.timing_geometrical = function(opts)
  -- Function which computes common delta so that overall duration will have
  -- desired value (based on supplied `opts`)
  local duration_unit, duration_value = opts.unit, opts.duration
  local make_delta = function(n_steps, is_in_out)
    local total_time = duration_unit == 'step' and (duration_value * n_steps) or duration_value
    -- Exact solution to avoid possible (bad) approximation
    if n_steps == 1 then return total_time + 1 end
    if is_in_out then
      local n_half = math.ceil(0.5 * n_steps)
      if n_steps % 2 == 1 then total_time = total_time + math.pow(0.5 * total_time + 1, 1 / n_half) - 1 end
      return math.pow(0.5 * total_time + 1, 1 / n_half)
    end
    return math.pow(total_time + 1, 1 / n_steps)
  end

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
      local n_half, delta = math.ceil(0.5 * n), make_delta(n, true)
      local s_halved
      if n % 2 == 0 then
        s_halved = s <= n_half and (n_half - s) or (s - n_half - 1)
      else
        s_halved = s < n_half and (n_half - s) or (s - n_half)
      end
      return (delta - 1) * delta ^ s_halved
    end,
  })[opts.easing]
end

-- Animation paths ------------------------------------------------------------
H.path_line = function(destination, predicate)
  -- Don't animate in case of false predicate
  if not predicate(destination) then return {} end

  -- Travel along the biggest horizontal/vertical difference, but stop one
  -- step before destination
  local l, c = destination[1], destination[2]
  local l_abs, c_abs = math.abs(l), math.abs(c)
  local max_diff = math.max(l_abs, c_abs)

  local res = {}
  for i = 0, max_diff - 1 do
    local prop = i / max_diff
    table.insert(res, { H.round(prop * l), H.round(prop * c) })
  end
  return res
end

H.path_default_predicate = function(destination) return destination[1] < -1 or 1 < destination[1] end

-- Predicators ----------------------------------------------------------------
H.is_config_cursor_move = function(x)
  if type(x.enable) ~= 'boolean' then return false, H.msg_config('cursor_move.enable', 'boolean') end
  if not vim.is_callable(x.timing) then return false, H.msg_config('cursor_move.timing', 'callable') end
  if not vim.is_callable(x.path) then return false, H.msg_config('cursor_move.path', 'callable') end

  return true
end

H.is_config_scroll = function(x)
  if type(x.enable) ~= 'boolean' then return false, H.msg_config('scroll.enable', 'boolean') end
  if not vim.is_callable(x.timing) then return false, H.msg_config('scroll.timing', 'callable') end

  return true
end

H.msg_config = function(x_name, msg) return string.format('`%s` should be %s.', x_name, msg) end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.animate) %s', msg), 0) end

H.validate_if = function(predicate, x, x_name)
  local is_valid, msg = predicate(x, x_name)
  if not is_valid then H.error(msg) end
end

H.set_extmark_safely = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.str_width = function(x)
  -- Use first returned value (UTF-32 index, and not UTF-16 one)
  local res = vim.str_utfindex(x)
  return res
end

H.make_step = function(x) return x == 0 and 0 or (x < 0 and -1 or 1) end

H.round = function(x) return math.floor(x + 0.5) end

-- `virtcol2col()` is only present in Neovim>=0.8. Earlier Neovim versions will
-- have troubles dealing with multibyte characters.
H.virtcol2col = vim.fn.virtcol2col or function(_, _, col) return col end

return MiniAnimate