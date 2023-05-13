-- TODO
--
-- Code:
-- - Rehighlight all on `ColorScheme` event (as it might have erased highlight
--   groups which are defined in `config`).
-- - Probably, try to optimize to not use rather expensive `H.get_config()` in
--   `process_lines()` as it will be called on **every** change (like after
--   typing single character in Insert mode)

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
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniHipatterns.config = {
  -- Array of highlighters (table with <pattern> and <group> fields)
  highlighters = {},

  -- Delay (in ms) to wait after change to apply highlighting
  delay = 100,
}
--minidoc_afterlines_end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniHipatterns.config

-- Timer for debounce
H.timer = vim.loop.new_timer()

-- Cache of stacked changes used for debounced highlighting
H.cache = {}

-- Namespaces
H.ns_id = { highlight = vim.api.nvim_create_namespace('MiniHipatternsHighlight') }

-- Data about processed buffers
H.buf_data = {}

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

  vim.api.nvim_create_autocmd(
    'BufEnter',
    { group = augroup, pattern = '*', callback = H.on_bufenter, desc = 'Attach highlight watcher' }
  )
end

H.is_disabled = function(buf_id)
  return vim.g.miniindentscope_disable == true or vim.b[buf_id or 0].miniindentscope_disable == true
end

H.get_config = function(config, buf_id)
  buf_id = buf_id or 0
  return vim.tbl_deep_extend('force', MiniHipatterns.config, vim.b[buf_id].minihipatterns_config or {}, config or {})
end

-- Autocommands ---------------------------------------------------------------
H.on_bufenter = function(data)
  local buf_id = data.buf

  -- Don't process buffer more than once
  if H.buf_data[buf_id] then return end

  -- Add highlighting to whole buffer
  H.process_lines(buf_id, 1, vim.api.nvim_buf_line_count(buf_id))

  -- Add watcher to current buffer
  vim.api.nvim_buf_attach(buf_id, false, {
    on_lines = function(_, _, _, from_line, _, to_line) H.process_lines(buf_id, from_line + 1, to_line + 1) end,
  })

  -- Mark buffer as processed
  H.buf_data[buf_id] = true
end

-- Highlighting ---------------------------------------------------------------
H.process_lines = function(buf_id, from_line, to_line)
  H.timer:stop()

  table.insert(H.cache, { buf_id, from_line, to_line })

  -- Probably, try to optimize to not use rather expencive `H.get_config()`
  H.timer:start(H.get_config().delay, 0, H.process_cached_changes)
end

H.process_cached_changes = vim.schedule_wrap(function()
  local cache = H.normalize_cache()

  for buf_id, lines_to_process in pairs(cache) do
    local highlighters = H.get_config(nil, buf_id).highlighters
    for line_num, _ in pairs(lines_to_process) do
      H.apply_highlighters(buf_id, line_num, highlighters)
    end
  end

  H.cache = {}
end)

H.normalize_cache = function()
  local res = {}
  for _, change in ipairs(H.cache) do
    -- `change` is { buf_id, from_line, to_line }
    local buf_id = change[1]
    local buf_lines_to_process = res[buf_id] or {}
    for i = change[2], change[3] do
      buf_lines_to_process[i] = true
    end
    res[buf_id] = buf_lines_to_process
  end

  return res
end

H.apply_highlighters = vim.schedule_wrap(function(buf_id, line_num, highlighters)
  if not vim.api.nvim_buf_is_valid(buf_id) then return end

  local line = H.get_line(buf_id, line_num)
  if line == nil then return end

  for _, hi in ipairs(highlighters) do
    -- TODO
  end
end)

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.hipatterns) %s', msg), 0) end

H.get_line = function(buf_id, line_num)
  local ok, line_tbl = pcall(vim.api.nvim_buf_get_lines, buf_id, line_num - 1, line_num, true)
  if not ok then return nil end
  return line_tbl[1]
end

return MiniHipatterns
