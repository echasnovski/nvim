vim.api.nvim_buf_set_keymap(0, 'i', '<M-i>', ' = ', { noremap = true })

-- Use custom comment leaders to allow both nested variants (`--` and `----`)
-- and "docgen" variant (`---`).
vim.cmd([[setlocal comments=:---,:--]])

-- Customize 'mini.nvim'
vim.b.minisurround_config = {
  custom_surroundings = {
    s = { input = { '%[%[().-()%]%]' }, output = { left = '[[', right = ']]' } },
  },
}

vim.b.miniai_config = {
  custom_textobjects = {
    s = { '%[%[().-()%]%]' },
  },
}

if _G.MiniSplitjoin ~= nil then
  local gen_hook = MiniSplitjoin.gen_hook
  local add_comma_curly = gen_hook.add_trailing_separator({ brackets = { '%b{}' } })
  local remove_comma_curly = gen_hook.remove_trailing_separator({ brackets = { '%b{}' } })
  local pad_curly = gen_hook.pad_edges({ brackets = { '%b{}' } })

  vim.b.minisplitjoin_config = {
    split = { hook_post = add_comma_curly },
    join = {
      hook_post = function(join_positions) pad_curly(remove_comma_curly(join_positions)) end,
    },
  }
end
