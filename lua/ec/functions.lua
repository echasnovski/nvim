-- Helper table
local H = {}

-- Very early R&D for 'mini.pick'
-- - Find files
EC.read_dir_builtin = function(dir_path)
  local res = {}
  for name, fs_type in vim.fs.dir(dir_path, { depth = math.huge }) do
    if fs_type == 'file' then table.insert(res, string.format('%s/%s', dir_path, name)) end
  end
  return res
end

EC.read_dir_find = function(dir_path) return vim.fn.systemlist({ 'find', dir_path, '-type', 'f' }) end

EC.read_dir_rg = function(dir_path)
  return vim.fn.systemlist({ 'rg', '--files', '--color', 'never', '--no-ignore', '--', dir_path })
end

EC.read_dir_globpath = function(dir_path) return vim.fn.globpath(dir_path, '**', false, true) end

-- - Find patterns inside file
EC.read_file_libuv = function(path)
  -- Read file content
  local fd = vim.loop.fs_open(path, 'r', 1)

  local is_text = vim.loop.fs_read(fd, 1024, 0):find('\0') == nil
  local content = ''
  if is_text then
    local size = vim.loop.fs_stat(path).size
    content = vim.loop.fs_read(fd, size, 0)
  end

  vim.loop.fs_close(fd)

  return vim.split(content, '\n')
end

EC.read_file_builtin = function(path) return vim.fn.readfile(path) end

EC.find_in_file = function(path, pattern, read_fun)
  local lines = read_fun(path)
  if lines == nil then return nil end

  local res = {}
  for i, l in ipairs(lines) do
    if string.find(l, pattern) ~= nil then table.insert(res, i) end
  end
  return res
end

-- - Find pattern inside whole directory
EC.find_in_dir = function(path, pattern, read_dir_fun, read_file_fun)
  local files = read_dir_fun(path)

  local res = {}
  for _, file_path in ipairs(files) do
    local lines = read_file_fun(file_path) or {}

    for i, l in ipairs(lines) do
      if string.find(l, pattern) ~= nil then table.insert(res, { file_path, i, l }) end
    end
  end

  return res
end

EC.find_in_dir_rg = function(dir_path, pattern)
  return vim.fn.systemlist({ 'rg', '-e', pattern, '--color', 'never', '--no-ignore', '--', dir_path })
end

-- Show Neoterm's active REPL, i.e. in which command will be executed when one
-- of `TREPLSend*` will be used
EC.print_active_neoterm = function()
  local msg
  if vim.fn.exists('g:neoterm.repl') == 1 and vim.fn.exists('g:neoterm.repl.instance_id') == 1 then
    msg = 'Active REPL neoterm id: ' .. vim.g.neoterm.repl.instance_id
  elseif vim.g.neoterm.last_id ~= 0 then
    msg = 'Active REPL neoterm id: ' .. vim.g.neoterm.last_id
  else
    msg = 'No active REPL'
  end

  print(msg)
end

-- Create scratch buffer and focus on it
EC.new_scratch_buffer = function()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(0, buf)
end

-- Make action for `<CR>` which respects completion and autopairs
--
-- Mapping should be done after everything else because `<CR>` can be
-- overridden by something else (notably 'mini-pairs.lua'). This should be an
-- expression mapping:
-- vim.api.nvim_set_keymap('i', '<CR>', 'v:lua._cr_action()', { expr = true })
--
-- Its current logic:
-- - If no popup menu is visible, use "no popup keys" getter. This is where
--   autopairs plugin should be used. Like with 'nvim-autopairs'
--   `get_nopopup_keys` is simply `npairs.autopairs_cr`.
-- - If popup menu is visible:
--     - If item is selected, execute "confirm popup" action and close
--       popup. This is where completion engine takes care of snippet expanding
--       and more.
--     - If item is not selected, close popup and execute '<CR>'. Reasoning
--       behind this is to explicitly select desired completion (currently this
--       is also done with one '<Tab>' keystroke).
EC.cr_action = function()
  if vim.fn.pumvisible() ~= 0 then
    local item_selected = vim.fn.complete_info()['selected'] ~= -1
    return item_selected and H.keys['ctrl-y'] or H.keys['ctrl-y_cr']
  else
    return require('mini.pairs').cr()
  end
end

-- Functions to move arguments left/right. Depends on 'vim-exchange'
EC.move_arg = function(direction)
  local miniclue_is_active = _G.MiniClue ~= nil

  if miniclue_is_active then MiniClue.disable_all_triggers() end

  local cmd = string.format('normal cxiacxi%sa', direction == 'left' and 'l' or 'n')
  vim.cmd(cmd)

  if miniclue_is_active then MiniClue.enable_all_triggers() end
end

-- Insert section
EC.insert_section = function(symbol, total_width)
  symbol = symbol or '='
  total_width = total_width or 79

  -- Insert template: 'commentstring' but with '%s' replaced by section symbols
  local comment_string = vim.bo.commentstring
  local content = string.rep(symbol, total_width - (comment_string:len() - 2))
  local section_template = comment_string:format(content)
  vim.fn.append(vim.fn.line('.'), section_template)

  -- Enable Replace mode in appropriate place
  local inner_start = comment_string:find('%%s')
  vim.fn.cursor(vim.fn.line('.') + 1, inner_start)
  vim.cmd([[startreplace]])
