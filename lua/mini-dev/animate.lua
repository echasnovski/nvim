-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- TODO:
-- Code:
-- - General:
--     - Clean up and refactor (especially layout animation).
-- - Scroll:
--     - Think about making it work for `WinScrolled` in any window. If not,
--       document that scrolling is animated only inside current window (the
--       most common case).
-- - Layout:
--     - Animate when there are closed window(s). Should work with `:only` and
--       any current layout.
--     - Think about accounting for `VimResized`.
--
-- Tests:
-- - General:
--     - Timing generators work.
--     - "Single animation active" rule is true for all supported animations.
--     - Emits "done event" after finishing.
-- - Cursor move:
--     - Path generators work.
--     - Mark can be placed inside/outside line width.
--     - Multibyte characters are respected.
--     - Folds are ignored.
--     - Window view does not matter.
-- - Scroll:
--     - `max_n_output` in default `subscroll` correctly respected: total number
--       of steps never exceeds it and subscroll are divided as equal as
--       possible (with remainder equally split between all subscrolls).
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
-- - Layout:
--     - Works when resizing windows (`<C-w>|`, `<C-w>_`, `<C-w>=`, other
--       manual command).
--     - Works when opening new windows (`<C-w>v`, `<C-w>s`, other manual
--       command).
--     - Works when closing windows (`:quit`, manual command).
--     - Doesn't animate scroll during layout animation (including at the end).
--     - Works with `winheight`/`winwidth` in Neovim>=0.9.
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
--       emitted by mouse wheel. Like by setting `min_input` option of
--       |MiniAnimate.gen_subscroll.equal()| to be one greater than that number.
--     - It breaks the use of several scrolling commands in the same command.
--       Use |MiniAnimate.execute_after()| to schedule action after reaching
--       target window view. Example: a useful `nnoremap n nzvzz` mapping
--       (consecutive application of |n|, |zv|, and |zz|) should have this
--       right hand side:
-- `<Cmd>lua vim.cmd('normal! n'); MiniAnimate.execute_after('scroll', 'normal! zvzz')<CR>`.
--
-- - If output of either `config.cursor.path()` or `config.scroll.subscroll()`
--   is `nil` or array of length 0, animation is suspended.
-- - Animation of scroll and layout works best with Neovim>=0.9 (after updates
--   to |WinScrolled| event and introduction of |WinResized| event). For
--   example, animation resulting from effect of 'winheight'/'winwidth' will
--   work properly.
--   Context:
--     - https://github.com/neovim/neovim/issues/18222
--     - https://github.com/vim/vim/issues/10628
--     - https://github.com/neovim/neovim/pull/13589
--     - https://github.com/neovim/neovim/issues/11532

-- Documentation ==============================================================
--- Animate common Neovim actions
---
--- Features:
--- - Animate cursor movement within same buffer. Cursor path is configurable.
--- - Animate scrolling.
--- - Animate layout change (usually during window close/open/resize).
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
--- - 'DanilaMihailov/beacon.nvim'
--- - 'camspiers/lens.vim'
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

local buf_id = vim.api.nvim_create_buf(false, true)

_G.animate_window_shade = function(win_id)
  if not vim.api.nvim_win_is_valid(win_id) then return end
  local is_normal_win = vim.api.nvim_win_get_config(win_id).relative == ''
  if not is_normal_win then return end

  local pos = vim.fn.win_screenpos(win_id)
  local height, width = vim.api.nvim_win_get_height(win_id), vim.api.nvim_win_get_width(win_id)

  local n_steps = math.max(height, width)

  local float_config = {
    relative = 'editor',
    anchor = 'NW',
    width = width,
    height = height,
    row = pos[1] - 1,
    col = pos[2] + 20,
    focusable = false,
    zindex = 10,
    style = 'minimal',
  }
  local float_win_id = vim.api.nvim_open_win(buf_id, false, float_config)
  vim.api.nvim_win_set_option(float_win_id, 'winblend', 60)

  local timing = H.get_config().layout.timing

  local step_action = function(step)
    if not vim.api.nvim_win_is_valid(float_win_id) then return false end

    if step == 0 then return true end

    if n_steps <= step then
      vim.api.nvim_win_close(float_win_id, true)
      return false
    end

    local coef = step / n_steps
    local new_config = {
      relative = 'editor',
      width = math.ceil((1 - coef) * width),
      height = math.ceil((1 - coef) * height),
      row = math.floor(pos[1] + 0.5 * coef * height),
      col = math.floor(pos[2] + 0.5 * coef * width),
    }
    vim.api.nvim_win_set_config(float_win_id, new_config)
    return true
  end
  local step_timing = function(step) return timing(step, n_steps) end

  MiniAnimate.animate(step_action, step_timing)
