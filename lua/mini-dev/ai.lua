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
--- What it doesn't (and probably won't) do:
--- - Have special operators to specially handle whitespace (like `I` and `A`
---   in 'targets.vim'). Whitespace handling is assumed to be done inside
---   textobject specification (like `i(` and `i)` handle whitespace differently).
--- - Have "last" and "next" textobject modifiers (like `il` and `in` in
---   'targets.vim'). Either set and use appropriate `config.search_method` or
---   move to the next place and then use textobject. For a quicker movements,
---   see |mini.jump| and |mini.jump2d|.
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
---@text # Options ~
---
--- ## Custom textobjects
---
--- Example imitating word: `{ w = { '()()%f[%w]%w+()[ \t]*()' } }`
MiniAi.config = {
  -- Table with textobject id as fields, textobject spec (or function returning
  -- textobject spec) as values
  custom_textobjects = nil,

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Main textobject prefixes
    around = 'a',
    inside = 'i',

    -- Move cursor to certain part of textobject
    goto_left = 'g[',
    goto_right = 'g]',
  },

  n_lines = 20,

  -- How to search for object (first inside current line, then inside
  -- neighborhood). One of 'cover', 'cover_or_next', 'cover_or_prev',
  -- 'cover_or_nearest'. For more details, see `:h MiniSurround.config`.
  search_method = 'cover',
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Find textobject region
---
---@param id string Single character string representing textobject id.
---@param ai_type string One of `'a'` or `'i'`.
---@param opts table|nil Options. Possible fields:
---   - <n_lines> - Number of lines within which textobject is searched.
---     Default: `config.n_lines` (see |MiniAi.config|).
---   - <n_times> - Number of times to perform a consecutive search. Each one
---     is done with reference region being previous found textobject region.
---     Default: 1.
---   - <reference_region> - Table describing region to try to cover.
---     Fields: <left> and <right> for start and end positions. Each position
---     is also a table with line <line> and columns <col> (both start at 1).
---     Default: single cell region describing cursor position.
---   - <search_method> - Search method. Default: `config.search_method`.
---
---@return table|nil Table describing region of textobject or `nil` if no
---   textobject was consecutively found `opts.n_times` times.
MiniAi.find_textobject = function(id, ai_type, opts)
  local tobj_spec = H.get_textobject_spec(id)
  if tobj_spec == nil then return end

  if not (ai_type == 'a' or ai_type == 'i') then H.error([[`ai_type` should be one of 'a' or 'i'.]]) end
  opts = vim.tbl_deep_extend('force', H.get_default_opts(), opts or {})

  local tobj_region = H.find_textobject_region(tobj_spec, ai_type, opts)

  if tobj_region == nil then
    local msg = string.format(
      [[No textobject %s found covering region%s within %d line%s and `config.search_method = '%s'`.]],
      vim.inspect(ai_type .. id),
      opts.n_times > 1 and (' %s times'):format(opts.n_times) or '',
      opts.n_lines,
      opts.n_lines > 1 and 's' or '',
      opts.search_method
    )
    H.message(msg)
  end

  return tobj_region
end

