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
        au CursorMoved,CursorMovedI,TextChanged,TextChangedI,WinScrolled * lua MiniIndentscope.auto_draw()

        au FileType TelescopePrompt let b:miniindentscope_disable=v:true
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
  -- Which character to use for drawing vertical scope line
  symbol = '╎',

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

function MiniIndentscope.auto_draw()
  if H.is_disabled() then
    H.undraw_line()
    return
  end

  H.event_id = H.event_id + 1

  local scope = MiniIndentscope.get_scope()
  local line_hash = H.line_hash_compute(scope)

  -- Don't draw same line
  if H.line_hash_is_equal(line_hash, H.drawn_line_hash) then
    return
  end

  H.undraw_line()

  -- Draw line only after all events are processed
  vim.defer_fn(function()
    H.draw_line(line_hash)
  end, 0)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniIndentscope.config

-- Namespace for drawing vertical line
H.ns_id = vim.api.nvim_create_namespace('MiniIndentscope')

-- Cache for currently drawn scope
H.drawn_line_hash = nil

-- Event counter
H.event_id = 0

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

-- Work with indent -----------------------------------------------------------
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

function H.draw_line(line_hash)
  line_hash = line_hash or H.line_hash_compute(MiniIndentscope.get_scope())
  if line_hash == nil then
    return
  end

  local opts = {
    hl_mode = 'combine',
    priority = 0,
    right_gravity = false,
    virt_text = { { line_hash.text, 'MiniIndentscope' } },
    virt_text_pos = 'overlay',
  }

  local current_event_id = H.event_id
  local draw_at_line = function(l)
    if H.event_id ~= current_event_id then
      H.undraw_line()
      return false
    end
    return pcall(vim.api.nvim_buf_set_extmark, line_hash.buf_id, H.ns_id, l - 1, 0, opts)
  end

  -- Originate rays at cursor line
  local cur_line = math.min(math.max(vim.fn.line('.'), line_hash.top), line_hash.bottom)
  H.draw_ray('up', cur_line, line_hash.top, draw_at_line)
  H.draw_ray('down', cur_line + 1, line_hash.bottom, draw_at_line)

  H.drawn_line_hash = line_hash
end

function H.draw_ray(direction, from_line, to_line, draw_fun)
  local increment = direction == 'up' and -1 or 1
  local cur_l, async = from_line, nil

  local draw = vim.schedule_wrap(function()
    local line_is_outside = (direction == 'up' and cur_l < to_line) or (direction == 'down' and cur_l > to_line)
    if line_is_outside then
      async:close()
      return
    end
    local success = draw_fun(cur_l)
    if not success then
      async:close()
    end
    cur_l = cur_l + increment
    -- vim.loop.sleep(2)
    async:send()
  end)
  async = vim.loop.new_async(draw)
  async:send()
end

--- Compute hash of line to be displayed
---
--- Here `hash` means information that uniquely identifies drawn line. So:
--- - If all elements of two hashes are equal, then they represent same line to
---   be drawn by `H.draw_line()`.
---
---@return table|nil Table with hash info or `nil` in case line shouldn't be drawn.
---@private
function H.line_hash_compute(scope)
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

function H.line_hash_is_equal(hash_1, hash_2)
  if type(hash_1) ~= 'table' or type(hash_2) ~= 'table' then
    return false
  end

  return hash_1.buf_id == hash_2.buf_id
    and hash_1.text == hash_2.text
    and hash_1.top == hash_2.top
    and hash_1.bottom == hash_2.bottom
end

function H.is_line_outside(line, border, direction)
  return (direction == 'up' and line < border) or (direction == 'down' and line > border)
end

function H.undraw_line()
  vim.api.nvim_buf_clear_namespace(0, H.ns_id, 0, -1)
  H.drawn_line_hash = nil
end

-- Utilities ------------------------------------------------------------------
function H.notify(msg)
  vim.notify(('(mini.indentscope) %s'):format(msg))
end

return MiniIndentscope
