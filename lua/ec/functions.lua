-- Helper table
local H = {}

-- Show Neoterm's active REPL, i.e. in which command will be executed when one
-- of `TREPLSend*` will be used
EC.print_active_neoterm = function()
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

-- Create scratch buffer and focus on it
EC.new_scratch_buffer = function()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(0, buf)
end

--- Generate plugin documentation using annotations in Lua files
---
--- This runs shell command with headless Neovim.
---
--- This requires:
--- - 'tjdevries/tree-sitter-lua' plugin (its `docgen` Lua plugin). It does not
---   need to be active in current session.
--- - Script that actually generates plugin documentation.
---
---@param script_path string: Path (relative to current working directory) to
--- script generating plugin documentation. Default: './scripts/gendocs.lua'.
EC.generate_plugin_doc = function(script_path)
  script_path = script_path or './scripts/gendocs.lua'
  local cmd_table = {
    'nvim --headless --noplugin',
    '-u ~/.config/nvim/misc/scripts/docgen_init.vim',
    [[-c 'luafile %s' -c 'qa']],
  }
  local cmd = string.format(table.concat(cmd_table, ' '), script_path)
  vim.cmd('!' .. cmd)
  vim.cmd('helptags ALL')
end

-- Make action for `<CR>` which respects completion and autopairs
--
-- Mapping should be done after everything else because `<CR>` can be
-- overridden by something else (notably 'mini-pairs.lua'). This should be an
-- expression mapping:
-- vim.api.nvim_set_keymap('i', '<CR>', 'v:lua._cr_action()', { expr = true })
--
-- Its current logic:
-- - If no popup menu is visible, use "no popup keys" getter. This is where
--   autopairs plugin should be used. Like with 'nvim-autopairs'
--   `get_nopopup_keys` is simply `npairs.autopairs_cr`.
-- - If popup menu is visible:
--     - If item is selected, execute "confirm popup" action and close
--       popup. This is where completion engine takes care of snippet expanding
--       and more.
--     - If item is not selected, close popup and execute '<CR>'. Reasoning
--       behind this is to explicitly select desired completion (currently this
--       is also done with one '<Tab>' keystroke).
EC.cr_action = function()
  if vim.fn.pumvisible() ~= 0 then
    local item_selected = vim.fn.complete_info()['selected'] ~= -1
    if item_selected then
      H.confirm_popup()
      return H.keys['ctrl-y']
    else
      return H.keys['ctrl-y_cr']
    end
  else
    return H.get_nopopup_keys()
  end
end

-- Helper data
---- Commonly used keys
H.keys = {
  ['cr'] = vim.api.nvim_replace_termcodes('<CR>', true, true, true),
  ['ctrl-y'] = vim.api.nvim_replace_termcodes('<C-y>', true, true, true),
  ['ctrl-y_cr'] = vim.api.nvim_replace_termcodes('<C-y><CR>', true, true, true),
}

-- Helper functions
---- Confirm popup selection with current completion plugin. Examples:
---- - nvim-cmp: `require('cmp').confirm`.
---- - nvim-compe: `function() vim.fn['compe#confirm'](H.keys.cr) end`
---- - completion-nvim: `require('completion').confirmCompletion` (don't forget
----   `vim.g.completion_confirm_key = ''`)
----
---- Current usage: 'mini.completion' doesn't require any confirmation.
H.confirm_popup = function() end

---- Get keys for expression mapping when no popup is visible. Examples:
---- - No autopairs plugin: `function() return H.keys.cr end`.
---- - nvim-autopairs: `require('nvim-autopairs').autopairs_cr`
H.get_nopopup_keys = function()
  return require('mini.pairs').cr()
end
