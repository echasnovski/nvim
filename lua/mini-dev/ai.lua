-- MIT License Copyright (c) 2022 Evgeni Chasnovski

-- Documentation ==============================================================
--- Module for creating custom `a`/`i` textobjects. Basically, like
--- 'wellle/targets.vim' but in Lua and slightly different.
---
--- Features:
--- - Customizable creation of `a`/`i` textobjects using Lua patterns. Should
---   allow `v:count`, search method, dot-repeat.
--- - Extensive defaults.
---
--- Utilizes same basic ideas about searching object as |mini.surround|, but
--- has more advanced features.
---
--- # Setup~
---
--- This module needs a setup with `require('mini.ai').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniAi`
--- which you can use for scripting or manually (with `:lua MiniAi.*`).
---
--- See |MiniAi.config| for available config settings.
---
--- You can override runtime config settings (like `config.textobjects`) locally to
--- buffer inside `vim.b.miniai_config` which should have same structure as
--- `MiniAi.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons~
---
--- - 'wellle/targets.vim':
---     - ...
---
--- # Disabling~
---
--- To disable, set `g:miniai_disable` (globally) or `b:miniai_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag mini.ai
---@tag MiniAi
---@toc_entry Custom a/i textobjects

-- Module definition ==========================================================
MiniAi = {}
H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniAi.config|.
---
---@usage `require('mini.ai').setup({})` (replace `{}` with your `config` table)
MiniAi.setup = function(config)
  -- Export module
  _G.MiniAi = MiniAi

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--stylua: ignore start
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniAi.config = {
  textobjects = {},

  -- How to search for object (first inside current line, then inside
  -- neighborhood). One of 'cover', 'cover_or_next', 'cover_or_prev',
  -- 'cover_or_nearest'. For more details, see `:h MiniSurround.config`.
  search_method = 'cover'
}
--minidoc_afterlines_end
--stylua: ignore end

-- Module functionality =======================================================

-- Helper data ================================================================
-- Module default config
H.default_config = MiniAi.config

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    objects = { config.objects, 'table' },
    search_method = { config.search_method, 'string' },
  })

  return config
end

H.apply_config = function(config)
  MiniAi.config = config

  -- Make mappings
end

H.is_disabled = function() return vim.g.miniai_disable == true or vim.b.miniai_disable == true end

H.get_config =
  function(config) return vim.tbl_deep_extend('force', MiniAi.config, vim.b.miniai_config or {}, config or {}) end

H.is_search_method = function(x, x_name)
  x = x or H.get_config().search_method
  x_name = x_name or '`config.search_method`'

  if vim.tbl_contains({ 'cover', 'cover_or_prev', 'cover_or_next', 'cover_or_nearest' }, x) then return true end
  local msg = ([[%s should be one of 'cover', 'cover_or_prev', 'cover_or_next', 'cover_or_nearest'.]]):format(x_name)
  return false, msg
end

H.validate_search_method = function(x, x_name)
  local is_valid, msg = H.is_search_method(x, x_name)
  if not is_valid then H.error(msg) end
end

-- Work with finding textobjects ----------------------------------------------
H.find_textobject = function(textobject_info)
  -- `textobject_info` should be a table describing iterative search inside neighborhood.
  if textobject_info == nil then return nil end
  local config = H.get_config()
  local n_lines = config.n_lines

  -- First try only current line as it is the most common use case
  local tobj = H.find_textobject_in_neighborhood(textobject_info, 0)
    or H.find_textobject_in_neighborhood(textobject_info, n_lines)

  if tobj == nil then
    local msg = ([[No textobject '%s' found within %d line%s and `config.search_method = '%s'`.]]):format(
      textobject_info.id,
      n_lines,
      n_lines > 1 and 's' or '',
      config.search_method
    )
    H.message(msg)
  end

  return tobj
end

