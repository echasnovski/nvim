-- TODO
--
-- Code:
-- - Think about the best way to force detach (not through `vim.b.xxx_disable`).

--- *mini.hipatterns* Highlight patterns in text
--- *MiniHipatterns*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Highlight configurable patterns asynchronously with debounce/throttle.
---
--- # Setup ~
---
--- This module doesn't need setup, but it can be done to improve usability.
--- Setup with `require('mini.hipatterns').setup({})` (replace `{}` with your
--- `config` table). It will create global Lua table `MiniHipatterns` which you can
--- use for scripting or manually (with `:lua MiniHipatterns.*`).
---
--- See |MiniHipatterns.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.minihipatterns_config`
--- will have no effect here.
---
--- # Comparisons ~
---
--- - 'folke/todo-comments':
--- - 'folke/paint.nvim':
--- - 'norcalli/nvim-colorizer.lua':
--- - 'uga-rosa/ccc.nvim':
---
--- # Disabling ~
---
--- To disable, set `vim.g.minihipatterns_disable` (globally) or
--- `vim.b.minihipatterns_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
MiniHipatterns = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniHipatterns.config|.
---
---@usage `require('mini.hipatterns').setup({})` (replace `{}` with your `config` table)
MiniHipatterns.setup = function(config)
  -- Export module
  _G.MiniHipatterns = MiniHipatterns

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniHipatterns.config = {
  -- Array of highlighters (table with <pattern>, <group>, <priority> fields)
  highlighters = {
    { pattern = 'abcd', group = 'IncSearch' },
    { pattern = 'xx(yy)', group = 'Error' },
    { pattern = 'TODO', group = 'Todo', priority = 200 },
    { pattern = 'NOTE', group = 'MiniStatuslineModeInsert', priority = 200 },
    {
      pattern = function(buf_id) return vim.api.nvim_buf_line_count(buf_id) > 300 and 'MORE' or 'LESS' end,
      group = function(buf_id, match) return match == 'MORE' and 'DiagnosticError' or 'DiagnosticInfo' end,
      priority = 200,
    },
  },

  -- Delay (in ms) to wait after change to apply highlighting
  delay = 100,
}
--minidoc_afterlines_end

MiniHipatterns.attach = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  -- Don't attach more than once
  if H.is_buf_attached(buf_id) then return end

  -- Register attached buffer with cached data for performance
  H.update_attached_data(buf_id)

  -- Add highlighting to whole buffer
  H.process_change(buf_id, 1, vim.api.nvim_buf_line_count(buf_id), H.buf_attached[buf_id].delay)

  -- Add watchers to current buffer
  vim.api.nvim_buf_attach(buf_id, false, {
    on_lines = function(_, _, _, from_line, _, to_line)
      local buf_data = H.buf_attached[buf_id]
      -- Properly detach if registered to detach
      if buf_data == nil then return true end
      H.process_change(buf_id, from_line + 1, to_line, buf_data.delay)
    end,
    on_reload = function() MiniHipatterns.reload(buf_id) end,
    on_detach = function() MiniHipatterns.detach(buf_id) end,
  })
end

MiniHipatterns.detach = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  H.buf_attached[buf_id] = nil
  vim.api.nvim_buf_clear_namespace(buf_id, H.ns_id.highlight, 0, -1)
end

MiniHipatterns.reload = function(buf_id)
  MiniHipatterns.detach(buf_id)
  MiniHipatterns.attach(buf_id)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniHipatterns.config

-- Timer for debounce
H.timer = vim.loop.new_timer()

-- Cache of queued changes used for debounced highlighting
H.change_queue = {}

-- Namespaces
H.ns_id = { highlight = vim.api.nvim_create_namespace('MiniHipatternsHighlight') }

-- Data about processed buffers
H.buf_attached = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  return config
end

H.apply_config = function(config) MiniHipatterns.config = config end

