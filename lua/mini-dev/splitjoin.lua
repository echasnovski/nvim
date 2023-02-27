-- MIT License Copyright (c) 2023 Evgeni Chasnovski

-- TODO:
--
-- Code:
-- - Decide if it is worth doing Lua pattern-based approach or
--   `searchpairpos()` one. First one is **very** fast, second one is slow on
--   big buffers with many false (not balanced) matches. The second one has
--   more compact implementation and can be used to ignore matches in strings
--   (but *slow*).
-- - Split from end to start. This should not require extmarks for determining
--   where to split.
-- - Design:
--     - Ensure correct indentation logic:
--         - Split in such a way that preserve indent of previous line.
--         - Indent all lines after first split and before last split.
--     - `split(opts)` and `join(opts)` should be forced variant of toggle.
--       One of main use cases for `split()` is to update linewise addition of
--       surrounding to be on separate lines with indented inner ones.
--     - `split_at(positions)` and `join_at(from_line, to_line)` are low-level split and join.
-- - Features:
--     - Ensure that it works both inside strings and comments.
--     - Ensure it works on empty brackets.
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
  brackets = { '()', '[]', '{}' },
  separators = { ',' },

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

MiniSplitjoin.toggle = function(opts)
  -- If ends are on different lines - join the lines.
  -- If ends are on same line:
  -- - Parse "arguments" (line parts separated by delimiter pattern).
  -- - Put each one on new line (accounting for indent and 'commentstring').
  opts = vim.tbl_deep_extend('force', H.get_config(), opts or {})
  opts.brackets = opts.brackets or { '()', '[]', '{}' }
  opts.separators = opts.separators or { ',' }

  -- Find smallest surrounding brackets (`()`, `[]`, `{}`) on cursor position.
  local region = H.find_smallest_bracket_region(opts.brackets)
  if region == nil then return end

  if region.from.line == region.to.line then
    -- Split
  else
    -- Join
    MiniSplitjoin.join(region.from.line, region.to.line)
  end
end

MiniSplitjoin.split = function(line, cols)
  -- Put extmarks at split positions and cursor
  local split_extmarks = {}
  for i, col in ipairs(cols) do
    split_extmarks[i] = vim.api.nvim_buf_set_extmark(0, H.ns_id, line - 1, col - 1, {})
  end

  local cursor_extmark = H.put_extmark_at_cursor()

  -- Perform split consecutively ignoring indent options
  local cache = { ai = vim.bo.autoindent, si = vim.bo.smartindent, cin = vim.bo.cindent }
  vim.bo.autoindent, vim.bo.smartindent, vim.bo.cindent = true, false, false

  local shiftwidth = vim.fn.shiftwidth()
  local tab = vim.bo.expandtab and string.rep(' ', shiftwidth) or '\t'
  local bs = string.rep(H.keys.bs, vim.bo.expandtab and shiftwidth or 1)
  local n = #split_extmarks
  for i = 1, n do
    H.put_cursor_at_extmark(split_extmarks[i])
    local indent_key = i == 1 and (i == n and '' or tab) or (i < n and '' or bs)
    vim.cmd('normal! a\r' .. indent_key .. '\27')
  end

  vim.bo.autoindent, vim.bo.smartindent, vim.bo.cindent = cache.ai, cache.si, cache.cin

  H.put_cursor_at_extmark(cursor_extmark)

  -- Clear namespace
  vim.api.nvim_buf_clear_namespace(0, H.ns_id, 0, -1)
end

MiniSplitjoin.join = function(from_line, to_line)
  -- Join preserving cursor position
  local cursor_extmark = H.put_extmark_at_cursor()

  local join_command = string.format('%s,%sjoin', from_line, to_line)
  vim.cmd(join_command)

  H.put_cursor_at_extmark(cursor_extmark)

  -- Clear namespace
  vim.api.nvim_buf_clear_namespace(0, H.ns_id, 0, -1)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniSplitjoin.config

H.ns_id = vim.api.nvim_create_namespace('MiniSplitjoin')

