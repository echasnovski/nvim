-- MIT License Copyright (c) 2023 Evgeni Chasnovski

-- TODO:
--
-- Code:
-- - Make sure splitting doesn't trigger `InsertEnter` and `InsertLeave`.
-- - Design:
--     - Ensure correct indentation logic:
--         - Split in such a way that preserve indent of previous line.
--         - Indent all lines after first split and before last split.
-- - Features:
--     - Ensure that it works both inside strings and comments.
--     - Ensure it works on empty brackets.
-- - Polish.
--
-- Tests:
--
-- Documentation:
--

-- Documentation ==============================================================
--- Split and join elements in container
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
  -- TODO: replace with `nil`
  brackets = { '%b()', '%b[]', '%b{}' },
  separator = ',',
  exclude_regions = { '%b""', "%b''", '%b()', '%b[]', '%b{}' },

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

  local region = H.find_smallest_bracket_region(pos, opts.brackets)
  if region == nil then return end

  if region.from.line == region.to.line then
    -- Split
    local positions = H.find_split_positions(region, opts.separator, opts.exclude_regions)
    MiniSplitjoin.split_at(positions)
  else
    -- Join
    MiniSplitjoin.join_at(region.from.line, region.to.lie)
  end
end

MiniSplitjoin.split = function(pos, opts)
  pos = pos or vim.api.nvim_win_get_cursor(0)
  opts = H.get_opts(opts)

  local region = H.find_smallest_bracket_region(pos, opts.brackets)
  if region == nil then return end

  local positions = H.find_split_positions(region, opts.separator, opts.exclude_regions)
  MiniSplitjoin.split_at(positions)
end

MiniSplitjoin.join = function(pos, opts)
  pos = pos or vim.api.nvim_win_get_cursor(0)
  opts = H.get_opts(opts)

  local region = H.find_smallest_bracket_region(pos, opts.brackets)
  if region == nil then return end

  MiniSplitjoin.join_at(region.from.line, region.to.line)
end

MiniSplitjoin.split_at = function(positions)
  positions = H.sort_positions(positions)
  local n_pos = #positions

  -- Cache intermediately used values
  local cache = { ci = vim.bo.copyindent, ai = vim.bo.autoindent, si = vim.bo.smartindent, cin = vim.bo.cindent }
  vim.bo.copyindent, vim.bo.autoindent, vim.bo.smartindent, vim.bo.cindent = true, false, false, false

  local cursor_extmark = H.put_extmark_at_cursor()

  -- Split
  local shiftwidth = vim.fn.shiftwidth()
  local tab = vim.bo.expandtab and string.rep(' ', shiftwidth) or '\t'
  for i = n_pos, 1, -1 do
    vim.api.nvim_win_set_cursor(0, positions[i])

    -- Treat last one specially to split only between edge positions
    local insert_enter = i == n_pos and 'i' or 'a'
    local indent_keys = i == n_pos and '' or tab
    vim.cmd('normal! ' .. insert_enter .. '\r' .. indent_keys .. '\27')
  end

  -- Remove trailing whitespace in inner lines
  local from_line, to_line = positions[1][1] + 1, positions[n_pos][1] + n_pos - 1
  vim.cmd('keeppatterns ' .. from_line .. ',' .. to_line .. [[s/\s*$//]])

  -- Put cursor back on tracked position
  H.put_cursor_at_extmark(cursor_extmark)

  -- Clear up
  vim.bo.copyindent, vim.bo.autoindent, vim.bo.smartindent, vim.bo.cindent = cache.ci, cache.ai, cache.si, cache.cin
end

MiniSplitjoin.join_at = function(from_line, to_line)
  if to_line <= from_line then return end

  -- Join preserving cursor position
  local cursor_extmark = H.put_extmark_at_cursor()

  -- - Use `keepmarks` to preserve `[`/`]` marks
  local join_command = string.format('keepmarks %s,%sjoin', from_line, to_line)
  vim.cmd(join_command)

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

  --stylua: ignore
  vim.validate({
    brackets   = { config.brackets,   'table', true },
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

  return { brackets = brackets, separator = separator, exclude_regions = exclude_regions }
end

-- Regions --------------------------------------------------------------------
H.find_smallest_bracket_region = function(pos, brackets)
  pos = pos or vim.api.nvim_win_get_cursor(0)
  brackets = brackets or { '%b()', '%b[]', '%b{}' }

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

  -- Remove separators that are in excluded regions
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

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.splitjoin) %s', msg), 0) end

H.sort_positions = function(positions)
  local res = vim.deepcopy(positions)
  table.sort(res, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  return res
end

return MiniSplitjoin
