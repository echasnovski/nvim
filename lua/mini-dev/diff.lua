-- TODO:
--
-- Code:
--
-- - `goto()` with directions "first"/"prev"/"next"/"last"; `wrap` and `n_times`.
-- - `setqflist()`.
-- - `apply_hunk()` to apply hunk at cursor.
-- - `apply_range()` to apply hunk constructed from range.
-- - `textobject` for hunk textobject.
--
-- Docs:
--
-- Tests:

--- *mini.diff* Work with diff hunks
--- *MiniDiff*
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Show "as you type" 1-way diff by visualizing diff hunks (linewise parts
---   of text that are different between current and reference versions).
---   Visualization can be with colored signs, colored line numbers, etc.
---
--- - Special toggleable view with detailed hunk information directly in text area.
---
--- - Completely configurable and extensible source of text to compare against:
---   text at latest save, file state from Git, etc.
---
--- - Manage diff hunks: navigate, apply, textobject, and more.
---
--- What it doesn't do:
---
--- - Provide functionality to work directly with Git outside of working with
---   Git-related hunks (see |MiniDiff.gen_source.git()|).
---
--- Sources with more details:
--- - |MiniDiff-overview|
--- - |MiniDiff-source-specification|
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.diff').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniDeps`
--- which you can use for scripting or manually (with `:lua MiniDeps.*`).
---
--- See |MiniDeps.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minidiff_config` which should have same structure as
--- `MiniDeps.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'lewis6991/gitsigns.nvim':
---     - Can display only Git diff hunks, while this module has extensible design.
---     - Provides more functionality to work with Git outside of hunks.
---       This module does not (by design).
---
--- # Highlight groups ~
---
--- * `MiniDiffAdd`        - add hunks.
--- * `MiniDiffChange`     - change hunks.
--- * `MiniDiffDelete`     - delete hunks.
--- * `MiniDiffTextAdd`    - "add" part of hunk in text area.
--- * `MiniDiffTextChange` - "change" part of hunk in text area.
--- * `MiniDiffTextDelete` - "delete" part of hunk in text area.
---
--- To change any highlight group, modify it directly with |:highlight|.

---@tag MiniDiff-overview

---@tag MiniDiff-plugin-specification

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
MiniDiff = {}
H = {}

--- Module setup
---
--- Calling this function creates user commands described in |MiniDeps-commands|.
---
---@param config table|nil Module config table. See |MiniDeps.config|.
---
---@usage `require('mini.deps').setup({})` (replace `{}` with your `config` table).
MiniDiff.setup = function(config)
  -- Export module
  _G.MiniDiff = MiniDiff

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniDiff.config = {
  -- Source for how to reference text is computed/updated/visualized/etc.
  source = nil,

  -- Delays (in ms) defining asynchronous visualization process
  delay = {
    -- How much to wait for update after every text change
    text_change = 200,

    -- How much to wait for update after window scroll
    scroll = 50,
  },

  -- Various options
  options = {
    -- Diff algorithm
    algorithm = 'patience',

    -- Whether to use "indent heuristic"
    indent_heuristic = true,
  },
}
--minidoc_afterlines_end

--- Enable diff tracking in buffer
MiniDiff.enable = function(buf_id, config)
  buf_id = H.validate_buf_id(buf_id)
  config = H.validate_config_arg(config)

  -- Don't enable more than once
  if H.is_buf_enabled(buf_id) then return end

  -- Register enabled buffer with cached data for performance
  H.update_cache(buf_id, config)

  -- Attach source
  H.cache[buf_id].source.attach(buf_id)

  -- Add buffer watchers
  vim.api.nvim_buf_attach(buf_id, false, {
    -- Called on every text change (`:h nvim_buf_lines_event`)
    on_lines = function(_, _, _, from_line, _, to_line)
      local buf_cache = H.cache[buf_id]
      -- Properly detach if highlighting is disabled
      if buf_cache == nil then return true end
      H.process_lines(buf_id, from_line + 1, to_line, buf_cache.delay.text_change)
    end,

    -- Called when buffer content is changed outside of current session
    on_reload = function() pcall(MiniDiff.update, buf_id) end,

    -- Called when buffer is unloaded from memory (`:h nvim_buf_detach_event`),
    -- **including** `:edit` command
    on_detach = function() MiniDiff.disable(buf_id) end,
  })

  -- Add buffer autocommands
  local augroup = vim.api.nvim_create_augroup('MiniDiffBuffer' .. buf_id, { clear = true })
  H.cache[buf_id].augroup = augroup

  local update_buf = vim.schedule_wrap(function()
    if not H.is_buf_enabled(buf_id) then return end
    H.update_cache(buf_id, config)
  end)

  local bufwinenter_opts = { group = augroup, buffer = buf_id, callback = update_buf, desc = 'Update buffer cache' }
  vim.api.nvim_create_autocmd('BufWinEnter', bufwinenter_opts)

  -- TODO: This should (if needed) update only visualization, not recompute diff
  -- vim.api.nvim_create_autocmd(
  --   'WinScrolled',
  --   { group = augroup, buffer = buf_id, callback = H.update_view, desc = 'Update visualization in view' }
  -- )

  -- Add highlighting to whole buffer
  H.process_lines(buf_id, 1, vim.api.nvim_buf_line_count(buf_id), 0)
