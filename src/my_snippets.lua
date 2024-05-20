local all_snippets = {
  ['if'] = 'if $1 then\n\t$0\nend',
  ['ife'] = 'if $1 then\n\t$0\nelse\n\t-- TODO\nend',
  ['then'] = 'then\n\t$0\nend',
  ['eif'] = 'elseif $1 then\n\t$0\nend',
  -- TODO: Make it work. Probably by allowing custom number of bytes to remove
  -- when expanding snippet (instead of `#prefix`)
  ['  el'] = 'else\n$0',
  ['fun'] = 'function($1)\n\t$0\nend',
  ['for'] = 'for ${1:i}=${2:first},${3:last}${4:,step} do\n\t$0\nend',
  ['forp'] = 'for ${1:name},${2:val} in pairs(${3:table_name}) do\n\t$0\nend',
  ['fori'] = 'for ${1:idx},${2:val} in ipairs(${3:table_name}) do\n\t$0\nend',
  ['do'] = 'do\n\t$0\nend',
  ['repeat'] = 'repeat\n\t$1\nuntil $0',
  ['wh'] = 'while $1 do\n\t$0\nend',
  ['pcall'] = 'local ok, $1 = pcall($0)',
  ['l'] = 'local $1 = $0',
  ['desc'] = "describe('$1', function()\n\t$0\nend)",
  ['it'] = "it('$1', function()\n\t$0\nend)",
  ['TS'] = "T['$1'] = new_set()$0",
  ['T'] = "T['$1']['$2'] = function()\n\t$0MiniTest.skip()\nend",
}

local get_snippet_at_cursor = function()
  local line = vim.api.nvim_get_current_line()
  local offset = vim.fn.mode() == 'i' and 0 or 1
  local col = vim.api.nvim_win_get_cursor(0)[2] + offset

  -- TODO: Probably make matching character configurable
  local prefix = line:sub(1, col):match('[%w_-.]*$')
  local res = all_snippets[prefix]
  if vim.is_callable(res) then return res(), prefix end
  return res, prefix
end

local jump_or_expand = function()
  if vim.snippet.active({ direction = 1 }) then return vim.snippet.jump(1) end

  local snippet, prefix = get_snippet_at_cursor()
  if type(snippet) ~= 'string' then return end

  vim.schedule(function()
    local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_text(0, lnum - 1, col - #prefix, lnum - 1, col, {})
    vim.snippet.expand(snippet)
  end)
end

-- Make snippet keymaps
local go_right = function() jump_or_expand() end

local go_left = function()
  if vim.snippet.active({ direction = -1 }) then vim.snippet.jump(-1) end
end

vim.keymap.set({ 'i', 's' }, '<C-l>', go_right)
vim.keymap.set({ 'i', 's' }, '<C-h>', go_left)

-- Tweak to stop snippet session while exiting into Normal mode
-- -- NOTE: autocommand doesn't work because currently tabstop selection in
-- -- `vim.snippet` itself exits into Normal mode
-- -- (see https://github.com/neovim/neovim/issues/26449#issuecomment-1845843529)
-- local augroup = vim.api.nvim_create_augroup('my_snippets', {})
-- local opts = {
--   pattern = '*:n',
--   group = augroup,
--   callback = function() vim.snippet.stop() end,
--   desc = 'Stop snippet session and exit to Normal mode',
-- }
-- vim.api.nvim_create_autocmd('ModeChanged', opts)

vim.keymap.set({ 'i', 's' }, '<C-e>', function()
  vim.snippet.stop()
  vim.fn.feedkeys('\27', 'n')
end, { desc = 'Stop snippet session' })

-- -- Notify about presence of snippet. This is my attempt to try to live without
-- -- snippet autocompletion. At least for the time being to get used to new
-- -- snippets. NOTE: this code is run *very* frequently, but it seems to be fast
-- -- enough (~0.1ms during normal typing).
-- local luasnip_ns = vim.api.nvim_create_namespace('luasnip')
--
-- Config.luasnip_notify_clear = function() vim.api.nvim_buf_clear_namespace(0, luasnip_ns, 0, -1) end
--
-- Config.luasnip_notify = function()
--   if not luasnip.expandable() then
--     Config.luasnip_notify_clear()
--     return
--   end
--
--   local line = vim.api.nvim_win_get_cursor(0)[1] - 1
--   vim.api.nvim_buf_set_virtual_text(0, luasnip_ns, line, { { '!', 'Special' } }, {})
-- end
--
-- vim.cmd([[au InsertEnter,CursorMovedI,TextChangedI,TextChangedP * lua pcall(Config.luasnip_notify)]])
-- vim.cmd([[au InsertLeave * lua pcall(Config.luasnip_notify_clear)]])
