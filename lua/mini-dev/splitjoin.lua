-- MIT License Copyright (c) 2023 Evgeni Chasnovski

-- TODO:
--
-- Code:
-- - Design:
--     - Ensure correct indentation logic:
--         - Split in such a way that preserve indent of previous line.
--         - Indent all lines after first split and before last split.
--     - If there is more options, move them into `detect` while creating
--       `split` and `join` ones.
--     - Account for the following use cases (???via hooks??? or ???via
--       targeted options???):
--         - Join adds single space padding right near brackets.
--         - Split adds trailing comma.
--         - Join removes trailing comma.
--         - Split puts commas on line starts. Needs custom join string.
-- - Features:
--     - Ensure that it works both inside strings and comments.
--     - Ensure it works on empty brackets.
--
-- Tests:
--
-- Documentation:
--

-- Documentation ==============================================================
--- Split/join elements inside brackets
---
--- Features:
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
  brackets = nil,
  separator = nil,
  exclude_regions = nil,

  -- Do you want this as a way to manage all nuances?
  -- Like "pad braces"
  hooks = {
    split = {
      pre = function() end,
      post = function() end,
    },
    join = {
      pre = function() end,
      post = function() end,
    },
  },
}
--minidoc_afterlines_end

MiniSplitjoin.toggle = function(pos, opts)
  pos = pos or vim.api.nvim_win_get_cursor(0)
  opts = H.get_opts(opts)

  local region = opts.region or H.find_smallest_bracket_region(pos, opts.brackets)
  if region == nil then return end

  if region.from.line == region.to.line then
    -- Split
    local positions = H.find_split_positions(region, opts.separator, opts.exclude_regions)
    MiniSplitjoin.split_at(positions)
  else
    -- Join
    MiniSplitjoin.join_at(region.from.line, region.to.line)
  end
end

MiniSplitjoin.split = function(pos, opts)
  pos = pos or vim.api.nvim_win_get_cursor(0)
  opts = H.get_opts(opts)

  local region = opts.region or H.find_smallest_bracket_region(pos, opts.brackets)
  if region == nil then return end

  local positions = H.find_split_positions(region, opts.separator, opts.exclude_regions)
  MiniSplitjoin.split_at(positions)
end

MiniSplitjoin.join = function(pos, opts)
  pos = pos or vim.api.nvim_win_get_cursor(0)
  opts = H.get_opts(opts)

  local region = opts.region or H.find_smallest_bracket_region(pos, opts.brackets)
  if region == nil then return end

  MiniSplitjoin.join_at(region.from.line, region.to.line)
end

MiniSplitjoin.split_at = function(positions)
  positions = H.sort_positions(positions)
  local n_pos = #positions
  local first_pos, last_pos = positions[1], positions[n_pos]

  -- Cache intermediately used values
  local cursor_extmark = H.put_extmark_at_cursor()

  -- Split at positions. Do it from end to avoid updating positions due to text
  -- changes. Treat last one differently to allow it be exactly last bracket.
  H.split_at_position({ last_pos[1], last_pos[2] - 1 })
  for i = n_pos - 1, 1, -1 do
    H.split_at_position(positions[i])
  end

  -- Increase indent of inner lines
  local tab = vim.bo.expandtab and string.rep(' ', vim.fn.shiftwidth()) or '\t'
  for i = first_pos[1] + 1, last_pos[1] + n_pos - 1 do
    H.increase_indent(i, tab)
  end

  -- Put cursor back on tracked position
  H.put_cursor_at_extmark(cursor_extmark)
end

MiniSplitjoin.join_at = function(from_line, to_line)
  if to_line <= from_line then return end

  -- Join preserving cursor position
  local cursor_extmark = H.put_extmark_at_cursor()

  -- Join bottom up to avoid updating lines
  -- Make first and last joins without space
  if (to_line - from_line) > 1 then H.join_with_below(to_line - 1, '') end
  for i = to_line - 2, from_line + 1, -1 do
    H.join_with_below(i, ' ')
  end
  H.join_with_below(from_line, '')

  H.put_cursor_at_extmark(cursor_extmark)
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
    brackets = { config.brackets, 'table', true },
    separator = { config.separators, 'string', true },
    exclude_regions = { config.exclude_regions, 'table', true },
  })

  return config
end

--stylua: ignore
H.apply_config = function(config)
  MiniSplitjoin.config = config
end

H.is_disabled = function() return vim.g.minisplitjoin_disable == true or vim.b.minisplitjoin_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniSplitjoin.config, vim.b.minisplitjoin_config or {}, config or {})
end

H.get_opts = function(opts)
  opts = opts or {}

  -- Can't use usual `vim.tbl_deep_extend()` because it doesn't work properly on arrays
  local config = H.get_config()
  local brackets = opts.brackets or config.brackets or { '%b()', '%b[]', '%b{}' }
  local separator = opts.separator or config.separator or ','
  local exclude_regions = opts.exclude_regions or config.exclude_regions or { '%b()', '%b[]', '%b{}', '%b""', "%b''" }

  return { region = opts.region, brackets = brackets, separator = separator, exclude_regions = exclude_regions }
end

-- Split ----------------------------------------------------------------------
H.split_at_position = function(pos)
  -- Take into account whitespace before-or-at and after split column
  local line = vim.fn.getline(pos[1])
  local n_whitespace_left = line:sub(1, pos[2] + 1):match('%s*$'):len()
  local n_whitespace_right = line:sub(pos[2] + 2):match('^%s*'):len()

  -- Split line into two at column on position (last column of left part).
  -- Left part stays, right part goes on new line with this lines indent.
  -- Whitespace around position is removed: left part would contribute trailing
  -- whitespace, right part would interfer with indent.
  local line_at = pos[1] - 1
  local from_col = pos[2] + 1 - n_whitespace_left
  local to_col = pos[2] + 1 + n_whitespace_right
  vim.api.nvim_buf_set_text(0, line_at, from_col, line_at, to_col, { '', H.get_indent(line) })
end

-- Join -----------------------------------------------------------------------
H.join_with_below = function(line_num, join_string)
  local lines = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num + 1, true)
  local above_start_col = lines[1]:len() - lines[1]:match('%s*$'):len()
  local below_end_col = H.get_indent(lines[2]):len()

  vim.api.nvim_buf_set_text(0, line_num - 1, above_start_col, line_num, below_end_col, { join_string })
end

-- Regions --------------------------------------------------------------------
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

  -- -- - Also exclude trailing separator or it will lead to extra empty line
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
H.get_indent = function(line)
  -- Make it respect various comment leaders
  local indent_with_comment = ''
  for _, leader in ipairs(H.get_comment_leaders()) do
    local cur_match = line:match('^%s*' .. vim.pesc(leader) .. '%s*')
    -- Use biggest match in case of several matches. Allows respecting "nested"
    -- comment leaders like "---" and "--".
    if type(cur_match) == 'string' and indent_with_comment:len() < cur_match:len() then
      indent_with_comment = cur_match
    end
  end

  if indent_with_comment ~= '' then return indent_with_comment end

  return line:match('^%s*')
end

H.increase_indent = function(line_num, by_string)
  local n_indent = H.get_indent(vim.fn.getline(line_num)):len()
  vim.api.nvim_buf_set_text(0, line_num - 1, n_indent, line_num - 1, n_indent, { by_string })
end

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

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.splitjoin) %s', msg), 0) end

H.sort_positions = function(positions)
  local res = vim.deepcopy(positions)
  table.sort(res, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  return res
end

return MiniSplitjoin