H.keys = {
  bs = vim.api.nvim_replace_termcodes('<B,S>', true, true, true),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  --stylua: ignore
  vim.validate({
    ['brackets']   = { config.brackets,   'table', true },
    ['separators'] = { config.separators, 'table', true },
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

-- Regions --------------------------------------------------------------------
H.find_separators_in_region = function(region, brackets, separators)
  brackets = H.get_config().brackets
  separators = H.get_config().separators

  local from, to = region.from, region.to

  -- Define which separators to skip and when to stop search
  local res = {}
  local register = function()
    -- Ignore separators in strings
    if H.is_cursor_on_string() then return true end

    -- Stop search (by "not ignoring" item) if gone outside of region
    local cur_pos = vim.api.nvim_win_get_cursor(0)
    local line, col = cur_pos[1], cur_pos[2] + 1
    if to.line < line or (to.line == line and to.col < col) then return false end

    -- Ignore separators inside nested brackets
    if not vim.deep_equal(region, H.find_smallest_bracket_region(brackets)) then return true end

    -- Register this match but "ignore it" to continute search
    table.insert(res, { line = line, col = col })
    return true
  end

  -- Make search of separators inside region
  local init_pos = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_win_set_cursor(0, { from.line, from.col - 1 })

  local pattern = table.concat(separators, [[\|]])
  vim.fn.search(pattern, 'nWz', nil, nil, register)

  vim.api.nvim_win_set_cursor(0, init_pos)

  return res
end

H.find_smallest_bracket_region_prev = function(brackets)
  brackets = brackets or H.get_config().brackets

  -- Find all regions
  local cur_pos = vim.api.nvim_win_get_cursor(0)
  local skip = H.make_skip(cur_pos)

  local regions = {}
  for _, br in ipairs(brackets) do
    local from, to = H.find_surrounding_region(br:sub(1, 1), br:sub(2, 2), skip)
    local is_valid_from, is_valid_to = from.line ~= 0 or from.col ~= 0, to.line ~= 0 or to.col ~= 0
    if is_valid_from and is_valid_to then table.insert(regions, { from = from, to = to }) end
  end
  if #regions == 0 then return nil end

  -- Compute smallest region
  local line_bytes = H.get_line_offset()

  local res, cur_byte_diff = {}, math.huge
  for _, r in ipairs(regions) do
    local byte_from, byte_to = line_bytes[r.from.line] + r.from.col, line_bytes[r.to.line] + r.to.col
    local byte_diff = byte_to - byte_from
    if byte_diff < cur_byte_diff then
      res, cur_byte_diff = r, byte_diff
    end
  end

  return res
end

H.find_surrounding_region = function(left, right, skip)
  local left_pattern, right_pattern = [[\V]] .. left, [[\V]] .. right
  local searchpairpos = function(flags)
    -- local res = vim.fn.searchpairpos(left_pattern, '', right_pattern, 'nWz' .. flags, skip)
    local res = vim.fn.searchpairpos(left_pattern, '', right_pattern, 'nWz' .. flags, H.is_cursor_on_string)
    return { line = res[1], col = res[2] }
  end

  local row, col = vim.fn.line('.'), vim.fn.col('.')
  local char_at_cursor = vim.fn.getline(row):sub(col, col)

  if char_at_cursor == left then return { line = row, col = col }, searchpairpos('') end
  if char_at_cursor == right then return searchpairpos('b'), { line = row, col = col } end
  return searchpairpos('b'), searchpairpos('')
end

H.get_line_offset = function()
  -- Compute number of bytes at line starts
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  local res, cur_byte = {}, 0
  for i, l in ipairs(lines) do
    res[i] = cur_byte
    cur_byte = cur_byte + l:len() + 1
  end
  return res
end

H.make_skip = function(position)
  -- Try tree-sitter
  local skip_regions = H.make_treesitter_skip_regions(position[1], position[2])
  if skip_regions == nil then return [[synIDattr(synID(line("."), col("."), 0), "name") =~? "string\|comment"]] end

  return function()
    local cur_pos = vim.api.nvim_win_get_cursor(0)
    return H.is_pos_in_skip(cur_pos[1], cur_pos[2], skip_regions)
  end
end

H.make_treesitter_skip_regions = function(line, col)
  local lang = vim.bo.filetype
  local ok, parser = pcall(vim.treesitter.get_parser, 0, lang)
  if not ok then return nil end

  local skip_regions = {}
  for i = 1, vim.api.nvim_buf_line_count(0) do
    skip_regions[i] = {}
  end

  local string_regions = H.find_treesitter_regions(parser, 'string')
  if not H.is_pos_in_regions(line, col, string_regions) then H.append_to_skip_regions(skip_regions, string_regions) end

  local comment_regions = H.find_treesitter_regions(parser, 'comment')
  if not H.is_pos_in_regions(line, col, comment_regions) then
    H.append_to_skip_regions(skip_regions, comment_regions)
  end

  return skip_regions
end

H.append_to_skip_regions = function(skip_regions, regions)
  for _, r in ipairs(regions) do
    if r[1] == r[3] then
      local l_num = r[1]
      table.insert(skip_regions[l_num], { r[2], r[4] })
    else
      table.insert(skip_regions[r[1]], { r[2], math.huge })
      for i = r[1] + 1, r[3] - 1 do
        skip_regions[i].all = true
      end
      table.insert(skip_regions[r[3]], { 0, r[4] })
    end
  end
end

H.is_pos_in_skip = function(line, col, skip_regions)
  if skip_regions[line].all then return true end

  for _, span in ipairs(skip_regions[line]) do
    if span[1] <= col and col < span[2] then return true end
  end
  return false
end

H.is_pos_in_regions = function(line, col, regions)
  for _, r in ipairs(regions) do
    if r[1] <= line and line <= r[3] and r[2] <= col and col < r[4] then return true end
  end
  return false
end

H.find_treesitter_regions = function(parser, node_name)
  local query = vim.treesitter.query.parse_query(parser:lang(), '(' .. node_name .. ') @_capture')

  local ranges = {}
  for _, tree in ipairs(parser:trees()) do
    for _, node, _ in query:iter_captures(tree:root(), 0) do
      local row1, col1, row2, col2 = node:range()
      -- Make region lines 1-based end-inclusive, columns 0-based end-exclusive
      table.insert(ranges, { row1 + 1, col1, row2 + 1, col2 })
    end
  end

  return ranges
end

H.find_smallest_bracket_region = function(brackets)
  brackets = brackets or { '()', '[]', '{}' }

  local patterns = vim.tbl_map(function(x) return '%b' .. x end, brackets)
  local neigh = H.get_neighborhood()
  local cur_offset = neigh.pos_to_offset(H.get_cursor_pos())

  local best_span = H.find_smallest_covering(neigh['1d'], cur_offset + 1, patterns)
  if best_span == nil then return nil end
  return neigh.span_to_region(best_span)
end

H.find_smallest_covering = function(line, ref_pos, patterns)
  local res, min_width = nil, math.huge
  for _, pattern in ipairs(patterns) do
    local cur_init = 0
    local left, right = string.find(line, pattern, cur_init)
    while left do
      if left <= ref_pos and ref_pos <= right and (right - left) < min_width then
        res, min_width = { from = left, to = right }, right - left
      end

      cur_init = left + 1
      left, right = string.find(line, pattern, cur_init)
    end
  end

  return res
end

-- Simplified version of "neighborhood" from 'mini.ai':
-- - Use whol buffer.
-- - No empty regions or spans.
H.get_neighborhood = function()
  local neigh2d = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  -- Append 'newline' character to distinguish between lines in 1d case
  -- (crucial for handling empty lines)
  for k, v in pairs(neigh2d) do
    neigh2d[k] = v .. '\n'
  end
  local neigh1d = table.concat(neigh2d, '')
  local line_offsets = H.get_line_offset()
  local n_lines = #neigh2d

  -- Convert 2d buffer position to 1d offset
  local pos_to_offset = function(pos) return line_offsets[pos.line] + pos.col end

  -- Convert 1d offset to 2d buffer position
  local offset_to_pos = function(offset)
    for i = 1, n_lines - 1 do
      if line_offsets[i] <= offset and offset < line_offsets[i + 1] then
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
end

H.is_cursor_on_string = function()
  -- If tree-sitter is active, use it. Otherwise use built-in syntax.
  local ok, captures = pcall(vim.treesitter.get_captures_at_cursor, 0)
  if ok then
    -- NOTE: this **really** slows down `searchpairpos` in big file with many
    -- intermediate matches
    return vim.tbl_contains(captures, 'string')
  else
    local attr_name = vim.fn.synIDattr(vim.fn.synID(vim.fn.line('.'), vim.fn.col('.'), 0), 'name')
    return attr_name:lower():find('string') ~= nil
  end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error(string.format('(mini.splitjoin) %s', msg), 0) end

H.get_cursor_pos = function()
  local pos = vim.api.nvim_win_get_cursor(0)
  return { line = pos[1], col = pos[2] }
end

return MiniSplitjoin