end

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
  -- NOTEs:
  -- - Inside `WinScrolled` try to first animate layout before scroll to avoid
  --   flickering.
  -- - Use `WinClosed` to update layout state because it is not always properly
  --   updated in Neovim<0.9. Use `vim.schedule()` to operate *after* closed
  --   window is removed from layout.
  vim.api.nvim_exec(
    [[augroup MiniAnimate
        au!
        au CursorMoved * lua MiniAnimate.auto_cursor()
        au WinEnter    * lua MiniAnimate.on_win_enter()
        au WinClosed   * lua vim.schedule(MiniAnimate.on_win_closed)
        au WinScrolled * lua MiniAnimate.auto_layout(); MiniAnimate.auto_scroll()
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

  -- Window vertical scroll
  scroll = {
    enable = true,
    timing = function(_, n) return math.min(10, 250 / n) end,
    subscroll = function(total_scroll)
      return H.subscroll_equal(total_scroll, { min_input = 2, max_input = 10000000, max_n_output = 60 })
    end,
  },

  -- Layout change
  layout = {
    enable = true,
    timing = function(_, n) return math.min(10, 250 / n) end,
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
    if H.cache.scroll_is_active then
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

--- Generate subscroll
---
--- Subscroll - callable which takes `total_scroll` argument (single positive
--- integer) and returns array of positive integers each representing the
--- amount of lines needs to be scrolled in corresponding step. All subscroll
--- values should sum to input `total_scroll`.
MiniAnimate.gen_subscroll = {}

MiniAnimate.gen_subscroll.equal = function(opts)
  opts = vim.tbl_deep_extend('force', { min_input = 2, max_input = 10000000, max_n_output = 60 }, opts or {})

  return function(total_scroll) return H.subscroll_equal(total_scroll, opts) end
end

MiniAnimate.auto_cursor = function()
  -- Don't animate if disabled
  local cursor_config = H.get_config().cursor
  if not cursor_config.enable or H.is_disabled() then
    -- Reset state to not use an outdated one if enabled again
    H.cache.cursor_state = { buf_id = nil, pos = {} }
    return
  end

  -- Don't animate if inside scroll animation
  if H.cache.scroll_is_active then return end

  -- Update necessary information. NOTE: tracking only on `CursorMoved` and not
  -- inside every animation step (like in scroll animation) for performance
  -- reasons: cursor movement is much more common action than scrolling.
  local prev_state, new_state = H.cache.cursor_state, H.get_cursor_state()
  H.cache.cursor_state = new_state
  H.cache.cursor_event_id = H.cache.cursor_event_id + 1

  -- Don't animate if changed buffer
  if new_state.buf_id ~= prev_state.buf_id then return end

  -- Make animation step data and possibly animate
  local animate_step = H.make_cursor_step(prev_state, new_state, cursor_config)
  if not animate_step then return end

  H.start_cursor()
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

MiniAnimate.auto_scroll = function()
  -- Don't animate if disabled
  local scroll_config = H.get_config().scroll
  if not scroll_config.enable or H.is_disabled() then
    -- Reset state to not use an outdated one if enabled again
    H.cache.scroll_state = { buf_id = nil, win_id = nil, view = {} }
    return
  end

  -- Don't animate if nothing to animate. Mostly used to distinguish
  -- `WinScrolled` due to module animation from the other ones.
  local prev_state = H.cache.scroll_state
  if prev_state.view.topline == vim.fn.line('w0') then return end

  -- Update necessary information
  local new_state = H.get_scroll_state()
  H.cache.scroll_state = new_state
  H.cache.scroll_event_id = H.cache.scroll_event_id + 1

  -- Don't animate if changed buffer or window
  if new_state.buf_id ~= prev_state.buf_id or new_state.win_id ~= prev_state.win_id then return end

  -- Don't animate if inside layout animation. This reduces computations and
  -- occasional flickering.
  if H.cache.layout_is_active then return end

  -- Make animation step data and possibly animate
  local animate_step = H.make_scroll_step(prev_state, new_state, scroll_config)
  if not animate_step then return end

  H.start_scroll(prev_state)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

MiniAnimate.auto_layout = function()
  -- Don't animate if disabled
  local layout_config = H.get_config().layout
  if not layout_config.enable or H.is_disabled() then
    -- Reset state to not use an outdated one if enabled again
    H.cache.layout_state = {}
    return
  end

  -- Don't animate if inside scroll animation. This reduces computations and
  -- occasional flickering.
  if H.cache.scroll_is_active then return end

  -- Don't animate if nothing to animate. Mostly used to distinguish
  -- `WinScrolled` from module animation and other ones.
  local prev_state, new_state = H.cache.layout_state, H.get_layout_state()

  -- Don't animate if there is nothing to animate. This also stops
  local is_same_state = H.layout_state_is_equal(prev_state, new_state)
  if is_same_state then return end

  -- Update necessary information.
  H.cache.layout_state = new_state
  H.cache.layout_event_id = H.cache.layout_event_id + 1

  -- Make animation step data and possibly animate
  local animate_step = H.make_layout_step(prev_state, new_state, layout_config)
  if not animate_step then return end

  H.start_layout(animate_step.initial_state)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

MiniAnimate.on_win_enter = function() H.cache.scroll_state = H.get_scroll_state() end

-- TODO: Remove after Neovim<=0.9 is dropped (very long time from now)
MiniAnimate.on_win_closed = function() H.cache.layout_state = H.get_layout_state() end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniAnimate.config

-- Cache for various operations
H.cache = {
  -- Cursor move animation data
  cursor_event_id = 0,
  cursor_is_active = false,
  cursor_state = { buf_id = nil, pos = {} },

  -- Scroll animation data
  scroll_event_id = 0,
  scroll_is_active = false,
  scroll_state = { buf_id = nil, win_id = nil, view = {} },

  -- Layout animation data
  layout_event_id = 0,
  layout_is_active = false,
  layout_state = {},
}

H.ns_id = {
  cursor = vim.api.nvim_create_namespace('MiniAnimateCursor'),
}

H.animation_done_events = {
  cursor = 'MiniAnimateCursorDone',
  scroll = 'MiniAnimateScrollDone',
  layout = 'MiniAnimateLayoutDone',
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
    layout = { config.layout, H.is_config_layout },
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
  if path == nil or #path == 0 then return end

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

-- Scroll ---------------------------------------------------------------------
H.make_scroll_step = function(state_from, state_to, opts)
  local from_line, to_line = state_from.view.topline, state_to.view.topline

  -- Compute how subscrolling is done
  local total_scroll = H.get_n_visible_lines(from_line, to_line) - 1
  local step_scrolls = opts.subscroll(total_scroll)

  -- Don't animate if no subscroll steps is returned
  if step_scrolls == nil or #step_scrolls == 0 then return end

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
      local ok, _ = pcall(H.scroll_action, scroll_key, step_scrolls[step], final_cursor_pos)
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

-- Layout ---------------------------------------------------------------------
H.make_layout_step = function(state_from, state_to, opts)
  -- Align starting state (make pair tweenable: consisting from same set of
  -- windows in same window layout). Stop if impossible.
  local state_from_aligned = H.layout_state_align_from(state_from, state_to)
  if state_from_aligned == nil then return end

  -- Compute number of animation steps
  local n_steps = H.layout_state_get_n_steps(state_from_aligned, state_to)
  if n_steps == nil or n_steps <= 1 then return end

  -- Create animation step
  local event_id, timing = H.cache.layout_event_id, opts.timing

  return {
    initial_state = state_from_aligned,
    step_action = function(step)
      -- Do nothing on initialization
      if step == 0 then return true end

      -- Stop animation if another layout animation is active. Don't use
      -- `stop_layout()` because it will also mean to stop parallel animation.
      if H.cache.layout_event_id ~= event_id then return false end

      -- Preform animation. Possibly stop on error.
      local step_state = H.layout_state_convex(state_from_aligned, state_to, step / n_steps)
      local ok, _ = pcall(H.apply_layout_state, step_state)
      if not ok then return H.stop_layout(state_to) end

      -- Properly stop animation if step is too big
      if n_steps <= step then return H.stop_layout(state_to) end

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.start_layout = function(start_state)
  H.cache.layout_is_active = true
  if start_state ~= nil then H.apply_layout_state(start_state) end
  return true
end

H.stop_layout = function(end_state)
  if end_state ~= nil then H.apply_layout_state(end_state) end
  H.cache.layout_is_active = false
  H.emit_done_event('layout')
  return false
end

H.get_layout_state = function() return H.enhance_winlayout(vim.fn.winlayout()) end

H.enhance_winlayout = function(layout)
  layout.container = layout[1]
  layout[1] = nil

  local second = layout[2]
  layout[2] = nil
  if layout.container == 'leaf' then
    -- Second element is a window id
    layout.win_id = second
    layout.height = vim.api.nvim_win_get_height(second)
    layout.width = vim.api.nvim_win_get_width(second)
    layout.view = vim.api.nvim_win_call(second, vim.fn.winsaveview)
    return layout
  end

  -- Second element is an array
  layout.content = second
  for i, l in ipairs(second) do
    second[i] = H.enhance_winlayout(l)
  end
  return layout
end

H.apply_layout_state = function(state)
  if state.container == 'leaf' then
    local win_id = state.win_id
    if not vim.api.nvim_win_is_valid(win_id) then return end

    -- If state dimensions are not accurate enough, this settings might lead to
    -- moving `cmdheight`
    vim.api.nvim_win_set_height(win_id, state.height)
    vim.api.nvim_win_set_width(win_id, state.width)

    -- Allow states without `view` (mainly inside animation)
    if state.view ~= nil then vim.api.nvim_win_call(win_id, function() vim.fn.winrestview(state.view) end) end
    return
  end
  for _, s in ipairs(state.content) do
    H.apply_layout_state(s)
  end

  -- Update current layout state to be able to start another layout animation
  -- at any current animation step. Recompute state to also capture `view`.
  H.cache.layout_state = H.get_layout_state()
end

-- Layout state ---------------------------------------------------------------
H.layout_state_is_equal = function(state_1, state_2, check_dims)
  if check_dims == nil then check_dims = true end

  if state_1.container ~= state_2.container then return false end
  if state_1.container == 'leaf' then
    if state_1.win_id ~= state_2.win_id then return false end
    if check_dims and (state_1.height ~= state_2.height or state_1.width ~= state_2.width) then return false end
    return true
  end

  if #state_1.content ~= #state_2.content then return false end
  for i = 1, #state_1.content do
    local res = H.layout_state_is_equal(state_1.content[i], state_2.content[i], check_dims)
    if not res then return false end
  end

  return true
end

H.layout_state_align_from = function(state_from, state_to)
  -- State can be empty at the start
  if vim.tbl_isempty(state_from) then return end

  -- Check alignability (stop if can't align):
  local pair_summary = H.layout_state_summarize_pair(state_from, state_to)
  local has_closed = not vim.tbl_isempty(pair_summary.closed)
  local has_common = not vim.tbl_isempty(pair_summary.common)
  local has_opened = not vim.tbl_isempty(pair_summary.opened)

  -- - There should be common windows which are in the same layout (not
  --   accounting for dimensions). Meaning there should be no moving of same
  --   window (like with `<C-w>J`, etc.).
  if not has_common then return end
  local common_from = H.layout_state_filter(state_from, pair_summary.common)
  local common_to = H.layout_state_filter(state_to, pair_summary.common)
  if not H.layout_state_is_equal(common_from, common_to, false) then return end

  -- -- - Not common windows are present in only one input.
  -- --   So that there is only closed (present in `state_from`) or opened
  -- --   (present in `state_to`) windows.
  if has_closed and has_opened then return end

  -- Take `state_to` layout and infer aligned dimensions from `state_from`
  if has_closed then
    -- There are common and closed windows.
    --
    -- Dimensions of common windows are set to imitate "immediate disappear of
    -- closed windows". This needs an emulation of window closing which will
    -- appropriately add to dimension along container to "next" sublayout along
    -- parent container ("last" if deleted window is last in parent container).
    -- Adding dimension to a particular side should be done recursively
    -- imitating removing the split. Having emulation of window close, emulate
    -- closing one by one in `state_from` of all windows known to be closed and
    -- (hopefully) treat the outcome as starting point for tweening.
    --
    -- !!! OR !!!
    -- - Open new windows at the exact place as closed ones. This should lead
    --   to the same layout as `state_from` but with different window ids in
    --   place of a closed ones. A rough idea:
    --     - Create scratch buffer (`buf_id`) and command queue holder.
    --     - Traverse `state_from` layout in natural order. Keep track of last
    --       common window id within each subcontainer.
    --     - For each closed window add command to queue that will restore it
    --       in split once common window is traversed. A command will consist
    --       from these parts (depending on parent container type and side of
    --       reopened window relative to latest common window, if present):
    --       'topleft'/'botright' .. 'split'/'vsplit' .. ' | buffer ' .. buf_id
    --       Keep track of new window id to map it to id of closed one it is
    --       ought to replace.
    --       If there is a common window in current parent container, execute
    --       command right away.
    --     - If found new common window, execute all split commands.
    -- - Update `state_from` with replacing closed window ids by corresponding
    --   new ones.
    -- - Replace `state_to` with layout from `state_from`, but dimensions
    --   reflecting `state_to`: common windows - exact ones, reopened - zero on
    --   dimension along the parent container.
    -- - Inside `stop_layout()` close reopened windows.
    -- TODO
    return
  end

  if has_opened then
    -- There are common and opened windows.
    -- - Dimensions of common windows are taken from `state_from`.
    -- - Dimensions of new windows are set to imitate their "appearance from
    --   nothing": dimenstion along container (width if window is in "row"
    --   container, height - if in "col") is set to zero and the other is
    --   taken from `state_to`.
    return H.layout_state_align_from_with_opened(state_to, pair_summary)
  end

  -- Only common windows
  -- Remove `view` from initial state because it can be outdated
  return H.layout_state_remove_view(state_from)
end

H.layout_state_remove_view = function(state)
  if state.container == 'leaf' then
    state.view = nil
  else
    state.content = vim.tbl_map(H.layout_state_remove_view, state.content)
  end
  return state
end

H.layout_state_align_from_with_opened = function(state_to, pair_summary)
  local f
  f = function(s, parent_container)
    if s.container == 'leaf' then
      -- Case of single window in layout
      if parent_container == nil then return s end

      local win_summary = pair_summary[s.win_id]
      -- By default take dimensions from `state_from`. For opened windows take
      -- them from `state_to` while squashing along the parent container.
      local res = {
        container = 'leaf',
        win_id = s.win_id,
        height = win_summary.height_from,
        width = win_summary.width_from,
      }
      if win_summary.class == 'opened' then
        local is_parent_row = parent_container == 'row'
        res.height = is_parent_row and win_summary.height_to or 0
        res.width = is_parent_row and 0 or win_summary.width_to
      end

      return res
    end

    local content = {}
    for i, sub_s in ipairs(s.content) do
      content[i] = f(sub_s, s.container)
    end
    return { container = s.container, content = content }
  end

  return f(vim.deepcopy(state_to), nil)
end

H.layout_state_get_n_steps = function(state_from, state_to)
  local f
  f = function(s_from, s_to, cur_res)
    -- Also perform extra checks for alignment
    if cur_res == nil then return nil end
    if s_from.container ~= s_to.container then return nil end

    if s_from.container == 'leaf' then
      if s_from.win_id ~= s_to.win_id then return nil end
      local height_absidff = math.abs(s_to.height - s_from.height)
      local width_absidff = math.abs(s_to.width - s_from.width)
      return math.max(cur_res, height_absidff, width_absidff)
    end

    if #s_from.content ~= #s_to.content then return nil end
    local res = cur_res
    for i = 1, #s_from.content do
      res = math.max(res, f(s_from.content[i], s_to.content[i], res))
    end
    return res
  end

  return f(state_from, state_to, 0)
end

H.layout_state_convex = function(state_from, state_to, coef)
  -- Assumes aligned states
  local f
  f = function(s_from, s_to)
    if s_to.container == 'leaf' then
      return {
        container = 'leaf',
        win_id = s_to.win_id,
        height = H.convex_point(s_from.height, s_to.height, coef),
        width = H.convex_point(s_from.width, s_to.width, coef),
      }
    end
    local content = {}
    for i = 1, #s_to.content do
      content[i] = f(s_from.content[i], s_to.content[i])
    end
    return { container = s_to.container, content = content }
  end

  return f(state_from, state_to)
end

H.layout_state_summarize_pair = function(state_from, state_to)
  local winmap_from, winmap_to = H.layout_state_to_winmap(state_from), H.layout_state_to_winmap(state_to)

  local res = { closed = {}, common = {}, opened = {} }
  for win_id, win_data in pairs(winmap_from) do
    res[win_id] = { height_from = win_data.height, width_from = win_data.width }
    local class = winmap_to[win_id] and 'common' or 'closed'
    res[win_id].class = class
    res[class][win_id] = true
  end

  for win_id, win_data in pairs(winmap_to) do
    res[win_id] = res[win_id] or {}
    res[win_id].height_to, res[win_id].width_to = win_data.height, win_data.width

    if not winmap_from[win_id] then
      res[win_id].class, res.opened[win_id] = 'opened', true
    end
  end

  return res
end

-- Window map (`winmap`) is a table with keys being window id present in layout
-- and any value. Here values are window dimensions. Used for quick access by
-- window id (including if it exists).
H.layout_state_to_winmap = function(state)
  local res = {}
  local traverse
  traverse = function(s)
    if s.container == 'leaf' then
      -- Using table instead of array is more efficient. Works because there
      -- can't be two equal window ids.
      res[s.win_id] = { height = s.height, width = s.width }
      return
    end
    for _, sub_s in ipairs(s.content) do
      traverse(sub_s)
    end
  end
  traverse(state)

  return res
end

H.layout_state_filter = function(state, winmap)
  local f
  f = function(s)
    if s.container == 'leaf' then
      if winmap[s.win_id] then return s end
      return nil
    end

    -- Construct new content to always preserve it as array. Doing
    -- `s.content[i] = f(sub_s)` may lead to nonconsecutive integer keys.
    local new_content = {}
    for _, sub_s in ipairs(s.content) do
      table.insert(new_content, f(sub_s))
    end

    -- Possible collapse redundant container
    if #new_content == 0 then return nil end
    if #new_content == 1 then return new_content[1] end

    return { container = s.container, content = new_content }
  end
  local res = f(vim.deepcopy(state)) or {}

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

-- Animation subscroll --------------------------------------------------------
H.subscroll_equal = function(total_scroll, opts)
  -- Animate only when `total_scroll` is inside appropriate range
  if not (opts.min_input <= total_scroll and total_scroll <= opts.max_input) then return end

  -- Don't make more than `max_n_output` steps
  local n_steps = math.min(total_scroll, opts.max_n_output)
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
  if not vim.is_callable(x.subscroll) then return false, H.msg_config('scroll.subscroll', 'callable') end

  return true
end

H.is_config_layout = function(x)
  if type(x.enable) ~= 'boolean' then return false, H.msg_config('layout.enable', 'boolean') end
  if not vim.is_callable(x.timing) then return false, H.msg_config('layout.timing', 'callable') end

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
  local res, coef = {}, x / n
  for i = 1, n do
    res[i] = math.floor(i * coef) - math.floor((i - 1) * coef)
  end
  return res
end

H.convex_point = function(x, y, coef) return H.round((1 - coef) * x + coef * y) end

-- `virtcol2col()` is only present in Neovim>=0.8. Earlier Neovim versions will
-- have troubles dealing with multibyte characters.
H.virtcol2col = vim.fn.virtcol2col or function(_, _, col) return col end

H.tbl_intersect_keys = function(tbl_1, tbl_2)
  local res_1, res_2 = {}, {}
  for k, v in pairs(tbl_1) do
    if tbl_2[k] ~= nil then
      res_1[k], res_2[k] = v, tbl_2[k]
    end
  end

  return res_1, res_2
end

return MiniAnimate