end

-- Execute current line with `lua`
EC.execute_lua_line = function()
  local line = 'lua ' .. vim.api.nvim_get_current_line()
  vim.api.nvim_command(line)
  print(line)
  vim.api.nvim_input('<Down>')
end

-- Tabpage with lazygit
EC.open_lazygit = function()
  vim.cmd('tabedit')
  vim.cmd('setlocal nonumber signcolumn=no')

  -- Unset vim environment variables to be able to call `vim` without errors
  vim.fn.termopen('VIMRUNTIME= VIM= lazygit --git-dir=$(git rev-parse --git-dir)', {
    on_exit = function()
      vim.cmd('silent! :checktime')
      vim.cmd('silent! :bw')
    end,
  })
  vim.cmd('startinsert')
  vim.b.minipairs_disable = true
end

-- Toggle quickfix window
EC.toggle_quickfix = function()
  local quickfix_wins = vim.tbl_filter(
    function(win_id) return vim.fn.getwininfo(win_id)[1].quickfix == 1 end,
    vim.api.nvim_tabpage_list_wins(0)
  )

  local command = #quickfix_wins == 0 and 'copen' or 'cclose'
  vim.cmd(command)
end

-- Custom 'statuscolumn' for Neovim>=0.9
--
-- Revisit this with a better API.
--
-- Ideally, it should **efficiently** allow users to define each column for
-- a particular signs. Like:
-- - First column is for signs from 'gitsigns.nvim' and todo-comments.
-- - Second - diagnostic errors and warnings.
-- - Then line number.
-- - Then a column for everything else with highest priority.
--
-- Other notes:
-- - Make sure to allow fixed width for parts to exclude possibility of
--   horizontal shifts. Relevant, for example, for "absolute number" ->
--   "relative number" conversion.
-- - Set up `active()` and `inactive()` with change like in 'mini.statusline'.
-- - Should somehow not show any status column where it shouldn't be (like in
--   help files).
_G.statuscol_times = {}
EC.statuscolumn = function()
  local start_time = vim.loop.hrtime()

  local lnum = vim.v.lnum

  -- Line part
  local line = EC.get_line_statuscolumn_string(lnum, 3)

  -- Sign part
  local signs = EC.get_sign_statuscolumn_string(lnum, 2)

  local res = string.format('%s%%=%s', signs, line)
  local end_time = vim.loop.hrtime()
  table.insert(_G.statuscol_times, 0.000001 * (end_time - start_time))
  return res
end

EC.get_line_statuscolumn_string = function(lnum, width)
  local number, relativenumber = vim.wo.number, vim.wo.relativenumber
  if not (number or relativenumber) then return '' end

  local is_current_line = lnum == vim.fn.line('.')

  -- Compute correct line number value
  local show_relnum = relativenumber and not (number and is_current_line)
  local text = vim.v.virtnum ~= 0 and '' or (show_relnum and vim.v.relnum or (number and lnum or ''))
  text = tostring(text):sub(1, width)

  -- Compute correct highlight group
  local hl = 'LineNr'
  if is_current_line and vim.wo.cursorline then
    local cursorlineopt = vim.wo.cursorlineopt
    local cursorline_affects_number = cursorlineopt:find('number') ~= nil or cursorlineopt:find('both') ~= nil

    hl = cursorline_affects_number and 'CursorLineNr' or 'LineNr'
  elseif vim.wo.relativenumber then
    local relnum = vim.v.relnum
    hl = relnum < 0 and 'LineNrAbove' or (relnum > 0 and 'LineNrBelow' or 'LineNr')
  end

  -- Combine result
  return string.format('%%#%s#%s ', hl, text)
end

EC.get_sign_statuscolumn_string = function(lnum, width)
  local signs = vim.fn.sign_getplaced(vim.api.nvim_get_current_buf(), { group = '*', lnum = lnum })[1].signs
  if #signs == 0 then return string.rep(' ', width) end

  local parts, sign_definitions = {}, {}
  local cur_width = 0
  for i = #signs, 1, -1 do
    local name = signs[i].name

    local def = sign_definitions[name] or vim.fn.sign_getdefined(name)[1]
    sign_definitions[name] = def

    cur_width = cur_width + vim.fn.strdisplaywidth(def.text)
    local s = string.format('%%#%s#%s', def.texthl, vim.trim(def.text or ''))
    table.insert(parts, s)
  end
  local sign_string = table.concat(parts, '') .. string.rep(' ', width - cur_width)

  return sign_string
end

-- if vim.fn.exists('&statuscolumn') == 1 then
--   vim.o.signcolumn = 'no'
--   vim.o.statuscolumn = '%!v:lua.EC.statuscolumn()'
-- end

-- Overwrite `vim.ui.select()` with Telescope ---------------------------------
EC.ui_select_default = vim.ui.select

