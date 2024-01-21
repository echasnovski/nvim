-- Mappings for code commenting
vim.keymap.set('x', 'gc', '<Plug>VSCodeCommentary')
vim.keymap.set('n', 'gc', '<Plug>VSCodeCommentary')
vim.keymap.set('o', 'gc', '<Plug>VSCodeCommentary')
vim.keymap.set('n', 'gcc', '<Plug>VSCodeCommentaryLine')

-- Simulate tab switching
vim.keymap.set('n', ']b', '<Cmd>Tabnext<CR>')
vim.keymap.set('n', '[b', '<Cmd>Tabprev<CR>')

-- Workaround for executing visual selection in VS Code (for example, in Python
-- interactive window)
Config.vscode_execute_line_or_selection = function(cur_mode, vscode_command)
  local visual_mode
  if cur_mode == 'normal' then
    -- Visually select current line
    vim.cmd('normal! V')
    visual_mode = 'V'
  else
    -- My guess is that this is probably needed because visual selection is
    -- 'reset' before function is called
    vim.cmd('normal! gv')
    visual_mode = vim.fn.visualmode()
  end

  if visual_mode == 'V' then
    vim.fn.VSCodeNotifyRange(vscode_command, vim.fn.line('v'), vim.fn.line('.'), 1)
  else
    local start_pos, end_pos = vim.fn.getpos([['<]]), vim.fn.getpos([['>]])
    -- `getpos()` returns `{bufnum, lnum, col, off}`, only 2 and 3 are needed
    vim.fn.VSCodeNotifyRangePos(vscode_command, start_pos[2], end_pos[2], start_pos[3], end_pos[3] + 1, 1)
  end

  -- Wait some time because otherwise following commands, when working
  -- remotely, seem to be executed before sending range to remote computer
  -- which upon delivery will execute the wrong range (usually a single line
  -- after desired selection)
  vim.loop.sleep(100)

  -- Escape to normal mode and move past selection (depending on submode)
  local finish_cmd = 'normal! \27' .. (visual_mode == 'v' and '`>l' or "'>j")
  vim.cmd(finish_cmd)
end

-- 'Send to Jupyter'
local map_send = function(mode, lhs, cur_mode, vscode_command)
  local rhs =
    string.format([[:<C-u>lua Config.vscode_execute_line_or_selection('%s', '%s')<CR>]], cur_mode, vscode_command)
  vim.keymap.set(mode, lhs, rhs, { silent = true })
end

map_send('n', '<Leader>j', 'normal', 'jupyter.execSelectionInteractive')
map_send('x', '<Leader>j', 'visual', 'jupyter.execSelectionInteractive')

map_send('x', '<Leader>r', 'visual', 'r.runSelection')
vim.keymap.set('n', '<Leader>r', [[:<C-u>call VSCodeCall('r.runSelection')<CR>]])