end

--- Disable diff tracking in buffer
MiniDiff.disable = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return end
  H.cache[buf_id] = nil

  vim.api.nvim_del_augroup_by_id(buf_cache.augroup)
  for _, ns in pairs(H.ns_id) do
    H.clear_namespace(buf_id, ns, 0, -1)
  end
  if vim.is_callable(buf_cache.source.detach) then buf_cache.source.detach() end
end

--- Toggle diff tracking in buffer
MiniDiff.toggle = function(buf_id, config)
  buf_id = H.validate_buf_id(buf_id)
  config = H.validate_config_arg(config)

  if H.is_buf_enabled(buf_id) then
    MiniDiff.disable(buf_id)
  else
    MiniDiff.enable(buf_id, config)
  end
end

--- Update diff in buffer
MiniDiff.update = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)
  if not H.is_buf_enabled(buf_id) then H.error(string.format('Buffer %d is not enabled.', buf_id)) end
  H.process_lines(buf_id, 1, vim.api.nvim_buf_line_count(buf_id), 0)
end

MiniDiff.set_ref_text = function(buf_id, text)
  buf_id = H.validate_buf_id(buf_id)
  if type(text) == 'table' then text = table.concat(text, '\n') end
  if type(text) ~= 'string' then H.error('`text` should be either string or array.') end

  if not H.is_buf_enabled(buf_id) then MiniDiff.enable(buf_id) end
  H.cache[buf_id].ref_text = text
  H.process_lines(buf_id, 1, vim.api.nvim_buf_line_count(buf_id), 0)
end

--- Generate builtin highlighters
---
--- This is a table with function elements. Call to actually get highlighter.
MiniDiff.gen_source = {}

MiniDiff.gen_source.git = function()
  -- TODO
  local augroups = {}
  local attach = function(buf_id) end
  local detach = function(buf_id) end
  local apply_hunks = function(hunks) end

  return { attach = attach, detach = detach, apply_hunks = apply_hunks }
end

MiniDiff.gen_source.save = function(opts)
  local default_hl_groups = { add = 'MiniDiffAdd', change = 'MiniDiffChange', delete = 'MiniDiffDelete' }
  -- TODO: Decide on default style
  opts =
    vim.tbl_deep_extend('force', { style = 'number', sign_text = '▒', hl_groups = default_hl_groups }, opts or {})

  local style, sign_text = opts.style or 'sign', nil
  if style == 'sign' then sign_text = opts.sign_text end
  local field = ({ sign = 'sign_hl_group', number = 'number_hl_group', cursorline = 'cursorline_hl_group' })[style]
  local extmark_opts = {
    add = { [field] = opts.hl_groups.add, sign_text = sign_text },
    change = { [field] = opts.hl_groups.change, sign_text = sign_text },
    delete = { [field] = opts.hl_groups.delete, sign_text = sign_text },
  }

  local augroups = {}
  local attach = function(buf_id)
    local augroup = vim.api.nvim_create_augroup('MiniDiffSourceSaveBuffer' .. buf_id, { clear = true })
    augroups[buf_id] = augroup

    local set_ref = function()
      if vim.bo[buf_id].modified then return end
      MiniDiff.set_ref_text(buf_id, vim.api.nvim_buf_get_lines(buf_id, 0, -1, false))
    end

    local au_opts = { group = augroup, buffer = buf_id, callback = set_ref, desc = 'Set reference text after save' }
    vim.api.nvim_create_autocmd('BufWritePost', au_opts)
    set_ref()
  end

  local detach = function(buf_id) pcall(vim.api.nvim_del_augroup_by_id, augroups[buf_id]) end

  -- TODO
  local apply_hunks = function(hunks) end

  return { extmark_opts = extmark_opts, attach = attach, detach = detach, apply_hunks = apply_hunks }
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniDiff.config

