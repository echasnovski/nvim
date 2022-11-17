-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO:
-- Code:
-- - Resize:
--     - Ensure there is proper animation for new forcused windows (most common
--       case). Needs to determine along which dimension to animate.
--
-- Tests:
-- - General:
--     - Timing generators work.
--     - "Single animation active" rule is true for all supported animations.
-- - Cursor move:
--     - Path generators work.
--     - Mark can be placed inside/outside line width.
--     - Multibyte characters are respected.
--     - Folds are ignored.
--     - Window view does not matter.
-- - Scroll:
--     - `max_steps` in default `subscroll` correctly respected: total number
--       of steps never exceeds it and subscroll are divided as equal as
--       possible (with remainder split in tails).
--     - Manual scroll during animated scroll is done without jump directly
--       from current window view.
--     - One command resulting into several `WinScrolled` events (like
--       `nnoremap n nzvzz`) is not really working.
--       Use `MiniAnimate.execute_after()`.
--     - There shouldn't be any step after `n_steps`. Specifically, manually
--       setting cursor *just* after scroll end should not lead to restoring
--       cursor some time later. This is more a test for appropriate treatment
--       of step 0.
--     - Cursor during scroll should be placed at final position or at first
--       column of top/bottom line (whichever is closest) if it is outside of
--       current window view.
--     - Switching window and/or buffer should result into immediate stop of
--       animation.
--
-- Documentation:
-- - Manually scrolling (like with `<C-d>`/`<C-u>`) while scrolling animation
--   is performed leads to a scroll from the window view active at the moment
--   of manual scroll. Leads to an undershoot of scrolling.
-- - Scroll animation is essentially a precisely scheduled non-blocking
--   subscroll. This has two important interconnected consequences:
--     - If another scroll is attempted to be done during the animation, it is
--       done based on the **currently visible** window view. Example: if user
--       presses |CTRL-D| and then |CTRL-U| when animation is half done, window
--       will not display the previous view half of 'scroll' above it.
--       This especially affects scrolling with mouse wheel, as each its turn
--       results in a new scroll for number of lines defined by 'mousescroll'.
--       To mitigate this issue, configure `config.scroll.subscroll()` to
--       return `nil` if number of lines to scroll is less or equal to one
--       emitted by mouse wheel. Like by setting `min_to_animate` option of
--       |MiniAnimate.gen_subscroll.equal()| to be one greater than that number.
--     - It breaks the use of several scrolling commands in the same command.
--       Use |MiniAnimate.execute_after()| to schedule action after reaching
--       target window view. Example: a useful `nnoremap n nzvzz` mapping
--       (combination of |n|, |zv|, and |zz|) should have this right hand side:
--       `n<Cmd>lua MiniAnimate.execute_after('scroll', 'normal! zvzz')<CR>`.
-- - If output of either `config.cursor.path()` or `config.scroll.subscroll()`
--   is `nil` or array of length 0, animation is suspended.
-- - Animated of scroll and resize are done only for current window. This is a
--   current limitation of |WinScrolled| event. Context:
--     - https://github.com/neovim/neovim/issues/18222
--     - https://github.com/vim/vim/issues/10628
--     - https://github.com/neovim/neovim/pull/13589
--     - https://github.com/neovim/neovim/issues/11532

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
        au WinScrolled * lua MiniAnimate.auto_resize()
        au WinEnter    * lua MiniAnimate.on_win_enter()
      augroup END]],
    false
  )
  -- Create highlighting
  vim.api.nvim_exec('hi default MiniAnimateCursor gui=reverse,nocombine', false)
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

  -- Window resize
  resize = {
    enable = true,
    timing = function(_, n) return math.min(10, 250 / n) end,
    subresize = function(total_resize) return H.subresize_equal(total_resize) end,
  },

  -- Window vertical scroll
  scroll = {
    enable = true,
    timing = function(_, n) return math.min(10, 250 / n) end,
    subscroll = function(total_scroll)
      return H.subscroll_equal(total_scroll, { min_to_animate = 2, max_to_animate = 10000000, max_number = 60 })
    end,
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
MiniAnimate.is_active = function(animation_type)
  local res = H.cache[animation_type .. '_is_active']
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

-- Action (step 0) - wait (step 1) - action (step 1) - ...
MiniAnimate.animate = function(step_action, step_timing, opts)
  opts = vim.tbl_deep_extend('force', { max_steps = 10000000 }, opts or {})

  local step, max_steps = 0, opts.max_steps
  local timer, wait_time = vim.loop.new_timer(), 0

  local draw_step
  draw_step = vim.schedule_wrap(function()
    local ok, should_continue = pcall(step_action, step)
    if not (ok and should_continue and step < max_steps) then
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

--- Generate subresize
---
--- Subresize - callable which takes `total_resize` argument (table with
--- <height> and <width> fields for how much vertical and horizontal resizing
--- should be done) and returns array resizing tables (similar to `total_resize`)
--- representing the amount of resizing in corresponding step. All fields in
--- subresize values should sum to corresponding field in input `total_scroll`.
MiniAnimate.gen_subresize = {}

---@param opts table Options. Currently is not used (reserved for future).
MiniAnimate.gen_subresize.equal = function(opts)
  return function(total_resize) return H.subresize_equal(total_resize) end
end

--- Generate subscroll
---
--- Subscroll - callable which takes `total_scroll` argument (single positive
--- integer) and returns array of positive integers each representing the
--- amount of lines needs to be scrolled in corresponding step. All subscroll
--- values should sum to input `total_scroll`.
MiniAnimate.gen_subscroll = {}

MiniAnimate.gen_subscroll.equal = function(opts)
  opts = vim.tbl_deep_extend('force', { min_to_animate = 2, max_number = 60 }, opts or {})

  return function(total_scroll) return H.subscroll_equal(total_scroll, opts) end
end

MiniAnimate.auto_cursor = function()
  -- Don't animate if inside scroll animation
  if H.cache.scroll_is_active then return end

  -- Update necessary information. NOTE: tracking only on `CursorMoved` and not
  -- inside every animation step (like in scroll animation) for performance
  -- reasons: cursor movement is much more common action than scrolling.
  local prev_state, new_state = H.cache.cursor_state, H.get_cursor_state()
  H.cache.cursor_state = new_state
  H.cache.cursor_event_id = H.cache.cursor_event_id + 1

  -- Possibly animate
  local cursor_config = H.get_config().cursor
  local should_animate = cursor_config.enable and not H.is_disabled() and new_state.buf_id == prev_state.buf_id
  if not should_animate then return end

  local animate_step = H.make_cursor_step(prev_state, new_state, cursor_config)
  if not animate_step then return end

  H.start_cursor()
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

MiniAnimate.auto_resize = function(is_new)
  -- Don't animate if nothing has changed since last registered resize.
  -- Mostly used to distinguish `WinScrolled` from animation and other ones.
  local prev_state, new_state = H.cache.resize_state, H.get_resize_state()

  local is_same_state = prev_state.win_id == new_state.win_id
    and prev_state.height == new_state.height
    and prev_state.width == new_state.width
  if is_same_state then return end

  -- Update necessary information.
  H.cache.resize_state = new_state
  H.cache.resize_event_id = H.cache.resize_event_id + 1

  -- Possibly animate
  local resize_config = H.get_config().resize
  local should_animate = resize_config.enable and not H.is_disabled() and new_state.win_id == prev_state.win_id
  if not should_animate then return end

  local animate_step = H.make_resize_step(prev_state, new_state, resize_config)
  if not animate_step then return end

  H.start_resize(prev_state)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

MiniAnimate.auto_scroll = function()
  -- Don't animate if nothing has changed since last registered scroll.
  -- Mostly used to distinguish `WinScrolled` from animation and other ones.
  local prev_state = H.cache.scroll_state
  if prev_state.view.topline == vim.fn.line('w0') then return end

  -- Update necessary information
  local new_state = H.get_scroll_state()
  H.cache.scroll_state = new_state
  H.cache.scroll_event_id = H.cache.scroll_event_id + 1

  -- Possibly animate
  local scroll_config = H.get_config().scroll
  local should_animate = scroll_config.enable
    and not H.is_disabled()
    and new_state.buf_id == prev_state.buf_id
    and new_state.win_id == prev_state.win_id
  if not should_animate then return end

  local animate_step = H.make_scroll_step(prev_state, new_state, scroll_config)
  if not animate_step then return end

  H.start_scroll(prev_state)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

MiniAnimate.on_win_enter = function()
  H.cache.scroll_state = H.get_scroll_state()
  H.cache.resize_state = H.get_resize_state()
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniAnimate.config

-- Cache for various operations
H.cache = {
  -- Cursor move animation data
  cursor_event_id = 0,
  cursor_is_active = false,
  cursor_state = { buf_id = nil, pos = {} },

  -- Resize animation data
  resize_event_id = 0,
  resize_is_active = false,
  resize_state = { win_id = nil, height = nil, width = nil },

  -- Scroll animation data
  scroll_event_id = 0,
  scroll_is_active = false,
  scroll_state = { buf_id = nil, win_id = nil, view = {} },
}

H.ns_id = {
  cursor = vim.api.nvim_create_namespace('MiniAnimateCursor'),
}

H.animation_done_events = {
  cursor = 'MiniAnimateCursorDone',
  resize = 'MiniAnimateResizeDone',
  scroll = 'MiniAnimateScrollDone',
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
    resize = { config.resize, H.is_config_resize },
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
H.make_cursor_step = function(state_from, state_to, opts)
  local pos_from, pos_to = state_from.pos, state_to.pos
  local destination = { pos_to[1] - pos_from[1], pos_to[2] - pos_from[2] }
  local path = opts.path(destination)
  if path == nil or #path == 0 then return H.stop_cursor() end

  local n_steps = #path
  local timing = opts.timing

  -- Using explicit buffer id allows correct animation stop after buffer switch
  local event_id, buf_id = H.cache.cursor_event_id, state_from.buf_id

  return {
    step_action = function(step)
      -- Undraw previous mark. Doing it before early return allows to clear
      -- last animation mark.
      H.undraw_cursor_mark(buf_id)

      -- Stop animation if another cursor movement is active. Don't use
      -- `stop_cursor()` because it will also mean to stop parallel animation.
      if H.cache.cursor_event_id ~= event_id then return false end

      -- Don't draw outside of prescribed number of steps or not inside current buffer
      if n_steps <= step or vim.api.nvim_get_current_buf() ~= buf_id then return H.stop_cursor() end

      -- Draw cursor mark (starting from initial zero step)
      local pos = path[step + 1]
      H.draw_cursor_mark(pos_from[1] + pos[1], pos_from[2] + pos[2], buf_id)
      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.get_cursor_state = function()
  -- Use character column to allow tracking outside of line width
  local curpos = vim.fn.getcursorcharpos()
  return { buf_id = vim.api.nvim_get_current_buf(), pos = { curpos[2], curpos[3] + curpos[4] } }
end

H.draw_cursor_mark = function(line, virt_col, buf_id)
  -- Use only absolute coordinates. Allows to not draw outside of buffer.
  if line <= 0 or virt_col <= 0 then return end

  -- Compute window column at which to place mark. Don't use explicit `col`
  -- argument because it won't allow placing mark outside of text line.
  local win_col = virt_col - vim.fn.winsaveview().leftcol
  if win_col < 1 then return end

  -- Set extmark
  local extmark_opts = {
    id = 1,
    hl_mode = 'combine',
    priority = 1000,
    right_gravity = false,
    virt_text = { { ' ', 'MiniAnimateCursor' } },
    virt_text_win_col = win_col - 1,
    virt_text_pos = 'overlay',
  }
  pcall(vim.api.nvim_buf_set_extmark, buf_id, H.ns_id.cursor, line - 1, 0, extmark_opts)
end

H.undraw_cursor_mark = function(buf_id) pcall(vim.api.nvim_buf_del_extmark, buf_id, H.ns_id.cursor, 1) end

H.start_cursor = function()
  H.cache.cursor_is_active = true
  return true
end

H.stop_cursor = function()
  H.cache.cursor_is_active = false
  H.emit_done_event('cursor')
  return false
end

-- Resize ---------------------------------------------------------------------
H.make_resize_step = function(state_from, state_to, opts)
  -- Compute how subresizing is done
  local height_diff, width_diff = state_to.height - state_from.height, state_to.width - state_from.width
  local total_resize = { height = math.abs(height_diff), width = math.abs(width_diff) }
  local step_resizes = opts.subresize(total_resize)

  -- Don't animate if no subresize steps is returned
  if step_resizes == nil or #step_resizes == 0 then return H.stop_resize(state_to) end

  -- Create animation step
  local event_id, win_id = H.cache.resize_event_id, state_from.win_id
  local n_steps, timing = #step_resizes, opts.timing

  -- Compute array of window states for easier step code
  local height_sign, width_sign = height_diff > 0 and 1 or -1, width_diff > 0 and 1 or -1
  local step_states, prev_size = {}, state_from
  for i, resize in ipairs(step_resizes) do
    --stylua: ignore
    step_states[i] = {
      win_id = win_id,
      height = prev_size.height + height_sign * resize.height,
      width  = prev_size.width + width_sign * resize.width,
    }
    prev_size = step_states[i]
  end

  return {
    step_action = function(step)
      -- Stop animation if another resize is active. Don't use `stop_resize()`
      -- because it will also mean to stop parallel animation.
      if H.cache.resize_event_id ~= event_id then return false end

      -- Stop animation if jumped to different buffer or window. Don't restore
      -- window view as it can only operate on current window.
      if not vim.api.nvim_get_current_win() == win_id then return H.stop_resize() end

      -- Preform resize. Possibly stop on error.
      local cur_state = step_states[step]
      local ok, _ = pcall(H.apply_resize_state, cur_state)
      if not ok then return H.stop_resize(state_to) end

      -- Update current resize state for two reasons:
      -- - Be able to distinguish manual `WinScrolled` event from one created
      --   by `apply_resize_state()`.
      -- - Be able to start manual resizing at any animation step.
      H.cache.resize_state = cur_state

      -- Properly stop animation if step is too big
      if n_steps <= step then return H.stop_resize(state_to) end

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.apply_resize_state = function(state)
  -- Allow supplying non-valid state for initial "resize"
  if state == nil then return end
  vim.api.nvim_win_set_height(state.win_id, state.height)
  vim.api.nvim_win_set_width(state.win_id, state.width)
end

H.start_resize = function(start_state)
  H.cache.resize_is_active = true
  if start_state ~= nil then H.apply_resize_state(start_state) end
  return true
end

H.stop_resize = function(end_state)
  if end_state ~= nil then H.apply_resize_state(end_state) end
  H.cache.resize_is_active = false
  H.emit_done_event('resize')
  return false
end

H.get_resize_state = function()
  local win_id = vim.api.nvim_get_current_win()
  return { win_id = win_id, height = vim.api.nvim_win_get_height(win_id), width = vim.api.nvim_win_get_width(win_id) }
end

-- Scroll ---------------------------------------------------------------------
H.make_scroll_step = function(state_from, state_to, opts)
  local from_line, to_line = state_from.view.topline, state_to.view.topline

  -- Compute how subscrolling is done
  local total_scroll = H.get_n_visible_lines(from_line, to_line) - 1
  local step_scrolls = opts.subscroll(total_scroll)

  -- Don't animate if no subscroll steps is returned
  if step_scrolls == nil or #step_scrolls == 0 then return H.stop_scroll(state_to) end

  -- Compute scrolling key ('\25' and '\5' are escaped '<C-Y>' and '<C-E>') and
  -- final cursor position
  local scroll_key = from_line < to_line and '\5' or '\25'
  local final_cursor_pos = { state_to.view.lnum, state_to.view.col }

  local event_id, buf_id, win_id = H.cache.scroll_event_id, state_from.buf_id, state_from.win_id
  local n_steps, timing = #step_scrolls, opts.timing
  return {
    step_action = function(step)
      -- Stop animation if another scroll is active. Don't use `stop_scroll()`
      -- because it will also mean to stop parallel animation.
      if H.cache.scroll_event_id ~= event_id then return false end

      -- Stop animation if jumped to different buffer or window. Don't restore
      -- window view as it can only operate on current window.
      local is_same_win_buf = vim.api.nvim_get_current_buf() == buf_id and vim.api.nvim_get_current_win() == win_id
      if not is_same_win_buf then return H.stop_scroll() end

      -- Preform scroll. Possibly stop on error.
      -- NOTE: use `0` for scroll step for inital step zero.
      local ok, _ = pcall(H.scroll_action, scroll_key, step_scrolls[step] or 0, final_cursor_pos)
      if not ok then return H.stop_scroll(state_to) end

      -- Update current scroll state for two reasons:
      -- - Be able to distinguish manual `WinScrolled` event from one created
      --   by `H.scroll_action()`.
      -- - Be able to start manual scrolling at any animation step.
      H.cache.scroll_state = H.get_scroll_state()

      -- Properly stop animation if step is too big
      if n_steps <= step then return H.stop_scroll(state_to) end

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.scroll_action = function(key, n, final_cursor_pos)
  -- Scroll. Allow supplying non-valid `n` for initial "scroll" which sets
  -- cursor immediately, which reduces flicker.
  if n ~= nil and n > 0 then
    local command = string.format('normal! %d%s', n, key)
    vim.cmd(command)
  end

  -- Set cursor to properly handle final cursor position
  local top, bottom = vim.fn.line('w0'), vim.fn.line('w$')
  --stylua: ignore start
  local line, col = final_cursor_pos[1], final_cursor_pos[2]
  if line < top    then line, col = top,    0 end
  if bottom < line then line, col = bottom, 0 end
  --stylua: ignore end
  vim.api.nvim_win_set_cursor(0, { line, col })
end

H.start_scroll = function(start_state)
  H.cache.scroll_is_active = true
  if start_state ~= nil then vim.fn.winrestview(start_state.view) end
  return true
end

H.stop_scroll = function(end_state)
  if end_state ~= nil then vim.fn.winrestview(end_state.view) end
  H.cache.scroll_is_active = false
  H.emit_done_event('scroll')
  return false
end

H.get_scroll_state = function()
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

-- Animation subscroll --------------------------------------------------------
H.subscroll_equal = function(total_scroll, opts)
  -- Animate only when `total_scroll` is inside appropriate range
  if not (opts.min_to_animate <= total_scroll and total_scroll <= opts.max_to_animate) then return end

  -- Don't make more than `max_number` steps
  local n_steps = math.min(total_scroll, opts.max_number)
  return H.divide_equal(total_scroll, n_steps)
end

-- Animation subresize --------------------------------------------------------
H.subresize_equal = function(total_resize)
  local n_steps = math.max(total_resize.height, total_resize.width)
  local step_height = H.divide_equal(total_resize.height, n_steps)
  local step_width = H.divide_equal(total_resize.width, n_steps)
  local res = {}
  for i = 1, n_steps do
    res[i] = { height = step_height[i], width = step_width[i] }
  end
  return res
end

-- Predicators ----------------------------------------------------------------
H.is_config_cursor = function(x)
  if type(x.enable) ~= 'boolean' then return false, H.msg_config('cursor.enable', 'boolean') end
  if not vim.is_callable(x.timing) then return false, H.msg_config('cursor.timing', 'callable') end
  if not vim.is_callable(x.path) then return false, H.msg_config('cursor.path', 'callable') end

  return true
end

H.is_config_resize = function(x)
  if type(x.enable) ~= 'boolean' then return false, H.msg_config('resize.enable', 'boolean') end
  if not vim.is_callable(x.timing) then return false, H.msg_config('resize.timing', 'callable') end
  if not vim.is_callable(x.subresize) then return false, H.msg_config('resize.subresize', 'callable') end

  return true
end

H.is_config_scroll = function(x)
  if type(x.enable) ~= 'boolean' then return false, H.msg_config('scroll.enable', 'boolean') end
  if not vim.is_callable(x.timing) then return false, H.msg_config('scroll.timing', 'callable') end
  if not vim.is_callable(x.subscroll) then return false, H.msg_config('scroll.subscroll', 'callable') end

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