vim.ui.select = function(items, opts, on_choice)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  opts = opts or {}

  -- Create picker options
  local picker_opts = {
    prompt_title = opts.prompt,
    finder = finders.new_table({ results = items }),
    sorter = conf.generic_sorter(),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        -- Operate only on first selection
        on_choice(selection[1], selection.index)
      end)
      return true
    end,
  }

  pickers.new({}, picker_opts):find()
end

-- Manage 'mini.test' screenshots ---------------------------------------------
local S = {}
EC.minitest_screenshots = S

S.browse = function(dir_path)
  dir_path = dir_path or 'tests/screenshots'
  S.files = vim.fn.readdir(dir_path)
  S.dir_path = dir_path

  vim.ui.select(S.files, { prompt = 'Choose screenshot:' }, function(_, idx)
    if idx == nil then return end
    S.file_id = idx

    S.setup_windows()
    S.show()
  end)
end

S.setup_windows = function()
  -- Set up tab page
  vim.cmd('tabnew')
  S.buf_id_text = vim.api.nvim_get_current_buf()
  S.win_id_text = vim.api.nvim_get_current_win()
  vim.cmd('setlocal bufhidden=wipe nobuflisted')
  vim.cmd('au CursorMoved <buffer> lua EC.minitest_screenshots.sync_cursor()')

  vim.cmd('belowright wincmd v | wincmd = | enew')
  S.buf_id_attr = vim.api.nvim_get_current_buf()
  S.win_id_attr = vim.api.nvim_get_current_win()
  vim.cmd('setlocal bufhidden=wipe nobuflisted')
  vim.cmd('au CursorMoved <buffer> lua EC.minitest_screenshots.sync_cursor()')

  vim.api.nvim_set_current_win(S.win_id_text)

  --stylua: ignore start
  local win_options = {
    colorcolumn = '', cursorline = true, cursorcolumn = true, fillchars = 'eob: ',
    foldcolumn = '0', foldlevel = 999,   number = false,      relativenumber = false,
    spell = false,    signcolumn = 'no', wrap = false,
  }
  for name, value in pairs(win_options) do
    vim.api.nvim_win_set_option(S.win_id_text, name, value)
    vim.api.nvim_win_set_option(S.win_id_attr, name, value)
  end

  -- Set up behavior
  for _, buf_id in ipairs({ S.buf_id_text, S.buf_id_attr }) do
    vim.api.nvim_buf_set_keymap(buf_id, 'n', 'q', ':tabclose!<CR>', { noremap = true })
    vim.api.nvim_buf_set_keymap(buf_id, 'n', 'D', '<Cmd>lua EC.minitest_screenshots.delete_current()<CR>', { noremap = true })
    vim.api.nvim_buf_set_keymap(buf_id, 'n', 'J', '<Cmd>lua EC.minitest_screenshots.show_next()<CR>', { noremap = true })
    vim.api.nvim_buf_set_keymap(buf_id, 'n', 'K', '<Cmd>lua EC.minitest_screenshots.show_prev()<CR>', { noremap = true })
  end
  --stylua: ignore end
end

S.show = function(path)
  path = path or (S.dir_path .. '/' .. S.files[S.file_id])

  local lines = vim.fn.readfile(path)
  local n = 0.5 * (#lines - 3)

  local text_lines = { path, 'Text' }
  vim.list_extend(text_lines, vim.list_slice(lines, 1, n + 1))
  vim.api.nvim_buf_set_lines(S.buf_id_text, 0, -1, true, text_lines)

  local attr_lines = { path, 'Attr' }
  vim.list_extend(attr_lines, vim.list_slice(lines, n + 3, 2 * n + 3))
  vim.api.nvim_buf_set_lines(S.buf_id_attr, 0, -1, true, attr_lines)

  pcall(MiniTrailspace.unhighlight)
end

S.sync_cursor = function()
  -- Don't use `vim.api.nvim_win_get_cursor()` because of multibyte characters
  local line, col = vim.fn.winline(), vim.fn.wincol()
  local cur_win_id = vim.api.nvim_get_current_win()
  -- Don't use `vim.api.nvim_win_set_cursor()`: it doesn't redraw cursorcolumn
  local command = string.format('windo call setcursorcharpos(%d, %d)', line, col)
  vim.cmd(command)
  vim.api.nvim_set_current_win(cur_win_id)
end

S.show_next = function()
  S.file_id = math.fmod(S.file_id, #S.files) + 1
  S.show()
end

S.show_prev = function()
  S.file_id = math.fmod(S.file_id + #S.files - 2, #S.files) + 1
  S.show()
end

S.delete_current = function()
  local path = S.dir_path .. '/' .. S.files[S.file_id]
  vim.fn.delete(path)
  print('Deleted file ' .. vim.inspect(path))
end

-- Split-join arguments -------------------------------------------------------
-- Helper data ================================================================
-- Commonly used keys
H.keys = {
  ['cr'] = vim.api.nvim_replace_termcodes('<CR>', true, true, true),
  ['ctrl-y'] = vim.api.nvim_replace_termcodes('<C-y>', true, true, true),
  ['ctrl-y_cr'] = vim.api.nvim_replace_termcodes('<C-y><CR>', true, true, true),
}
