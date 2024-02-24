-- TODO:
--
-- Code:
--
-- - REALLLY think about renaming to 'mini.hunks'.
--
-- - When moving added line upwards, extmark should not temporarily shift down.
--
-- - Add `config.mappings` with `gh`/`gH` for apply/undo hunk operators,
--   `gh` as textobject (think about different name to have work in both Visual
--   and Opertor-pending modes)?
--
-- - `toggle_style()` - set style to target if not equal to current, apply
--   previous otherwise.
-- - `goto()` with directions "first"/"prev"/"next"/"last"; `wrap` and `n_times`.
-- - `setqflist()`.
-- - `apply_range()` to apply hunks constructed from range.
-- - `undo_range()` to undo hunks constructed from range. NOTE: does not need
--   source method as it modifies current text based on reference text.
-- - `textobject` for hunk textobject.
--
-- Docs:
--
-- Tests:
-- - Updates if no redraw seemingly is done. Example for `save` source: `yyp`
--   should add green highlighting and `<C-s>` should remove it.
--
-- - Deleting last line should be visualized.

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
--- * `MiniDiffSignAdd`    - add hunks with gutter view.
--- * `MiniDiffSignChange` - change hunks with gutter view.
--- * `MiniDiffSignDelete` - delete hunks with gutter view.
--- * `MiniDiffLineAdd`    - add hunks with line view.
--- * `MiniDiffLineChange` - change hunks with line view.
--- * `MiniDiffLineDelete` - delete hunks with line view.
--- * `MiniDiffWordAdd`    - add hunks with word view.
--- * `MiniDiffWordChange` - change hunks with word view.
--- * `MiniDiffWordDelete` - delete hunks with word view.
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
  -- Options for how hunks are visualized
  view = {
    -- General visualization style. Available values are:
    -- 'sign', 'number', 'line', 'word'.
    style = vim.o.number and 'number' or 'sign',

    -- Signs used for hunks with 'sign' view
    signs = { add = '▒', change = '▒', delete = '▒' },

    -- Priority of used extmarks
    priority = 10,
  },

  -- Source for how to reference text is computed/updated/etc.
  source = nil,

  -- Delays (in ms) defining asynchronous visualization process
  delay = {
    -- How much to wait for update after every text change
    text_change = 200,
  },

  -- Various options
  options = {
    -- Diff algorithm
    algorithm = 'patience',

    -- Whether to use "indent heuristic"
    indent_heuristic = true,

    -- The amount of second-stage diff to align lines (on Neovim>=0.9)
    linematch = 60,
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
      -- Properly detach if diffing is disabled
      if buf_cache == nil then return true end
      H.schedule_diff_update(buf_id, buf_cache.config.delay.text_change)
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

  -- Immediately process whole buffer
  H.schedule_diff_update(buf_id, 0)
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
  H.schedule_diff_update(buf_id, 0)
end

-- TODO: Or maybe not export this and export `apply_range(buf_id, from, to)` directly?
MiniDiff.apply_hunks = function(buf_id, hunks)
  buf_id = H.validate_buf_id(buf_id)
  hunks = H.validate_hunks(hunks)
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then H.error('Buffer ' .. buf_id .. ' does not have enabled source.') end
  buf_cache.source.apply_hunks(buf_id, hunks)
end

MiniDiff.get_buf_data = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return nil end
  return vim.deepcopy({
    ref_text = buf_cache.ref_text,
    hunks = buf_cache.hunks,
    hunk_summary = buf_cache.hunk_summary,
    config = buf_cache.config,
  })
end

MiniDiff.set_ref_text = function(buf_id, text)
  buf_id = H.validate_buf_id(buf_id)
  if type(text) == 'table' then text = table.concat(text, '\n') end
  if type(text) ~= 'string' then H.error('`text` should be either string or array.') end

  if not H.is_buf_enabled(buf_id) then MiniDiff.enable(buf_id) end
  H.cache[buf_id].ref_text = text
  H.schedule_diff_update(buf_id, 0)
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

MiniDiff.gen_source.save = function()
  local augroups = {}
  local attach = function(buf_id)
    local augroup = vim.api.nvim_create_augroup('MiniDiffSourceSaveBuffer' .. buf_id, { clear = true })
    augroups[buf_id] = augroup

    local set_ref = function()
      if vim.bo[buf_id].modified then return end
      MiniDiff.set_ref_text(buf_id, vim.api.nvim_buf_get_lines(buf_id, 0, -1, false))
    end

    -- Autocommand are more effecient than file watcher as it doesn't read disk
    local au_opts = { group = augroup, buffer = buf_id, callback = set_ref, desc = 'Set reference text after save' }
    vim.api.nvim_create_autocmd({ 'BufWritePost', 'FileChangedShellPost' }, au_opts)
    set_ref()
  end

  local detach = function(buf_id) pcall(vim.api.nvim_del_augroup_by_id, augroups[buf_id]) end

  local apply_hunks = function(buf_id, hunks)
    -- Compute new lines after hunks are applied
    local cur_lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
    local ref_lines = vim.split(H.cache[buf_id].ref_text, '\n')
    local new_lines = H.apply_hunks_to_lines(hunks, ref_lines, cur_lines)

    -- Write new lines to a file
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, new_lines)
    vim.cmd('write')
    vim.cmd('undo' .. (vim.fn.has('nvim-0.8') == 1 and '!' or ''))

    -- Infer if new file state is modified
    local is_modified = #cur_lines ~= #new_lines
    for i = 1, math.min(#cur_lines, #new_lines) do
      if cur_lines[i] ~= new_lines[i] then is_modified = true end
    end
    vim.bo[buf_id].modified = is_modified
  end

  return { attach = attach, detach = detach, apply_hunks = apply_hunks }
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniDiff.config

-- TODO: Use `Git` source by default?
H.default_source = MiniDiff.gen_source.save()

-- Timers
H.timer_debounce = vim.loop.new_timer()
H.timer_view = vim.loop.new_timer()

-- Namespaces per highlighter name
H.ns_id = {
  viz = vim.api.nvim_create_namespace('MiniDiffViz'),
  text = vim.api.nvim_create_namespace('MiniDiffText'),
}

-- Cache of buffers waiting for debounced diff update
H.bufs_to_update = {}

-- Cache per enabled buffer
H.cache = {}

-- Common extmark data for supported styles
--stylua: ignore
H.style_extmark_data = {
  sign       = { hl_group_prefix = 'MiniDiffSign', field = 'sign_hl_group' },
  number     = { hl_group_prefix = 'MiniDiffSign', field = 'number_hl_group' },
  line       = { hl_group_prefix = 'MiniDiffLine', field = 'line_hl_group' },
  word       = { hl_group_prefix = 'MiniDiffWord' },
}

-- Permanent `vim.diff()` options
H.vimdiff_opts = { result_type = 'indices', ctxlen = 0, interhunkctxlen = 0 }
H.vimdiff_supports_linematch = vim.fn.has('nvim-0.9') == 1

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  vim.validate({
    view = { config.view, 'table' },
    source = { config.source, 'table', true },
    delay = { config.delay, 'table' },
    options = { config.options, 'table' },
  })

  vim.validate({
    ['view.style'] = { config.view.style, 'string' },
    ['view.signs'] = { config.view.signs, 'table' },
    ['view.priority'] = { config.view.priority, 'number' },

    ['delay.text_change'] = { config.delay.text_change, 'number' },

    ['options.algorithm'] = { config.options.algorithm, 'string' },
    ['options.indent_heuristic'] = { config.options.indent_heuristic, 'boolean' },
    ['options.linematch'] = { config.options.linematch, 'number' },
  })

  vim.validate({
    ['view.signs.add'] = { config.view.signs.add, 'string' },
    ['view.signs.change'] = { config.view.signs.change, 'string' },
    ['view.signs.delete'] = { config.view.signs.delete, 'string' },
  })

  return config
end

H.apply_config = function(config)
  MiniDiff.config = config

  -- Register decoration provider which actually makes visualization
  local ns_id_viz = H.ns_id.viz
  local on_win = function(_, _, bufnr, top, bottom)
    local buf_cache = H.cache[bufnr]
    if buf_cache == nil then return false end

    if buf_cache.needs_clear then
      H.clear_namespace(bufnr, ns_id_viz, 0, -1)
      buf_cache.needs_clear = false
    end

    local redraw_line_data = buf_cache.redraw_line_data
    for i = top + 1, bottom + 1 do
      if redraw_line_data[i] ~= nil then
        H.set_extmark(bufnr, ns_id_viz, i - 1, 0, redraw_line_data[i])
        redraw_line_data[i] = nil
      end
    end
  end
  vim.api.nvim_set_decoration_provider(ns_id_viz, { on_win = on_win })
end

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
  hi('MiniDiffSignAdd',    { link = has_core_diff_hl and 'Added' or 'diffAdded' })
  hi('MiniDiffSignChange', { link = has_core_diff_hl and 'Changed' or 'diffChanged' })
  hi('MiniDiffSignDelete', { link = has_core_diff_hl and 'Removed' or 'diffRemoved'  })
  hi('MiniDiffLineAdd',    { link = 'MiniDiffSignAdd' })
  hi('MiniDiffLineChange', { link = 'MiniDiffSignChange' })
  hi('MiniDiffLineDelete', { link = 'MiniDiffSignDelete'  })
  hi('MiniDiffTextAdd',    { link = 'MiniDiffLineAdd' })
  hi('MiniDiffTextChange', { link = 'MiniDiffLineChange' })
  hi('MiniDiffTextDelete', { link = 'MiniDiffLineDelete'  })
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

H.validate_hunks = function(x)
  if not vim.tbl_islist(x) then H.error('`hunks` should be array.') end
  for _, h in ipairs(x) do
    if type(x) ~= 'table' then H.error('`hunks` items should be tables.') end
    if type(x.cur_start) ~= 'number' then H.error('`hunks` items should contain `cur_start` number field.') end
    if type(x.cur_count) ~= 'number' then H.error('`hunks` items should contain `cur_count` number field.') end
    if type(x.ref_start) ~= 'number' then H.error('`hunks` items should contain `ref_start` number field.') end
    if type(x.ref_count) ~= 'number' then H.error('`hunks` items should contain `ref_count` number field.') end
  end
  return x
end

H.validate_callable = function(x, name)
  if vim.is_callable(x) then return end
  H.error('`' .. name .. '` should be callable.')
end

-- Enabling -------------------------------------------------------------------
H.is_buf_enabled = function(buf_id) return H.cache[buf_id] ~= nil end

H.update_cache = function(buf_id, config)
  local buf_cache = H.cache[buf_id] or {}
  local buf_config = H.get_config(config, buf_id)
  buf_cache.config = buf_config
  buf_cache.extmark_opts = H.convert_view_to_extmark_opts(buf_config.view)
  buf_cache.source = H.normalize_source(buf_config.source or H.default_source)

  buf_cache.hunks, buf_cache.hunk_summary, buf_cache.redraw_line_data = {}, {}, {}

  H.cache[buf_id] = buf_cache
end

H.normalize_source = function(source)
  if type(source) ~= 'table' then H.error('`source` should be table.') end

  local res = { attach = source.attach, detach = source.detach, apply_hunks = source.apply_hunks }
  res.detach = source.detach or function(_) end
  res.apply_hunks = source.apply_hunks or function(_) end

  H.validate_callable(res.attach, 'source.attach')
  H.validate_callable(res.detach, 'source.detach')
  H.validate_callable(res.apply_hunks, 'source.apply_hunks')

  return res
end

H.convert_view_to_extmark_opts = function(view)
  local extmark_data = H.style_extmark_data[view.style]
  if extmark_data == nil then H.error('`view.style` ' .. vim.inspect(view.style) .. ' is not supported.') end

  -- TODO: Handle "word" style separately

  local signs = {}
  if view.style == 'sign' then signs = view.signs end
  local field, hl_group_prefix = extmark_data.field, extmark_data.hl_group_prefix
  return {
    add = { [field] = hl_group_prefix .. 'Add', sign_text = signs.add, priority = view.priority },
    change = { [field] = hl_group_prefix .. 'Change', sign_text = signs.change, priority = view.priority },
    delete = { [field] = hl_group_prefix .. 'Delete', sign_text = signs.delete, priority = view.priority },
  }
end

-- Processing -----------------------------------------------------------------
H.schedule_diff_update = vim.schedule_wrap(function(buf_id, delay_ms)
  H.bufs_to_update[buf_id] = true
  H.timer_debounce:stop()
  H.timer_debounce:start(delay_ms, 0, H.process_scheduled_buffers)
end)

H.process_scheduled_buffers = vim.schedule_wrap(function()
  for buf_id, _ in pairs(H.bufs_to_update) do
    H.update_buf_diff(buf_id)
  end
  H.bufs_to_update = {}
end)

H.update_buf_diff = vim.schedule_wrap(function(buf_id)
  -- Return early if buffer is not proper
  local buf_cache = H.cache[buf_id]
  if not vim.api.nvim_buf_is_valid(buf_id) or H.is_disabled(buf_id) or buf_cache == nil then return end

  -- Recompute diff hunks with summary
  local options = buf_cache.config.options
  H.vimdiff_opts.algorithm = options.algorithm
  H.vimdiff_opts.indent_heuristic = options.indent_heuristic
  if H.vimdiff_supports_linematch then H.vimdiff_opts.linematch = options.linematch end
  local cur_text = table.concat(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false), '\n')
  local diff = vim.diff(buf_cache.ref_text, cur_text, H.vimdiff_opts)

  local extmark_opts = buf_cache.extmark_opts
  local hunks, redraw_line_data = {}, {}
  local n_add, n_change, n_delete = 0, 0, 0
  for i, d in ipairs(diff) do
    local n_ref, n_cur = d[2], d[4]
    -- Hunk
    local type = n_ref == 0 and 'add' or (n_cur == 0 and 'delete' or 'change')
    hunks[i] = { type = type, ref_start = d[1], ref_count = n_ref, cur_start = d[3], cur_count = n_cur }

    -- Summary
    local hunk_n_change = math.min(n_ref, n_cur)
    n_add = n_add + n_cur - hunk_n_change
    n_change = n_change + hunk_n_change
    n_delete = n_delete + n_ref - hunk_n_change

    -- Register lines for redraw. At least one line should visualize hunk.
    local ext_opts = extmark_opts[type]
    local from, n = math.max(d[3], 1), math.max(n_cur, 1)
    for l_num = from, from + n - 1 do
      -- Prefer "change" hunk type over anything already there (like "delete")
      if redraw_line_data[l_num] == nil or type == 'change' then redraw_line_data[l_num] = ext_opts end
    end
  end
  local hunk_summary = { add = n_add, change = n_change, delete = n_delete }
  buf_cache.hunks, buf_cache.hunk_summary, buf_cache.redraw_line_data = hunks, hunk_summary, redraw_line_data

  -- Set buffer-local variable with summary for easier external usage
  vim.b.minidiff_summary = hunk_summary

  local summary = {}
  if n_add > 0 then table.insert(summary, '+' .. n_add) end
  if n_change > 0 then table.insert(summary, '~' .. n_change) end
  if n_delete > 0 then table.insert(summary, '-' .. n_delete) end
  vim.b.minidiff_summary_string = table.concat(summary, ' ')

  -- Request highlighting clear to be done in decoration provider
  buf_cache.needs_clear = true

  -- Force redraw. NOTE: Using 'redraw' not always works (`<Cmd>update<CR>`
  -- from keymap with "save" source will not redraw) and 'redraw!' flickers.
  vim.api.nvim__buf_redraw_range(buf_id, 0, -1)

  -- Redraw statusline to have possible statusline component up to date
  vim.cmd('redrawstatus')

  -- Trigger event for users to possibly hook into
  vim.api.nvim_exec_autocmds('User', { pattern = 'MiniDiffUpdated' })
end)