H.find_textobject_in_neighborhood = function(textobject_info, n_neighbors)
  local neigh = H.get_cursor_neighborhood(n_neighbors)
  local cur_offset = neigh.pos_to_offset(neigh.cursor_pos)

  -- Find span of object
  local spans = H.find_best_match(neigh['1d'], textobject_info.find, cur_offset)
  if spans == nil then return nil end

  spans.a = { from = neigh.offset_to_pos(spans.a.from), to = neigh.offset_to_pos(spans.a.to) }
  spans.i = { from = neigh.offset_to_pos(spans.i.from), to = neigh.offset_to_pos(spans.i.to) }
  return spans
end

-- Work with Lua patterns -----------------------------------------------------
-- Challenging examples:
-- '( (a) )', {'%b()', '^. .* .$'}, {left = 4, right = 4}
-- '(( a)  )', -//-, -//-
-- '((a) (b))', {'%b()', '%b()'}, {left = 7, right = 7}
-- Currently doesn't really work
H.find_iterative_match = function(line, pattern_arr, span)
  local cur_line, cur_span = line, span
  local cur_match, cur_offset = { left = 1, right = 0 }, 0
  for _, pattern in ipairs(pattern_arr) do
    local match_offset = cur_match.left - 1
    cur_span = { left = cur_span.left - match_offset, right = cur_span.right - match_offset }
    cur_offset = cur_offset + match_offset

    cur_match = H.find_best_match(cur_line, pattern, cur_span)
    if cur_match == nil then return nil end

    cur_line = cur_line:sub(cur_match.left, cur_match.right)
  end

  return { left = cur_match.left + cur_offset, right = cur_match.right + cur_offset }
end

-- Find the best match (left and right offsets in `line`). Here "best" is:
-- - Covering span (`left <= span.left <= span.right <= right`) with smallest
--   width.
-- - If no covering, one of "previous" or "next", depending on
--   `config.search_method`.
-- Output is a table with two numbers (or `nil` in case of no match):
-- indexes of left and right parts of match. They have the following property:
-- `line:sub(left, right)` matches `'^' .. pattern .. '$'`.
H.find_best_match = function(line, pattern, span)
  H.validate_search_method()

  local left_prev, right_prev, left, right, left_next, right_next
  local stop = false
  local init = 1
  while not stop do
    local match_left, match_right = line:find(pattern, init)
    if match_left == nil then
      -- Stop search, as nothing is found
      stop = true
    elseif match_right < span.right then
      -- Register as previous only if match is not nested
      if match_left < span.left then
        left_prev, right_prev = match_left, match_right
      end

      -- Continue search, because there might be better
      init = match_left + 1
    elseif match_left > span.left then
      -- Register as next only if match is not nested
      if match_right > span.right then
        left_next, right_next = match_left, match_right
      end

      -- Stop search, because already overt the edge
      stop = true
    else
      -- Successful match: match_left <= span[1] <= span[2] <= match_right
      if (left == nil) or (match_right - match_left < right - left) then
        left, right = match_left, match_right
      end

      -- Continue search, because there might be smaller match
      init = match_left + 1
    end
  end

  -- If didn't find covering match, try to infer from previous and next
  if left == nil then
    left, right = H.infer_match(
      { left = left_prev, right = right_prev },
      { left = left_next, right = right_next },
      span
    )
  end

  -- If still didn't find anything, return nothing
  if left == nil then return nil end

  -- Try make covering match even smaller
  -- This approach has some non-working edge cases, but is quite better
  -- performance wise than bruteforce "find from current offset"
  local line_pattern = '^' .. pattern .. '$'
  while
    -- Ensure covering
    left <= span.left
    and span.right <= (right - 1)
    -- Ensure at least 2 symbols
    and left < right - 1
    -- Ensure match
    and line:sub(left, right - 1):find(line_pattern)
  do
    right = right - 1
  end

  return { left = left, right = right }
end

