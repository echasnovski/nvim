-- Line part - table with fields `line`, `from`, `to`. Represent part of line
-- from `from` character (inclusive) to `to` character (inclusive).

-- Tests
--
-- func.call(a = (1 + 1), b = c(2, 3))

MiniSurround = {}

MiniSurround.search_num_lines = 5

MiniSurround.pairs = {
  ['('] = {pattern = '%b()', left = '(', right = ')'},
  [')'] = {pattern = '%b()', left = '(', right = ')'},
  ['['] = {pattern = '%b[]', left = '[', right = ']'},
  [']'] = {pattern = '%b[]', left = '[', right = ']'},
  ['{'] = {pattern = '%b{}', left = '{', right = '}'},
  ['}'] = {pattern = '%b{}', left = '{', right = '}'},
  ['<'] = {pattern = '%b<>', left = '<', right = '>'},
  ['>'] = {pattern = '%b<>', left = '<', right = '>'}
}

-- Cache to enable dot-repeatability. Here
-- - 'input' is used for searching (in 'delete' and first stage of 'replace').
-- - 'output' is used for adding (in 'add' and second stage of 'replace').
MiniSurround.cache_surrounding_input  = nil
MiniSurround.cache_surrounding_output = nil

function get_cursor_pos()
  local pos = vim.api.nvim_win_get_cursor(0)
  -- Convert from 0-based column to 1-based
  return {line = pos[1], col = pos[2] + 1}
end

function delete_line_part(line_part)
  local line = vim.fn.getline(line_part.line)
  local new_line = line:sub(1, line_part.from - 1) .. line:sub(line_part.to + 1)
  vim.fn.setline(line_part.line, new_line)
end

-- After this, `text` in line will start at `col` character
-- `col` should be not less than 1 (otherwise negative indexing will occur)
function insert_into_line(line_num, col, text)
  local line = vim.fn.getline(line_num)
  local new_line = line:sub(1, col - 1) .. text .. line:sub(col)
  vim.fn.setline(line_num, new_line)
end

-- Find the smallest (with the smallest width) `pattern` match in `line` which
-- covers character at `offset`.
-- Output is two numbers (or two `nil`s in case of no covering match): indexes
-- of left and right parts of match. They have two properties:
-- - `left <= offset <= right`.
-- - `line:sub(left, right)` matches `'^' .. pattern .. '$'`.
function find_smallest_covering_match(line, pattern, offset)
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
  return {left = left, right = right}
end

function get_cursor_neighborhood(n_neighbors)
  local cur_pos = get_cursor_pos()

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
    ['1d'] = neigh1d,
    ['2d'] = neigh2d,
    pos_to_offset = pos_to_offset,
    offset_to_pos = offset_to_pos
  }
end

function find_match_in_neighborhood(pattern, n_neighbors)
  local cur_pos = get_cursor_pos()
  local neigh = get_cursor_neighborhood(n_neighbors)
  local cur_offset = neigh.pos_to_offset(cur_pos)

  local surr = find_smallest_covering_match(neigh['1d'], pattern, cur_offset)
  if surr == nil then return nil end

  return {
    left = neigh.offset_to_pos(surr.left),
    right = neigh.offset_to_pos(surr.right)
  }
end

function give_msg(msg)
  vim.cmd(string.format([[echom "(mini-surround.lua) %s"]], msg))
end

function user_input(msg)
  local res = vim.fn.input('(mini-surround.lua) ' .. msg .. ': ')
  if res == '' then
    give_msg('Surrounding should not be empty.')
    return nil
  end
  return res
end

function get_char()
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

function get_surround_info(type)
  local char = get_char()

  -- Handle special cases
  if char == nil then return nil end
  if char == 'i' then return get_interactive_surrounding() end
  if char == 'f' then
    -- Differentiate input and output because input doesn't need user input
    return (type == 'input') and funcall_input() or funcall_output()
  end

  return MiniSurround.pairs[char] or default_surrounding(char)
end

function default_surrounding(char)
  local char_esc = vim.pesc(char)
  return {pattern = char_esc .. '.-' .. char_esc, left = char, right = char}
end