-- Hunks ----------------------------------------------------------------------
H.apply_hunks_to_lines = function(hunks, ref_lines, cur_lines)
  hunks = vim.deepcopy(hunks)
  table.sort(hunks, function(a, b) return a.ref_start < b.ref_start end)

  local res, lnum = {}, 0
  for _, h in ipairs(hunks) do
    -- "Add" hunks have reference start just above lines to be added
    local hunk_start = h.ref_start + (h.ref_count == 0 and 0 or -1)

    -- Add lines between hunks (and before first one)
    for i = lnum + 1, hunk_start do
      table.insert(res, ref_lines[i])
    end

    -- Replace deleted lines (maybe zero) with current lines (maybe zero)
    for j = h.cur_start, h.cur_start + h.cur_count - 1 do
      table.insert(res, cur_lines[j])
    end
    lnum = hunk_start + h.ref_count
  end

  -- Add lines after last hunk (even if there is no hunks)
  for i = lnum + 1, #ref_lines do
    table.insert(res, ref_lines[i])
  end

  return res
end

H.invert_hunk = function(hunk)
  --stylua: ignore
  return {
    cur_start = hunk.ref_start, cur_count = hunk.ref_count,
    ref_start = hunk.cur_start, ref_count = hunk.cur_count,
    type = hunk.cur_count == 0 and 'add' or (hunk.ref_count == 0 and 'delete' or 'change'),
  }
end

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
