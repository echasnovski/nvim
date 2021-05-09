-- This is a file for all commands that should be sourced after all other 'lua'
-- files are sourced

-- Helpers
local escape = function(s)
  return vim.api.nvim_replace_termcodes(s, true, true, true)
end

-- Setup `<CR>` key. This should be executed after everything else because
-- `<CR>` can be overridden by something else (notably 'mini-pairs.lua').
-- Its current logic:
-- - If no popup menu is visible, execute "no popup action".
-- - If popup menu is visible:
--     - If item is selected, execute "confirm popup selection" and close
--       popup. This is where completion engine takes care of snippet expanding
--       and more.
--     - If item is not selected, close popup and execute '<CR>'. Reasoning
--       behind this is to explicitly select desired completion (currently this
--       is also done with one '<Tab>' keystroke).
local has_compe, compe           = pcall(require, 'compe')
local has_completion, completion = pcall(require, 'completion')

---- `g:_using_delimitMate = 1` should be set whenever 'delimitMate' plugin is
---- actually used (currently it is defined right after call to `Plug`). The
---- reason for this workaround is that 'delimitMate' is loaded in 'afterload'
---- fashion. This means that there is no way (at least I couldn't find one) to
---- detect if 'delimitMate' was actually loaded or not when this file gets
---- evaluated. Also having to check if 'delimitMate' is installed on every
---- press of '<CR>' is not a good solution from performance point of view.
local has_delimitMate          = vim.g._using_delimitMate == 1
local has_minipairs, minipairs = pcall(require, 'mini-pairs')
local has_npairs, npairs       = pcall(require, 'nvim-autopairs')

---- Define what is "confirm popup selection"
local confirm_popup_selection = function() end
if has_compe then
  confirm_popup_selection = function(...)
    vim.fn['compe#confirm'](...)
  end
elseif has_completion then
  vim.g.completion_confirm_key = ''
  confirm_popup_selection = function(...)
    completion.confirmCompletion()
  end
end

---- Define what is "no popup action"
local nopopup_action = function() return escape('<CR>') end
if has_minipairs then
  nopopup_action = function()
    return minipairs.action_cr(minipairs.pairs_cr.i)
  end
elseif has_delimitMate then
  -- `<Plug>` symbol should be escaped in special way.
  -- Source: https://www.reddit.com/r/neovim/comments/kup1g0/feedkey_plug_in_lua_how/
  local plug = string.format('%c%c%c', 0x80, 253, 83)
  local delimitMateCR_command = plug .. 'delimitMateCR'
  nopopup_action = function() return delimitMateCR_command end
elseif has_npairs then
  nopopup_action = npairs.autopairs_cr
end

---- Define main function to be mapped to '<CR>'
_cr_action = function()
  if vim.fn.pumvisible() ~= 0 then
    local item_selected = vim.fn.complete_info()['selected'] ~= -1
    if item_selected then
      confirm_popup_selection(escape('<CR>'))
      return escape('<C-y>')
    else
      return escape('<C-y><CR>')
    end
  else
    return nopopup_action()
  end
end

vim.api.nvim_set_keymap(
  'i', '<CR>', 'v:lua._cr_action()',
  -- This shouldn't have `noremap = true` option in order to be usable with
  -- possible '<Plug>delimitMateCR' return
  {expr = true}
)
