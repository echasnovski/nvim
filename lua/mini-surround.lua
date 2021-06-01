-- Line part - table with fields `line`, `from`, `to`. Represent part of line
-- from `from` character (inclusive) to `to` character (inclusive).

-- Tests
--
-- func.call(a = (1 + 1), b = c(2, 3))
-- (((a)))
-- [(aaa(b = c(), d))]
-- (aa_a.a(b = c(), d))
-- 'aa'aaa'

MiniSurround = {}

MiniSurround.search_num_lines = 20

-- Balanced pairs of surroundings
MiniSurround.brackets = {
  ['('] = {find = '%b()', left = '(', right = ')'},
  [')'] = {find = '%b()', left = '(', right = ')'},
  ['['] = {find = '%b[]', left = '[', right = ']'},
  [']'] = {find = '%b[]', left = '[', right = ']'},
  ['{'] = {find = '%b{}', left = '{', right = '}'},
  ['}'] = {find = '%b{}', left = '{', right = '}'},
  ['<'] = {find = '%b<>', left = '<', right = '>'},
  ['>'] = {find = '%b<>', left = '<', right = '>'}
}

-- Cache to enable dot-repeatability. Here:
-- - 'input' is used for searching (in 'delete' and first stage of 'replace').
-- - 'output' is used for adding (in 'add' and second stage of 'replace').
MiniSurround.cache = {input = nil, output = nil}

-- Prepare data for highlighting
vim.api.nvim_exec([[hi link MiniSurroundHighlight IncSearch]], false)
MiniSurround.ns_id = vim.api.nvim_create_namespace('MiniSurround')
MiniSurround.highlight_duration = 500

-- Helpers
---- Work with operator marks
function get_marks_pos(mode)
  -- Region is inclusive on both ends
  local mark1, mark2
  if mode == 'visual' then
    mark1, mark2 = '<', '>'
  else
    mark1, mark2 = '[', ']'
  end

  local pos1 = vim.api.nvim_buf_get_mark(0, mark1)
  local pos2 = vim.api.nvim_buf_get_mark(0, mark2)

  return {
    -- Make columns 1-based instead of 0-based
    first  = {line = pos1[1], col = pos1[2] + 1},
    second = {line = pos2[1], col = pos2[2] + 1}
  }
end

---- Work with cursor
function cursor_adjust(line, col)
  local cur_pos = vim.api.nvim_win_get_cursor(0)

  -- Only adjust cursor if it is on the same line
  if cur_pos[1] ~= line then return end

  vim.api.nvim_win_set_cursor(0, {line, col - 1})
end

function cursor_cycle(pos_list)
  local cur_pos = vim.api.nvim_win_get_cursor(0)
  local cur_line = cur_pos[1]
  local cur_col = cur_pos[2] + 1

  local cur_is_on_left
  for _, pos in pairs(pos_list) do
    cur_is_on_left = (cur_line < pos.line) or
      (cur_line == pos.line and cur_col < pos.col)
    if cur_is_on_left then
      vim.api.nvim_win_set_cursor(0, {pos.line, pos.col - 1})
      return
    end
  end

  vim.api.nvim_win_set_cursor(0, {pos_list[1].line, pos_list[1].col - 1})
end

---- Work with user input
function give_msg(msg)
  vim.cmd(string.format([[echom "(mini-surround.lua) %s"]], msg))
end

