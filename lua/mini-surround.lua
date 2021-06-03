-- Line part - table with fields `line`, `from`, `to`. Represent part of line
-- from `from` character (inclusive) to `to` character (inclusive).

-- Tests
--
-- func.call(a = (1 + 1), b = c(2, 3))
-- (((a)))
-- [(aaa(b = c(), d))]
-- (aa_a.a(b = c(), d))
-- 'aa'aaa'
-- aaa(bbb(ccc(ddd(fff(eee)))))
--
-- aaa(bbb(ccc(
--   ddd
-- )))
--
-- <a>Hello<b class>World</a></b>
-- <div class='Hello'>
--   <p>aaa</p><br>
-- </div>
--
-- <a>Hello
-- <b>World
-- </a>
-- </b>

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
  return vim.fn.input('(mini-surround.lua) ' .. msg .. ': ')
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
------ Find the smallest (with the smallest width) covering (left and right
------ offsets in `line`) which inclused `offset` and within which `pattern` is
------ matched. Output is a table with two numbers (or `nil` in case of no
------ covering match): indexes of left and right parts of match. They have two
------ properties:
------ - `left <= offset <= right`.
------ - `line:sub(left, right)` matches `'^' .. pattern .. '$'`.
function find_smallest_covering(line, pattern, offset)
  local left, right, match_left, match_right
  local stop = false
  local init = 1
  while not stop do
    match_left, match_right = line:find(pattern, init)
    if (match_left == nil) or (match_left > offset) then
      -- Stop if first match is gone over `offset` to the right
      stop = true
    elseif match_right < offset then
      -- Try find covering match. Originally this was `init = math.max(init +
      -- 1, match_right)`.  Generally, this works fine, but there is an edge
      -- case with tags.  Consider example: '<a>hello<b>world</a></b>' and
      -- cursor inside '</b>'.  First match is '<a>...</a>'. It doesn't cover
      -- cursor, this branch is
      -- executed. If move to `match_right`, next iteration will match inside
      -- '></b>' and will find no match.
      -- This increases execution time, but tolerably so. On the plus side,
      -- this edge case currently gives wrong result even in 'vim-sandwich' :)
      init = match_left + 1
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

------ Extend covering to capture possible whole groups with count modifiers.
------ Primar usage is to match whole function call with pattern
------ `[%w_%.]+%b()`. Example:
------ `covering = {left = 4, right = 10}, line = '(aaa(b()b))',
------ pattern = '%g+%b()', direction = 'left'` should return
------ `{left = 2, right = 10}`.
------ NOTE: when used for pattern without count modifiers, can remove
------ "smallest width" property. For example:
------ `covering = {left = 2, right = 5}, line = '((()))',
------ pattern = '%(%(.-%)%)', direction = 'left'`
function extend_covering(covering, line, pattern, direction)
  local left, right = covering.left, covering.right
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

  -- Compute surround info
  ---- Return `nil` in case of a bad identifier
  if char == nil then return nil end

  ---- Handle special cases first
  if     char == 'f' then res = special_funcall(type)
  elseif char == 'i' then res = special_interactive(type)
  elseif char == 't' then res = special_tag(type)
  else res = MiniSurround.brackets[char] or default_surrounding(char) end

  -- Cache result
  if use_cache then MiniSurround.cache[type] = res end

  return res
end

function default_surrounding(char)
  local char_esc = vim.pesc(char)
  return {find = char_esc .. '.-' .. char_esc, left = char, right = char}
end

function special_funcall(type)
  -- Differentiate input and output because input doesn't need user action
  if type == 'input' then
    -- Allowed symbols followed by a balanced parenthesis.
    -- Can't use `%g` instead of allowed characters because of possible
    -- '[(fun(10))]' case
    return {id = 'f', find = '[%w_%.]+%b()', extract = '^([%w_%.]+%().*(%))$'}
  else
    local fun_name = user_input('Function name')
    return {left = fun_name .. '(', right = ')'}
  end
end

function special_interactive(type)
  -- Prompt for surroundings. Empty surrounding is not allowed for input.
  local left = user_input('Left surrounding')
  if type == 'input' and left == '' then return nil end
  local right = user_input('Right surrounding')
  if type == 'input' and right == '' then return nil end

  local left_esc, right_esc = vim.pesc(left), vim.pesc(right)
  local find = string.format('%s.-%s', left_esc, right_esc)
  local extract = string.format('^(%s).-(%s)$', left_esc, right_esc)
  return {find = find, extract = extract, left = left, right = right}
