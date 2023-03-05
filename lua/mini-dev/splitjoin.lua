-- MIT License Copyright (c) 2023 Evgeni Chasnovski

-- TODO:
--
-- Code:
-- - Design:
--     - Rethink again cost/benefit ratio of added hooks.
-- - Features:
--
-- Tests:
-- - General:
--     - Cursor should track its current position.
--     - Ensure that it works both inside strings and comments.
--     - Ensure it works on empty brackets.
--     - Arrays from `detect` are not extended deeply:
--       `detect.brackets = { '%b()' }` should detect only `()`, not `[]`/`{}`.
--     - Mappings should work inside visual selection using
--       `MiniSplitjoin.get_visual_region()`.
-- - Split:
--     - Any whitespace around separators or brackets should be removed.
--     - Correctly indents and tracks split positions with single argument and
--       trailing separator. It might not be the case if tracking of split
--       positions is done not correctly.
--       Example: 'f(aa,)' should result into {'f(', '\taa,' ')'}.
-- - Join:
--     - First and last joins are done without single space padding.
-- - Comment respect:
--     - Split inherits indent **with** comment leader on next line.
--     - Indent increase during split respects omment leaders if whole
--       increased block is commented.
--     - Join removes indent **with** comment leader before join.
--     - Both 'commentstring' and 'comments' are respected.
--
-- Documentation:
-- - Mostly designed to work around `toggle()`: split if all split positions
--   are on same line, join otherwise. If initial split positions are on
--   different lines, join first and then split.
-- - Actions can be done on Visual mode selection. Uses
--   |MiniSplitjoin.get_visual_region()|; treats selection as full brackets
--   (use `va)` and not `vi)`).
-- - Order of hook application might be important for correct detection of
--   brackets.

-- Documentation ==============================================================
--- Split and join arguments
---
--- Features:
--- - Provides dot-repeatable mappings and functions for split, join, and toggle.
--- - Works inside comments (not really on the edges of three-piece ones).
--- - Customizable detection.
--- - Customization pre and post hooks for both split and join.
--- - Provides low-level Lua functions for split and join at positions.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.splitjoin').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniSplitjoin`
--- which you can use for scripting or manually (with `:lua MiniSplitjoin.*`).
---
--- See |MiniSplitjoin.config| for available config settings.
---
--- You can override runtime config settings (like target options) locally
--- to buffer inside `vim.b.minisplitjoin_config` which should have same structure
--- as `MiniSplitjoin.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'Wansmer/treesj':
---     - Requires tree-sitter.
--- - 'FooSoft/vim-argwrap':
---     - Main reference for functionality.
--- - 'AndrewRadev/splitjoin.vim':
---     - Implements language-depended transformations.
---
--- # Disabling~
---
--- To disable, set `g:minisplitjoin_disable` (globally) or `b:minisplitjoin_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.splitjoin
---@tag MiniSplitjoin

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
MiniSplitjoin = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniSplitjoin.config|.
---
---@usage `require('mini.splitjoin').setup({})` (replace `{}` with your `config` table)
MiniSplitjoin.setup = function(config)
  -- Export module
  _G.MiniSplitjoin = MiniSplitjoin

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text Options ~
MiniSplitjoin.config = {
  -- Module mappings. Use `''` (empty string) to disable one.
  -- Created for both Normal and Visual modes.
  mappings = {
    toggle = 'gs',
    split = '',
    join = '',
  },

  -- Detection options: where split/join should be done
  detect = {
    brackets = nil,
    separator = nil,
    exclude_regions = nil,
  },

  -- Options for splitting
  split = {
    hook_pre = function(positions) return positions end,
    -- String added to inner lines after copied indent.
    -- Default is tab or 'shiftwidth' spaces (depends on 'expandtab').
    inner_pad = nil,
    hook_post = function(split_positions) end,
  },

  -- Options for joining
  join = {
    hook_pre = function(positions) return positions end,
    -- String added between inner lines
    inner_pad = ' ',
    hook_post = function(join_positions) end,
  },
}
--minidoc_afterlines_end

