-- TODO
--
-- Code:
--
-- Docs:

--- *mini.hipatterns* Highlight patterns in text
--- *MiniHipatterns*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Highlight configurable patterns asynchronously with debounce.
---
--- See |MiniHipatterns.config| and |MiniHipatterns.gen_highlighter| for examples
--- of common use cases.
---
--- Notes:
--- - It is auto-enabled only in "normal" buffers (see 'buftype'). You can
---   manually enable in other buffer type with |MiniHipatterns.enable()|.
---
--- - Sometimes (especially during frequent buffer updates on same line numbers)
---   highlighting can be outdated or not applied when it should be. This is due
---   to asynchronous nature of updates reacting to text changes (via
---   `on_lines` of |nvim_buf_attach()|).
---   To make them up to date, either use |MiniHipatterns.update()| or scroll
---   window (for example, with |CTRL-E| / |CTRL-Y|; this will ensure up to
---   date highlighting inside window view).
---
--- - There can be flicker when used together with 'mini.completion' or built-in
---   completion. This is due to https://github.com/neovim/neovim/issues/23653.
---   For better experience with 'mini.completion', make sure that its
---   `config.delay.completion` is less than this module's `config.delay.text_change`.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.hipatterns').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniHipatterns` which you can use for scripting or manually (with `:lua
--- MiniHipatterns.*`).
---
--- See |MiniHipatterns.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minihipatterns_config` which should have same structure as
--- `MiniHipatterns.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'folke/todo-comments':
---     - Oriented for "TODO", "NOTE", "FIXME" like patterns, while this module
---       can work with any Lua patterns and computable highlight groups.
---     - Has functionality beyond text highlighting (sign placing,
---       "telescope.nvim" extension, etc.), while this module only focuses on
---       highlighting text.
--- - 'folke/paint.nvim':
---     - Mostly similar to this module, but with slightly less functionality,
---       like computed pattern and highlight group, asynchronous delay, etc.
--- - 'NvChad/nvim-colorizer.lua':
---     - Oriented for color highlighting, while this module can work with any
---       Lua patterns and computable highlight groups.
---     - Has more built-in color spaces to highlight, while this module out of
---       the box provides only hex color highlighting
---       (see |MiniHipatterns.gen_highlighter.hex_color()|). Other types are
---       also possible to implement.
--- - 'uga-rosa/ccc.nvim':
---     - Has more than color highlighting functionality, which is compared to
---       this module in the same way as 'NvChad/nvim-colorizer.lua'.
---
--- # Highlight groups~
---
--- * `MiniHipatternsFixme` - suggested group to use for `FIXME`-like patterns.
--- * `MiniHipatternsHack` - suggested group to use for `HACK`-like patterns.
--- * `MiniHipatternsTodo` - suggested group to use for `TODO`-like patterns.
--- * `MiniHipatternsNote` - suggested group to use for `NOTE`-like patterns.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- This module can be disabled in three ways:
--- - Globally: set `vim.g.minihipatterns_disable` to `true`.
--- - Locally for buffer permanently: set `vim.b.minihipatterns_disable` to `true`.
--- - Locally for buffer termporarily (until next auto-enabling event):
---   use |MiniHipatterns.disable()|.
---
--- Considering high number of different scenarios and customization
--- intentions, writing exact rules for disabling module's functionality is
--- left to user. See |mini.nvim-disabling-recipes| for common recipes.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
-- TODO: Make local before public release
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

  -- Create default highlighting
  H.create_default_hl()
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Options ~
---
--- ## Highlighters ~
---
--- NOTE: `pattern` should have submatch delimited by placing `()` on start and
--- end, NOT by surrounding with it. Otherwise it will result in error
--- containing `number expected, got string`.
---
--- - Use only named entries for better buffer-local config (due to
---   `vim.tbl_deep_extend()` behavior).
--- ## Delay ~
---
--- # Common use cases ~
---
--- - TODO, NOTE, etc.
--- - Color highlighting.
--- - Trailing whitespace (if don't want to use more tailored 'mini.trailspace'): >
---
---   gen_hi.pattern('%f[%s]%s*$', 'Error')
---
--- - Indent levels?
---
--- - Enable only in certain filetypes (via `vim.b.minihipatterns_config` in
---   filetype plugin).
--- - Disable only in certain filetypes (via `vim.b.minihipatterns_disable`).
MiniHipatterns.config = {
  -- Table with highlighters (see |MiniHipatterns.config| for more details)
  highlighters = {},

  -- Delays (in ms) defining asynchronous highlighting process
  delay = {
    -- How much to wait after every text change
    text_change = 200,

    -- How much to wait after window scroll
    scroll = 50,
  },
}
--minidoc_afterlines_end

MiniHipatterns.enable = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  -- Don't enable more than once
  if H.is_buf_enabled(buf_id) then return end

  -- Register enabled buffer with cached data for performance
  H.update_buf_data(buf_id)

  -- Add highlighting to whole buffer
  H.process_lines(buf_id, 1, vim.api.nvim_buf_line_count(buf_id), 0)

  -- Add watchers to current buffer
  vim.api.nvim_buf_attach(buf_id, false, {
    on_lines = function(_, _, _, from_line, _, to_line)
      local buf_data = H.buf_enabled[buf_id]
      -- Properly detach if registered to detach
      if buf_data == nil then return true end
      H.process_lines(buf_id, from_line + 1, to_line, buf_data.delay.text_change)
    end,
    on_reload = function() pcall(MiniHipatterns.update, buf_id) end,
    on_detach = function() MiniHipatterns.disable(buf_id) end,
  })
end

MiniHipatterns.disable = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  H.buf_enabled[buf_id] = nil
  vim.api.nvim_buf_clear_namespace(buf_id, H.ns_id.highlight, 0, -1)
end

MiniHipatterns.toggle = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  local f = H.is_buf_enabled(buf_id) and MiniHipatterns.disable or MiniHipatterns.enable
  f(buf_id)
end

MiniHipatterns.update = function(buf_id, from_line, to_line)
  buf_id = H.validate_buf_id(buf_id)

  if not H.is_buf_enabled(buf_id) then H.error(string.format('Buffer %d is not enabled.', buf_id)) end

  from_line = from_line or 1
  if type(from_line) ~= 'number' then H.error('`from_line` should be a number.') end
  to_line = to_line or vim.api.nvim_buf_line_count(buf_id)
  if type(to_line) ~= 'number' then H.error('`to_line` should be a number.') end

  -- Process lines immediately without delay
  H.process_lines(buf_id, from_line, to_line, 0)
end

MiniHipatterns.get_enabled_buffers = function()
  local res = {}
  for buf_id, _ in pairs(H.buf_enabled) do
    if vim.api.nvim_buf_is_valid(buf_id) then
      table.insert(res, buf_id)
    else
      -- Cleanup after buffer is invalid
      H.buf_enabled[buf_id] = nil
    end
  end

  -- Ensure consistent order
  table.sort(res)

  return res
end

MiniHipatterns.gen_highlighter = {}

-- Add note about `%f[%w]()aaa()%f[%W]` pattern
-- Add example with `FIXME`, `HACK`, `TODO`, and `NOTE`.
MiniHipatterns.gen_highlighter.pattern = function(pattern, group, opts)
  pattern = H.validate_string(pattern, 'pattern')
  group = H.validate_string(group, 'group')
  opts = vim.tbl_deep_extend('force', { priority = 200, filter = H.always_true }, opts or {})

  return { pattern = H.wrap_pattern_with_filter(pattern, opts.filter), group = group, priority = opts.priority }
end

-- Works only with enabled |termguicolors|
MiniHipatterns.gen_highlighter.hex_color = function(opts)
  opts = vim.tbl_deep_extend('force', { style = 'full', priority = 200, filter = H.always_true }, opts or {})

  local pattern = opts.style == '#' and '()#()%x%x%x%x%x%x%f[%X]' or '#%x%x%x%x%x%x%f[%X]'

  return {
    pattern = H.wrap_pattern_with_filter(pattern, opts.filter),
    group = function(_, match) return H.compute_hex_color_group(match, opts.style) end,
    priority = opts.priority,
  }
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniHipatterns.config

-- Timers
H.timer_debounce = vim.loop.new_timer()
H.timer_view = vim.loop.new_timer()

-- Cache of queued changes used for debounced highlighting
H.change_queue = {}

-- Namespaces
H.ns_id = { highlight = vim.api.nvim_create_namespace('MiniHipatternsHighlight') }

-- Data about processed buffers
H.buf_enabled = {}

-- Data about created highlight groups for hex colors
H.hex_color_groups = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    highlighters = { config.highlighters, 'table' },
    delay = { config.delay, 'table' },
  })

  vim.validate({
    ['delay.text_change'] = { config.delay.text_change, 'number' },
    ['delay.scroll'] = { config.delay.scroll, 'number' },
  })

  return config
end

H.apply_config = function(config) MiniHipatterns.config = config end

H.create_autocommands = function()
  local augroup = vim.api.nvim_create_augroup('MiniHipatterns', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  au('BufWinEnter', '*', H.update_or_enable, 'Enable buffer pattern highlighters')
  au({ 'WinScrolled', 'FileType' }, '*', H.update_view, 'Update highlighting in the view')
  au('ColorScheme', '*', H.on_colorscheme, 'Reload all enabled pattern highlighters')
end

--stylua: ignore
H.create_default_hl = function()
  vim.api.nvim_set_hl(0, 'MiniHipatternsFixme', { default = true, link = 'DiagnosticError' })
  vim.api.nvim_set_hl(0, 'MiniHipatternsHack',  { default = true, link = 'DiagnosticWarn' })
  vim.api.nvim_set_hl(0, 'MiniHipatternsTodo',  { default = true, link = 'DiagnosticInfo' })
  vim.api.nvim_set_hl(0, 'MiniHipatternsNote',  { default = true, link = 'DiagnosticHint' })
end

H.is_disabled = function(buf_id)
  local buf_disable = H.get_buf_var(buf_id, 'minihipatterns_disable')
  return vim.g.miniindentscope_disable == true or buf_disable == true
end

H.get_config = function(config, buf_id)
  local buf_config = H.get_buf_var(buf_id, 'minihipatterns_config') or {}
  return vim.tbl_deep_extend('force', MiniHipatterns.config, buf_config, config or {})
end

H.get_buf_var = function(buf_id, name)
  if not vim.api.nvim_buf_is_valid(buf_id) then return nil end
  return vim.b[buf_id or 0][name]
end

-- Autocommands ---------------------------------------------------------------
H.update_or_enable = vim.schedule_wrap(function(data)
  -- Update buffer data in already enabled buffers
  if H.is_buf_enabled(data.buf) then
    H.update_buf_data(data.buf)
    return
  end

  -- Autoenable only in valid normal buffers. This function is scheduled so as
  -- to have the relevant `buftype`.
  if vim.api.nvim_buf_is_valid(data.buf) and vim.bo[data.buf].buftype == '' then MiniHipatterns.enable(data.buf) end
end)

H.update_view = vim.schedule_wrap(function(data)
  -- Update view only in enabled buffers
  local buf_data = H.buf_enabled[data.buf]
  if buf_data == nil then return end

  -- NOTE: due to scheduling (which is necessary for better performance),
  -- current buffer can be not the target one. But as there is no proper (easy
  -- and/or fast) way to get the view of certain buffer (except the current)
  -- accept this approach. The main problem of current buffer having not
  -- enabled highlighting is solved during processing buffer highlighters.

  -- Debounce without aggregating redraws (only last view should be updated)
  H.timer_view:stop()
  H.timer_view:start(buf_data.delay.scroll, 0, H.process_view)
end)

H.on_colorscheme = function()
  -- Reset created highlight groups for hex colors, as they are probably
  -- cleared after `:hi clear`
  H.hex_color_groups = {}

  -- Reload all currently enabled buffers
  for buf_id, _ in pairs(H.buf_enabled) do
    MiniHipatterns.disable(buf_id)
    MiniHipatterns.enable(buf_id)
  end
end

-- Validators -----------------------------------------------------------------
H.validate_buf_id = function(x)
  if x == nil or x == 0 then x = vim.api.nvim_get_current_buf() end
  if not (type(x) == 'number' and vim.api.nvim_buf_is_valid(x)) then
    H.error('`buf_id` should be `nil` or valid buffer id.')
  end

  return x
end

H.validate_string = function(x, name)
  if type(x) == 'string' then return x end
  H.error(string.format('`%s` should be string.'))
end

-- Enabling -------------------------------------------------------------------
H.is_buf_enabled = function(buf_id) return H.buf_enabled[buf_id] ~= nil end

H.update_buf_data = function(buf_id)
  local buf_config = H.get_config(nil, buf_id)
  H.buf_enabled[buf_id] = {
    highlighters = H.normalize_highlighters(buf_config.highlighters),
    delay = buf_config.delay,
  }
end

H.normalize_highlighters = function(highlighters)
  local res = {}
  for _, hi in pairs(highlighters) do
    local pattern = type(hi.pattern) == 'string' and function(...) return hi.pattern end or hi.pattern
    local group = type(hi.group) == 'string' and function(...) return hi.group end or hi.group
    local priority = hi.priority or 200

    if vim.is_callable(pattern) and vim.is_callable(group) and type(priority) == 'number' then
      table.insert(res, { pattern = pattern, group = group, priority = priority })
    end
  end

  return res
end

-- Processing -----------------------------------------------------------------
H.process_lines = vim.schedule_wrap(function(buf_id, from_line, to_line, delay_ms)
  table.insert(H.change_queue, { buf_id, from_line, to_line })

  -- Debounce
  H.timer_debounce:stop()
  H.timer_debounce:start(delay_ms, 0, H.process_change_queue)
end)

H.process_view = vim.schedule_wrap(function()
  table.insert(H.change_queue, { vim.api.nvim_get_current_buf(), vim.fn.line('w0'), vim.fn.line('w$') })

  -- Process immediately assuming debouncing should be already done
  H.process_change_queue()
end)

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
  -- Return early if buffer is not proper.
  -- Also check if buffer is enabled here mostly for better resilience. It
  -- might be actually needed due to various `schedule_wrap`s leading to change
  -- queue entery with not target (and improper) buffer.
  local buf_data = H.buf_enabled[buf_id]
  if not vim.api.nvim_buf_is_valid(buf_id) or H.is_disabled(buf_id) or buf_data == nil then return end

  -- Optimizations are done assuming small-ish number of highlighters and
  -- large-ish number of lines to process

  -- Remove current highlights
  local ns = H.ns_id.highlight
  for l_num, _ in pairs(lines_to_process) do
    vim.api.nvim_buf_clear_namespace(buf_id, ns, l_num - 1, l_num)
  end

  -- Add new highlights
  local highlighters = buf_data.highlighters
  for _, hi in ipairs(highlighters) do
    H.apply_highlighter(hi, buf_id, lines_to_process)
  end
end)

H.apply_highlighter = vim.schedule_wrap(function(hi, buf_id, lines_to_process)
  local pattern, group = hi.pattern(buf_id), hi.group
  if type(pattern) ~= 'string' then return end
  local pattern_has_line_start = pattern:sub(1, 1) == '^'

  -- Apply per proper line
  local ns = H.ns_id.highlight
  local extmark_opts = { priority = hi.priority }

  for l_num, _ in pairs(lines_to_process) do
    local line = H.get_line(buf_id, l_num)
    local from, to, sub_from, sub_to = line:find(pattern)

    while from and (from <= to) do
      -- Compute whole pattern match
      local match = line:sub(from, to)

      -- Compute (possibly inferred) submatch
      sub_from, sub_to = sub_from or from, sub_to or (to + 1)
      local sub_match = line:sub(sub_from, sub_to)

      -- Set extmark based on submatch
      extmark_opts.hl_group = group(buf_id, match, sub_match)
      extmark_opts.end_col = sub_to - 1
      if extmark_opts.hl_group ~= nil then H.set_extmark(buf_id, ns, l_num - 1, sub_from - 1, extmark_opts) end

      -- Overcome an issue that `string.find()` doesn't recognize `^` when
      -- `init` is more than 1
      if pattern_has_line_start then break end

      from, to, sub_from, sub_to = line:find(pattern, to + 1)
    end
  end
end)

-- Built-in highlighters ------------------------------------------------------
H.wrap_pattern_with_filter = function(pattern, filter)
  return function(...)
    if not filter(...) then return nil end
    return pattern
  end
end

H.compute_hex_color_group = function(hex_color, style)
  local hex = hex_color:lower():sub(2)
  local group_name = 'MiniHipatterns' .. hex

  -- Use manually tracked table instead of `vim.fn.hlexists()` because the
  -- latter still returns true for cleared highlights
  if H.hex_color_groups[group_name] then return group_name end

  -- Define highlight group if it is not already defined
  if style == 'full' or style == '#' then
    -- Compute opposite color based on Oklab lightness (for better contrast)
    local opposite = H.compute_opposite_color(hex)
    vim.api.nvim_set_hl(0, group_name, { fg = opposite, bg = hex_color })
  end

  if style == 'line' then vim.api.nvim_set_hl(0, group_name, { sp = hex_color, underline = true }) end

  -- Keep track of created groups to properly react on `:hi clear`
  H.hex_color_groups[group_name] = true

  return group_name
end

H.compute_opposite_color = function(hex)
  local dec = tonumber(hex, 16)
  local b = H.correct_channel(math.fmod(dec, 256) / 255)
  local g = H.correct_channel(math.fmod((dec - b) / 256, 256) / 255)
  local r = H.correct_channel(math.floor(dec / 65536) / 255)

  local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
  local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
  local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

  local l_, m_, s_ = H.cuberoot(l), H.cuberoot(m), H.cuberoot(s)

  local L = H.correct_lightness(0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_)

  return L < 0.5 and '#ffffff' or '#000000'
end

-- Function for RGB channel correction. Assumes input in [0; 1] range
-- https://bottosson.github.io/posts/colorwrong/#what-can-we-do%3F
H.correct_channel = function(x) return 0.04045 < x and math.pow((x + 0.055) / 1.055, 2.4) or (x / 12.92) end

-- Function for lightness correction
-- https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab
H.correct_lightness = function(x)
  local k1, k2 = 0.206, 0.03
  local k3 = (1 + k1) / (1 + k2)

  return 0.5 * (k3 * x - k1 + math.sqrt((k3 * x - k1) ^ 2 + 4 * k2 * k3 * x))
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.hipatterns) %s', msg), 0) end

H.get_line =
  function(buf_id, line_num) return vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)[1] or '' end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.always_true = function() return true end

H.cuberoot = function(x) return math.pow(x, 0.333333) end

return MiniHipatterns
