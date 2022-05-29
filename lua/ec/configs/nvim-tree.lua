local nvim_tree = require('nvim-tree')

-- Define Custom functions to simulate ranger's "going in" and "going out"
-- (might break if 'nvim-tree' is major refactored)
local get_node = require('nvim-tree.lib').get_node_at_cursor
local has_children = function(node)
  return type(node.nodes) == 'table' and vim.tbl_count(node.nodes) > 0
end

local key_down = vim.api.nvim_replace_termcodes('<Down>', true, true, true)

function EC.nvim_tree_go_in()
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
  node = get_node()
  if has_children(node) then
    vim.fn.feedkeys(key_down)
  end
end

function EC.nvim_tree_go_out()
  local node = get_node()

  if node.name == '..' then
    require('nvim-tree.lib').dir_up()
    return
  end

  nvim_tree.on_keypress('close_node')
end

-- Setup plugin
nvim_tree.setup({
  hijack_cursor = true,
  update_focused_file = { enable = false },
  git = { enable = false },
  respect_buf_cwd = true,
  view = {
    width = 40,
    mappings = {
      custom_only = false,
      list = {
        { key = 'l', cb = '<cmd>lua EC.nvim_tree_go_in()<CR>' },
        { key = 'h', cb = '<cmd>lua EC.nvim_tree_go_out()<CR>' },
      },
    },
  },
  renderer = {
    add_trailing = true,
    indent_markers = { enable = true },
    icons = {
      show = {
        git = false, -- Currently causes slowdown
        folder = true,
        file = true,
      },
      glyphs = { default = '' },
    },
  },
  actions = {
    open_file = {
      quit_on_open = true,
    },
  },
})