function user_char()
  local char = vim.fn.getchar()

  -- Terminate if input is `<Esc>`
  if char == 27 then return nil end

  if type(char) == 'number' then char = vim.fn.nr2char(char) end
  if char:find('^[%w%p%s]$') == nil then
    give_msg(
      [[Input must be single character: alphanumeric, punctuation, or space."]]
    )
    return nil
  end

  return char
end

function user_input(msg)
  local res = vim.fn.input('(mini-surround.lua) ' .. msg .. ': ')
  if res == '' then
    give_msg('Surrounding should not be empty.')
    return nil
  end
  return res
end

---- Work with line parts and text
function new_linepart(pos_left, pos_right)
  if pos_left.line ~= pos_right.line then
    give_msg('Positions span over multiple lines.')
    return nil
  end

  return {line = pos_left.line, from = pos_left.col, to = pos_right.col}
end

function linepart_to_pos_table(linepart)
  local res = {{line = linepart.line, col = linepart.from}}
  if linepart.from ~= linepart.to then
    table.insert(res, {line = linepart.line, col = linepart.to})
  end
  return res
end

function delete_linepart(linepart)
  local line = vim.fn.getline(linepart.line)
  local new_line = line:sub(1, linepart.from - 1) .. line:sub(linepart.to + 1)
  vim.fn.setline(linepart.line, new_line)
end

function insert_into_line(line_num, col, text)
  -- After this, `text` in line will start at `col` character `col` should be
  -- not less than 1 (otherwise negative indexing will occur)
  local line = vim.fn.getline(line_num)
  local new_line = line:sub(1, col - 1) .. text .. line:sub(col)
  vim.fn.setline(line_num, new_line)
end

---- Work with regular expressions
------ Find the smallest (with the smallest width) borders (left and right
------ offsets in `line`) which covers `offset` and within which `pattern` is
------ matched.  Output is a table with two numbers (or `nil` in case of no
------ covering match): indexes of left and right parts of match. They have
------ two properties:
------ - `left <= offset <= right`.
------ - `line:sub(left, right)` matches `'^' .. pattern .. '$'`.
function find_covering_borders(line, pattern, offset)
  local left, right, match_left, match_right
  local stop = false
  local init = 1
  while not stop do
    match_left, match_right = line:find(pattern, init)
    if (match_left == nil) or (match_left > offset) then
      -- Stop if first match is gone over `offset` to the right
      stop = true
    elseif match_right < offset then
      -- Proceed if whole match is on the left and move init to the right.
      -- Using `match_right` instead of `match_right + 1` to account for this
      -- situation: `line = '"a"aa"', pattern = '".-"', offset = 4`. Using
      -- plain `match_right` allows to find `"aa"`, but `match_right + 1` will
      -- not find anything.
      -- Need `max` here to ensure that `init` is actually moved to right.
      init = math.max(init + 1, match_right)
    else
      -- Successful match: match_left <= offset <= match_right
      -- Update result only if current has smaller width. This ensures
      -- "smallest width" condition. Useful when pattern is something like
      -- `".-"` and `line = '"a"aa"', offset = 3`.
      if (left == nil) or (match_right - match_left < right - left) then
        left, right = match_left, match_right
      end
      -- Try find smaller match
      init = match_left + 1
    end
  end

  if left == nil then return nil end

  -- Try make match even smaller. Can happen if there is `+` flag at the end.
  -- For example `line = '((()))', pattern = '%(.-%)+', offset = 3`.
  local line_pattern = '^' .. pattern .. '$'
  while left < right and line:sub(left, right - 1):find(line_pattern) do
    right = right - 1
  end

  return {left = left, right = right}
end

------ Extend borders to capture possible whole groups with count modifiers.
------ Primar usage is to match whole function call with pattern
------ `[%w_%.]+%b()`. Example:
------ `borders = {left = 4, right = 10}, line = '(aaa(b()b))',
------ pattern = '%g+%b()', direction = 'left'` should return
------ `{left = 2, right = 10}`.
------ NOTE: when used for pattern without count modifiers, can remove
------ "smallest width" property. For example:
------ `borders = {left = 2, right = 5}, line = '((()))',
------ pattern = '%(%(.-%)%)', direction = 'left'`
function extend_borders(borders, line, pattern, direction)
  local left, right = borders.left, borders.right
  local line_pattern = '^' .. pattern .. '$'
  local n = line:len()
  local is_matched = function(l, r)
    return l >= 1 and r <= n and line:sub(l, r):find(line_pattern) ~= nil
  end

  if direction ~= 'right' then
    while is_matched(left - 1, right) do left = left - 1 end
  end
  if direction ~= 'left' then
    while is_matched(left, right + 1) do right = right + 1 end
  end

  return {left = left, right = right}
end

---- Work with cursor neighborhood
function get_cursor_neighborhood(n_neighbors)
  -- Cursor position
  local cur_pos = vim.api.nvim_win_get_cursor(0)
  ---- Convert from 0-based column to 1-based
  cur_pos = {line = cur_pos[1], col = cur_pos[2] + 1}

  -- '2d neighborhood': position is determined by line and column
  line_start = math.max(1, cur_pos.line - n_neighbors)
  line_end = math.min(vim.api.nvim_buf_line_count(0), cur_pos.line + n_neighbors)
  neigh2d = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)

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

    return {line = line_start + line_num - 1, col = offset - line_offset}
  end

  return {
    cursor_pos = cur_pos,
    ['1d'] = neigh1d,
    ['2d'] = neigh2d,
    pos_to_offset = pos_to_offset,
    offset_to_pos = offset_to_pos
  }
end

-- Get surround information
---- `type` is one of 'input' or 'output'
function get_surround_info(type, use_cache)
  local res

  -- Try using cache
  if use_cache then
    res = MiniSurround.cache[type]
    if res ~= nil then return res end
  end

  -- Prompt user to enter identifier of surrounding
  local char = user_char()

  -- Handle special cases
  ---- Return `nil` in case of a bad identifier
  if char == nil then return nil end
  if char == 'i' then res = get_interactive_surrounding() end
  if char == 'f' then
    -- Differentiate input and output because input doesn't need user input
    res = (type == 'input') and funcall_input() or funcall_output()
  end

  -- Get from other sources if it is not special case
  res = res or MiniSurround.brackets[char] or default_surrounding(char)

  -- Cache result
  if use_cache then MiniSurround.cache[type] = res end

  return res
end

function default_surrounding(char)
  local char_esc = vim.pesc(char)
  return {find = char_esc .. '.-' .. char_esc, left = char, right = char}
end

function funcall_input()
  -- Allowed symbols followed by a balanced parenthesis.
  -- Can't use `%g` instead of allowed characters because of possible
  -- '[(fun(10))]' case
  return {id = 'f', find = '[%w_%.]+%b()', extract = '^([%w_%.]+%().*(%))$'}
end

function funcall_output()
  local fun_name = user_input('Function name')
  if fun_name == nil then return nil end
  return {left = fun_name .. '(', right = ')'}
end

function get_interactive_surrounding()
  local left = user_input('Left surrounding')
  if left == nil then return nil end
  local right = user_input('Right surrounding')
  if right == nil then return nil end

  local left_esc, right_esc = vim.pesc(left), vim.pesc(right)
  local find = string.format('%s.-%s', left_esc, right_esc)
  local extract = string.format('^(%s).-(%s)$', left_esc, right_esc)
  return {find = find, extract = extract, left = left, right = right}
end

-- Find surrounding
function find_surrounding_in_neighborhood(surround_info, n_neighbors)
  local neigh = get_cursor_neighborhood(n_neighbors)
  local cur_offset = neigh.pos_to_offset(neigh.cursor_pos)

  -- Find borders of surrounding
  local borders = find_covering_borders(
    neigh['1d'], surround_info.find, cur_offset
  )
  if borders == nil then return nil end
  ---- Tweak borders for function call surrounding
  if surround_info.id == 'f' then
    borders = extend_borders(borders, neigh['1d'], surround_info.find, 'left')
  end
  local substring = neigh['1d']:sub(borders.left, borders.right)

  -- Compute lineparts for left and right surroundings
  local extract = surround_info.extract or '^(.).*(.)$'
  local left, right = substring:match(extract)
  local l, r = borders.left, borders.right

  local left_from, left_to =
    neigh.offset_to_pos(l), neigh.offset_to_pos(l + left:len() - 1)
  local right_from, right_to =
    neigh.offset_to_pos(r - right:len() + 1), neigh.offset_to_pos(r)

  local left_linepart = new_linepart(left_from, left_to)
  if left_linepart == nil then return nil end
  local right_linepart = new_linepart(right_from, right_to)
  if right_linepart == nil then return nil end

  return {left = left_linepart, right = right_linepart}
end

function find_surrounding(surround_info)
  if surround_info == nil then return nil end

  -- First try only current line as it is the most common use case
  local surr = find_surrounding_in_neighborhood(surround_info, 0) or
    find_surrounding_in_neighborhood(surround_info, MiniSurround.search_num_lines)

  if surr == nil then
    give_msg(string.format(
      'No surrounding found within %d lines.',
      MiniSurround.search_num_lines
    ))
    return nil
  end

  return surr
end

-- Functions to be mapped
function MiniSurround.operator(task)
  MiniSurround.cache = {input = nil, output = nil}

  vim.cmd('set operatorfunc=v:lua.' .. 'MiniSurround.' .. task)
  return 'g@'
end

function MiniSurround.add(mode)
  -- Get marks' positions based on current mode
  local marks = get_marks_pos(mode)

  -- Get surround info. Try take from cache only in not visual mode (as there
  -- is no intended dot-repeatability).
  local surr_info
  if mode == 'visual' then
    surr_info = get_surround_info('output', false)
  else
    surr_info = get_surround_info('output', true)
  end
  if surr_info == nil then return '' end

  -- Add surrounding. Begin insert with 'end' to not break column numbers
  ---- Insert after the right mark (`+ 1` is for that)
  insert_into_line(marks.second.line, marks.second.col + 1, surr_info.right)
  insert_into_line(marks.first.line,  marks.first.col,      surr_info.left)

  -- Tweak cursor position
  cursor_adjust(marks.first.line, marks.first.col + surr_info.left:len())
end

function MiniSurround.delete()
  local start = os.clock()

  -- Find input surrounding
  local surr = find_surrounding(get_surround_info('input', true))
  if surr == nil then return '' end

  -- Delete surrounding. Begin with right to not break column numbers
  delete_linepart(surr.right)
  delete_linepart(surr.left)

  -- Tweak cursor position
  cursor_adjust(surr.left.line, surr.left.from)

  print(os.clock() - start)
end

function MiniSurround.replace()
  local start = os.clock()

  -- Find input surrounding
  local surr = find_surrounding(get_surround_info('input', true))
  if surr == nil then return '' end

  -- Get output surround info
  local new_surr_info = get_surround_info('output', true)
  if new_surr_info == nil then return '' end

  -- Delete input surrounding. Begin with right to not break column numbers
  delete_linepart(surr.right)
  delete_linepart(surr.left)

  -- Add output surrounding. Begin insert with 'end' to not break column numbers
  ---- Insert after the right mark (`+ 1` is for that)
  insert_into_line(surr.right.line, surr.right.from - 1, new_surr_info.right)
  insert_into_line(surr.left.line, surr.left.from, new_surr_info.left)

  -- Tweak cursor position
  cursor_adjust(surr.left.line, surr.left.from + new_surr_info.left:len())

  print(os.clock() - start)
end

function MiniSurround.find()
  -- Find surrounding
  local surr = find_surrounding(get_surround_info('input', true))
  if surr == nil then return '' end

  -- Make list of positions to cycle through
  local pos_list = linepart_to_pos_table(surr.left)
  local pos_table_right = linepart_to_pos_table(surr.right)
  for _, v in pairs(pos_table_right) do table.insert(pos_list, v) end

  -- Cycle cursor through positions
  cursor_cycle(pos_list)
end

function MiniSurround.highlight()
  -- Find surrounding
  local surr = find_surrounding(get_surround_info('input', false))
  if surr == nil then return '' end

  -- Highlight surrounding
  vim.api.nvim_buf_add_highlight(
    0, MiniSurround.ns_id, 'MiniSurroundHighlight',
    surr.left.line - 1, surr.left.from - 1, surr.left.to
  )
  vim.api.nvim_buf_add_highlight(
    0, MiniSurround.ns_id, 'MiniSurroundHighlight',
    surr.right.line - 1, surr.right.from - 1, surr.right.to
  )

  vim.defer_fn(
    function()
      vim.api.nvim_buf_clear_namespace(
        0, MiniSurround.ns_id, surr.left.line - 1, surr.right.line
      )
    end,
    MiniSurround.highlight_duration
  )
end

-- Make mappings
---- NOTE: In mappings construct ` . ' '` "disables" motion required by `g@`.
---- It is used to enable dot-repeatability in the first place.
vim.api.nvim_set_keymap(
  'n', 'ta', [[v:lua.MiniSurround.operator('add')]],
  {expr = true, noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  'x', 'ta', [[:<c-u>lua MiniSurround.add('visual')<cr>]],
  {noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  'n', 'td', [[v:lua.MiniSurround.operator('delete') . ' ']],
  {expr = true, noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  'n', 'tr', [[v:lua.MiniSurround.operator('replace') . ' ']],
  {expr = true, noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  'n', 'tf', [[v:lua.MiniSurround.operator('find') . ' ']],
  {expr = true, noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  'n', 'th', [[:<c-u>lua MiniSurround.highlight()<cr>]],
  {noremap = true, silent = true}
)

return MiniSurround
