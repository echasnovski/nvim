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
        au CursorMoved,CursorMovedI             * lua MiniIndentscope.auto_draw()
        au TextChanged,TextChangedI,WinScrolled * lua MiniIndentscope.auto_draw({ force = true })
      augroup END]],
    false
  )

  -- Create highlighting
  vim.api.nvim_exec([[hi default link MiniIndentscope Delimiter]], false)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniIndentscope.config = {
  -- Delay (in ms) between event and start of drawing scope indicator
  draw_delay = { default = 100 },

  -- Duration (in ms) of scope's first drawing
  draw_duration = { default = 100 },

  -- Rules by which indent is computed in ambiguous cases: when there are two
  -- conflicting indent values. Can be one of:
  -- 'min' (take minimum), 'max' (take maximum), 'next', 'previous'.
  rules = {
    -- Indent of blank line (empty or containing only whitespace). Two indent
    -- values (`:h indent()`) are from previous (`:h prevnonblank()`) and next
    -- (`:h nextnonblank()`) non-blank lines.
    blank = 'max',

    -- Indent of the whole scope. Two indent values are from top and bottom
    -- lines with indent strictly less than current 'indent at cursor'.
    scope = 'max',
  },

  -- Which character to use for drawing scope indicator
  symbol = '╎',
}
--minidoc_afterlines_end

-- Module data ================================================================

-- Module functionality =======================================================
---@param line number Line number (starts from 1).
---@param col number Column number (starts from 1).
---@private
function MiniIndentscope.get_scope(line, col)
  local curpos = (not line or not col) and vim.fn.getcurpos() or {}
  -- Use `curpos[5]` (`curswant`, see `:h getcurpos()`) to account for blank
  -- and empty lines.
  line, col = line or curpos[2], col or curpos[5]

  -- Compute "indent at column"
  local indent = math.min(col, H.get_line_indent(line))

  -- Make early return
  if indent <= 0 then
    return { indent = -1, input = { line = line, column = col }, range = { top = 1, bottom = vim.fn.line('$') } }
  end

  -- Compute scope
  local top, top_indent = H.cast_ray(line, indent, 'up')
  local bottom, bottom_indent = H.cast_ray(line, indent, 'down')

  local scope_rule = H.indent_rules[MiniIndentscope.config.rules.scope]
  return {
    indent = scope_rule(top_indent, bottom_indent),
    input = { line = line, column = col },
    range = { top = top, bottom = bottom },
  }
end

function MiniIndentscope.auto_draw(opts)
  if H.is_disabled() then
    H.undraw_indicator()
    return
  end

  opts = opts or {}
  H.current.event_id = H.current.event_id + 1

  local scope = MiniIndentscope.get_scope()
  local indicator = H.indicator_compute(scope)
  local draw_opts = H.make_draw_opts(opts, scope, indicator)

  H.current.scope = scope

  if draw_opts.delay > 0 then
    H.undraw_indicator()
  end

  -- Use `defer_fn()` even if `delay` is 0 to draw line only after all events
  -- are processed (stops flickering)
  vim.defer_fn(function()
    draw_opts.cursor_gap_line = (scope.indent + 1) == vim.fn.col('.') and vim.fn.line('.') or nil

    H.draw_indicator(indicator, draw_opts)
  end, draw_opts.delay)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniIndentscope.config

-- Namespace for drawing vertical line
H.ns_id = vim.api.nvim_create_namespace('MiniIndentscope')

-- Table with current relevalnt data:
-- - `event_id` - counter for events.
-- - `scope`.
-- - `indicator`.
-- - `finished_draw` - if drawing was finished.
-- - `cursor_gap_line` - line number where extmark wasn't put for current
--   indicator due to cursor being there.
H.current = { event_id = 0, scope = {}, indicator = {} }

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
    rules = { config.rules, 'table' },
    ['rules.blank'] = { config.rules.blank, 'string' },
    ['rules.scope'] = { config.rules.scope, 'string' },
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

  return scope_1.indent == scope_2.indent
    and scope_1.range.top == scope_2.range.top
    and scope_1.range.bottom == scope_2.range.bottom
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

  -- Don't draw line with negative scope
  if scope.indent < 0 then
    return
  end

  -- Extmarks will be located at column zero but show indented text:
  -- - This allows showing line even on empty lines.
  -- - Text indentation should depend on current window view because extmarks
  --   can't scroll to be past left window side. Sources:
  --     - Neovim issue: https://github.com/neovim/neovim/issues/14050
  --     - Used fix: https://github.com/lukas-reineke/indent-blankline.nvim/pull/155
  local leftcol = vim.fn.winsaveview().leftcol
  if leftcol > scope.indent then
    return
  end

  local text = string.rep(' ', scope.indent - leftcol) .. MiniIndentscope.config.symbol

  -- Draw line only inside current window view
  local top = math.max(scope.range.top, vim.fn.line('w0'))
  local bottom = math.min(scope.range.bottom, vim.fn.line('w$'))

  return { buf_id = vim.api.nvim_get_current_buf(), text = text, top = top, bottom = bottom }