MiniSplitjoin.toggle = function(pos, opts)
  if H.is_disabled() then return end

  pos = pos or vim.api.nvim_win_get_cursor(0)
  opts = H.get_opts(opts)

  local region = opts.region or H.find_smallest_bracket_region(pos, opts.detect.brackets)
  if region == nil then return end
  opts.region = region

  if region.from.line == region.to.line then
    return MiniSplitjoin.split(pos, opts)
  else
    return MiniSplitjoin.join(pos, opts)
  end
end

MiniSplitjoin.split = function(pos, opts)
  if H.is_disabled() then return end

  pos = pos or vim.api.nvim_win_get_cursor(0)
  opts = H.get_opts(opts)

  local region = opts.region or H.find_smallest_bracket_region(pos, opts.detect.brackets)
  if region == nil then return end

  local positions = H.find_split_positions(region, opts.detect.separator, opts.detect.exclude_regions)

  -- Call pre-hook to possibly modify positions
  positions = opts.split.hook_pre(positions)

  -- Split at positions
  local split_positions = MiniSplitjoin.split_at(positions, { inner_pad = opts.split.inner_pad })

  -- Call post-hook to tweak splits. Add left bracket for easier hook code.
  table.insert(split_positions, 1, { region.from.line, region.from.col - 1 })
  opts.split.hook_post(split_positions)
end

MiniSplitjoin.join = function(pos, opts)
  if H.is_disabled() then return end

  pos = pos or vim.api.nvim_win_get_cursor(0)
  opts = H.get_opts(opts)

  local region = opts.region or H.find_smallest_bracket_region(pos, opts.detect.brackets)
  if region == nil then return end

  local positions = H.find_join_positions(region)

  -- Call pre-hook to possibly modify join lines
  positions = opts.join.hook_pre(positions)

  -- Join consecutive lines to become one
  local join_positions = MiniSplitjoin.join_at(positions, { inner_pad = opts.join.inner_pad })

  -- Call pos-hook to tweak joins. Add left bracket for easier hook code.
  table.insert(join_positions, 1, { region.from.line, region.from.col - 1 })
  opts.join.hook_post(join_positions)
end

MiniSplitjoin.gen_hook = {}

MiniSplitjoin.gen_hook.pad_edges = function(opts)
  opts = opts or {}
  local pad = opts.pad or ' '
  local brackets = opts.brackets or H.get_opts(opts).detect.brackets
  local n_pad = pad:len()

  return function(join_positions)
    -- Act only on actual join
    local n_pos = #join_positions
    if n_pos == 0 or pad == '' then return join_positions end

    -- Act only if brackets are matched. First join position should be exactly
    -- on left bracket, last - just before right bracket.
    local first, last = join_positions[1], join_positions[n_pos]
    local brackets_matched = H.is_positions_inside_brackets(first, last, brackets)
    if not brackets_matched then return join_positions end

    -- Pad only in case of non-trivial join
    if first[1] == last[1] and (last[2] - first[2]) <= 1 then return join_positions end

    -- Add pad after left and before right edges
    H.set_text(first[1] - 1, last[2], first[1] - 1, last[2], { pad })
    H.set_text(first[1] - 1, first[2] + 1, first[1] - 1, first[2] + 1, { pad })

    -- Update `join_positions` to reflect text change
    -- - Account for left pad
    for i = 2, n_pos do
      join_positions[i][2] = join_positions[i][2] + n_pad
    end
    -- - Account for right pad
    join_positions[n_pos][2] = join_positions[n_pos][2] + n_pad

    return join_positions
  end
end

