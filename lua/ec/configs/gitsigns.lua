-- Setup
require('gitsigns').setup({
  signs = {
    add = { text = '▒' },
    change = { text = '▒' },
    changedelete = { text = '▓' },
    delete = { text = '▓' },
    topdelete = { text = '▓' },
    untracked = { text = '░' },
  },
  preview_config = { border = 'double' },
  watch_gitdir = { interval = 1000 },
})

local goto_hunk_cmd = function(direction)
  local center = function() vim.cmd('normal! zvzz') end

  return function()
    require('gitsigns')[direction .. '_hunk']()
    if MiniAnimate ~= nil then
      MiniAnimate.execute_after('scroll', function() vim.defer_fn(center, 5) end)
    else
      cetner()
    end
  end
end

vim.keymap.set('n', '[h', goto_hunk_cmd('prev'), { desc = 'Backward hunk' })
vim.keymap.set('n', ']h', goto_hunk_cmd('next'), { desc = 'Forward hunk' })
