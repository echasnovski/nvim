require('mini.comment').setup()
require('mini.completion').setup({ lsp_completion = { source_func = 'omnifunc', auto_setup = false } })
MiniCompletion.lsp_completion.process_items = function(items, base)
  -- Don't show 'Text' and 'Snippet' suggestions
  items = vim.tbl_filter(function(x)
    return x.kind ~= 1 and x.kind ~= 15
  end, items)
  return MiniCompletion.default_process_items(items, base)
end
require('mini.cursorword').setup()
require('mini.misc').setup()
require('mini.pairs').setup({ modes = { insert = true, command = true, terminal = true } })
require('mini.statusline').setup()
require('mini.surround').setup()
require('mini.tabline').setup()
require('mini.trailspace').setup()