MiniSplitjoin.gen_hook.add_trailing_separator = function(opts)
  opts = opts or {}
  local sep = opts.sep or ','
  local brackets = opts.brackets or H.get_opts(opts).detect.brackets

  return function(split_positions)
    -- Add only in case there is at least one argument
    local n_pos = #split_positions
    if n_pos < 3 then return split_positions end

    -- Act only if brackets are matched
    local first, last = split_positions[1], split_positions[n_pos]
    local brackets_matched = H.is_positions_inside_brackets(first, last, brackets)
    if not brackets_matched then return split_positions end

    -- Act only if there is no trailing separator already
    local target_line = vim.fn.getline(last[1] - 1)
    local target_col = target_line:find(vim.pesc(sep) .. '$')
    if target_col ~= nil then return split_positions end

    -- Add trailing separator
    local col = target_line:len()
    H.set_text(last[1] - 2, col, last[1] - 2, col, { sep })

    -- Don't update `split_positions`, as appending to line has no effect
    return split_positions
  end
end

MiniSplitjoin.gen_hook.remove_trailing_separator = function(opts)
  opts = opts or {}
  local sep = opts.sep or ','
  local brackets = opts.brackets or H.get_opts(opts).detect.brackets
  local n_sep = sep:len()

  return function(join_positions)
    -- Act only on actual join
    local n_pos = #join_positions
    if n_pos == 0 then return join_positions end

    -- Act only if brackets are matched
    local first, last = join_positions[1], join_positions[n_pos]
    local brackets_matched = H.is_positions_inside_brackets(first, last, brackets)
    if not brackets_matched then return join_positions end

    -- Act only if there is matched trailing separator
    local target_line = vim.fn.getline(last[1]):sub(1, last[2])
    local target_col = target_line:find(vim.pesc(sep) .. '%s*$')
    if target_col == nil then return join_positions end

    -- Remove trailing separator
    H.set_text(last[1] - 1, target_col - 1, last[1] - 1, target_col - 1 + n_sep, {})

    -- Update `join_positions` to reflect text change
    join_positions[n_pos] = { last[1], last[2] - n_sep }
    return join_positions
  end
end

---@param positions table Array of positions at which to perform split. Each
---   split increases line count.
---
---@return table Array of new positions to where input `positions` were moved.
MiniSplitjoin.split_at = function(positions, opts)
  opts = vim.tbl_deep_extend('force', { inner_pad = nil }, opts or {})
  local n_pos = #positions
  if n_pos == 0 then return {} end

  -- Cache values that might change
  local cursor_extmark = H.put_extmark_at_positions({ vim.api.nvim_win_get_cursor(0) })[1]
  local input_extmarks = H.put_extmark_at_positions(positions)

  -- Split at positions which are changing following extmarks
  for i = 1, n_pos do
    H.split_at_extmark(input_extmarks[i])
  end

  -- Possibly increase indent of inner lines
  if opts.inner_pad ~= '' then
    local first_new_pos = H.get_extmark_pos(input_extmarks[1])
    local last_new_pos = H.get_extmark_pos(input_extmarks[n_pos])
    H.increase_indent(first_new_pos[1], last_new_pos[1] - 1, opts.inner_pad)
  end

  -- Put cursor back on tracked position
  H.put_cursor_at_extmark(cursor_extmark)

  -- Reconstruct input positions
  local res = vim.tbl_map(H.get_extmark_pos, input_extmarks)
  vim.api.nvim_buf_clear_namespace(0, H.ns_id, 0, -1)
  return res
end

---@param positions table Array of positions at which to perform join. Each
---   join not at first line reduces number of lines.
---
---@return table Array of new positions to where input `positions` were moved.
MiniSplitjoin.join_at = function(positions, opts)
  opts = vim.tbl_deep_extend('force', { inner_pad = ' ' }, opts or {})
  local n_pos = #positions
  if n_pos == 0 then return {} end

  -- Cache values that might change
  local cursor_extmark = H.put_extmark_at_positions({ vim.api.nvim_win_get_cursor(0) })[1]
  local input_extmarks = H.put_extmark_at_positions(positions)

  -- Join at positions which are changing following extmarks
  for i = 1, n_pos do
    local cur_pad_string = (i == 1 or i == n_pos) and '' or opts.inner_pad
    H.join_at_extmark(input_extmarks[i], cur_pad_string)
  end

  -- Put cursor back on tracked position
  H.put_cursor_at_extmark(cursor_extmark)

  -- Reconstruct input positions
  local res = vim.tbl_map(H.get_extmark_pos, input_extmarks)
  vim.api.nvim_buf_clear_namespace(0, H.ns_id, 0, -1)
  return res
