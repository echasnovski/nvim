-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO:
-- Code:
-- - Scroll:
--     - Rethink back-to-back scrolling. Consider following cases: spamming
--       `<C-d>`; mouse wheel scroll.
--       ???Maybe??? debounce after animation start (with configurable delay)?
--       So first scroll is animated. If during animation manual scroll is
--       triggered, animation is suspended and this scroll is done immediately.
--       Also all other ones within debounce delay from previous not-animated
--       one.
--     - Ensure there is no flickering at the start and end of animation.
--     - Think about smoother cursor experience during scroll.
-- - Window resize, utilizing `WinScrolled` event.
--
-- Tests:
-- - Cursor move:
--     - All timing and path generators.
--     - Mark placing inside/outside line width.
--     - Multibyte characters.
--     - Folds.
--     - Window view.
--     - Simultenous animations.
-- - Scroll:
--     - `max_steps` in default `subscrolls` correctly respected: total number
--       of steps never exceeds it and subscrolls are divided as equal as
--       possible (with remainder split in tails).
--     - Manual scroll during animated scroll is done without jump directly
--       from current window view.
--     - One command emitting several `WinScrolled` events should work
--       properly based on the last view. Example: `nnoremap n nzvzz`.
--
-- Documentation:
-- - Manually scrolling (like with `<C-d>`/`<C-u>`) while scrolling animation
--   is performed leads to a scroll from the window view active at the moment
--   of manual scroll. Leads to an undershoot of scrolling.
-- - Scroll animation is essentially a precisely scheduled non-blocking
--   subscrolls. This has two important interconnected consequences:
--     - If another scroll is attempted to be done during the animation, it is
--       done based on the **currently visible** window view. Example: if user
--       presses |CTRL-D| and then |CTRL-U| when animation is half done, window
--       will not display the previous view half of 'scroll' above it.
--     - It breaks the use of several scrolling commands in the same command.
--       Use |MiniAnimate.execute_after()| to schedule action after reaching
--       target window view. Example: a useful `nnoremap n nzvzz` mapping
--       (combination of |n|, |zv|, and |zz|) should have this right hand side:
--       `n<Cmd>lua MiniAnimate.execute_after('scroll', 'normal! zvzz')<CR>`.
-- - If output of either `config.cursor.path()` or `config.scroll.subscrolls()`
--   is `nil` or array of length 0, animation is suspended.