--- Visually select textobject region
---
--- Does nothing if no region is found.
---
---@param id string Single character string representing textobject id.
---@param ai_type string One of `'a'` or `'i'`.
---@param opts table|nil Same as in |MiniAi.find_textobject()|. Extra fields:
---   - <vis_mode> - One of `'v'`, `'V'`, `'<C-v>'`. Default: Latest visual mode.
MiniAi.select_textobject = function(id, ai_type, opts)
  opts = opts or {}
  local tobj_region = MiniAi.find_textobject(id, ai_type, opts)
  if tobj_region == nil then return end
  local set_cursor = function(position) vim.api.nvim_win_set_cursor(0, { position.line, position.col - 1 }) end

  H.exit_visual_mode()
  local vis_mode = opts.vis_mode and vim.api.nvim_replace_termcodes(opts.vis_mode, true, true, true)
    or vim.fn.visualmode()

  -- TODO: Decide if this should be kept or opting for using `Vi(` instead of
  -- `Vi)` is enough.
  -- -- Possibly correct region for linewise mode: don't include first and last
  -- -- line if textobject contains only whitespace on them. This is default
  -- -- Neovim behavior for `i)`, for example.
  -- if vis_mode == 'V' and ai_type == 'i' then
  --   local left_line, right_line = tobj_region.left.line, tobj_region.right.line
  --   local left_whitespace = vim.fn.getline(left_line):sub(tobj_region.left.col):match('^%s*$') ~= nil
  --   local right_whitespace = vim.fn.getline(right_line):sub(1, tobj_region.right.col):match('^%s*$') ~= nil
  --   local has_inner_lines = (right_line - left_line) > 1
  --   if left_whitespace and right_whitespace and has_inner_lines then
  --     -- Set ``
  --     tobj_region.left = { line = left_line + 1, col = 1 }
  --     tobj_region.right = { line = right_line - 1, col = 1 }
  --   end
  -- end

  -- Allow going past end of line in order to collapse multiline regions
  local cache_virtualedit = vim.o.virtualedit
  vim.o.virtualedit = 'onemore'

  pcall(function()
    -- Open enough folds to show left and right edges
    set_cursor(tobj_region.left)
    vim.cmd('normal! zv')
    set_cursor(tobj_region.right)
    vim.cmd('normal! zv')

    -- Visually select only valid regions
    vim.cmd('normal! ' .. vis_mode)
    set_cursor(tobj_region.left)
  end)

  -- Restore options
  vim.o.virtualedit = cache_virtualedit
end