end

MiniSplitjoin.get_visual_region = function()
  local from_pos, to_pos = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  local from, to = { line = from_pos[2], col = from_pos[3] }, { line = to_pos[2], col = to_pos[3] }
  -- Tweak for linewise Visual selection
  if vim.fn.visualmode() == 'V' then
    from.col, to.col = 0, vim.fn.col({ to.line, '$' })
  end

  return { from = from, to = to }
end

--- Operator for Normal mode mappings
---
--- Main function to be used in expression mappings. No need to use it
--- directly, everything is setup in |MiniSplitjoin.setup()|.
---
---@param task string Name of task task.
MiniSplitjoin.operator = function(task)
  local is_init_call = task == 'toggle' or task == 'split' or task == 'join'
  if not is_init_call then return MiniSplitjoin[H.cache.operator_task]() end

  if H.is_disabled() then
    -- Using `<Esc>` helps to stop moving cursor caused by current
    -- implementation detail of adding `' '` inside expression mapping
    return [[\<Esc>]]
  end

  H.cache.operator_task = task
  vim.cmd('set operatorfunc=v:lua.MiniSplitjoin.operator')
  return 'g@'
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniSplitjoin.config

H.ns_id = vim.api.nvim_create_namespace('MiniSplitjoin')

H.cache = { operator_task = nil }

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    detect = { config.detect, 'table' },
    split = { config.split, 'table' },
    join = { config.join, 'table' },
  })

  vim.validate({
    ['detect.brackets'] = { config.detect.brackets, 'table', true },
    ['detect.separator'] = { config.detect.separators, 'string', true },
    ['detect.exclude_regions'] = { config.detect.exclude_regions, 'table', true },

    ['split.hook_pre'] = { config.split.hook_pre, 'function' },
    ['split.inner_pad'] = { config.split.inner_pad, 'string', true },
    ['split.hook_post'] = { config.split.hook_post, 'function' },

    ['join.hook_pre'] = { config.join.hook_pre, 'function' },
    ['join.inner_pad'] = { config.join.inner_pad, 'string', true },
    ['join.hook_post'] = { config.join.hook_post, 'function' },
  })

  return config
end

--stylua: ignore
H.apply_config = function(config)
  MiniSplitjoin.config = config

  -- Make mappings
  local maps = config.mappings

  H.map('n', maps.toggle, 'v:lua.MiniSplitjoin.operator("toggle") . " "', { expr = true, desc = 'Toggle arguments' })
  H.map('n', maps.split,  'v:lua.MiniSplitjoin.operator("split") . " "',  { expr = true, desc = 'Split arguments' })
  H.map('n', maps.join,   'v:lua.MiniSplitjoin.operator("join") . " "',   { expr = true, desc = 'Join arguments' })

  H.map('x', maps.toggle, ':<C-u>lua MiniSplitjoin.toggle(nil, { region = MiniSplitjoin.get_visual_region() })<CR>', { desc = 'Toggle arguments' })
  H.map('x', maps.split,  ':<C-u>lua MiniSplitjoin.split(nil,  { region = MiniSplitjoin.get_visual_region() })<CR>', { desc = 'Split arguments' })
  H.map('x', maps.join,   ':<C-u>lua MiniSplitjoin.join(nil,   { region = MiniSplitjoin.get_visual_region() })<CR>', { desc = 'Join arguments' })
end

H.is_disabled = function() return vim.g.minisplitjoin_disable == true or vim.b.minisplitjoin_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniSplitjoin.config, vim.b.minisplitjoin_config or {}, config or {})
end