-- Documentation ==============================================================
--- Animate common Neovim actions
---
--- Features:
--- - Animate cursor movement within same buffer. Cursor path is configurable.
--- - Animate window scrolling.
--- - Animate window resize.
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
--- * `MiniAnimateCursor` - highlight of cursor during its animated movement.
--- * `MiniAnimateCursorPrefix` - highlight of space between line end and
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
        au CursorMoved * lua MiniAnimate.auto_cursor()
        au WinScrolled * lua MiniAnimate.auto_scroll()
        au WinEnter    * lua MiniAnimate.on_win_enter()
      augroup END]],
    false
  )
  -- Create highlighting
  vim.api.nvim_exec(
    [[hi default MiniAnimateCursor gui=reverse,nocombine
      hi MiniAnimateCursorPrefix guifg=NONE guibg=NONE gui=nocombine]],
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
  cursor = {
    enable = true,
    timing = function(_, n) return math.min(10, 250 / n) end,
    path = function(destination) return H.path_line(destination, H.path_default_predicate) end,
  },

  -- Window vertical scroll
  scroll = {
    enable = true,
    timing = function(_, n) return math.min(10, 250 / n) end,
    subscrolls = function(total_scroll)
      return H.subscrolls_equal(total_scroll, { min_to_animate = 2, max_to_animate = 10000000, max_n_subscrolls = 60 })
    end,
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
MiniAnimate.is_active = function(animation_type)
  local res = ({
    cursor = H.cache.cursor_is_active,
    scroll = H.cache.scroll_is_active,
    resize = H.cache.resize_is_active,
  })[animation_type]
  if res == nil then H.error('Wrong `animation_type` for `is_active()`.') end
  return res
end

MiniAnimate.execute_after = function(animation_type, action)
  local event_name = H.animation_done_events[animation_type]
  if event_name == nil then H.error('Wrong `animation_type` for `execute_after`.') end

  local callable = action
  if type(callable) == 'string' then callable = function() vim.cmd(action) end end
  if not vim.is_callable(callable) then
    H.error('Argument `action` of `execute_after()` should be string or callable.')
  end

  -- Schedule conditional action execution to allow animation to actually take
  -- effect. This helps creating more universal mappings, because some commands
  -- (like `n`) not always result into scrolling.
  vim.schedule(function()
    if MiniAnimate.is_active('scroll') then
      -- TODO: use `nvim_create_autocmd()` after Neovim<=0.6 support is dropped
      MiniAnimate._action = callable
      local au_cmd = string.format('au User %s ++once lua MiniAnimate._action(); MiniAnimate._action = nil', event_name)
      vim.cmd(au_cmd)
    else
      callable()
    end
  end)
end

MiniAnimate.animate = function(step_action, step_timing)
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
--- point in (line, col) coordinates) and returns array of relative to (0, 0)
--- places for animation to visit.
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

MiniAnimate.gen_path.walls = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.path_default_predicate
  local width = opts.width or 10

  return function(destination)
    -- Don't animate in case of false predicate
    if not predicate(destination) then return {} end

    local dest_line, dest_col = destination[1], destination[2]
    local res = {}
    for i = width, 1, -1 do
      table.insert(res, { dest_line, dest_col + i })
      table.insert(res, { dest_line, dest_col - i })
    end
    return res
  end
end

MiniAnimate.gen_path.spiral = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.path_default_predicate
  local width = opts.width or 2

  local add_layer = function(res, w, destination)
    local dest_line, dest_col = destination[1], destination[2]
    --stylua: ignore start
    for j = -w, w-1 do table.insert(res, { dest_line - w, dest_col + j }) end
    for i = -w, w-1 do table.insert(res, { dest_line + i, dest_col + w }) end
    for j = -w, w-1 do table.insert(res, { dest_line + w, dest_col - j }) end
    for i = -w, w-1 do table.insert(res, { dest_line - i, dest_col - w }) end
    --stylua: ignore end
  end

  return function(destination)
    -- Don't animate in case of false predicate
    if not predicate(destination) then return {} end

    local res = {}
    for w = width, 1, -1 do
      add_layer(res, w, destination)
    end
    return res
  end
end

--- Generate subscrolls
---
--- Subscrolls - callable which takes `total_scroll` argument (single positive
--- integer) and returns array of positive integers each representing the
--- amount of lines needs to be scrolled in corresponding step. All subscroll
--- values should sum to input `total_scroll`.
MiniAnimate.gen_subscrolls = {}

MiniAnimate.gen_subscrolls.equal = function(opts)
  opts = vim.tbl_deep_extend('force', { min_to_animate = 2, max_n_subscrolls = 60 }, opts or {})

  return function(total_scroll) return H.subscrolls_equal(total_scroll, opts) end
end

MiniAnimate.auto_cursor = function()
  -- Don't animate if inside scroll animation
  if H.cache.scroll_is_active then return end

  -- Track necessary information
  local prev_tracking, new_tracking = H.cache.cursor_tracking, H.compute_cursor_tracking()
  H.cache.cursor_tracking = new_tracking

  -- Possibly animate
  local cursor_config = H.get_config().cursor
  local should_animate = cursor_config.enable and not H.is_disabled() and new_tracking.buf_id == prev_tracking.buf_id
  if not should_animate then return end

  local animate_step = H.make_cursor_step(prev_tracking, new_tracking, cursor_config)
  if not animate_step then return end

  H.start_cursor()
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

MiniAnimate.auto_scroll = function()
  -- Don't animate if nothing has changed sinse last registered scroll.
  -- Mostly used to distinguish `WinScrolled` from animation and other ones.
  if H.cache.scroll_tracking.view.topline == vim.fn.line('w0') then return end

  H.cache.scroll_event_id = H.cache.scroll_event_id + 1

  -- Track necessary information
  local prev_tracking, new_tracking = H.cache.scroll_tracking, H.compute_scroll_tracking()
  H.cache.scroll_tracking = new_tracking

  -- Possibly animate
  local scroll_config = H.get_config().scroll
  local should_animate = scroll_config.enable
    and not H.is_disabled()
    and new_tracking.buf_id == prev_tracking.buf_id
    and new_tracking.win_id == prev_tracking.win_id
  if not should_animate then return end

  local animate_step = H.make_scroll_step(prev_tracking, new_tracking, scroll_config)
  if not animate_step then return end

  H.start_scroll(prev_tracking.view)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

MiniAnimate.on_win_enter = function() H.cache.scroll_tracking = H.compute_scroll_tracking() end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniAnimate.config

-- Cache for various operations
H.cache = {
  -- Cursor move animation data
  cursor_is_active = false,
  cursor_tracking = { buf_id = nil, pos = {} },
  cursor_mark_id = 1,

  -- Scroll animation data
  scroll_is_active = false,
  scroll_tracking = { buf_id = nil, win_id = nil, view = {} },
  scroll_event_id = 0,
}

H.ns_id = {
  cursor = vim.api.nvim_create_namespace('MiniAnimateCursor'),
}

H.animation_done_events = {
  cursor = 'MiniAnimateCursorDone',
  scroll = 'MiniAnimateScrollDone',
  resize = 'MiniAnimateResizeDone',
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    cursor = { config.cursor, H.is_config_cursor },
    scroll = { config.scroll, H.is_config_scroll },
  })

  return config