function funcall_input()
  -- Non-space followed by a balanced parenthesis
  return {pattern = '%g%b()'}
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

  local pattern = vim.pesc(left) .. '.-' .. vim.pesc(right)
  return {pattern = pattern, left = left, right = right}
end

function get_region_edges(mode)
  -- Region is inclusive on both ends
  local mark1, mark2
  if mode == 'visual' then
    mark1, mark2 = '<', '>'
  else
    mark1, mark2 = '[', ']'
  end

  local pos_start = vim.api.nvim_buf_get_mark(0, mark1)
  local pos_end = vim.api.nvim_buf_get_mark(0, mark2)

  -- Make columns 1-based instead of 0-based
  pos_start[2] = pos_start[2] + 1
  pos_end[2] = pos_end[2] + 1

  return pos_start, pos_end
end

-- Currently it has big problems: can't make balancing
function find_pattern(pattern, dir)
  dir = dir or 'right'
  local flags = 'cnW'
  if dir == 'left' then flags = flags .. 'b' end

  local pos_left = vim.fn.searchpos(pattern, flags)
  if pos_left[1] == 0 and pos_left[2] == 0 then
    give_msg(string.format('No pattern %s is found on the %s.', pattern, dir))
    return nil
  end

  local pos_right = vim.fn.searchpos(pattern, flags .. 'e')

  if pos_left[1] ~= pos_right[1] then
    give_msg('Found pattern spans over multiple lines.')
    return nil
  end

  return {line = pos_left[1], from = pos_left[2], to = pos_right[2]}
end

function MiniSurround.operator(task)
  -- Clear cache
  MiniSurround.cache_surrounding_input = nil
  MiniSurround.cache_surrounding_output = nil

  local fun = 'MiniSurround.' .. task
  vim.cmd('set operatorfunc=v:lua.' .. fun)
  return 'g@'
end

function MiniSurround.add(mode)
  -- Get region based on current mode
  local pos_start, pos_end = get_region_edges(mode)

  -- Get surrounding. Try take from cache only in not visual mode (as there is
  -- no intended dot-repeatability).
  local surrounding
  if mode == 'visual' then
    surrounding = get_surround_info('output')
  else
    surrounding = MiniSurround.cache_surrounding_output or get_surround_info('output')
  end
  ---- Don't do anything in case of a bad surrounding
  if surrounding == nil then return '' end
  ---- Cache surrounding for dot-repeatability
  MiniSurround.cache_surrounding_output = surrounding

  -- Add surroundings
  ---- Begin insert with 'end' to not break column numbers
  ---- Insert after the region end (`+ 1` is for that)
  insert_into_line(pos_end[1], pos_end[2] + 1, surrounding.right)
  insert_into_line(pos_start[1], pos_start[2], surrounding.left)
end

-- `mode` is present only for compatibility with 'operatorfunc' interface
function MiniSurround.delete(mode)
  local start = os.clock()

  -- Get surrounding
  local surrounding = MiniSurround.cache_surrounding_input or get_surround_info('input')
  ---- Don't do anything in case of a bad surrounding
  if surrounding == nil then return '' end
  ---- Cache surrounding for dot-repeatability
  MiniSurround.cache_surrounding_input = surrounding

  -- Find surrounding
  local line_part_left = find_pattern(surrounding.left, 'left')
  if line_part_left == nil then return '' end

  local line_part_right = find_pattern(surrounding.right, 'right')
  if line_part_right == nil then return '' end

  -- Delete surrounding. Begin with right to not break column numbers
  delete_line_part(line_part_right)
  delete_line_part(line_part_left)

  print(os.clock() - start)
end

function MiniSurround.replace(mode)
  return nil
end

-- Temporary mappings
vim.api.nvim_set_keymap(
  'n', 'ta', [[v:lua.MiniSurround.operator('add')]],
  {expr = true, noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  'x', 'ta', [[:<c-u>lua MiniSurround.add('visual')<cr>]],
  {noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  -- Here ' ' "disables" motion required by `g@`
  'n', 'td', [[v:lua.MiniSurround.operator('delete') . ' ']],
  {expr = true, noremap = true, silent = true}
)

return MiniSurround