end

function H.indicator_is_equal(indicator_1, indicator_2)
  if type(indicator_1) ~= 'table' or type(indicator_2) ~= 'table' then
    return false
  end

  return indicator_1.buf_id == indicator_2.buf_id
    and indicator_1.text == indicator_2.text
    and indicator_1.top == indicator_2.top
    and indicator_1.bottom == indicator_2.bottom
end

-- Drawing --------------------------------------------------------------------
-- TODO: remove duraction tracking
_G.draw_durations = {}
function H.draw_indicator(indicator, opts)
  local start_time = vim.loop.hrtime()

  indicator = indicator or H.indicator_compute(MiniIndentscope.get_scope())
  opts = opts or H.make_draw_opts(opts)
  if indicator == nil or H.current.event_id ~= opts.event_id then
    return
  end

  -- Ensure that there is always only one indicator
  if opts.type ~= 'update' then
    H.undraw_indicator()
  end

  -- Make drawing function
  local draw_fun = H.make_draw_function(indicator, opts)

  -- Perform drawing
  H.current.indicator = indicator

  if opts.type == 'update' then
    H.draw_indicator_update(draw_fun, opts.cursor_gap_line)
  elseif opts.type == 'sync' then
    H.draw_indicator_sync(draw_fun, indicator.top, indicator.bottom)
  else
    -- Originate rays at cursor line
    H.draw_indicator_async(draw_fun, indicator.top, indicator.bottom, vim.fn.line('.'))
  end

  local end_time = vim.loop.hrtime()
  table.insert(_G.draw_durations, 0.000001 * (end_time - start_time))
end

function H.draw_indicator_async(draw_fun, top, bottom, origin)
  local line_up, line_down, async = origin, origin + 1, nil

  local draw = vim.schedule_wrap(function()
    local can_up, can_down = top <= line_up, line_down <= bottom
    if not (can_up or can_down) then
      H.current.finished_draw = true
      async:close()
      return
    end

    local success = true
    if can_up then
      success = success and draw_fun(line_up)
      line_up = line_up - 1
    end
    if can_down then
      success = success and draw_fun(line_down)
      line_down = line_down + 1
    end

    if not success then
      async:close()
    end

    vim.loop.sleep(2)
    async:send()
  end)
  async = vim.loop.new_async(draw)
  async:send()
end

function H.draw_indicator_sync(draw_fun, top, bottom)
  for l = top, bottom do
    local success = draw_fun(l)
    if not success then
      return
    end
  end
  H.current.finished_draw = true
end

function H.draw_indicator_update(draw_fun, cursor_gap_line)
  if H.current.cursor_gap_line ~= nil then
    draw_fun(H.current.cursor_gap_line)
    H.current.cursor_gap_line = nil
  end

  if cursor_gap_line ~= nil then
    vim.api.nvim_buf_clear_namespace(H.current.indicator.buf_id, H.ns_id, cursor_gap_line - 1, cursor_gap_line)
    H.current.cursor_gap_line = cursor_gap_line
  end
end

function H.undraw_indicator()
  local buf_id = H.current.indicator.buf_id or 0
  vim.api.nvim_buf_clear_namespace(buf_id, H.ns_id, 0, -1)

  H.current.cursor_gap_line = nil
  H.current.finished_draw = nil
  H.current.indicator = {}
end

function H.make_draw_opts(opts, scope, indicator)
  local res = {
    event_id = H.current.event_id,
    type = 'async',
    delay = MiniIndentscope.config.draw_delay.default,
  }

  if H.scope_is_equal(scope, H.current.scope) then
    -- Update line immediately for same scope in 'sync' fashion
    res.type = 'sync'
    res.delay = 0
  end

  if H.indicator_is_equal(indicator, H.current.indicator) then
    res.type = H.current.finished_draw and 'update' or 'sync'
  end

  if opts.force then
    res.type = 'sync'
  end

  return res
end

function H.make_draw_function(indicator, opts)
  local extmark_opts = {
    hl_mode = 'combine',
    priority = 0,
    right_gravity = false,
    virt_text = { { indicator.text, 'MiniIndentscope' } },
    virt_text_pos = 'overlay',
  }

  local current_event_id = opts.event_id
  local cursor_gap_line = opts.cursor_gap_line

  return function(l)
    -- Don't draw if outdated
    if H.current.event_id ~= current_event_id then
      -- H.undraw_indicator()
      return false
    end

    -- Don't put extmark if it will conflict with cursor
    if l == cursor_gap_line then
      H.current.cursor_gap_line = cursor_gap_line
      return true
    end

    return pcall(vim.api.nvim_buf_set_extmark, indicator.buf_id, H.ns_id, l - 1, 0, extmark_opts)
  end
end

-- Utilities ------------------------------------------------------------------
function H.notify(msg)
  vim.notify(('(mini.indentscope) %s'):format(msg))
end

return MiniIndentscope