end

H.apply_config = function(config) MiniAnimate.config = config end

H.is_disabled = function() return vim.g.minianimate_disable == true or vim.b.minianimate_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniAnimate.config, vim.b.minianimate_config or {}, config or {})
end

-- General animation ----------------------------------------------------------
H.emit_done_event = function(animation_type) vim.cmd('doautocmd User ' .. H.animation_done_events[animation_type]) end

-- Cursor ---------------------------------------------------------------------
H.make_cursor_step = function(data_from, data_to, opts)
  local pos_from, pos_to = data_from.pos, data_to.pos
  local destination = { pos_to[1] - pos_from[1], pos_to[2] - pos_from[2] }
  local path = opts.path(destination)
  if path == nil or #path == 0 then return H.stop_cursor() end

  local n_steps = #path
  local timing = opts.timing

  -- Using explicit buffer id allows correct animation stop after buffer switch
  local draw_opts = { buf_id = data_from.buf_id, mark_id = H.cache.cursor_mark_id }
  H.cache.cursor_mark_id = draw_opts.mark_id + 1

  return {
    step_action = function(step)
      -- Undraw previous mark. Doing it before early return allows to clear
      -- last animation mark.
      H.undraw_cursor_mark(draw_opts)

      -- Don't draw outside of prescribed number of steps or not inside current buffer
      if n_steps < step or vim.api.nvim_get_current_buf() ~= draw_opts.buf_id then return H.stop_cursor() end

      -- Draw cursor mark
      local pos = path[step]
      H.draw_cursor_mark(pos_from[1] + pos[1], pos_from[2] + pos[2], draw_opts)
      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.compute_cursor_tracking = function()
  -- Use character column to allow tracking outside of linw width
  local curpos = vim.fn.getcursorcharpos()
  return { buf_id = vim.api.nvim_get_current_buf(), pos = { curpos[2], curpos[3] + curpos[4] } }
end

H.draw_cursor_mark = function(line, virt_col, opts)
  -- Use only absolute coordinates. Allows to not draw outside of buffer.
  if line <= 0 or virt_col <= 0 then return end

  local extmark_opts = {
    id = opts.mark_id,
    hl_mode = 'combine',
    priority = 1000,
    right_gravity = false,
    virt_text = { { ' ', 'MiniAnimateCursor' } },
    virt_text_pos = 'overlay',
  }

  -- Allow drawing mark outside of '$' mark of line (its width plus one)
  local n_past_line = virt_col - vim.fn.virtcol({ line, '$' })
  if n_past_line > 0 then
    virt_col = virt_col - n_past_line
    extmark_opts.virt_text =
      { { string.rep(' ', n_past_line), 'MiniAnimateCursorPrefix' }, { ' ', 'MiniAnimateCursor' } }
  end

  local mark_col = H.virtcol2col(0, line, virt_col - 1)
  pcall(vim.api.nvim_buf_set_extmark, opts.buf_id, H.ns_id.cursor, line - 1, mark_col, extmark_opts)
end

H.undraw_cursor_mark = function(opts) pcall(vim.api.nvim_buf_del_extmark, opts.buf_id, H.ns_id.cursor, opts.mark_id) end

H.start_cursor = function()
  H.cache.cursor_is_active = true
  return true
end

H.stop_cursor = function()
  H.cache.cursor_is_active = false
  H.emit_done_event('cursor')
  return false
end

-- Scroll ---------------------------------------------------------------------
H.make_scroll_step = function(data_from, data_to, opts)
  local from_line, to_line = data_from.view.topline, data_to.view.topline

  -- Compute how subscrolls are done
  local total_scroll = H.get_n_visible_lines(from_line, to_line) - 1
  local step_scrolls = opts.subscrolls(total_scroll)

  -- Don't animate if no subscroll steps is returned
  if step_scrolls == nil or #step_scrolls == 0 then return H.stop_scroll(data_to.view) end

  -- Compute scrolling step
  local scroll_step = from_line < to_line and H.scroll_down or H.scroll_up

  local event_id, buf_id, win_id = H.cache.scroll_event_id, data_from.buf_id, data_from.win_id
  local n_steps, timing = #step_scrolls, opts.timing
  return {
    step_action = function(step)
      -- Stop animation if another scroll is active. Don't use `stop_scrolling`
      -- because it will also mean to stop parallel animation.
      if H.cache.scroll_event_id ~= event_id then return false end

      -- Stop animation if jumped to different buffer or window. Don't restore
      -- window view as it can only operate on current window.
      local is_same_win_buf = vim.api.nvim_get_current_buf() == buf_id and vim.api.nvim_get_current_win() == win_id
      if not is_same_win_buf then return H.stop_scroll(false) end

      -- Properly stop animation if step is too big
      if n_steps < step then return H.stop_scroll(data_to.view) end

      -- Preform scroll. Possibly stop on error.
      local ok, _ = pcall(scroll_step, step_scrolls[step])
      if not ok then return H.stop_scroll(data_to.view) end

      -- Update current scroll tracking for two reasons:
      -- - Be able to distinguish manual `WinScrolled` event from one created
      --   by `scroll_step()`.
      -- - Be able to start manual scrolling at any animation step.
      H.cache.scroll_tracking = H.compute_scroll_tracking()

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

-- Key '\25' is escaped '<C-Y>'
H.scroll_up = function(n) vim.cmd(('normal! %d\25'):format(n or 1)) end

-- Key '\5' is escaped '<C-E>'
H.scroll_down = function(n) vim.cmd(('normal! %d\5'):format(n or 1)) end

H.start_scroll = function(start_view)
  H.cache.scroll_is_active = true
  if start_view ~= nil then vim.fn.winrestview(start_view) end
  return true
end

H.stop_scroll = function(end_view)
  if end_view ~= nil then vim.fn.winrestview(end_view) end
  H.cache.scroll_is_active = false
  H.emit_done_event('scroll')
  return false
end

H.compute_scroll_tracking = function()
  return {
    buf_id = vim.api.nvim_get_current_buf(),
    win_id = vim.api.nvim_get_current_win(),
    view = vim.fn.winsaveview(),
  }
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

-- Animation subscrolls -------------------------------------------------------
H.subscrolls_equal = function(total_scroll, opts)
  -- Animate only when `total_scroll` is inside appropriate range
  if not (opts.min_to_animate <= total_scroll and total_scroll <= opts.max_to_animate) then return end

  -- Don't make more than `max_n_subscrolls` steps
  local n_steps = math.min(total_scroll, opts.max_n_subscrolls)
  return H.divide_equal(total_scroll, n_steps)
end

-- Predicators ----------------------------------------------------------------
H.is_config_cursor = function(x)
  if type(x.enable) ~= 'boolean' then return false, H.msg_config('cursor.enable', 'boolean') end
  if not vim.is_callable(x.timing) then return false, H.msg_config('cursor.timing', 'callable') end
  if not vim.is_callable(x.path) then return false, H.msg_config('cursor.path', 'callable') end

  return true
end

H.is_config_scroll = function(x)
  if type(x.enable) ~= 'boolean' then return false, H.msg_config('scroll.enable', 'boolean') end
  if not vim.is_callable(x.timing) then return false, H.msg_config('scroll.timing', 'callable') end
  if not vim.is_callable(x.subscrolls) then return false, H.msg_config('scroll.subscrolls', 'callable') end

  return true
end

H.msg_config = function(x_name, msg) return string.format('`%s` should be %s.', x_name, msg) end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.animate) %s', msg), 0) end

H.validate_if = function(predicate, x, x_name)
  local is_valid, msg = predicate(x, x_name)
  if not is_valid then H.error(msg) end
end

H.get_n_visible_lines = function(from_line, to_line)
  local min_line, max_line = math.min(from_line, to_line), math.max(from_line, to_line)

  -- If `max_line` is inside fold, scrol should stop on the fold (not after)
  local max_line_fold_start = vim.fn.foldclosed(max_line)
  local target_line = max_line_fold_start == -1 and max_line or max_line_fold_start

  local i, res = min_line, 1
  while i < target_line do
    res = res + 1
    local end_fold_line = vim.fn.foldclosedend(i)
    i = (end_fold_line == -1 and i or end_fold_line) + 1
  end
  return res
end

H.make_step = function(x) return x == 0 and 0 or (x < 0 and -1 or 1) end

H.round = function(x) return math.floor(x + 0.5) end

H.divide_equal = function(x, n)
  local res = {}
  local base, remainder = math.floor(x / n), x % n

  -- Distribute equally with the remainder being inside tails
  local tail_left = math.floor(0.5 * remainder)
  local tail_right = n - (remainder - tail_left)
  for i = 1, n do
    local is_in_tail = i <= tail_left or tail_right < i
    res[i] = base + (is_in_tail and 1 or 0)
  end

  return res
end

-- `virtcol2col()` is only present in Neovim>=0.8. Earlier Neovim versions will
-- have troubles dealing with multibyte characters.
H.virtcol2col = vim.fn.virtcol2col or function(_, _, col) return col end

return MiniAnimate