H.get_opts = function(opts)
  opts = opts or {}

  -- Infer detect options. Can't use usual `vim.tbl_deep_extend()` because it
  -- doesn't work properly on arrays
  local default_detect = {
    brackets = { '%b()', '%b[]', '%b{}' },
    separator = ',',
    exclude_regions = { '%b()', '%b[]', '%b{}', '%b""', "%b''" },
  }
  local config = H.get_config()

  return {
    region = opts.region,
    -- Extend `detect` not deeply to avoid unwanted values from longer defaults
    detect = vim.tbl_extend('force', default_detect, config.detect, opts.detect or {}),
    split = vim.tbl_deep_extend('force', config.split, opts.split or {}),
    join = vim.tbl_deep_extend('force', config.join, opts.join or {}),
  }
end

-- Split ----------------------------------------------------------------------
H.split_at_extmark = function(extmark_id)
  local pos = H.get_extmark_pos(extmark_id)

  -- Split
  H.set_text(pos[1] - 1, pos[2], pos[1] - 1, pos[2], { '', '' })

  -- Remove trailing whitespace on split line
  local split_line = vim.fn.getline(pos[1])
  local start_of_trailspace = split_line:find('%s*$')
  H.set_text(pos[1] - 1, start_of_trailspace - 1, pos[1] - 1, split_line:len(), {})

  -- Adjust indent on new line
  local cur_indent = H.get_indent(vim.fn.getline(pos[1] + 1))
  local new_indent = H.get_indent(split_line)
  H.set_text(pos[1], 0, pos[1], cur_indent:len(), { new_indent })
end

H.find_split_positions = function(region, separator, exclude_regions)
  local sep_positions = H.find_separator_positions(region, separator, exclude_regions)
  local n_pos = #sep_positions

  for i = 1, n_pos - 1 do
    sep_positions[i][2] = sep_positions[i][2] + 1
  end
  return sep_positions
end

-- Join -----------------------------------------------------------------------
H.join_at_extmark = function(extmark_id, pad)
  local line_num = H.get_extmark_pos(extmark_id)[1]
  if line_num <= 1 then return end

  -- Join by replacing trailing whitespace of above line and indent of current
  -- one with `pad`
  local lines = vim.api.nvim_buf_get_lines(0, line_num - 2, line_num, true)
  local above_start_col = lines[1]:len() - lines[1]:match('%s*$'):len()
  local below_end_col = H.get_indent(lines[2]):len()

  H.set_text(line_num - 2, above_start_col, line_num - 1, below_end_col, { pad })
end

H.find_join_positions = function(region, separator, exclude_regions)
  -- Join whole region into single line
  local lines = vim.api.nvim_buf_get_lines(0, region.from.line - 1, region.to.line, true)

  local res = {}
  for i = 2, #lines do
    table.insert(res, { region.from.line + i - 1, H.get_indent(lines[i]):len() })
  end
  return res
end

-- Detect ---------------------------------------------------------------------
H.find_smallest_bracket_region = function(pos, brackets)
  local neigh = H.get_neighborhood()
  local cur_offset = neigh.pos_to_offset({ line = pos[1], col = pos[2] + 1 })

  local best_span = H.find_smallest_covering(neigh['1d'], cur_offset, brackets)
  if best_span == nil then return nil end

  return neigh.span_to_region(best_span)
end

H.find_smallest_covering = function(line, ref_offset, patterns)
  local res, min_width = nil, math.huge
  for _, pattern in ipairs(patterns) do
    local cur_init = 0
    local left, right = string.find(line, pattern, cur_init)
    while left do
      if left <= ref_offset and ref_offset <= right and (right - left) < min_width then
        res, min_width = { from = left, to = right }, right - left
      end

      cur_init = left + 1
      left, right = string.find(line, pattern, cur_init)
    end
  end

  return res
end

