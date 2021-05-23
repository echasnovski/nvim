MiniComment = {}

function MiniComment.make_comment_parts()
  local cs = vim.api.nvim_buf_get_option(0, 'commentstring')

  if cs == '' then
    vim.api.nvim_command([[echom "Option 'commentstring' is empty."]])
    return {left = '', right = ''}
  end

  -- Assumed structure of 'commentstring':
  -- <space> <left> <space> <'%s'> <space> <right> <space>
  -- So this extracts parts without surrounding whitespace
  local left, right = cs:match('^%s*(.-)%s*%%s%s*(.-)%s*$')
  return {left = left, right = right}
end

function MiniComment.make_comment_function(comment_parts, indent)
  local indent_str = string.rep(' ', indent)
  local nonindent_start = indent + 1

  local l, r = comment_parts.left, comment_parts.right
  local lpad = (l == '') and '' or ' '
  local rpad = (r == '') and '' or ' '

  local empty_comment = indent_str .. l .. r
  local nonempty_format = indent_str .. l .. lpad .. '%s' .. rpad .. r

  return function(line)
  -- Line is empty if it doesn't have anything except whitespace
    if (line:find('^%s*$') ~= nil) then
      -- If doesn't want to comment empty lines, return `line` here
      return empty_comment
    else
      return string.format(nonempty_format, line:sub(nonindent_start))
    end
  end
end

function MiniComment.make_uncomment_function(comment_parts)
  local l, r = comment_parts.left, comment_parts.right
  local lpad = (l == '') and '' or '[ ]?'
  local rpad = (r == '') and '' or '[ ]?'

  local uncomment_regex = string.format(
    -- Usage of `lpad` and `rpad` as possbile single space enables uncommenting
    -- of commented empty lines without trailing whitespace (like '  #').
    [[^(%%s-)%s%s(.-)%s%s%%s-$]],
    vim.pesc(l), lpad, rpad, vim.pesc(r)
  )

  return function(line)
    indent_str, new_line = string.match(line, uncomment_regex)
    -- Return original if line is not commented
    if new_line == nil then return line end
    -- Remove indent if line is a commented empty line
    if new_line == '' then indent_str = '' end
    return indent_str .. new_line
  end
end

function MiniComment.make_comment_check(comment_parts)
  local l, r = comment_parts.left, comment_parts.right
  -- String is commented if it has structure:
  -- <space> <left> <anything> <right> <space>
  local regex = string.format([[^%%s-%s.*%s%%s-$]], vim.pesc(l), vim.pesc(r))

  return function(line) return line:find(regex) ~= nil end
end

function MiniComment.get_lines_info(lines, comment_parts)
  local indent = math.huge
  local indent_cur = indent

  local is_comment = true
  local comment_check = MiniComment.make_comment_check(comment_parts)

  for _, l in pairs(lines) do
    -- Update lines indent: minimum of all indents except empty lines
    if indent > 0 then
      _, indent_cur = l:find('^%s*')
      -- Condition "current indent equals line length" detects empty line
      if (indent_cur < indent) and (indent_cur < l:len()) then
        indent = indent_cur
      end
    end

    -- Update comment info: lines are comment if every single line is comment
    if is_comment then is_comment = comment_check(l) end
  end

  return indent, is_comment
end

function MiniComment.toggle_comments(line_start, line_end)
  local start = os.clock()

  local comment_parts = MiniComment.make_comment_parts()
  local lines = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
  local indent, is_comment = MiniComment.get_lines_info(lines, comment_parts)

  if is_comment then
    f = MiniComment.make_uncomment_function(comment_parts)
  else
    f = MiniComment.make_comment_function(comment_parts, indent)
  end

  for n, l in pairs(lines) do lines[n] = f(l) end

  -- NOTE: This function call removes marks inside written range. To write
  -- lines in a way that saves marks, use one of:
  -- - `lockmarks` command when doing mapping (current approach).
  -- - `vim.fn.setline(line_start, lines)`, but this is **considerably**
  --   slower: on 10000 lines 280ms compared to 40ms currently.
  vim.api.nvim_buf_set_lines(0, line_start - 1, line_end, false, lines)

  print(os.clock() - start)
end

function MiniComment.operator(mode)
  if mode == nil then
    vim.cmd([[set operatorfunc=v:lua.MiniComment.operator]])
    -- BIG NOTE: this approach doesn't keep marks!!!
    return 'g@'
  end

  local line1, line2
  if mode == 'visual' then
    line1 = vim.api.nvim_buf_get_mark(0, '<')[1]
    line2 = vim.api.nvim_buf_get_mark(0, '>')[1]
  else
    -- When used as 'operatorfunc', `mode` is one of "line", "char", or "block"
    -- (see `:help g@`).
    line1 = vim.api.nvim_buf_get_mark(0, '[')[1]
    line2 = vim.api.nvim_buf_get_mark(0, ']')[1]
  end

  MiniComment.toggle_comments(line1, line2)
  return ''
end

vim.api.nvim_set_keymap(
  -- This mapping is equivalent of `g@_` (after setting 'operatorfunc') which
  -- translates to 'apply on current line'. Using this approach results into
  -- dot-repeatability of this mapping.
  'n', 'gcc', [[v:lua.MiniComment.operator() . '_']],
  {expr = true, noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  'n', 'gc', [[v:lua.MiniComment.operator()]],
  {expr = true, noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  'x', 'gc', [[:<c-u>lockmarks lua MiniComment.operator('visual')<cr>]],
  {noremap = true, silent = true}
)
