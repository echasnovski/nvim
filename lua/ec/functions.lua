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
-- - Needs Neovim>=0.9 to work with 'selection=exclusive'. See
--   https://github.com/neovim/neovim/pull/21735 .
--
-- TODO:
-- Code:
-- - Polish behavior with folds.
-- - Try to think about favoring `p` instead of `P` when moved vertically to
--   line end.
--
-- Non-obvious tests:
-- - Can move any selection (charwise, linewise, blockwise) in any direction
--   (up, down, left, right) on any interenal position (edge/non-edge line,
--   edge/non-edge column).
-- - Doesn't modify any register or `virtualedit`.
-- - Undos all consecutive moves at once.
-- - Works with `selection=exclusive`: both horizontal and vertical moves;
--   inside line, at line end, on empty line.
-- - Special handling of linewise mode:
--     - Horizontal movement is donw with indentation.
--     - Reformatting is done when appropriate.
-- - Doesn't create unnecessary jumps.
-- - Can move past line end.
EC.move_selection = function(direction, opts)
  opts = vim.tbl_deep_extend('force', { reindent_linewise = true, allow_past_line_end = true }, opts or {})

  -- This could have been a one-line expression mappings, but there are issues:
  -- - Initial yanking modifies some register. Not critical, but also not good.
  -- - Doesn't work at movement edges (first line for `K`, etc.). See
  --   https://github.com/vim/vim/issues/11786
  -- - Results into each movement being a separate undo block, which is
  --   inconvenient with several back-to-back movements.
  local cur_mode = vim.fn.mode()

  -- Act only inside visual mode
  if not (cur_mode == 'v' or cur_mode == 'V' or cur_mode == '\22') then return end

  -- Define common predicates
  local dir_type = (direction == 'up' or direction == 'down') and 'vert' or 'hori'
  local is_linewise = cur_mode == 'V'

  -- Cache useful data because it will be reset when executing commands
  local count1 = vim.v.count1

  -- Determine of previous action was this type of move
  local is_moving = vim.deep_equal(H.move_state, H.get_move_state())
  if not is_moving then H.move_state.curswant = nil end

  -- Allow undo of consecutive moves at once (direction doesn't matter)
  local normal_command = (is_moving and 'undojoin |' or '') .. ' keepjumps normal! '
  local cmd = function(x) vim.cmd(normal_command .. x) end

  if is_linewise and dir_type == 'hori' then
    -- Use indentation as horizontal movement for linewise selection
    cmd(count1 .. H.indent_keys[direction] .. 'gv')
  else
    -- Cut selection while saving caching register
    local cache_z_reg = vim.fn.getreg('z')
    cmd('"zx')

    -- Detect edge selection: last line(s) for vertical and last character(s)
    -- for horizontal. At this point (after cutting selection) cursor is on the
    -- edge which can happen in two cases:
    --   - Move second to last selection towards edge (like in 'abc' move 'b'
    --     to right or second to last line down).
    --   - Move edge selection away from edge (like in 'abc' move 'c' to left
    --     or last line up).
    -- Use condition that removed selection was further than current cursor
    -- to distinguish between two cases.
    local is_edge_selection_hori = dir_type == 'hori' and vim.fn.col('.') < vim.fn.col("'<")
    local is_edge_selection_vert = dir_type == 'vert' and vim.fn.line('.') < vim.fn.line("'<")
    local is_edge_selection = is_edge_selection_hori or is_edge_selection_vert

    -- Possibly add single space to allow moving past end of line
    if opts.allow_past_line_end and is_edge_selection_hori then cmd('a ') end

    -- Use `p` as paste key instead of `P` in cases which might require moving
    -- selection to place which is unreachable with `P`: right to be line end
    -- and down to be last line.
    local can_go_overline = not is_linewise and direction == 'right'
    local can_go_overbuf = is_linewise and direction == 'down'
    local paste_key = (can_go_overline or can_go_overbuf) and 'p' or 'P'

    -- Restore `curswant` to try moving cursor to initial column (just like
    -- default `hjkl` moves)
    if dir_type == 'vert' then H.set_curswant(H.move_state.curswant) end

    -- Move cursor with `hjkl` `count1` times dealing with special cases.
    -- Possibly reduce number of moves by one to not overshoot move.
    local n = count1 - ((paste_key == 'p' or is_edge_selection) and 1 or 0)
    if n > 0 then cmd(n .. H.move_keys[direction]) end

    -- Save curswant
    H.move_state.curswant = H.get_curswant()

    -- Paste
    cmd('"z' .. paste_key)

    -- Select newly moved region. Another way is to use something like `gvhoho`
    -- but it doesn't work well with selections spanning several lines.
    cmd('`[1v')

    -- Restore intermediate values
    vim.fn.setreg('z', cache_z_reg)
  end

  -- Reindent linewise selection if `=` can do that
  if opts.reindent_linewise and is_linewise and dir_type == 'vert' and vim.o.equalprg == '' then cmd('=gv') end

  -- Track new state to allow joining in single undo block
  H.move_state = H.get_move_state()
end

H.move_keys = { left = 'h', down = 'j', up = 'k', right = 'l' }
H.indent_keys = { left = '<', right = '>' }

H.move_state = { buf_id = nil, changedtick = nil, curswant = nil }
H.get_move_state = function()
  return {
    buf_id = vim.api.nvim_get_current_buf(),
    changedtick = vim.b.changedtick,
    curswant = H.move_state.curswant or H.get_curswant(),
  }
end

-- This is needed for compatibility with Neovim<=0.6
-- TODO: Remove after compatibility with Neovim<=0.6 is dropped
H.getcursorcharpos = vim.fn.exists('*getcursorcharpos') == 1 and vim.fn.getcursorcharpos or vim.fn.getcurpos
H.setcursorcharpos = vim.fn.exists('*setcursorcharpos') == 1 and vim.fn.setcursorcharpos or vim.fn.cursor

H.get_curswant = function() return H.getcursorcharpos()[5] end
H.set_curswant = function(x)
  if x == nil then return end

  local cursor_pos = H.getcursorcharpos()
  cursor_pos[5] = x
  -- `setcursorcharpos()` doesn't take buffer id as first element
  table.remove(cursor_pos, 1)
  H.setcursorcharpos(cursor_pos)
end

vim.keymap.set('x', 'H', [[<Cmd>lua EC.move_selection('left')<CR>]])
vim.keymap.set('x', 'J', [[<Cmd>lua EC.move_selection('down')<CR>]])
vim.keymap.set('x', 'K', [[<Cmd>lua EC.move_selection('up')<CR>]])
vim.keymap.set('x', 'L', [[<Cmd>lua EC.move_selection('right')<CR>]])

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
