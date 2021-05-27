-- Line part - table with fields `line`, `from`, `to`. Represent part of line
-- from `from` character (inclusive) to `to` character (inclusive).

-- Tests
--
-- func.call(a = (1 + 1), b = c(2, 3))

MiniSurround = {}

MiniSurround.search_num_lines = 5

MiniSurround.pairs = {
  ['('] = {left = '(', right = ')'},
  [')'] = {left = '(', right = ')'},
  ['['] = {left = '[', right = ']'},
  [']'] = {left = '[', right = ']'},
  ['{'] = {left = '{', right = '}'},
  ['}'] = {left = '{', right = '}'},
  ['<'] = {left = '<', right = '>'},
  ['>'] = {left = '<', right = '>'}
}

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

-- After this, `text` will in line will start at `col` character
-- `col` should be not less than 1 (otherwise negative indexing will occur)
function insert_into_line(line_num, col, text)
  local line = read_line(line_num)
  local new_line = line:sub(1, col - 1) .. text .. line:sub(col)
  return write_line(line_num, new_line)
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

function get_char()
  local char = vim.fn.getchar()
  if type(char) == 'number' then char = vim.fn.nr2char(char) end

  if string.find(char, '^[%w%p%s]$') == nil then
    vim.cmd(
      [[echom "(mini-surround.lua) Input should be single character: ]] ..
      [[alphanumeric, punctuation, or space."]]
    )
    return nil
  end
  return char
end

function get_region(mode)
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

function input_surround(msg)
  local char = get_char()
  if char == nil then return nil end
  return MiniSurround.pairs[char] or {left = char, right = char}
end

function MiniSurround.operator(task)
  local fun = 'MiniSurround.' .. task
  vim.cmd('set operatorfunc=v:lua.' .. fun)
  return 'g@'
end

function MiniSurround.add(mode)
  local start = os.clock()

  local pos_start, pos_end = get_region(mode)
  local surround = input_surround()
  if surround == nil then return end

  -- Insert first at end then at start in order to not break column numbers
  -- Insert after the region end (`+ 1` is for that)
  insert_into_line(pos_end[1], pos_end[2] + 1, surround.right)
  -- Insert before the region start
  insert_into_line(pos_start[1], pos_start[2], surround.left)

  print(os.clock() - start)
end

function MiniSurround.delete(mode)
  return nil
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

return MiniSurround
