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

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniAi.config = {
  custom_textobjects = nil,

  n_lines = 20,

  -- How to search for object (first inside current line, then inside
  -- neighborhood). One of 'cover', 'cover_or_next', 'cover_or_prev',
  -- 'cover_or_nearest'. For more details, see `:h MiniSurround.config`.
  search_method = 'cover',
}
--minidoc_afterlines_end

-- Module functionality =======================================================

-- Helper data ================================================================
-- Module default config
H.default_config = MiniAi.config

-- TODO: add `f` and `t`
H.builtin_textobjects = {
  ['('] = { '%b()', '^.().*().$' },
  [')'] = { '%b()', '^.().*().$' },
  ['['] = { '%b[]', '^.().*().$' },
  [']'] = { '%b[]', '^.().*().$' },
  ['{'] = { '%b{}', '^.().*().$' },
  ['}'] = { '%b{}', '^.().*().$' },
  ['<'] = { '%b<>', '^.().*().$' },
  ['>'] = { '%b<>', '^.().*().$' },
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  -- General idea: if some table elements are not present in user-supplied
  -- `config`, take them from default config
  vim.validate({ config = { config, 'table', true } })
  config = vim.tbl_deep_extend('force', H.default_config, config or {})

  vim.validate({
    custom_textobjects = { config.custom_textobjects, 'table', true },
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
-- _G.textobject_info = { id = '(', composed_pattern = { '%b()', '^.().*().$' }, type = 'i' }

---@param textobject_info table Information about textobject:
---   - <id> - single character id.
---   - <type> - one of `'a'` or `'i'`.
---   - <composed_pattern> - composed pattern with last item{s} having
---     extraction template.
---@private
H.find_textobject = function(textobject_info, n_times, opts)
  -- `textobject_info` should be a table describing iterative search inside neighborhood.
  if textobject_info == nil then return nil end
  local config = H.get_config(opts)
  local n_lines = config.n_lines
  local find_opts = { search_method = config.search_method, n_times = n_times, tobj_type = textobject_info.type }

  -- First try only current line as it is the most common use case
  local tobj_region = H.find_textobject_in_neighborhood(textobject_info, 0, find_opts)
    or H.find_textobject_in_neighborhood(textobject_info, n_lines, find_opts)

  if tobj_region == nil then
    local msg = string.format(
      [[No textobject '%s' found covering cursor%s within %d line%s and `config.search_method = '%s'`.]],
      textobject_info.id,
      n_times > 1 and ('%s times'):format(n_times) or '',
      n_lines,
      n_lines > 1 and 's' or '',
      config.search_method
    )
    H.message(msg)
  end

  return tobj_region
end

H.find_textobject_in_neighborhood = function(textobject_info, n_neighbors, opts)
  local neigh = H.get_cursor_neighborhood(n_neighbors)
  local line = neigh['1d']
  local cur_offset = neigh.pos_to_offset(neigh.cursor_pos)

  -- Find `n_times` evolving matching spans starting from cursor offset span
  local find_res = { span = { left = cur_offset, right = cur_offset } }
  for _ = 1, opts.n_times do
    local find_opts = { span_to_cover = find_res.span, search_method = opts.search_method }
    find_res = H.find_best_match(line, textobject_info.composed_pattern, find_opts)
    if find_res.span == nil then return nil end
  end

  -- Extract appropriate span
  local extract_span = find_res.span
  local extract_pattern = find_res.nested_pattern[#find_res.nested_pattern]
  local offsets = H.extract_offsets(line, extract_span, extract_pattern, opts.tobj_type)

  return { left = neigh.offset_to_pos(offsets.left), right = neigh.offset_to_pos(offsets.right) }
end

-- Work with matching spans ---------------------------------------------------
--- - **Pattern** - string describing Lua pattern.
--- - **Span** - interval inside a string. Like `[1, 5]`.
--- - **Span `[a1, a2]` is nested inside `[b1, b2]`** <=> `b1 <= a1 <= a2 <= b2`.
---   It is also **span `[b1, b2]` covers `[a1, a2]`**.
--- - **Nested pattern** - array of patterns aimed to describe nested spans.
--- - **Span matches nested pattern** if there is a sequence of increasingly
---   nested spans each matching corresponding pattern within substring of
---   previous span (input string for first span). Example:
---     Nested patterns: `{ '%b()', '^. .* .$' }` (padded balanced `()`)
---     Input string: `( ( () ( ) ) )`
---                   `12345678901234`
---   Here are all matching spans `[1, 14]` and `[3, 12]`. Both `[5, 6]` and
---   `[8, 10]` match first pattern but not second. All other combinations of
---   `(` and `)` don't match first pattern (not balanced)
--- - **Composed pattern**: array with each element describing possible pattern
---   at that place. Elements can be arrays or string patterns. Composed pattern
---   basically defines all possible combinations of nested pattern (their
---   cartesian product). Example:
---     Composed pattern: `{{'%b()', '%b[]'}, '^. .* .$'}`
---     Composed pattern expanded into equivalent array of nested patterns:
---       `{ '%b()', '^. .* .$' }` and `{ '%b[]', '^. .* .$' }`
--- - **Span matches composed pattern** if it matches at least one nested
---   pattern from expanded composed pattern.
---
---@param line string
---@param composed_pattern table
---@param opts table Fields: `span_to_cover`, `search_method`
---@private
H.find_best_match = function(line, composed_pattern, opts)
  local best_span, best_nested_pattern, current_nested_pattern
  local f = function(span)
    if H.is_better_span(span, best_span, opts) then
      best_span = span
      best_nested_pattern = current_nested_pattern
    end
  end

  for _, nested_pattern in ipairs(H.cartesian_product(composed_pattern)) do
    current_nested_pattern = nested_pattern
    H.iterate_matched_spans(line, nested_pattern, f)
  end

  return { span = best_span, nested_pattern = best_nested_pattern }
end

H.iterate_matched_spans = function(line, nested_pattern, f)
  local max_level = #nested_pattern
  -- Keep track of visited spans to ensure only one call of `f`.
  -- Example: `((a) (b))`, `{'%b()', '%b()'}`
  local visited = {}

  local process
  process = function(level, level_line, level_offset)
    local pattern = nested_pattern[level]
    local init = 1
    while init <= level_line:len() do
      local left, right = H.string_find(level_line, pattern, init)
      if left == nil then break end

      if level == max_level then
        local found_match = { left = left + level_offset, right = right + level_offset }
        local found_match_id = string.format('%s_%s', found_match.left, found_match.right)
        if not visited[found_match_id] then
          f(found_match)
          visited[found_match_id] = true
        end
      else
        local next_level_line = level_line:sub(left, right)
        local next_level_offset = level_offset + left - 1
        process(level + 1, next_level_line, next_level_offset)
      end

      init = left + 1
    end
  end

  process(1, line, 0)
end

H.is_better_span = function(candidate, current, opts)
  local span_to_cover = opts.span_to_cover
  -- Assumptions:
  -- - `candidate` and `span_to_cover` are never `nil`
  local is_candidate_covering = H.is_span_covering(candidate, span_to_cover)
  local is_current_covering = H.is_span_covering(current, span_to_cover)

  -- Covering span is always better than not covering span
  if is_candidate_covering and not is_current_covering then return true end
  if not is_candidate_covering and is_current_covering then return false end

  if is_candidate_covering then
    -- Covering candidate is better than covering current if it is narrower
    return (candidate.right - candidate.left) < (current.right - current.left)
  else
    local search_method = opts.search_method
    if search_method == 'cover' then return false end
    -- Candidate never should be nested inside `span_to_cover`
    if H.is_span_covering(span_to_cover, candidate) then return false end

    local is_good_candidate = (search_method == 'cover_or_next' and H.is_span_on_left(span_to_cover, candidate))
      or (search_method == 'cover_or_prev' and H.is_span_on_left(candidate, span_to_cover))
      or (search_method == 'cover_or_nearest')

    if not is_good_candidate then return false end
    if current == nil then return true end

    -- Non-covering good candidate is better than non-covering current if it is
    -- closer to `span_to_cover`
    return H.span_distance(candidate, span_to_cover) < H.span_distance(current, span_to_cover)
  end
end

H.is_span_covering = function(span, span_to_cover)
  if span == nil then return false end
  return (span.left <= span_to_cover.left) and (span_to_cover.right <= span.right)
end

H.is_span_on_left = function(span_1, span_2) return (span_1.left <= span_2.left) and (span_1.right <= span_2.right) end

H.span_distance = function(span_1, span_2)
  -- Choosing a distance between two spans is a tricky topic. This boils down
  -- to a choice in certain edge situations. Example: span to cover is [1, 10].
  -- Which should be chosen as closer one: [2, 100], [3, 13]?
  -- Possible choices of distance between [a1, a2] and [b1, b2]:
  -- - Hausdorff distance: max(|a1 - b1|, |a2 - b2|). Here [3, 13] is closer.
  --   Source:
  --   https://math.stackexchange.com/questions/41269/distance-between-two-ranges
  -- - Minimum distance: min(|a1 - b1|, |a2 - b2|). Here [2, 100] is closer.
  --   This better incapsulates the following suggestion: between two spans to
  -- - Usual distance between sets: zero if intersecting,
  -- return math.max(math.abs(span_1.left - span_2.left), math.abs(span_1.right - span_2.right))
  return math.min(math.abs(span_1.left - span_2.left), math.abs(span_1.right - span_2.right))
end

-- Work with Lua patterns -----------------------------------------------------
H.extract_offsets = function(line, extract_span, extract_pattern, tobj_type)
  local s = line:sub(extract_span.left, extract_span.right)
  local positions = { s:match(extract_pattern) }

  local is_all_numbers = true
  for _, pos in ipairs(positions) do
    if type(pos) ~= 'number' then is_all_numbers = false end
  end

  local is_valid_positions = is_all_numbers and (#positions == 2 or #positions == 4)
  if not is_valid_positions then
    local msg = 'Could not extract proper positions (two or four empty captures) from '
      .. string.format([[string '%s' with extraction pattern '%s'.]], s, extract_pattern)
    H.error(msg)
  end

  local left_offset = extract_span.left - 1
  if #positions == 2 then
    --stylua: ignore
    return ({
      a = { left = left_offset + 1,            right = left_offset + s:len() },
      i = { left = left_offset + positions[1], right = left_offset + positions[2] - 1 },
    })[tobj_type]
  end

  return ({
    a = { left = left_offset + positions[1], right = left_offset + positions[4] - 1 },
    i = { left = left_offset + positions[2], right = left_offset + positions[3] - 1 },
  })[tobj_type]
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

-- Work with textobject info --------------------------------------------------
H.make_textobject_table = function()
  -- Extend builtins with data from `config`
  local textobjects = vim.tbl_deep_extend('force', H.builtin_textobjects, H.get_config().custom_textobjects or {})

  -- Use default surrounding info for not supplied single character identifier
  return setmetatable(textobjects, {
    __index = function(_, key)
      local key_esc = vim.pesc(key)
      return { ('%s.-%s'):format(key_esc, key_esc), '^.().*().$' }
    end,
  })
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

H.string_find = function(s, pattern, init)
  -- Match only start of full string if pattern says so.
  -- This is needed because `string.find()` doesn't do this.
  -- Example: `string.find('(aaa)', '^.*$', 4)` returns `4, 5`
  if pattern:sub(1, 1) == '^' and init > 1 then return nil end
  return string.find(s, pattern, init)
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

return MiniAi