H.find_separator_positions = function(region, separator, exclude_regions)
  local neigh = H.get_neighborhood()
  local region_span = neigh.region_to_span(region)
  local region_s = neigh['1d']:sub(region_span.from, region_span.to)

  -- Match separator endings
  local seps = {}
  region_s:gsub(separator .. '()', function(r) table.insert(seps, r - 1) end)

  -- Remove separators that are in excluded regions.
  local inner_string, forbidden = region_s:sub(2, -2), {}
  local add_to_forbidden = function(l, r) table.insert(forbidden, { l + 1, r }) end

  for _, pat in ipairs(exclude_regions) do
    inner_string:gsub('()' .. pat .. '()', add_to_forbidden)
  end

  -- - Also exclude trailing separator
  inner_string:gsub('()' .. separator .. '%s*()$', add_to_forbidden)

  local sub_offsets = vim.tbl_filter(function(x) return not H.is_offset_inside_spans(x, forbidden) end, seps)

  -- Treat enclosing brackets as separators
  if region_s:len() > 2 then
    -- Use only last bracket in case of empty brackets
    table.insert(sub_offsets, 1, 1)
  end
  table.insert(sub_offsets, region_s:len())

  -- Convert offsets to positions
  local start_offset = region_span.from
  return vim.tbl_map(function(sub_off)
    local res = neigh.offset_to_pos(start_offset + sub_off - 1)
    -- Convert to `nvim_win_get_cursor()` format
    return { res.line, res.col - 1 }
  end, sub_offsets)
end

H.is_offset_inside_spans = function(ref_point, spans)
  for _, span in ipairs(spans) do
    if span[1] <= ref_point and ref_point <= span[2] then return true end
  end
  return false
end

H.is_positions_inside_brackets = function(from_pos, to_pos, brackets)
  local text_lines = vim.api.nvim_buf_get_text(0, from_pos[1] - 1, from_pos[2], to_pos[1] - 1, to_pos[2] + 1, {})
  local text = table.concat(text_lines, '\n')

  for _, b in ipairs(brackets) do
    if text:find('^' .. b .. '$') ~= nil then return true end
  end
  return false
end

H.is_char_at_position = function(position, char)
  local present_char = vim.fn.getline(position[1]):sub(position[2] + 1, position[2] + 1)
  return present_char == char
end

-- Simplified version of "neighborhood" from 'mini.ai':
-- - Use whol buffer.
-- - No empty regions or spans.
--
-- NOTEs:
-- - `region = { from = { line = a, col = b }, to = { line = c, col = d } }`.
--   End-inclusive charwise selection. All `a`, `b`, `c`, `d` are 1-based.
-- - `offset` is the number between 1 to `neigh1d:len()`.
H.get_neighborhood = function()
  local neigh2d = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  -- Append 'newline' character to distinguish between lines in 1d case
  -- (crucial for handling empty lines)
  for k, v in pairs(neigh2d) do
    neigh2d[k] = v .. '\n'
  end
  local neigh1d = table.concat(neigh2d, '')
  local n_lines = #neigh2d

  -- Compute offsets for just before line starts
  local line_offsets = {}
  local cur_offset = 0
  for i = 1, n_lines do
    line_offsets[i] = cur_offset
    cur_offset = cur_offset + neigh2d[i]:len()
  end

  -- Convert 2d buffer position to 1d offset
  local pos_to_offset = function(pos) return line_offsets[pos.line] + pos.col end

  -- Convert 1d offset to 2d buffer position
  local offset_to_pos = function(offset)
    for i = 1, n_lines - 1 do
      if line_offsets[i] < offset and offset <= line_offsets[i + 1] then
        return { line = i, col = offset - line_offsets[i] }
      end
    end

    return { line = n_lines, col = offset - line_offsets[n_lines] }
  end

  -- Convert 2d region to 1d span
  local region_to_span =
    function(region) return { from = pos_to_offset(region.from), to = pos_to_offset(region.to) } end

  -- Convert 1d span to 2d region
  local span_to_region = function(span) return { from = offset_to_pos(span.from), to = offset_to_pos(span.to) } end

  return {
    ['1d'] = neigh1d,
    ['2d'] = neigh2d,
    pos_to_offset = pos_to_offset,
    offset_to_pos = offset_to_pos,
    region_to_span = region_to_span,
    span_to_region = span_to_region,
  }
end