end

function special_tag(type)
  -- Differentiate input and output because input doesn't need user action
  if type == 'input' then
    -- NOTE: having group capture and backreference in 'find' pattern increases
    -- execution time. This is mostly visible when searching in a very big '1d
    -- neighborhood'.
    return {find = '<([^ >]-).->.-</%1>', extract = '^(<.->).*(</[^/]->)$'}
  else
    local tag_name = user_input('Tag name')
    return {left = '<' .. tag_name .. '>', right = '</' .. tag_name .. '>'}
  end
end

-- Find surrounding
function find_surrounding_in_neighborhood(surround_info, n_neighbors)
  local neigh = get_cursor_neighborhood(n_neighbors)
  local cur_offset = neigh.pos_to_offset(neigh.cursor_pos)

  -- Find covering of surrounding
  local covering = find_smallest_covering(
    neigh['1d'], surround_info.find, cur_offset
  )
  if covering == nil then return nil end
  ---- Tweak covering for function call surrounding
  if surround_info.id == 'f' then
    covering = extend_covering(covering, neigh['1d'], surround_info.find, 'left')
  end
  local substring = neigh['1d']:sub(covering.left, covering.right)

  -- Compute lineparts for left and right surroundings
  local extract = surround_info.extract or '^(.).*(.)$'
  local left, right = substring:match(extract)
  local l, r = covering.left, covering.right

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

---- NOTE: more simple approach would have been to use combination of
---- `searchpairpos()` (to search for balanced pair) and `searchpos()` (to
---- search end of balanced search and for unbalanced pairs). However, there
---- are several problems with it:
---- - It is slower (around 2-5 times) than current Lua pattern approach.
---- - It has limitations when dealing with crucial 'function call' search.
----   Function call is defined as 'non-empty function name followed by
----   balanced pair of "(" and ")"'. Naive use of `searchpairpos()` is to use
----   `searchpairpos('\w\+(', '', ')')` which works most of the time.
----   However, in example `foo(a = (1 + 1), b = c(1, 2))` this will match
----   `o(a = (1 + 1)` when cursor is on 'a'. This is because '(' inside it is
----   not recognized for balancing because it doesn't match '\w\+('.
----
---- Vim's approach also has some upsides:
---- - `searchpairpos()` allows skipping of certain matches, like if it is
----   inside string or comment. It works decently well with example from help
----   (with `synIDattr`, etc.) but this only works when Vim's builtin
----   highlighting is used. When treesitter's highlighting is active, this
----   doesn't work.
----
---- All in all, using Vim's builtin functions is doable, but leads to roughly
---- same efforts as Lua pattern approach.
function find_surrounding(surround_info)
  if surround_info == nil then return nil end
  local n_lines = MiniSurround.search_num_lines

  -- First try only current line as it is the most common use case
  local surr = find_surrounding_in_neighborhood(surround_info, 0) or
    find_surrounding_in_neighborhood(surround_info, n_lines)

  if surr == nil then
    give_msg(string.format('No surrounding found within %d lines.', n_lines))
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

  -- Compute adjustment for adding right surrounding
  local n_del_left = 0
  if surr.left.line == surr.right.line then
    n_del_left = surr.left.to - surr.left.from + 1
  end

  -- Add output surrounding. Begin insert with 'end' to not break column numbers
  insert_into_line(surr.right.line, surr.right.from - n_del_left, new_surr_info.right)
  insert_into_line(surr.left.line, surr.left.from, new_surr_info.left)

  -- Tweak cursor position
  cursor_adjust(surr.left.line, surr.left.from + new_surr_info.left:len())

  print(os.clock() - start)
end

function MiniSurround.find()
  local start = os.clock()

  -- Find surrounding
  local surr = find_surrounding(get_surround_info('input', true))
  if surr == nil then return '' end

  -- Make list of positions to cycle through
  local pos_list = linepart_to_pos_table(surr.left)
  local pos_table_right = linepart_to_pos_table(surr.right)
  for _, v in pairs(pos_table_right) do table.insert(pos_list, v) end

  -- Cycle cursor through positions
  cursor_cycle(pos_list)

  print(os.clock() - start)
end

function MiniSurround.highlight()
  local start = os.clock()

  -- Find surrounding
  local surr = find_surrounding(get_surround_info('input', true))
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

  print(os.clock() - start)
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
  'n', 'th', [[v:lua.MiniSurround.operator('highlight') . ' ']],
  {expr = true, noremap = true, silent = true}
)

return MiniSurround
