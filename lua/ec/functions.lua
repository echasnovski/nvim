-- Helper table
local H = {}

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
    if item_selected then
      return H.keys['ctrl-y']
    else
      return H.keys['ctrl-y_cr']
    end
  else
    return require('mini.pairs').cr()
  end
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

-- Floating window with lazygit
EC.open_lazygit = function()
  vim.cmd('tabedit')
  vim.cmd('setlocal nonumber signcolumn=no')

  vim.fn.termopen('lazygit --git-dir=$(git rev-parse --git-dir)', {
    on_exit = function()
      vim.cmd('silent! :checktime')
      vim.cmd('silent! :bw')
    end,
  })
  vim.cmd('startinsert')
  vim.b.minipairs_disable = true
end

-- Move visually selected region
--
-- - Doesn't really work with 'selection=exclusive'. See
--   https://github.com/vim/vim/issues/11791 .
--
-- TODO:
-- Non-obvious tests:
-- - Doesn't modify any register or `virtualedit`.
-- - Works with `virtualedit=all` (can move to outside of line).
-- - Undos all consecutive moves at once.
-- - Works with `selection=exclusive`: both horizontal and vertical moves;
--   inside line, at line end, on empty line.
-- - Special handling of linewise mode:
--     - Horizontal movement is donw with indentation.
--     - Reformatting is done when appropriate.
EC.move_visual_selection = function(direction)
  -- This could have been a one-line expression mappings, but there are issues:
  -- - Initial yanking modifies some register. Not critical, but also not good.
  -- - Doesn't work at movement edges (first line for `K`, etc.). See
  --   https://github.com/vim/vim/issues/11786
  -- - Results into each movement being a separate undo block, which is
  --   inconvenient with several back-to-back movements.
  local cur_mode = vim.fn.mode()

  -- Act only inside visual mode
  if not (cur_mode == 'v' or cur_mode == 'V' or cur_mode == '\22') then return end

  -- Allow undo of consecutive moves at once (direction doesn't matter)
  local is_moving = vim.deep_equal(H.vis_move_state, H.get_vis_move_state())
  local normal_command = (is_moving and 'undojoin |' or '') .. ' normal! '
  local cmd = function(x) vim.cmd(normal_command .. x) end

  -- Cache `v:count1` because it will be reset when executing commands
  local count1 = vim.v.count1

  if cur_mode == 'V' and (direction == 'left' or direction == 'right') then
    -- Use indentation as horizontal movement for linewise selection
    cmd(count1 .. H.indent_keys[direction] .. 'gv')
  else
    -- Yank selection while saving caching register
    local cache_z_reg = vim.fn.getreg('z')
    cmd('"zx')

    -- Move cursor. If needed, use `'onemore'` 'virtualedit' for these reasons:
    -- - Allow moving selection at the end of line (later use of `P` makes it impossible).
    -- - Allow vertical movement in case of `selection=exclusive` (needs go past line end).
    local cache_virtualedit = vim.o.virtualedit
    if not string.find(cache_virtualedit, 'all') then vim.o.virtualedit = 'onemore' end
    cmd(count1 .. H.move_keys[direction])

    -- Paste
    cmd('"zP')

    -- Select newly moved region. Another way is to use something like `gvhoho`
    --              moved    aaaa
    -- but it doesn't work well with selections spanning several lines.
    cmd('`[1v')

    -- Restore options
    vim.fn.setreg('z', cache_z_reg)
    vim.o.virtualedit = cache_virtualedit
  end

  -- Reformat linewsie selection if `=` can do that
  if cur_mode == 'V' and (direction == 'up' or direction == 'down') and vim.o.equalprg == '' then cmd('=gv') end

  -- Track new state to allow joining in single undo block
  H.vis_move_state = H.get_vis_move_state()
end

H.move_keys = { left = 'h', down = 'j', up = 'k', right = 'l' }
H.indent_keys = { left = '<', right = '>' }

H.get_vis_move_state =
  function() return { buf_id = vim.api.nvim_get_current_buf(), changedtick = vim.b.changedtick } end
H.vis_move_state = H.get_vis_move_state()

vim.keymap.set('x', 'H', [[<Cmd>lua EC.move_visual_selection('left')<CR>]])
vim.keymap.set('x', 'J', [[<Cmd>lua EC.move_visual_selection('down')<CR>]])
vim.keymap.set('x', 'K', [[<Cmd>lua EC.move_visual_selection('up')<CR>]])
vim.keymap.set('x', 'L', [[<Cmd>lua EC.move_visual_selection('right')<CR>]])

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

-- Helper data ================================================================
-- Commonly used keys
H.keys = {
  ['cr'] = vim.api.nvim_replace_termcodes('<CR>', true, true, true),
  ['ctrl-y'] = vim.api.nvim_replace_termcodes('<C-y>', true, true, true),
  ['ctrl-y_cr'] = vim.api.nvim_replace_termcodes('<C-y><CR>', true, true, true),
}
