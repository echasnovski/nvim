-- Show Neoterm's active REPL, i.e. in which command will be executed when one
-- of `TREPLSend*` will be used
_G.print_active_neoterm = function()
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

-- Zoom in and out of a buffer, making it full screen in a floating window.
-- This function is useful when working with multiple windows but temporarily
-- needing to zoom into one to see more of the code from that buffer.
local zoom_winid = nil
_G.zoom_toggle = function()
  if zoom_winid and vim.api.nvim_win_is_valid(zoom_winid) then
    vim.api.nvim_win_close(zoom_winid, true)
    zoom_winid = nil
  else
    -- Currently very big `width` and `height` get truncated to maximum allowed
    local opts = { relative = 'editor', row = 0, col = 0, width = 1000, height = 1000 }
    zoom_winid = vim.api.nvim_open_win(0, true, opts)
    vim.cmd([[normal! zz]])
  end
end