H.create_autocommands = function()
  local augroup = vim.api.nvim_create_augroup('MiniHipatterns', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  au('BufWinEnter', '*', H.on_bufwinenter, 'Attach highlight watcher')
  au('FileType', '*', function(data) MiniHipatterns.reload(data.buf) end, 'Reload buffer watcher')
  au('ColorScheme', '*', H.on_colorscheme, 'Reload all attached watchers')
end

H.is_disabled = function(buf_id)
  return vim.g.miniindentscope_disable == true or vim.b[buf_id or 0].miniindentscope_disable == true
end

H.get_config = function(config, buf_id)
  buf_id = buf_id or 0
  local ok, buf_config = pcall(vim.api.nvim_buf_get_var, buf_id, 'minihipatterns_config')
  buf_config = ok and (buf_config or {}) or {}
  return vim.tbl_deep_extend('force', MiniHipatterns.config, buf_config, config or {})
end

-- Autocommands ---------------------------------------------------------------
H.on_bufwinenter = function(data)
  if H.is_buf_attached(data.buf) then
    H.update_attached_data(data.buf)
    return
  end

  MiniHipatterns.attach(data.buf)
end

H.on_colorscheme = function()
  -- Reload all currently attached buffers
  for buf_id, _ in pairs(H.buf_attached) do
    MiniHipatterns.reload(buf_id)
  end
end

-- Watchers -------------------------------------------------------------------
H.validate_buf_id = function(buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  if not (type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id)) then
    H.error('`buf_id` should be `nil` or valid buffer id.')
  end

  return buf_id
end

H.is_buf_attached = function(buf_id) return H.buf_attached[buf_id] ~= nil end

H.update_attached_data = function(buf_id)
  local buf_config = H.get_config(nil, buf_id)
  H.buf_attached[buf_id] = {
    highlighters = H.normalize_highlighters(buf_config.highlighters),
    delay = buf_config.delay,
  }
end

H.normalize_highlighters = function(highlighters)
  local res = {}
  for _, hi in ipairs(highlighters) do
    local pattern = type(hi.pattern) == 'string' and function(...) return hi.pattern end or hi.pattern
    local group = type(hi.group) == 'string' and function(...) return hi.group end or hi.group
    local priority = hi.priority or 110

    if vim.is_callable(pattern) and vim.is_callable(group) and type(priority) == 'number' then
      table.insert(res, { pattern = pattern, group = group, priority = priority })
    end
  end

  return res
end

-- Highlighting ---------------------------------------------------------------
H.process_change = function(buf_id, from_line, to_line, delay)
  H.timer:stop()
  table.insert(H.change_queue, { buf_id, from_line, to_line })
  H.timer:start(delay, 0, H.process_change_queue)
end

H.process_change_queue = vim.schedule_wrap(function()
  local queue = H.normalize_change_queue()

  for buf_id, lines_to_process in pairs(queue) do
    H.process_buffer_changes(buf_id, lines_to_process)
  end

  H.change_queue = {}
end)

H.normalize_change_queue = function()
  local res = {}
  for _, change in ipairs(H.change_queue) do
    -- `change` is { buf_id, from_line, to_line }; lines are already 1-indexed
    local buf_id = change[1]

    local buf_lines_to_process = res[buf_id] or {}
    for i = change[2], change[3] do
      buf_lines_to_process[i] = true
    end

    res[buf_id] = buf_lines_to_process
  end

  return res
end

H.process_buffer_changes = vim.schedule_wrap(function(buf_id, lines_to_process)
  if not vim.api.nvim_buf_is_valid(buf_id) or H.is_disabled(buf_id) then return end

  -- Optimizations are done assuming small-ish number of highlighters and
  -- large-ish number of lines to process

  -- Remove current highlights
  local ns = H.ns_id.highlight
  for l_num, _ in pairs(lines_to_process) do
    vim.api.nvim_buf_clear_namespace(buf_id, ns, l_num - 1, l_num)
  end

  -- Add new highlights
  local highlighters = H.buf_attached[buf_id].highlighters
  for _, hi in ipairs(highlighters) do
    H.apply_highlighter(hi, buf_id, lines_to_process)
  end
end)

H.apply_highlighter = vim.schedule_wrap(function(hi, buf_id, lines_to_process)
  local pattern, group = hi.pattern(buf_id), hi.group
  if pattern == nil then return end

  -- Apply per proper line
  local ns = H.ns_id.highlight
  local extmark_opts = { priority = hi.priority }

  for l_num, _ in pairs(lines_to_process) do
    local line = H.get_line(buf_id, l_num)
    local from, to, match = line:find(pattern)

    while from do
      if match and match ~= '' then
        -- Not 100% full proof approach, as `match` string can be contained
        -- more than once with actual one not being first (like in '%w%w(%w)')
        from, to = line:find(match, from, true)
      else
        match = line:sub(from, to)
      end

      extmark_opts.hl_group = group(buf_id, match)
      extmark_opts.end_col = to
      if extmark_opts.hl_group ~= nil then H.set_extmark(buf_id, ns, l_num - 1, from - 1, extmark_opts) end

      from, to, match = line:find(pattern, to + 1)
    end
  end
end)

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.hipatterns) %s', msg), 0) end

H.get_line =
  function(buf_id, line_num) return vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)[1] or '' end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

return MiniHipatterns