H.infer_match = function(prev, next, span)
  local has_prev = prev.left ~= nil and prev.right ~= nil
  local has_next = next.left ~= nil and next.right ~= nil
  local search_method = H.get_config().search_method

  if not (has_prev or has_next) or search_method == 'cover' then return end
  if search_method == 'cover_or_prev' then return prev.left, prev.right end
  if search_method == 'cover_or_next' then return next.left, next.right end

  if search_method == 'cover_or_nearest' then
    local dist_prev, dist_next = H.span_distance(prev, span), H.span_distance(next, span)

    if dist_next <= dist_prev then
      return next.left, next.right
    else
      return prev.left, prev.right
    end
  end
end

H.span_distance = function(span_1, span_2)
  local ok, res = pcall(function()
    -- Hausdorff distance. Source:
    -- https://math.stackexchange.com/questions/41269/distance-between-two-ranges
    return math.max(math.abs(span_1.left - span_2.left), math.abs(span_1.right - span_2.right))
  end)

  return ok and res or math.huge
end

-- Work with cursor neighborhood ----------------------------------------------
H.get_cursor_neighborhood = function(n_neighbors)
  -- Cursor position
  local cur_pos = vim.api.nvim_win_get_cursor(0)
  -- Convert from 0-based column to 1-based
  cur_pos = { line = cur_pos[1], col = cur_pos[2] + 1 }

  -- '2d neighborhood': position is determined by line and column
  local line_start = math.max(1, cur_pos.line - n_neighbors)
  local line_end = math.min(vim.api.nvim_buf_line_count(0), cur_pos.line + n_neighbors)
  local neigh2d = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
  -- Append 'newline' character to distinguish between lines in 1d case
  for k, v in pairs(neigh2d) do
    neigh2d[k] = v .. '\n'
  end

  -- '1d neighborhood': position is determined by offset from start
  local neigh1d = table.concat(neigh2d, '')

  -- Convert from buffer position to 1d offset
  local pos_to_offset = function(pos)
    local line_num = line_start
    local offset = 0
    while line_num < pos.line do
      offset = offset + neigh2d[line_num - line_start + 1]:len()
      line_num = line_num + 1
    end

    return offset + pos.col
  end

  -- Convert from 1d offset to buffer position
  local offset_to_pos = function(offset)
    local line_num = 1
    local line_offset = 0
    while line_num <= #neigh2d and line_offset + neigh2d[line_num]:len() < offset do
      line_offset = line_offset + neigh2d[line_num]:len()
      line_num = line_num + 1
    end

    return { line = line_start + line_num - 1, col = offset - line_offset }
  end

  return {
    cursor_pos = cur_pos,
    ['1d'] = neigh1d,
    ['2d'] = neigh2d,
    pos_to_offset = pos_to_offset,
    offset_to_pos = offset_to_pos,
  }
end

-- Utilities ------------------------------------------------------------------
H.message = function(msg) vim.cmd('echomsg ' .. vim.inspect('(mini.ai) ' .. msg)) end

H.error = function(msg) error(string.format('(mini.ai) %s', msg)) end

H.map = function(mode, key, rhs, opts)
  if key == '' then return end

  opts = vim.tbl_deep_extend('force', { noremap = true, silent = true }, opts or {})

  -- Use mapping description only in Neovim>=0.7
  if vim.fn.has('nvim-0.7') == 0 then opts.desc = nil end

  vim.api.nvim_set_keymap(mode, key, rhs, opts)
end

---@param arr table List of items. If item is list, consider as set for
---   product. Else - make it single item list.
---@private
H.cartesian_product = function(arr)
  if not (vim.tbl_islist(arr) and #arr > 0) then return {} end
  arr = vim.tbl_map(function(x) return vim.tbl_islist(x) and x or { x } end, arr)

  local res, cur_item = {}, {}
  local process
  process = function(level)
    for i = 1, #arr[level] do
      table.insert(cur_item, arr[level][i])
      if level == #arr then
        table.insert(res, vim.deepcopy(cur_item))
      else
        process(level + 1)
      end
      table.remove(cur_item, #cur_item)
    end
  end

  process(1)
  return res
end

-- Some ideas about how compound pattern for "argument textobject" might look like
-- _G.pattern_arr = { { '%b()', '%b[]', '%b{}' }, <some set of complex regexes to define argument> }

return MiniAi