--- Make expression to visually select textobject
---
--- Designed to be used inside expression mapping. No need to use directly.
---
--- Textobject identifier is taken from user single character input.
--- Default `n_times` option is taken from |v:count1|.
---
---@param mode string One of 'x' (Visual) or 'o' (Operator-pending).
---@param ai_type string One of `'a'` or `'i'`.
MiniAi.expr_textobject = function(mode, ai_type)
  local tobj_id = H.user_textobject_id(ai_type)

  if tobj_id == nil then return '' end

  -- Fall back to builtin `a`/`i` textobjects in case of invalid id
  if H.get_textobject_spec(tobj_id) == nil then return ai_type .. tobj_id end

  -- Use Visual selection as reference region for Visual mode mappings
  local reference_region_field = ''
  if mode == 'x' then
    reference_region_field = ', reference_region = '
      .. vim.inspect(H.get_visual_region(), { newline = '', indent = '' })
  end

  local res = string.format(
    [[<Cmd>lua MiniAi.select_textobject('%s', '%s', {n_times = %d%s})<CR>]],
    vim.fn.escape(tobj_id, [[']]),
    vim.fn.escape(ai_type, [[']]),
    vim.v.count1,
    reference_region_field
  )
  return vim.api.nvim_replace_termcodes(res, true, true, true)
end

-- --- Move cursor to edge of textobject
-- ---
-- ---@param side string One of `'left'` or `'right'`.
-- ---@param id string Single character string representing textobject id.
-- ---@param ai_type string One of `'a'` or `'i'`.
-- ---@param opts table|nil Same as in |MiniAi.find_textobject()|.
-- MiniAi.move_cursor = function(side, id, ai_type, opts)
--   if not (side == 'left' or side == 'right') then H.error([[`side` should be one of 'left' or 'right'.]]) end
--   local tobj_region = MiniAi.find_textobject(id, ai_type, opts)
--   if tobj_region == nil then return end
--
--   local dest = tobj_region[side]
--   vim.api.nvim_win_set_cursor(0, { dest.line, dest.col - 1 })
-- end
--
-- MiniAi.operator = function(side, add_to_jumplist)
--   -- Get user input
--   local tobj_id = H.user_textobject_id('a')
--   if tobj_id == nil then return end
--
--   -- Add movement to jump list
--   if add_to_jumplist then vim.cmd('normal! m`') end
--
--   -- Move cursor
--   MiniAi.move_cursor(side, tobj_id, 'a', { n_times = vim.v.count1 })
-- end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniAi.config

H.builtin_textobjects = {
  -- Use balanced pair for brackets
  ['('] = { '%b()', '^.%s*().-()%s*.$' },
  [')'] = { '%b()', '^.().-().$' },
  ['['] = { '%b[]', '^.%s*().-()%s*.$' },
  [']'] = { '%b[]', '^.().-().$' },
  ['{'] = { '%b{}', '^.%s*().-()%s*.$' },
  ['}'] = { '%b{}', '^.().-().$' },
  ['<'] = { '%b<>', '^.%s*().-()%s*.$' },
  ['>'] = { '%b<>', '^.().-().$' },
  -- Argument. Probably better to use treesitter-based textobject.
  ['a'] = {
    { '%b()', '%b[]', '%b{}' },
    -- Around argument is between comma(s) and edge(s). One comma is included.
    -- Inner argument - around argument minus comma and "outer" whitespace
    { ',()%s*().-()%s*,()', '^.()%s*().-()%s*().$', '^.()%s*().-()%s*,()', '(),%s*().-()%s*().$' },
  },
  -- Brackets
  ['b'] = { { '%b()', '%b[]', '%b{}' }, '^.().*().$' },
  -- Function call. Probably better to use treesitter-based textobject.
  ['f'] = { '%f[%w_%.][%w_%.]+%b()', '^.-%(().*()%)$' },
  -- Tag
  ['t'] = { '<(%w-)%f[^<%w][^<>]->.-</%1>', '^<.->().*()</[^/]->$' },
  -- Quotes
  ['q'] = { { "'.-'", '".-"', '`.-`' }, '^.().*().$' },
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
  local maps = config.mappings

  H.map('n', maps.goto_left, [[<Cmd>lua MiniAi.operator('left')<CR>]], { desc = 'Move to left "around"' })
  H.map('n', maps.goto_right, [[<Cmd>lua MiniAi.operator('right')<CR>]], { desc = 'Move to right "around"' })

  H.map('x', maps.around, [[v:lua.MiniAi.expr_textobject('x', 'a')]], { expr = true, desc = 'Around textobject' })
  H.map('x', maps.inside, [[v:lua.MiniAi.expr_textobject('x', 'i')]], { expr = true, desc = 'Inside textobject' })
  H.map('o', maps.around, [[v:lua.MiniAi.expr_textobject('o', 'a')]], { expr = true, desc = 'Around textobject' })
  H.map('o', maps.inside, [[v:lua.MiniAi.expr_textobject('o', 'i')]], { expr = true, desc = 'Inside textobject' })
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

H.validate_tobj_pattern = function(x)
  local msg = string.format('%s is not a textobject pattern.', vim.inspect(x))
  if type(x) ~= 'table' then H.error(msg) end
  for _, val in ipairs(vim.tbl_flatten(x)) do
    if type(val) ~= 'string' then H.error(msg) end
  end
end

H.validate_search_method = function(x, x_name)
  local is_valid, msg = H.is_search_method(x, x_name)
  if not is_valid then H.error(msg) end
end

-- Work with textobject info --------------------------------------------------
H.make_textobject_table = function()
  -- Extend builtins with data from `config`. Don't use `tbl_deep_extend()`
  -- because only top level keys should be merged.
  local textobjects = vim.tbl_extend('force', H.builtin_textobjects, H.get_config().custom_textobjects or {})

  -- Use default textobject pattern only for some characters: punctuation,
  -- whitespace, digits.
  return setmetatable(textobjects, {
    __index = function(_, key)
      if not (type(key) == 'string' and string.find(key, '^[%p%s%d]$')) then return end
      -- Include both sides in `a` textobject because:
      -- - This feels more coherent and leads to less code.
      -- - There are issues with evolving in Visual mode because reference
      --   region will be smaller than pattern match. This lead to acceptance
      --   of pattern and the same region will be highlighted again.
      local key_esc = vim.pesc(key)
      return { string.format('%s.-%s', key_esc, key_esc), '^.().*().$' }
    end,
  })
end

H.get_textobject_spec = function(id)
  local textobject_tbl = H.make_textobject_table()
  local spec = textobject_tbl[id]
  -- Allow function returning spec
  if type(spec) == 'function' then spec = spec() end

  -- This is needed to allow easy disabling of textobject identifiers
  if not (type(spec) == 'table' and #spec > 0) then return nil end
  return spec
end

-- Work with finding textobjects ----------------------------------------------
---@param tobj_spec table Composed pattern. Last item(s) - extraction template.
---@param ai_type string One of `'a'` or `'i'`.
---@param opts table Textobject options with all fields present.
---@private
H.find_textobject_region = function(tobj_spec, ai_type, opts)
  local reference_region, n_times, n_lines = opts.reference_region, opts.n_times, opts.n_lines

  -- Find `n_times` matching spans evolving from reference region span
  -- First try to find inside 0-neighborhood
  local neigh = H.get_neighborhood(reference_region, 0)
  local find_res = { span = neigh.region_to_span(reference_region) }

  local cur_n_times = 0
  while cur_n_times < n_times do
    local new_find_res = H.find_best_match(neigh['1d'], tobj_spec, find_res.span, opts)

    -- If didn't find in 0-neighborhood, try extended one.
    -- Stop if didn't find in extended neighborhood.
    if new_find_res.span == nil then
      if neigh.n_neighbors > 0 then return end

      local found_region = neigh.span_to_region(find_res.span)
      neigh = H.get_neighborhood(reference_region, n_lines)
      find_res = { span = neigh.region_to_span(found_region) }
    else
      find_res = new_find_res
      cur_n_times = cur_n_times + 1
    end
  end

  -- Extract local (with respect to best matched span) span
  local s = neigh['1d']:sub(find_res.span.left, find_res.span.right)
  local extract_pattern = find_res.nested_pattern[#find_res.nested_pattern]
  local local_span = H.extract_span(s, extract_pattern, ai_type)

  -- Convert local span to region
  local offset = find_res.span.left - 1
  local found_span = { left = local_span.left + offset, right = local_span.right + offset }
  return neigh.span_to_region(found_span)
end

H.get_default_opts = function()
  local config = H.get_config()
  local cur_pos = vim.api.nvim_win_get_cursor(0)
  cur_pos = { line = cur_pos[1], col = cur_pos[2] + 1 }
  return {
    n_lines = config.n_lines,
    n_times = 1,
    reference_region = { left = cur_pos, right = cur_pos },
    search_method = config.search_method,
  }
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
---@param reference_span table Span to cover.
---@param opts table Fields: <search_method>.
---@private
H.find_best_match = function(line, composed_pattern, reference_span, opts)
  local best_span, best_nested_pattern, current_nested_pattern
  local f = function(span)
    if H.is_better_span(span, best_span, reference_span, opts) then
      best_span = span
      best_nested_pattern = current_nested_pattern
    end
  end

  for _, nested_pattern in ipairs(H.cartesian_product(composed_pattern)) do
    current_nested_pattern = nested_pattern
    H.iterate_matched_spans(line, nested_pattern, reference_span, f)
  end

  return { span = best_span, nested_pattern = best_nested_pattern }
end

H.iterate_matched_spans = function(line, nested_pattern, reference_span, f)
  local max_level = #nested_pattern
  -- Keep track of visited spans to ensure only one call of `f`.
  -- Example: `((a) (b))`, `{'%b()', '%b()'}`
  local visited = {}

  local process
  process = function(level, level_line, level_offset)
    local pattern = nested_pattern[level]
    local init = 1
    while init <= level_line:len() do
      local local_reference_span =
        { left = reference_span.left - level_offset, right = reference_span.right - level_offset }
      local left, right = H.string_find(level_line, pattern, init, local_reference_span)
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

---@param candidate table Candidate span to test agains `current`.
---@param current table|nil Current best span.
---@param reference table Reference span to cover.
---@param opts table Fields: <search_method>.
---@private
H.is_better_span = function(candidate, current, reference, opts)
  -- Candidate never equals reference to allow incrementing textobjects
  if H.is_span_equal(candidate, reference) then return false end

  -- Covering span is always better than not covering span
  local is_candidate_covering = H.is_span_covering(candidate, reference)
  local is_current_covering = H.is_span_covering(current, reference)

  if is_candidate_covering and not is_current_covering then return true end
  if not is_candidate_covering and is_current_covering then return false end

  if is_candidate_covering then
    -- Covering candidate is better than covering current if it is narrower
    return (candidate.right - candidate.left) < (current.right - current.left)
  else
    local search_method = opts.search_method
    if search_method == 'cover' then return false end
    -- Candidate never should be nested inside `span_to_cover`
    if H.is_span_covering(reference, candidate) then return false end

    local is_good_candidate = (search_method == 'cover_or_next' and H.is_span_on_left(reference, candidate))
      or (search_method == 'cover_or_prev' and H.is_span_on_left(candidate, reference))
      or (search_method == 'cover_or_nearest')

    if not is_good_candidate then return false end
    if current == nil then return true end

    -- Non-covering good candidate is better than non-covering current if it is
    -- closer to `span_to_cover`
    return H.span_distance(candidate, reference, search_method) < H.span_distance(current, reference, search_method)
  end
end

H.is_span_covering = function(span, span_to_cover)
  if span == nil or span_to_cover == nil then return false end
  return (span.left <= span_to_cover.left) and (span_to_cover.right <= span.right)
end

H.is_span_equal = function(span_1, span_2)
  if span_1 == nil or span_2 == nil then return false end
  return (span_1.left == span_2.left) and (span_1.right == span_2.right)
end

H.is_span_on_left = function(span_1, span_2)
  if span_1 == nil or span_2 == nil then return false end
  return (span_1.left <= span_2.left) and (span_1.right <= span_2.right)
end

H.is_span_contains = function(span, point) return span.left <= point and point <= span.right end

H.span_distance = function(span_1, span_2, search_method)
  -- Other possible choices of distance between [a1, a2] and [b1, b2]:
  -- - Hausdorff distance: max(|a1 - b1|, |a2 - b2|).
  --   Source:
  --   https://math.stackexchange.com/questions/41269/distance-between-two-ranges
  -- - Minimum distance: min(|a1 - b1|, |a2 - b2|).

  -- Distance is chosen so that "next span" in certain direction is the closest
  if search_method == 'cover_or_next' then return math.abs(span_1.left - span_2.left) end
  if search_method == 'cover_or_prev' then return math.abs(span_1.right - span_2.right) end
  if search_method == 'cover_or_nearest' then
    return math.min(math.abs(span_1.left - span_2.left), math.abs(span_1.right - span_2.right))
  end
end

-- Work with Lua patterns -----------------------------------------------------
H.extract_span = function(s, extract_pattern, tobj_type)
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

  local ai_spans
  if #positions == 2 then
    ai_spans = {
      a = { left = 1, right = s:len() },
      i = { left = positions[1], right = positions[2] - 1 },
    }
  else
    ai_spans = {
      a = { left = positions[1], right = positions[4] - 1 },
      i = { left = positions[2], right = positions[3] - 1 },
    }
  end

  return ai_spans[tobj_type]
end

-- Work with cursor neighborhood ----------------------------------------------
---@param reference_region table Reference region.
---@param n_neighbors number Maximum number of neighbors to include before
---   start line and after end line.
---@private
H.get_neighborhood = function(reference_region, n_neighbors)
  if reference_region == nil then
    -- Use region covering cursor position by default
    local cur_pos = vim.api.nvim_win_get_cursor(0)
    cur_pos = { line = cur_pos[1], col = cur_pos[2] + 1 }
    reference_region = { left = cur_pos, right = cur_pos }
  end
  n_neighbors = n_neighbors or 0

  -- '2d neighborhood': position is determined by line and column
  local line_start = math.max(1, reference_region.left.line - n_neighbors)
  local line_end = math.min(vim.api.nvim_buf_line_count(0), reference_region.right.line + n_neighbors)
  local neigh2d = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
  -- Append 'newline' character to distinguish between lines in 1d case
  for k, v in pairs(neigh2d) do
    neigh2d[k] = v .. '\n'
  end

  -- '1d neighborhood': position is determined by offset from start
  local neigh1d = table.concat(neigh2d, '')

  -- Convert 2d buffer position to 1d offset
  local pos_to_offset = function(pos)
    local line_num = line_start
    local offset = 0
    while line_num < pos.line do
      offset = offset + neigh2d[line_num - line_start + 1]:len()
      line_num = line_num + 1
    end

    return offset + pos.col
  end

  -- Convert 1d offset to 2d buffer position
  local offset_to_pos = function(offset)
    local line_num = 1
    local line_offset = 0
    while line_num <= #neigh2d and line_offset + neigh2d[line_num]:len() < offset do
      line_offset = line_offset + neigh2d[line_num]:len()
      line_num = line_num + 1
    end

    return { line = line_start + line_num - 1, col = offset - line_offset }
  end

  -- Convert 2d region to 1d span
  local region_to_span =
    function(region) return { left = pos_to_offset(region.left), right = pos_to_offset(region.right) } end

  -- Convert 1d span to 2d region
  local span_to_region = function(span)
    -- NOTE: this might lead to outside of line positions due to added `\n` at
    -- the end of lines in 1d-neighborhood. However, this is crucial for
    -- allowing `i` textobjects to collapse multiline selections.
    return { left = offset_to_pos(span.left), right = offset_to_pos(span.right) }
  end

  return {
    n_neighbors = n_neighbors,
    region = reference_region,
    ['1d'] = neigh1d,
    ['2d'] = neigh2d,
    pos_to_offset = pos_to_offset,
    offset_to_pos = offset_to_pos,
    region_to_span = region_to_span,
    span_to_region = span_to_region,
  }
end

-- Work with user input -------------------------------------------------------
H.user_textobject_id = function(ai_type)
  -- Get from user single character textobject identifier
  local needs_help_msg = true
  vim.defer_fn(function()
    if not needs_help_msg then return end

    local msg = string.format('Enter %s textobject identifier (single character) ', ai_type)
    H.message(msg)
  end, 1000)
  local ok, char = pcall(vim.fn.getchar)
  needs_help_msg = false

  -- Terminate if couldn't get input (like with <C-c>) or it is `<Esc>`
  if not ok or char == 27 then return nil end

  if type(char) == 'number' then char = vim.fn.nr2char(char) end
  if char:find('^[%w%p%s]$') == nil then
    H.message('Input must be single character: alphanumeric, punctuation, or space.')
    return nil
  end

  return char
end

-- Work with Visual mode ------------------------------------------------------
H.is_visual_mode = function()
  local ctrl_v = vim.api.nvim_replace_termcodes('<C-v>', true, true, true)
  local cur_mode = vim.fn.mode()
  return cur_mode == 'v' or cur_mode == 'V' or cur_mode == ctrl_v, cur_mode
end

H.exit_visual_mode = function()
  local is_vis, mode = H.is_visual_mode()
  if is_vis then vim.cmd('normal! ' .. mode) end
end

H.get_visual_region = function()
  local is_vis, _ = H.is_visual_mode()
  if not is_vis then return end
  local res = {
    left = { line = vim.fn.line('v'), col = vim.fn.col('v') },
    right = { line = vim.fn.line('.'), col = vim.fn.col('.') },
  }
  if res.left.line > res.right.line or (res.left.line == res.right.line and res.left.col > res.right.col) then
    res = { left = res.right, right = res.left }
  end
  return res
end

-- Utilities ------------------------------------------------------------------
H.message = function(msg) vim.cmd('echomsg ' .. vim.inspect('(mini.ai) ' .. msg)) end

H.error = function(msg) error(string.format('(mini.ai) %s', msg), 0) end

H.map = function(mode, key, rhs, opts)
  if key == '' then return end

  opts = vim.tbl_deep_extend('force', { noremap = true, silent = true }, opts or {})

  -- Use mapping description only in Neovim>=0.7
  if vim.fn.has('nvim-0.7') == 0 then opts.desc = nil end

  vim.api.nvim_set_keymap(mode, key, rhs, opts)
end

H.string_find = function(s, pattern, init, reference_span)
  -- Match only start of full string if pattern says so.
  -- This is needed because `string.find()` doesn't do this.
  -- Example: `string.find('(aaa)', '^.*$', 4)` returns `4, 5`
  if pattern:sub(1, 1) == '^' and init > 1 then return nil end

  -- Determine of pattern should be specially handled. If not, fallback to
  -- usual method.
  local pattern_first, pattern_second = pattern:match('^(.-)%.%-(.-)$')
  local is_special_pattern = type(pattern_first) == 'string'
    and pattern_first:len() > 0
    and type(pattern_second) == 'string'
    and pattern_second:len() > 0
    -- Don't specially handle patterns having `%.-`
    and pattern_first:sub(-1) ~= '%'
  if not is_special_pattern then return string.find(s, pattern, init) end

  -- Use custom logic for 'a.-b' patterns (`a` and `b` may be different
  -- strings). It takes into account occurence inside span.
  -- This is needed to make possible the consecutive evolving of textobjects
  -- defined by left and right parts. Key idea is to match in a way that allows
  -- consecutive covering matches.
  -- Conditions on first (possibly more than 1 character) and second (possibly
  -- more than one character) of matched positions based on their relation to
  -- reference span:
  -- - If first not fully inside, second should also not be fully inside but
  --   its end match is allowed to be on edge.
  -- - If first is fully inside, second should not be fully inside.
  local first_left, first_right = string.find(s, pattern_first, init)
  if first_left == nil then return nil end

  local allow_right_edge = not H.is_span_covering(reference_span, { left = first_left, right = first_right })
  local second_left, second_right = first_right, nil
  repeat
    second_left, second_right = string.find(s, pattern_second, second_left + 1)
    if second_left == nil then return nil end
    local is_outside = not H.is_span_covering(reference_span, { left = second_left, right = second_right })
      or (allow_right_edge and second_right == reference_span.right)
  until is_outside

  return first_left, second_right
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
        -- Flatten array to allow tables as elements of step tables
        table.insert(res, vim.tbl_flatten(vim.deepcopy(cur_item)))
      else
        process(level + 1)
      end
      table.remove(cur_item, #cur_item)
    end
  end

  process(1)
  return res
end

-- TODO:
-- - Make `move_cursor()` work consecutively.
-- - Refactor so that `operator()` affects jumplist only if cursor moved.
-- - Deal with empty `i` selection. This is crucial to work with `ci)` (start
--   Insert mode inside empty parenthesis), `di)`, etc.

-- Notes:
-- - To consecutively evolve `i`textobject, use `count` 2. Example: `2i)`.

-- Test cases

-- Brackets:
-- (
-- ___ [ (aaa) (bbb) ]  [{ccc}]
-- )
-- (ddd)

-- Brackets with whitespace:
-- (  aa   ) [  bb   ] {  cc   }

-- Multiline brackets to test difference between `i)` and `i(`; also collapsing
-- multiline regions (uncomment before testing):
-- (
--
-- a
--
-- )

-- Empty selections:
-- () [] {}
-- '' "" ``
-- __ 44

-- Evolving of quotes:
-- '   ' ' ' ' '  '
-- ' '  " ' ' "   ' '

-- Evolving of default textobjects:
-- aa__bb_cc__dd
-- aa________bb______cc
-- 1  2  2  1  2  1  2

-- Evolution of custom textobject using 'a.-b' pattern:
-- vim.b.miniai_config = { custom_textobjects = { ['~'] = {'``.-~~', '^..().*().$'} } }
-- `` `` ~~ ~~ `` ~~

-- Argument textobject:
-- (  aa  , bb,  cc  ,        dd)
-- f(aaa, g(bbb, ccc), ddd)
-- (aa) = f(aaaa, g(bbbb), ddd)

-- Cases from 'wellle/targets.vim':
-- vector<int> data = { variable1 * variable2, test(variable3, 10) * 15 };
-- struct Foo<A, Fn(A) -> bool> { ... }
-- if (window.matchMedia("(min-width: 180px)").matches) {

MiniAi.setup()
MiniAi.config.search_method = 'cover_or_next'
return MiniAi
