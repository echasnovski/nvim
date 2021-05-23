MiniComment = {}

local is_line_empty = function(line)
  -- Line is empty if it doesn't have anything except whitespace
  return line:find('^%s*$') ~= nil
end

local compute_comment_part_padding = function(part)
  -- Returns two elements: literal padding and padding to be used inside regex
  if part == '' then
    return '', ''
  else
    return ' ', '[ ]?'
  end
end

get_comment_patterns = function()
  local cs = vim.api.nvim_buf_get_option(0, 'commentstring')

  if cs == '' then
    vim.api.nvim_command([[echom "Option 'commentstring' is empty."]])
    return nil
  end

  local left, right = cs:match('^(.*)%%s(.*)$')
  left, right = left:gsub('%s', ''), right:gsub('%s', '')
  local lpad, lpad_regex = compute_comment_part_padding(left)
  local rpad, rpad_regex = compute_comment_part_padding(right)

  return {
    comment = left .. lpad .. '%s' .. rpad .. right,
    comment_empty = left .. '%s' .. right,
    uncomment = string.format(
      [[^(%%s-)%s%s(.-)%s%s$]],
      vim.pesc(left), lpad_regex, rpad_regex, vim.pesc(right)
    )
  }
end

function MiniComment.comment_lines(line_start, line_end, indent_width)
  local start = os.clock()
  local patterns = get_comment_patterns()
  indent_width = indent_width or 0

  local indent_str = string.rep(' ', indent_width)
  local start_id = indent_width + 1

  local lines = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
  local pattern
  for n, l in pairs(lines) do
    if is_line_empty(l) then
      pattern = patterns.comment_empty
    else
      pattern = patterns.comment
    end

    lines[n] = indent_str .. string.format(pattern, l:sub(start_id))
  end

  vim.api.nvim_buf_set_lines(0, line_start - 1, line_end, false, lines)
  print(os.clock() - start)
end

function MiniComment.uncomment_lines(line_start, line_end)
  local start = os.clock()

  local patterns = get_comment_patterns()

  local lines = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)

  local indent, new_line
  for n, l in pairs(lines) do
    indent, new_line = string.match(l, patterns.uncomment)
    if new_line == '' then indent = '' end
    if new_line ~= nil then lines[n] = indent .. new_line end
  end

  vim.api.nvim_buf_set_lines(0, line_start - 1, line_end, false, lines)

  print(os.clock() - start)
end

function MiniComment.get_region_data(line_start, line_end)
  local lines = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
end

-- TODO add docs
local api = vim.api

local M = {}

M.config = {
  -- Linters prefer comment and line to hae a space in between
  marker_padding = true,
  -- should comment out empty or whitespace only lines
  comment_empty = true,
  -- Should key mappings be created
  create_mappings = true,
  -- Normal mode mapping left hand side
  line_mapping = "gcc",
  -- Visual/Operator mapping left hand side
  operator_mapping = "gc"
}

function M.get_comment_wrapper()
  local cs = api.nvim_buf_get_option(0, 'commentstring')

  -- make sure comment string is understood
  if cs:find('%%s') then
   local left = cs:match('^(.*)%%s')
   local right = cs:match('^.*%%s(.*)')

   -- left comment markers should have padding as linterers preffer
   if  M.config.marker_padding then
     if not left:match("%s$") then
       left = left .. " "
     end
     if right ~= "" and not right:match("^%s") then
       right = " " .. right
     end
   end

   return left, right
  else
    api.nvim_command('echom "Commentstring not understood: ' .. cs .. '"')
  end
end

function M.comment_line(l, indent, left, right, comment_empty)
  local line = l
  local comment_pad = indent

  if not comment_empty and l:match("^%s*$") then return line end

  -- most linters want padding to be formatted correctly
  -- so remove comment padding from line
  if comment_pad then
    line = l:gsub("^" .. comment_pad, "")
  else
    comment_pad = ""
  end

  if right ~= '' then line = line .. right end
  line = comment_pad .. left .. line
  return line
end

function M.uncomment_line(l, left, right)
  local line = l
  if right ~= '' then
    local esc_right = vim.pesc(right)
    line = line:gsub(esc_right .. '$', '')
  end
  local esc_left = vim.pesc(left)
  line = line:gsub(esc_left, '', 1)

  return line
end

function M.operator(mode)
  local line1, line2
  if not mode then
    line1 = api.nvim_win_get_cursor(0)[1]
    line2 = line1
  elseif mode:match("[vV]") then
    line1 = api.nvim_buf_get_mark(0, "<")[1]
    line2 = api.nvim_buf_get_mark(0, ">")[1]
  else
    line1 = api.nvim_buf_get_mark(0, "[")[1]
    line2 = api.nvim_buf_get_mark(0, "]")[1]
  end
  -- print("line1", line1, "line2", line2)

  M.comment_toggle(line1, line2)
end

function M.comment_toggle(line_start, line_end)
  local start = os.clock()

  local left, right = M.get_comment_wrapper()
  if not left or not right then return end

  local lines = api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
  if not lines then return end

  -- check if any lines commented, capture indent
  local esc_left = vim.pesc(left)
  local commented_lines_counter = 0
  local empty_counter = 0
  local indent
  for _,v in pairs(lines) do
    if v:find('^%s*' .. esc_left) then
      commented_lines_counter = commented_lines_counter + 1
    elseif v:match("^%s*$") then
      empty_counter = empty_counter + 1
    end
    -- TODO what if already commented line has smallest indent?
    -- TODO no tests for this indent block
    local line_indent = v:match("^%s+")
    if not line_indent then line_indent = "" end
    if not indent or string.len(line_indent) < string.len(indent) then
      indent = line_indent
    end
  end

  local comment = commented_lines_counter ~= (#lines - empty_counter)

  for i,v in pairs(lines) do
    local line
    if comment then
      line = M.comment_line(v, indent, left, right, M.config.comment_empty)
    else
      line = M.uncomment_line(v, left, right)
    end
    lines[i] = line
  end

  api.nvim_buf_set_lines(0, line_start - 1, line_end, false, lines)

  -- The lua call seems to clear the visual selection so reset it
  -- 2147483647 is vimL built in
  api.nvim_call_function("setpos", {"'<", {0, line_start, 1, 0}})
  api.nvim_call_function("setpos", {"'>", {0, line_end, 2147483647, 0}})

  print(os.clock() - start)
end

function M.setup(user_opts)
  if user_opts then
    for i,v in pairs(user_opts) do
      M.config[i] = v
    end
  end

  -- Messy, change with nvim_exec once merged
  vim.api.nvim_command('let g:loaded_text_objects_plugin = 1')
  local vim_func = [[
  function! CommentOperator(type) abort
    let reg_save = @@
    execute "lua require('mini-comment').operator('" . a:type. "')"
    let @@ = reg_save
  endfunction
  ]]
  vim.api.nvim_call_function("execute", {vim_func})
  vim.api.nvim_command("command! -range CommentToggle lua require('mini-comment').comment_toggle(<line1>, <line2>)")

  if M.config.create_mappings then
    local opts = {noremap = true, silent = true}
    vim.api.nvim_set_keymap("n", M.config.line_mapping, "<CMD>CommentToggle<CR>", opts)
    vim.api.nvim_set_keymap("n", M.config.operator_mapping, ":set operatorfunc=CommentOperator<cr>g@", opts)
    vim.api.nvim_set_keymap("v", M.config.operator_mapping, ":<c-u>call CommentOperator(visualmode())<cr>", opts)
  end
end

return M
