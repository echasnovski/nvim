local has_nvim_tree, nvim_tree = pcall(require, 'nvim-tree')
if not has_nvim_tree then return end

vim.g.nvim_tree_add_trailing = 1
vim.g.nvim_tree_auto_resize = 0
vim.g.nvim_tree_follow = 0
vim.g.nvim_tree_indent_markers = 1
vim.g.nvim_tree_respect_buf_cwd = 1
vim.g.nvim_tree_show_icons = {
  git = 0, -- Currently causes slowdown
  folders = 1,
  files = 1,
}
vim.g.nvim_tree_width = 40
vim.g.nvim_tree_quit_on_open = 1

-- Makes everything nicely aligned
vim.g.nvim_tree_icons = { default = '' }

-- Custom functions to simulate ranger's "going in" and "going out" (might
-- break if 'nvim-tree' is major refactored)
local get_node = require('nvim-tree.lib').get_node_at_cursor
local has_children = function(node)
  return type(node.entries) == 'table' and vim.tbl_count(node.entries) > 0
end

local key_down = vim.api.nvim_replace_termcodes('<Down>', true, true, true)

function _G.nvim_tree_go_in()
  local node = get_node()

  -- Don't go up if cursor is placed on '..'
  if node.name == '..' then
    vim.fn.feedkeys(key_down)
    return
  end

  -- Go inside if it is already an opened directory with children
  if has_children(node) and node.open == true then
    vim.fn.feedkeys(key_down)
    return
  end

  -- Peform 'edit' action
  nvim_tree.on_keypress('edit')

  -- Don't do anything if tree is not in focus
  if vim.api.nvim_buf_get_option(0, 'filetype') ~= 'NvimTree' then
    return
  end

  -- Go to first child node if it is a directory with children
  -- Get new node because before entries appear after first 'edit'
  local node = get_node()
  if has_children(node) then
    vim.fn.feedkeys(key_down)
  end
end

function _G.nvim_tree_go_out()
  local node = get_node()

  if node.name == '..' then
    require('nvim-tree.lib').dir_up()
    return
  end

  nvim_tree.on_keypress('close_node')
end

vim.g.nvim_tree_bindings = {
  { key = 'l', cb = '<cmd>lua _G.nvim_tree_go_in()<CR>' },
  { key = 'h', cb = '<cmd>lua _G.nvim_tree_go_out()<CR>' },
}
