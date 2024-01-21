-- Show line after desired maximum text width
vim.cmd('setlocal colorcolumn=89')

-- Keybindings
vim.keymap.set('i', '<M-i>', ' = ', { buffer = 0 })

-- Indentation
vim.g.pyindent_open_paren = 'shiftwidth()'
vim.g.pyindent_continue = 'shiftwidth()'

-- Section insert
Config.section_python = function()
  local cur_line = vim.fn.line('.')
  -- Insert section template
  vim.fn.append(cur_line, '# %% ')

  -- Enable Insert mode in appropriate place
  vim.api.nvim_win_set_cursor(0, { cur_line + 1, 4 })
  vim.cmd('startinsert!')
end

vim.keymap.set({ 'n', 'i' }, '<M-s>', '<Cmd>lua Config.section_python()<CR>', { buffer = 0 })

-- mini.indentscope
vim.b.miniindentscope_config = { options = { border = 'top' } }
