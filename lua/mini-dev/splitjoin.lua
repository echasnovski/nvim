-- MIT License Copyright (c) 2023 Evgeni Chasnovski

-- TODO:
--
-- Code:
-- - Design:
--     - ??? Move `config.hooks` into `config.split` and `config.join` ???
--     - ??? Make mappings ???
--     - Account for the following use cases (???via hooks??? or ???via
--       targeted options???):
--         - Split adds trailing comma.
--         - Join removes trailing comma.
--         - Split puts commas on line starts. Needs custom join string.
-- - Features:
--     - Split inside visual selection. Decide if it should include brackets or
--       not (like if `va}` or `vi}` should be used to achieve similar to
--       default behavior)
--
-- Tests:
-- - General:
--     - Cursor should track its current position.
--     - Ensure that it works both inside strings and comments.
--     - Ensure it works on empty brackets.
--     - Arrays from `detect` are not extended deeply: `detect.brackets
--       = { '%b()' }` should detect only `()` and not `[]` or `{}`.
-- - Split:
--     - Any whitespace around separators or brackets should be removed.
-- - Join:
--     - First and last joins are done without single space padding.
-- - Comment respect:
--     - Split inherits indent **with** comment leader on next line.
--     - Indent increase during split respects omment leaders if whole
--       increased block is commented.
--     - Join removes indent **with** comment leader before join.
--     - Both 'commentstring' and 'comments' are respected.
-- Documentation:
--