-- Extmarks -------------------------------------------------------------------
H.put_extmark_at_positions = function(positions)
  return vim.tbl_map(
    function(pos) return vim.api.nvim_buf_set_extmark(0, H.ns_id, pos[1] - 1, pos[2], {}) end,
    positions
  )
end

H.get_extmark_pos = function(extmark_id)
  local res = vim.api.nvim_buf_get_extmark_by_id(0, H.ns_id, extmark_id, {})
  return { res[1] + 1, res[2] }
end

H.put_cursor_at_extmark = function(id)
  local new_pos = vim.api.nvim_buf_get_extmark_by_id(0, H.ns_id, id, {})
  vim.api.nvim_win_set_cursor(0, { new_pos[1] + 1, new_pos[2] })
  vim.api.nvim_buf_del_extmark(0, H.ns_id, id)
end

-- Indent ---------------------------------------------------------------------
H.increase_indent = function(from_line, to_line, pad)
  if pad == nil then pad = vim.bo.expandtab and string.rep(' ', vim.fn.shiftwidth()) or '\t' end

  local lines = vim.api.nvim_buf_get_lines(0, from_line - 1, to_line, true)

  -- Respect comment leaders only if all lines are commented
  local comment_leaders = H.get_comment_leaders()
  local respect_comments = H.is_comment_block(lines, comment_leaders)

  -- Increase indent of all lines (end-inclusive)
  for i, l in ipairs(lines) do
    local n_indent = H.get_indent(l, respect_comments):len()

    -- Don't increase indent of blank lines (possibly respecting comments)
    local cur_by_string = l:len() == n_indent and '' or pad

    local line_num = from_line + i - 1
    H.set_text(line_num - 1, n_indent, line_num - 1, n_indent, { cur_by_string })
  end
end

H.get_indent = function(line, respect_comments)
  if respect_comments == nil then respect_comments = true end
  if not respect_comments then return line:match('^%s*') end

  -- Make it respect various comment leaders
  local comment_indent = H.get_comment_indent(line, H.get_comment_leaders())
  if comment_indent ~= '' then return comment_indent end

  return line:match('^%s*')
end

H.get_comment_indent = function(line, comment_leaders)
  local res = ''

  for _, leader in ipairs(comment_leaders) do
    local cur_match = line:match('^%s*' .. vim.pesc(leader) .. '%s*')
    -- Use biggest match in case of several matches. Allows respecting "nested"
    -- comment leaders like "---" and "--".
    if type(cur_match) == 'string' and res:len() < cur_match:len() then res = cur_match end
  end

  return res
end

-- Comments -------------------------------------------------------------------
H.get_comment_leaders = function()
  local res = {}

  -- From 'commentstring'
  table.insert(res, vim.split(vim.bo.commentstring, '%%s')[1])

  -- From 'comments'
  for _, comment_part in ipairs(vim.opt_local.comments:get()) do
    table.insert(res, comment_part:match(':(.*)$'))
  end

  -- Ensure there is no whitespace before or after
  return vim.tbl_map(vim.trim, res)
end

H.is_comment_block = function(lines, comment_leaders)
  for _, l in ipairs(lines) do
    if not H.is_commented(l, comment_leaders) then return false end
  end
  return true
end

H.is_commented = function(line, comment_leaders)
  for _, leader in ipairs(comment_leaders) do
    if line:find('^%s*' .. vim.pesc(leader) .. '%s*') ~= nil then return true end
  end
  return false
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.splitjoin) %s', msg), 0) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { remap = false, silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.set_text = function(start_row, start_col, end_row, end_col, replacement)
  local ok = pcall(vim.api.nvim_buf_set_text, 0, start_row, start_col, end_row, end_col, replacement)
  if not ok or #replacement == 0 then return end

  -- Fix cursor position if it was exactly on start position.
  -- See https://github.com/neovim/neovim/issues/22526.
  local cursor = vim.api.nvim_win_get_cursor(0)
  if (start_row + 1) == cursor[1] and start_col == cursor[2] then
    vim.api.nvim_win_set_cursor(0, { cursor[1], cursor[2] + replacement[1]:len() })
  end
end

return MiniSplitjoin
