-- MIT License Copyright (c) 2021 Evgeni Chasnovski
--
-- Custom *minimal* and *fast* commenting Lua module. This is basically a
-- reimplementation of 'tpope/vim-commentary' with help of
-- 'terrortylor/nvim-comment'.
--
-- To activate, put this file somewhere into 'lua' folder and call module's
-- `setup()`. For example, put as 'lua/mini/comment.lua' and execute
-- `require('mini.comment').setup()` Lua code.
--
-- Functionality:
-- - `MiniComment.operator()` function is meant to be used in '<expr>' mapping
--   to enable dot-repeatability and commenting on range.
-- - `MiniComment.toggle_comments()` toggles comments between two line numbers.
--   It uncomments if lines are comment (every line is a comment) and comments
--   otherwise. It respects indentation and doesn't insert trailing
--   whitespace. Toggle commenting not in visual mode is also dot-repeatable
--   and respects 'count'.
-- - `MiniComment.textobject()` implements comment textobject: all commented
--   lines adjacent to current one.
--
-- Details:
-- - Commenting depends on '&commentstring' option.
-- - There is no support for block comments: all comments are made per line.

-- Module and its helper
local MiniComment = {}
local H = {}

-- Module setup
function MiniComment.setup()
  -- Export module
  _G.MiniComment = MiniComment

  vim.api.nvim_set_keymap(
    'n', 'gc', 'v:lua.MiniComment.operator()',
    {expr = true, noremap = true, silent = true}
  )
  vim.api.nvim_set_keymap(
    'n', 'gcc', 'gc_',
    -- This mapping doesn't use `noremap = true` because it requires usage of
    -- already mapped `gc`.
    {silent = true}
  )
  vim.api.nvim_set_keymap(
    -- Using `:<c-u>` instead of `<cmd>` as latter results into executing before
    -- proper update of `'<` and `'>` marks which is needed to work correctly.
    'x', 'gc', [[:<c-u>lua MiniComment.operator('visual')<cr>]],
    {noremap = true, silent = true}
  )
  vim.api.nvim_set_keymap(
    'o', 'gc', [[<cmd>lua MiniComment.textobject()<cr>]],
    {noremap = true, silent = true}
  )
end

-- Module functionality
---- Main function to be mapped. It has a rather unintuitive logic: it should
---- be called without arguments inside expression mapping (returns `g@` to
---- enable action on motion or textobject) and with argument when action
---- should be performed.
function MiniComment.operator(mode)
  -- If used without arguments inside expression mapping:
  -- - Set itself as `operatorfunc` to be called later to perform action.
  -- - Return 'g@' which will then be executed resulting into waiting for a
  --   motion or text object. This textobject will then be recorded using `'[`
  --   and `'[` marks. After that, `operatorfunc` is called with `mode` equal
  --   to one of "line", "char", or "block".
  -- NOTE: setting `operatorfunc` inside this function enables usage of 'count'
  -- like `10gc_` toggles comments of 10 lines below (starting with current).
  if mode == nil then
    vim.cmd('set operatorfunc=v:lua.MiniComment.operator')
    return 'g@'
  end

  -- If called with non-nil `mode`, get target region and perform comment
  -- toggling over it.
  local mark1, mark2
  if mode == 'visual' then
    mark1, mark2 = '<', '>'
  else
    mark1, mark2 = '[', ']'
  end

  local l1 = vim.api.nvim_buf_get_mark(0, mark1)[1]
  local l2 = vim.api.nvim_buf_get_mark(0, mark2)[1]

  -- Using `vim.cmd()` wrapper to allow usage of `lockmarks` command, because
  -- raw execution will delete marks inside region (due to
  -- `vim.api.nvim_buf_set_lines()`).
  vim.cmd(
    string.format('lockmarks lua MiniComment.toggle_comments(%d, %d)', l1, l2)
  )
  return ''
end

function MiniComment.toggle_comments(line_start, line_end)
  local comment_parts = H.make_comment_parts()
  local lines = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
  local indent, is_comment = H.get_lines_info(lines, comment_parts)

  if is_comment then
    f = H.make_uncomment_function(comment_parts)
  else
    f = H.make_comment_function(comment_parts, indent)
  end

  for n, l in pairs(lines) do lines[n] = f(l) end

  -- NOTE: This function call removes marks inside written range. To write
  -- lines in a way that saves marks, use one of:
  -- - `lockmarks` command when doing mapping (current approach).
  -- - `vim.fn.setline(line_start, lines)`, but this is **considerably**
  --   slower: on 10000 lines 280ms compared to 40ms currently.
  vim.api.nvim_buf_set_lines(0, line_start - 1, line_end, false, lines)
end

---- Textobject function which selects all commented lines adjacent to cursor
---- line (if it itself is commented).
function MiniComment.textobject()
  local comment_parts = H.make_comment_parts()
  local comment_check = H.make_comment_check(comment_parts)
  local line_cur = vim.api.nvim_win_get_cursor(0)[1]

  if not comment_check(vim.fn.getline(line_cur)) then return end

  local line_start = line_cur
  while (line_start >= 2) and comment_check(vim.fn.getline(line_start - 1)) do
    line_start = line_start - 1
  end

  local line_end = line_cur
  local n_lines = vim.api.nvim_buf_line_count(0)
  while (line_end <= n_lines - 1) and comment_check(vim.fn.getline(line_end + 1)) do
    line_end = line_end + 1
  end

  -- This visual selection doesn't seem to change `'<` and `'>` marks when
  -- executed as `onoremap` mapping
  vim.cmd(string.format('normal! %dGV%dG', line_start, line_end))
end

-- Helpers
function H.make_comment_parts()
  local cs = vim.api.nvim_buf_get_option(0, 'commentstring')

  if cs == '' then
    vim.api.nvim_command(
      [[echom "(mini-comment.lua) Option 'commentstring' is empty."]]
    )
    return {left = '', right = ''}
  end

  -- Assumed structure of 'commentstring':
  -- <space> <left> <space> <'%s'> <space> <right> <space>
  -- So this extracts parts without surrounding whitespace
  local left, right = cs:match('^%s*(.-)%s*%%s%s*(.-)%s*$')
  return {left = left, right = right}
end

function H.make_comment_check(comment_parts)
  local l, r = comment_parts.left, comment_parts.right
  -- String is commented if it has structure:
  -- <space> <left> <anything> <right> <space>
  local regex = string.format([[^%%s-%s.*%s%%s-$]], vim.pesc(l), vim.pesc(r))

  return function(line) return line:find(regex) ~= nil end
end

function H.get_lines_info(lines, comment_parts)
  local indent = math.huge
  local indent_cur = indent

  local is_comment = true
  local comment_check = H.make_comment_check(comment_parts)

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

function H.make_comment_function(comment_parts, indent)
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

function H.make_uncomment_function(comment_parts)
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

return MiniComment