-- Timers
H.timer_debounce = vim.loop.new_timer()
H.timer_view = vim.loop.new_timer()

-- Namespaces per highlighter name
H.ns_id = {
  viz = vim.api.nvim_create_namespace('MiniDiffViz'),
  text = vim.api.nvim_create_namespace('MiniDiffText'),
}

-- Cache of queued changes used for debounced highlighting
H.change_queue = {}

-- Cache per enabled buffer
H.cache = {}

-- Permanent `vim.diff()` options
H.vimdiff_opts = { result_type = 'indices', ctxlen = 0, interhunkctxlen = 0 }
if vim.fn.has('nvim-0.9') == 1 then H.vimdiff_opts.linematch = true end

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    source = { config.source, 'table', true },
    delay = { config.delay, 'table' },
    options = { config.options, 'table' },
  })

  vim.validate({
    ['delay.text_change'] = { config.delay.text_change, 'number' },
    ['delay.scroll'] = { config.delay.scroll, 'number' },

    ['options.algorithm'] = { config.options.algorithm, 'string' },
    ['options.indent_heuristic'] = { config.options.indent_heuristic, 'boolean' },
  })

  return config
end

H.apply_config = function(config) MiniDiff.config = config end

H.create_autocommands = function()
  local augroup = vim.api.nvim_create_augroup('MiniDiff', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, pattern = pattern, callback = callback, desc = desc })
  end

  au('BufEnter', '*', H.auto_enable, 'Enable diff')
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  local has_core_diff_hl = vim.fn.has('nvim-0.10') == 1
  hi('MiniDiffAdd',        { link = has_core_diff_hl and 'Added' or 'diffAdded' })
  hi('MiniDiffChange',     { link = has_core_diff_hl and 'Changed' or 'diffChanged' })
  hi('MiniDiffDelete',     { link = has_core_diff_hl and 'Removed' or 'diffRemoved'  })
  hi('MiniDiffTextAdd',    { link = 'MiniDiffAdd' })
  hi('MiniDiffTextChange', { link = 'MiniDiffChange' })
  hi('MiniDiffTextDelete', { link = 'MiniDiffDelete'  })
end

H.is_disabled = function(buf_id)
  local buf_disable = H.get_buf_var(buf_id, 'minidiff_disable')
  return vim.g.minidiff_disable == true or buf_disable == true
end

H.get_config = function(config, buf_id)
  local buf_config = H.get_buf_var(buf_id, 'minidiff_config') or {}
  return vim.tbl_deep_extend('force', MiniDiff.config, buf_config, config or {})
end

H.get_buf_var = function(buf_id, name)
  if not vim.api.nvim_buf_is_valid(buf_id) then return nil end
  return vim.b[buf_id or 0][name]
end

-- Autocommands ---------------------------------------------------------------
H.auto_enable = vim.schedule_wrap(function(data)
  if H.is_buf_enabled(data.buf) then return end

  -- Autoenable only in valid normal buffers. This function is scheduled so as
  -- to have the relevant `buftype`.
  if vim.api.nvim_buf_is_valid(data.buf) and vim.bo[data.buf].buftype == '' then MiniDiff.enable(data.buf) end
end)

-- H.update_view = vim.schedule_wrap(function(data)
--   -- Update view only in enabled buffers
--   local buf_cache = H.cache[data.buf]
--   if buf_cache == nil then return end
--
--   -- NOTE: due to scheduling (which is necessary for better performance),
--   -- current buffer can be not the target one. But as there is no proper (easy
--   -- and/or fast) way to get the view of certain buffer (except the current)
--   -- accept this approach. The main problem of current buffer having not
--   -- enabled highlighting is solved during processing buffer highlighters.
--
--   -- Debounce without aggregating redraws (only last view should be updated)
--   H.timer_view:stop()
--   H.timer_view:start(buf_cache.delay.scroll, 0, H.process_view)
-- end)

-- Validators -----------------------------------------------------------------
H.validate_buf_id = function(x)
  if x == nil or x == 0 then return vim.api.nvim_get_current_buf() end

  if not (type(x) == 'number' and vim.api.nvim_buf_is_valid(x)) then
    H.error('`buf_id` should be `nil` or valid buffer id.')
  end

  return x
end

H.validate_config_arg = function(x)
  if x == nil or type(x) == 'table' then return x or {} end
  H.error('`config` should be `nil` or table.')
