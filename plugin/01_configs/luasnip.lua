local has_luasnip, luasnip = pcall(require, 'luasnip')
if not has_luasnip then
  return
end

luasnip.config.set_config({ history = true })

-- Load available snippets
require('luasnip/loaders/from_vscode').lazy_load({ paths = { './misc/snippets' } })

-- Make snippet keymaps
function _G.luasnip_go_right()
  if luasnip.expand_or_jumpable() then
    luasnip.expand_or_jump()
  end
end

function _G.luasnip_go_left()
  if luasnip.jumpable() then
    luasnip.jump(-1)
  end
end

vim.api.nvim_set_keymap('i', '<C-l>', [[<Cmd>lua _G.luasnip_go_right()<CR>]], {})
vim.api.nvim_set_keymap('s', '<C-l>', [[<Cmd>lua _G.luasnip_go_right()<CR>]], {})

vim.api.nvim_set_keymap('i', '<C-h>', [[<Cmd>lua _G.luasnip_go_left()<CR>]], {})
vim.api.nvim_set_keymap('s', '<C-h>', [[<Cmd>lua _G.luasnip_go_left()<CR>]], {})

-- Notify about presence of snippet. This is my attempt to try to live without
-- snippet autocompletion. At least for the time being to get used to new
-- snippets. NOTE: this code is run *very* frequently, but it seems to be fast
-- enough (~0.1ms during normal typing).
local luasnip_ns = vim.api.nvim_create_namespace('luasnip')

_G.luasnip_notify_clear = function()
  vim.api.nvim_buf_clear_namespace(0, luasnip_ns, 0, -1)
end

_G.luasnip_notify = function()
  if not luasnip.expandable() then
    _G.luasnip_notify_clear()
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  vim.api.nvim_buf_set_virtual_text(0, luasnip_ns, line, { { '!', 'Special' } }, {})
end

vim.cmd([[au InsertEnter,CursorMovedI,TextChangedI,TextChangedP * lua _G.luasnip_notify()]])
vim.cmd([[au InsertLeave * lua _G.luasnip_notify_clear()]])
