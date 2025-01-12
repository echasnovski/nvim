-- Helper table
local H = {}

-- Log for personal use during debugging
Config.log = {}

local start_hrtime = vim.loop.hrtime()
_G.add_to_log = function(...)
  local t = { ... }
  t.timestamp = 0.000001 * (vim.loop.hrtime() - start_hrtime)
  table.insert(Config.log, vim.deepcopy(t))
end

local log_buf_id
Config.log_print = function()
  if log_buf_id == nil or not vim.api.nvim_buf_is_valid(log_buf_id) then
    log_buf_id = vim.api.nvim_create_buf(true, true)
  end
  vim.api.nvim_win_set_buf(0, log_buf_id)
  vim.api.nvim_buf_set_lines(log_buf_id, 0, -1, false, vim.split(vim.inspect(Config.log), '\n'))
end

Config.log_clear = function()
  Config.log = {}
  start_hrtime = vim.loop.hrtime()
  vim.cmd('echo "Cleared log"')
end

-- Show Neoterm's active REPL, i.e. in which command will be executed when one
-- of `TREPLSend*` will be used
Config.print_active_neoterm = function()
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

-- Create listed scratch buffer and focus on it
Config.new_scratch_buffer = function() vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(true, true)) end

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
Config.cr_action = function()
  if vim.fn.pumvisible() ~= 0 then
    local item_selected = vim.fn.complete_info()['selected'] ~= -1
    return item_selected and '\25' or '\25\r'
  else
    return require('mini.pairs').cr()
  end
end

-- Insert section
Config.insert_section = function(symbol, total_width)
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
Config.execute_lua_line = function()
  local line = 'lua ' .. vim.api.nvim_get_current_line()
  vim.api.nvim_command(line)
  print(line)
  vim.api.nvim_input('<Down>')
end

-- Tabpage with lazygit
Config.open_lazygit = function()
  vim.cmd('tabedit')
  vim.cmd('setlocal nonumber signcolumn=no')

  -- Unset vim environment variables to be able to call `vim` without errors
  -- Use custom `--git-dir` and `--work-tree` to be able to open inside
  -- symlinked submodules
  vim.fn.termopen('VIMRUNTIME= VIM= lazygit --git-dir=$(git rev-parse --git-dir) --work-tree=$(realpath .)', {
    on_exit = function()
      vim.cmd('silent! :checktime')
      vim.cmd('silent! :bw')
    end,
  })
  vim.cmd('startinsert')
  vim.b.minipairs_disable = true
end

-- Toggle quickfix window
Config.toggle_quickfix = function()
  local cur_tabnr = vim.fn.tabpagenr()
  for _, wininfo in ipairs(vim.fn.getwininfo()) do
    if wininfo.quickfix == 1 and wininfo.tabnr == cur_tabnr then return vim.cmd('cclose') end
  end
  vim.cmd('copen')
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
Config.statuscolumn = function()
  local start_time = vim.loop.hrtime()

  local lnum = vim.v.lnum

  -- Line part
  local line = H.get_line_statuscolumn_string(lnum, 3)

  -- Sign part
  local signs = H.get_sign_statuscolumn_string(lnum, 2)

  local res = string.format('%s%%=%s', signs, line)
  local end_time = vim.loop.hrtime()
  table.insert(_G.statuscol_times, 0.000001 * (end_time - start_time))
  return res
end

H.get_line_statuscolumn_string = function(lnum, width)
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

H.get_sign_statuscolumn_string = function(lnum, width)
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
--   vim.o.statuscolumn = '%!v:lua.Config.statuscolumn()'
-- end

-- Manage 'mini.test' screenshots ---------------------------------------------
local S = {}
Config.minitest_screenshots = S

S.browse = function(dir_path)
  dir_path = dir_path or 'tests/screenshots'
  S.files = vim.fn.readdir(dir_path)
  S.dir_path = dir_path
  local preview_item = function(x) return vim.fn.readfile(dir_path .. '/' .. x) end
  local ui_opts = { prompt = 'Choose screenshot:', preview_item = preview_item }

  vim.ui.select(S.files, ui_opts, function(_, idx)
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
  vim.cmd('au CursorMoved <buffer> lua Config.minitest_screenshots.sync_cursor()')

  vim.cmd('belowright wincmd v | wincmd = | enew')
  S.buf_id_attr = vim.api.nvim_get_current_buf()
  S.win_id_attr = vim.api.nvim_get_current_win()
  vim.cmd('setlocal bufhidden=wipe nobuflisted')
  vim.cmd('au CursorMoved <buffer> lua Config.minitest_screenshots.sync_cursor()')

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
    vim.api.nvim_buf_set_keymap(buf_id, 'n', '<C-d>', '<Cmd>lua Config.minitest_screenshots.delete_current()<CR>', { noremap = true })
    vim.api.nvim_buf_set_keymap(buf_id, 'n', '<C-n>', '<Cmd>lua Config.minitest_screenshots.show_next()<CR>', { noremap = true })
    vim.api.nvim_buf_set_keymap(buf_id, 'n', '<C-p>', '<Cmd>lua Config.minitest_screenshots.show_prev()<CR>', { noremap = true })
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

  pcall(function() MiniTrailspace.unhighlight() end)
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

-- LuaLS "Go to source" =======================================================
-- Deal with the fact that LuaLS in case of `local a = function()` style
-- treats both `a` and `function()` as definitions of `a`.
-- Do this by tweaking `vim.lsp.buf_definition` mapping as client-local
-- handlers are ignored after https://github.com/neovim/neovim/pull/30877
local filter_line_locations = function(locations)
  local present, res = {}, {}
  for _, l in ipairs(locations) do
    local t = present[l.filename] or {}
    if not t[l.lnum] then
      table.insert(res, l)
      t[l.lnum] = true
    end
    present[l.filename] = t
  end
  return res
end

local show_location = function(location)
  local buf_id = location.bufnr or vim.fn.bufadd(location.filename)
  vim.bo[buf_id].buflisted = true
  vim.api.nvim_win_set_buf(0, buf_id)
  vim.api.nvim_win_set_cursor(0, { location.lnum, location.col - 1 })
  vim.cmd('normal! zv')
end

local on_list = function(args)
  local items = filter_line_locations(args.items)
  if #items > 1 then
    vim.fn.setqflist({}, ' ', { title = 'LSP locations', items = items })
    return vim.cmd('botright copen')
  end
  show_location(items[1])
end

Config.luals_unique_definition = function() return vim.lsp.buf.definition({ on_list = on_list }) end
