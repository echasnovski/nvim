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

function read_line(line_num)
  return vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]
end

function write_line(line_num, line)
  return vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, {line})
end

function delete_line_part(line_part)
  local line = read_line(line_part.line)
  local new_line = line:sub(1, line_part.from - 1) .. line:sub(line_part.to + 1)
  return write_line(line_part.line, new_line)
end

-- After this, `text` in line will start at `col` character
-- `col` should be not less than 1 (otherwise negative indexing will occur)
function insert_into_line(line_num, col, text)
  local line = read_line(line_num)
  local new_line = line:sub(1, col - 1) .. text .. line:sub(col)
  return write_line(line_num, new_line)
end

-- Find the smallest (with the smallest width) `pattern` match in `line` which
-- covers character at `position`.
-- Output is two numbers (or two `nil`s in case of no covering match): indexes
-- of left and right parts of match. They have two properties:
-- - `left <= position <= right`.
-- - `line:sub(left, right)` matches `'^' .. pattern .. '$'`.
function find_smallest_covering_match(line, pattern, position)
  local left, right, match_left, match_right
  local stop = false
  local init = 1
  while not stop do
    match_left, match_right = line:find(pattern, init)
    if (match_left == nil) or (match_left > position) then
      -- Stop if first match is gone over `position` to the right
      stop = true
    elseif match_right < position then
      -- Proceed if whole match is on the left
      init = match_right + 1
    else
      -- Successful match: match_left <= position <= match_right
      left, right = match_left, match_right
      -- Try find smaller match
      init = match_left + 1
    end
  end

  return left, right
end

function detect_funcall()
  local cur_pos = vim.api.nvim_win_get_cursor(0)
  local n_lines = MiniSurround.search_num_lines
  local lines = vim.api.nvim_buf_get_lines(
    0, cur_pos[1] - n_lines - 1, cur_pos[1] + n_lines, false
  )
  local big_line = table.concat(lines, '\n')

  -- Function call is a name ('%w_\.') followed by balanced '(' and ')'
  local funcall = string.match(big_line, [[[%w_\.]+%b()]])
  print(funcall)

  -- Now need to ensure that this function call contains current cursor
  -- position and is minimal (there is no function call with smaller length
  -- containing cursor)
end

function give_msg(msg)
  vim.cmd(string.format([[echom "(mini-surround.lua) %s"]], msg))
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

function user_surround_output(msg)
  local char = get_char()
  if char == nil then return nil end
  return MiniSurround.pairs[char] or {left = char, right = char}
end

function user_surround_input(msg)
  local char = get_char()
  if char == nil then return nil end
  return MiniSurround.pairs[char] or {left = char, right = char}
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

-- Currently it has problems
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
    surrounding = user_surround_output()
  else
    surrounding = MiniSurround.cache_surrounding_output or user_surround_output()
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
  local surrounding = MiniSurround.cache_surrounding_input or user_surround_input()
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