-- Documentation ==============================================================
--- Split and join arguments
---
--- Features:
--- - Provides mappable Lua functions for split, join, and toggle.
--- - Provides low-level Lua functions split and join.
--- - Works inside comments (not really on the edges of three-piece ones).
--- - Customizable detection.
--- - Customization pre and post hooks for both split and join.
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
  -- Detection options: where split/join should be done
  detect = {
    brackets = nil,
    separator = nil,
    exclude_regions = nil,
  },

  -- Options for splitting
  split = {
    indent_inner = true,
  },

  -- Options for joining
  join = {},

  -- Move hooks into split and join
  hooks = {
    split_pre = function(positions) return positions end,
    split_post = function(split_positions) _G.hooks_split_post = split_positions end,
    join_pre = function(from_line, to_line) return from_line, to_line end,
    join_post = function(join_positions) _G.hooks_join_post = join_positions end,
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
  positions = opts.hooks.split_pre(positions)

  -- Split at positions
  local split_positions = MiniSplitjoin.split_at(positions, opts.split)

  -- Call post-hook to tweak split result
  opts.hooks.split_post(split_positions)
end

MiniSplitjoin.join = function(pos, opts)
  if H.is_disabled() then return end

  pos = pos or vim.api.nvim_win_get_cursor(0)
  opts = H.get_opts(opts)

  local region = opts.region or H.find_smallest_bracket_region(pos, opts.detect.brackets)
  if region == nil then return end

  -- Call pre-hook to possibly modify join lines
  local from_line, to_line = opts.hooks.join_pre(region.from.line, region.to.line)

  -- Join consecutive lines to become one
  local join_positions = MiniSplitjoin.join_at(from_line, to_line, opts.join)

  -- Call pos-hook to tweak join result
  opts.hooks.join_post(join_positions)
end

MiniSplitjoin.gen_hook = {}

MiniSplitjoin.gen_hook.pad_edges = function(opts)
  opts = opts or {}
  local pad = opts.pad or ' '
  local brackets = opts.brackets or H.get_opts(opts).detect.brackets

  return function(join_positions)
    local first, last = join_positions[1], join_positions[#join_positions]
    local line, first_col, last_col = first[1], first[2] + 1, last[2] + 1

    -- Pad only in case of non-trivial join
    if first_col == last_col then return end

    -- Pad only if brackets are matched
    local linepart = vim.fn.getline(line):sub(first_col, last_col + 1)
    local brackets_matched = false
    for _, b in ipairs(brackets) do
      brackets_matched = brackets_matched or (linepart:find('^' .. b .. '$') ~= nil)
    end
    if not brackets_matched then return end

    H.set_text(line - 1, last_col, line - 1, last_col, { pad })
    H.set_text(line - 1, first_col, line - 1, first_col, { pad })
  end
end

MiniSplitjoin.gen_hook.add_trailing_separator = function(opts)
  return function(split_positions) end
end

MiniSplitjoin.gen_hook.remove_trailing_separator = function(opts)
  return function(join_positions) end
end

-- NOTE: not all `positions` might result into split. Ones resulting into blank
-- lines are not done.
MiniSplitjoin.split_at = function(positions, opts)
  opts = vim.tbl_deep_extend('force', { indent_inner = true }, opts or {})

  -- Normalize positions: sort and shift last one to the left allowing it be
  -- exactly last bracket
  positions = H.sort_positions(positions)
  local n_pos = #positions
  positions[n_pos] = { positions[n_pos][1], positions[n_pos][2] - 1 }

  -- Cache intermediately used values
  local cursor_extmark = H.put_extmark_at_cursor()

  -- Keep track of extmarks for a later reconstruction of actual split postions
  local split_extmarks_ids = {}

  -- Split at positions. Do it from end to avoid updating positions due to text
  -- changes.
  for i = n_pos, 1, -1 do
    local split_id = H.split_at_position(positions[i])
    table.insert(split_extmarks_ids, 1, split_id)
  end

  -- Do nothing if there were no actual splits. Can happen if splitting already
  -- split lines.
  local n_splits = #split_extmarks_ids
  if n_splits == 0 then return {} end

  -- Possibly increase indent of inner lines
  if opts.indent_inner then H.increase_indent(positions[1][1] + 1, positions[n_pos][1] + n_splits - 1) end

  -- Put cursor back on tracked position
  H.put_cursor_at_extmark(cursor_extmark)

  -- Reconstruct positions where splits actually occured
  local split_positions = vim.tbl_map(function(id)
    local pos = vim.api.nvim_buf_get_extmark_by_id(0, H.ns_id, id, {})
    -- Make them compatible with `nvim_win_set_cursor()` argument
    return { pos[1] + 1, pos[2] }
  end, split_extmarks_ids)
  vim.api.nvim_buf_clear_namespace(0, H.ns_id, 0, -1)

  return split_positions
end

MiniSplitjoin.join_at = function(from_line, to_line, opts)
  opts = vim.tbl_deep_extend('force', {}, opts or {})

  -- Join preserving cursor position
  local cursor_extmark = H.put_extmark_at_cursor()

  -- Keep track of actual join positions while joining
  local join_positions = {}

  -- Join
  local n_joins = to_line - from_line
  for i = 1, n_joins do
    table.insert(join_positions, { from_line, vim.fn.getline(from_line):len() - 1 })

    -- Don't pad first and last joins
    local join_string = (i == 1 or i == n_joins) and '' or ' '
    H.join_with_below(from_line, join_string)
  end

  -- Put cursor back on tracked position
  H.put_cursor_at_extmark(cursor_extmark)

  return join_positions
end

MiniSplitjoin.get_visual_region = function()
  local from_pos, to_pos = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  local from, to = { line = from_pos[2], col = from_pos[3] - 1 }, { line = to_pos[2], col = to_pos[3] + 1 }
  -- Tweak for linewise Visual selection
  if vim.fn.visualmode() == 'V' then
    from.col, to.col = 0, vim.fn.col({ to.line, '$' })
  end

  return { from = from, to = to }
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniSplitjoin.config

H.ns_id = vim.api.nvim_create_namespace('MiniSplitjoin')

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
    hooks = { config.hooks, 'table' },
  })

  vim.validate({
    ['detect.brackets'] = { config.detect.brackets, 'table', true },
    ['detect.separator'] = { config.detect.separators, 'string', true },
    ['detect.exclude_regions'] = { config.detect.exclude_regions, 'table', true },

    ['split.indent_inner'] = { config.split.indent_inner, 'boolean' },

    ['hooks.split_pre'] = { config.hooks.split_pre, 'function' },
    ['hooks.split_post'] = { config.hooks.split_post, 'function' },
    ['hooks.join_pre'] = { config.hooks.join_pre, 'function' },
    ['hooks.join_post'] = { config.hooks.join_post, 'function' },
  })

  return config
