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
        au CursorMoved,CursorMovedI,TextChanged,TextChangedI * lua MiniIndentscope.auto_draw()

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
  symbol = '│',

  -- To which part include edge blank lines. Can be `'inner'` or `'outer'`.
  edge_blank = { top = 'inner', bottom = 'inner' },
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

  local n_lines = vim.fn.line('$')
  local indent = H.get_indent_at_column(line, col)

  -- Make early return
  if indent == 0 then
    return { indent = -1, line = { top_outer = 0, top_inner = 1, bottom_inner = n_lines, bottom_outer = n_lines + 1 } }
  end

  -- Compute scope
  local cur_l, edge_blank = nil, MiniIndentscope.config.edge_blank

  -- Cast array upwards
  local top_outer, top_inner, top_indent
  cur_l = line
  while top_inner == nil and cur_l ~= 0 do
    local new_l = vim.fn.prevnonblank(cur_l - 1)
    local new_indent = vim.fn.indent(new_l)
    -- This comparison also works when `new_l` is invalid (`new_indent` is -1)
    if new_indent < indent then
      top_outer = new_l
      top_inner = edge_blank.top == 'inner' and (new_l + 1) or vim.fn.nextnonblank(cur_l)
      top_indent = new_indent
    end
    cur_l = new_l
  end

  -- Cast array downwards
  local bottom_outer, bottom_inner, bottom_indent
  cur_l = line
  while bottom_inner == nil and cur_l ~= 0 do
    local new_l = vim.fn.nextnonblank(cur_l + 1)
    local new_indent = vim.fn.indent(new_l)
    -- This comparison also works when `new_l` is invalid (`new_indent` is -1)
    if new_indent < indent then
      bottom_outer = new_l
      bottom_inner = edge_blank.bottom == 'inner' and (new_l - 1) or vim.fn.prevnonblank(cur_l)
      bottom_indent = new_indent
    end
    cur_l = new_l
  end

  return {
    indent = math.max(top_indent or -1, bottom_indent or -1),
    line = {
      input = line,
      top_outer = top_outer or 0,
      top_inner = top_inner or 1,
      bottom_inner = bottom_inner or n_lines,
      bottom_outer = bottom_outer or n_lines + 1,
    },
  }
end

function MiniIndentscope.auto_draw()
  if H.is_disabled() then
    H.undraw_line()
    return
  end

  local scope = MiniIndentscope.get_scope()
  if not H.should_redraw(scope) then
    return
  end

  H.undraw_line()
  H.draw_line(scope)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniIndentscope.config

-- Namespace for drawing vertical line
H.ns_id = vim.api.nvim_create_namespace('MiniIndentscope')

-- Cache for currently drawn scope
H.drawn_scope = nil

-- Functions to compute indent of blank line based on `edge_blank`
H.blank_indent_funs = {
  inner = {
    inner = function(prev_indent, next_indent)
      return math.max(prev_indent, next_indent)
    end,
    outer = function(prev_indent, next_indent)
      return next_indent
    end,
  },
  outer = {
    inner = function(prev_indent, next_indent)
      return prev_indent
    end,
    outer = function(prev_indent, next_indent)
      return math.min(prev_indent, next_indent)
    end,
  },
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
function H.setup_config(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  return config
end

function H.apply_config(config)
  MiniIndentscope.config = config
end

function H.is_disabled()
  return vim.g.miniindentscope_disable == true or vim.b.miniindentscope_disable == true
end

-- Work with indent -----------------------------------------------------------
-- Compute "indent at column": `min(col, <line indent>)`, where line indent:
-- - Equals output of `vim.fn.indent()` in case of non-blank line.
-- - Depends on `MiniIndentscope.config.edge_blank` in such way so as to
--   satisfy its definition.
function H.get_indent_at_column(line, col)
  local prev_nonblank = vim.fn.prevnonblank(line)
  local indent = vim.fn.indent(prev_nonblank)
  -- Compute indent of blank line depending on `edge_blank` values
  if line ~= prev_nonblank then
    local edge_blank = MiniIndentscope.config.edge_blank
    local indent_fun = H.blank_indent_funs[edge_blank.top][edge_blank.bottom]
    local next_indent = vim.fn.indent(vim.fn.nextnonblank(line))
    indent = indent_fun(indent, next_indent)
  end
  return math.min(col, indent)
end

function H.draw_line(scope)
  scope = scope or MiniIndentscope.get_scope()
  if scope.indent < 0 then
    return
  end

  -- Locate extmark at first column but show indented text. This allows showing
  -- line even on empty lines.
  local indented_text = string.rep(' ', scope.indent) .. MiniIndentscope.config.symbol
  local opts = {
    hl_mode = 'combine',
    priority = 1,
    virt_text = { { indented_text, 'MiniIndentscope' } },
    virt_text_pos = 'overlay',
  }

  for l = scope.line.top_inner - 1, scope.line.bottom_inner - 1 do
    vim.api.nvim_buf_set_extmark(0, H.ns_id, l, 0, opts)
  end

  H.drawn_scope = scope
end

function H.should_redraw(new_scope)
  if H.drawn_scope == nil then
    return true
  end
  return new_scope.indent ~= H.drawn_scope.indent
    or new_scope.line.top_inner ~= H.drawn_scope.line.top_inner
    or new_scope.line.bottom_inner ~= H.drawn_scope.line.bottom_inner
end

function H.undraw_line()
  vim.api.nvim_buf_clear_namespace(0, H.ns_id, 0, -1)
  H.drawn_scope = nil
end

-- Utilities ------------------------------------------------------------------
function H.notify(msg)
  vim.notify(('(mini.indentscope) %s'):format(msg))
end

return MiniIndentscope
