-- Helpers
local escape = function(s)
  return vim.api.nvim_replace_termcodes(s, true, true, true)
end

-- Setup `<CR>` key. Its current logic:
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
local has_npairs, npairs         = pcall(require, 'nvim-autopairs')

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
local nopopup_action = function() end
if has_npairs then
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
  {expr = true , noremap = true}
)