end

H.apply_config = function(config) MiniSplitjoin.config = config end

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
    hooks = vim.tbl_deep_extend('force', config.hooks, opts.hooks or {}),
  }
end

-- Split ----------------------------------------------------------------------
H.split_at_position = function(pos)
  -- Split line into two at column on position.
  -- Left part stays, right part goes on new line with this lines indent.
  -- Whitespace around position is removed: left part would contribute trailing
  -- whitespace, right part would interfer with indent.

  local line = vim.fn.getline(pos[1])

  -- Take into account whitespace before-or-at and after split column
  local n_whitespace_left = line:sub(1, pos[2] + 1):match('%s*$'):len()
  local n_whitespace_right = line:sub(pos[2] + 2):match('^%s*'):len()

  -- Don't split if it results into blank line. This will allow repeating
  -- `split()` without consequences and ignoring trailing last separator.
  local from_col = pos[2] + 1 - n_whitespace_left
  local to_col = pos[2] + 1 + n_whitespace_right
  if from_col == 0 or to_col == line:len() then return nil end

  -- Split
  local line_at = pos[1] - 1
  H.set_text(line_at, from_col, line_at, to_col, { '', H.get_indent(line) })

  local split_extmark_id = vim.api.nvim_buf_set_extmark(0, H.ns_id, line_at, from_col - 1, {})
  return split_extmark_id
end

H.sort_positions = function(positions)
  local res = vim.deepcopy(positions)
  table.sort(res, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  return res
end

-- Join -----------------------------------------------------------------------
H.join_with_below = function(line_num, join_string)
  -- Join line with the line below: replace trailing whitespace in current line
  -- and indent in next line with `join_string`

  local lines = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num + 1, true)
  local above_start_col = lines[1]:len() - lines[1]:match('%s*$'):len()
  local below_end_col = H.get_indent(lines[2]):len()

  H.set_text(line_num - 1, above_start_col, line_num, below_end_col, { join_string })
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

H.find_split_positions = function(region, separator, exclude_regions)
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

-- Extmarks at cursor ---------------------------------------------------------
H.put_extmark_at_cursor = function()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return vim.api.nvim_buf_set_extmark(0, H.ns_id, cursor[1] - 1, cursor[2], {})
end

H.put_cursor_at_extmark = function(id)
  local new_pos = vim.api.nvim_buf_get_extmark_by_id(0, H.ns_id, id, {})
  vim.api.nvim_win_set_cursor(0, { new_pos[1] + 1, new_pos[2] })
  vim.api.nvim_buf_del_extmark(0, H.ns_id, id)
end

-- Indent ---------------------------------------------------------------------
H.increase_indent = function(from_line, to_line)
  local lines = vim.api.nvim_buf_get_lines(0, from_line - 1, to_line, true)

  -- Respect comment leaders only if all lines are commented
  local comment_leaders = H.get_comment_leaders()
  local respect_comments = H.is_comment_block(lines, comment_leaders)

  -- Increase indent of all lines (end-inclusive)
  local by_string = vim.bo.expandtab and string.rep(' ', vim.fn.shiftwidth()) or '\t'
  for i, l in ipairs(lines) do
    local n_indent = H.get_indent(l, respect_comments):len()

    -- Don't increase indent of blank lines (possibly respecting comments)
    local cur_by_string = l:len() == n_indent and '' or by_string

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

H.set_text = function(...) pcall(vim.api.nvim_buf_set_text, 0, ...) end

return MiniSplitjoin