end

-- Enabling -------------------------------------------------------------------
H.is_buf_enabled = function(buf_id) return H.cache[buf_id] ~= nil end

H.update_cache = function(buf_id, config)
  local buf_cache = H.cache[buf_id] or {}
  local buf_config = H.get_config(config, buf_id)
  -- TODO: Use `Git` source by default?
  if buf_config.source == nil then
    buf_cache.source = MiniDiff.gen_source.save()
  else
    buf_config.source = H.normalize_source(buf_cache.source)
  end
  buf_cache.delay = buf_config.delay
  buf_cache.options = buf_config.options

  H.cache[buf_id] = buf_cache
end

H.normalize_source = function(source)
  if type(source) ~= 'table' then H.error('`source` should be table.') end

  local res = {}
  res.attach = source.attach
  if not vim.is_callable(res.attach) then H.error('`source.attach` should be callable.') end

  res.extmark_opts = {}
  for _, v in ipairs({ 'add', 'change', 'delete' }) do
    res.extmark_opts[v] = source.extmark_opts[v] or {}
    if type(res.extmark_opts[v]) ~= 'table' then H.error('`extmark_opts.' .. v .. '` should be table.') end
  end

  res.detach = source.detach or function(_) end
  if not vim.is_callable(res.detach) then H.error('`source.detach` should be callable.') end

  res.apply_hunks = source.apply_hunks or function(_) end
  if not vim.is_callable(res.apply_hunks) then H.error('`source.apply_hunks` should be callable.') end

  return res
end

-- Processing -----------------------------------------------------------------
H.process_lines = vim.schedule_wrap(function(buf_id, from_line, to_line, delay_ms)
  add_to_log('process_liens', { from_line = math.max(from_line - 1, 1), to_line = to_line })

  -- Make sure that that at least one line is processed (important to react
  -- after deleting line with extmark non-trivial `extmark_opts`)
  table.insert(H.change_queue, { buf_id, math.min(from_line, to_line), math.max(from_line, to_line) })

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
  -- queue entry with not target (and improper) buffer.
  local buf_cache = H.cache[buf_id]
  if not vim.api.nvim_buf_is_valid(buf_id) or H.is_disabled(buf_id) or buf_cache == nil then return end

  -- Recompute diff hunks
  H.vimdiff_opts.algorithm = buf_cache.options.algorithm
  H.vimdiff_opts.indent_heuristic = buf_cache.options.indent_heuristic
  local cur_text = table.concat(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false), '\n')
  local diff = vim.diff(buf_cache.ref_text, cur_text, H.vimdiff_opts)

  local hunks = {}
  for i, d in ipairs(diff) do
    -- [1] - start line of diff in ref text
    -- [2] - number of deleted (from reference) lines
    -- [3] - start line of diff in cur text
    -- [4] - number of added
    local type = d[2] == 0 and 'add' or (d[4] == 0 and 'delete' or 'change')
    hunks[i] = { type = type, ref_from = d[1], ref_to = d[1] + d[2], cur_from = d[3], cur_to = d[3] + d[4] }
  end
  buf_cache.hunks = hunks

  local ns = H.ns_id.viz
  -- Clear highlighting in target lines
  for l_num, _ in pairs(lines_to_process) do
    H.clear_namespace(buf_id, ns, l_num - 1, l_num)
  end

  -- Compute hunks which contain at least one `lines_to_process`, as the whole
  -- hunk should be redrawn (for example, type could have changed)
  -- TODO
  local hunks_to_redraw = hunks

  -- Redraw hunks
  local extmark_opts = buf_cache.source.extmark_opts
  for _, h in ipairs(hunks_to_redraw) do
    local from, to = math.max(h.cur_from, 1), h.cur_to
    if h.type == 'delete' then to = from + 1 end
    H.clear_namespace(buf_id, ns, from, to)
    for i = from, to - 1 do
      H.set_extmark(buf_id, ns, i - 1, 0, extmark_opts[h.type])
    end
  end
end)

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.diff) %s', msg), 0) end

H.notify = function(msg, level_name) vim.notify('(mini.diff) ' .. msg, vim.log.levels[level_name]) end

H.get_line = function(buf_id, line_num)
  return vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)[1] or ''
end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.get_extmarks = function(...)
  local ok, res = pcall(vim.api.nvim_buf_get_extmarks, ...)
  if not ok then return {} end
  return res
end

H.clear_namespace = function(...) pcall(vim.api.nvim_buf_clear_namespace, ...) end

return MiniDiff
