local nvim_tree = require('nvim-tree')
local api = require('nvim-tree.api')

-- Define Custom functions to simulate ranger's "going in" and "going out"
-- (might break if 'nvim-tree' is major refactored)
local get_node = require('nvim-tree.lib').get_node_at_cursor
local has_children = function(node) return type(node.nodes) == 'table' and vim.tbl_count(node.nodes) > 0 end

local key_down = vim.api.nvim_replace_termcodes('<Down>', true, true, true)

local nvim_tree_go_in = function()
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
  api.node.open.edit()

  -- Don't do anything if tree is not in focus
  if vim.api.nvim_buf_get_option(0, 'filetype') ~= 'NvimTree' then return end

  -- Go to first child node if it is a directory with children
  -- Get new node because before entries appear after first 'edit'
  node = get_node()
  if has_children(node) then vim.fn.feedkeys(key_down) end
end

local nvim_tree_go_out = function()
  local node = get_node()

  if node.name == '..' then
    require('nvim-tree.lib').dir_up()
    return
  end

  api.node.navigate.parent_close()
end

--stylua: ignore
local on_attach = function(bufnr)
  local opts = function(desc)
    return { desc = 'nvim-tree: ' .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
  end

  -- Subset of default mappings
  vim.keymap.set('n', '<',     api.node.navigate.sibling.prev, opts('Previous Sibling'))
  vim.keymap.set('n', '<CR>',  api.node.open.edit,             opts('Open'))
  vim.keymap.set('n', '<Tab>', api.node.open.preview,          opts('Open Preview'))
  vim.keymap.set('n', '>',     api.node.navigate.sibling.next, opts('Next Sibling'))
  vim.keymap.set('n', 'a',     api.fs.create,                  opts('Create'))
  vim.keymap.set('n', 'd',     api.fs.remove,                  opts('Delete'))
  vim.keymap.set('n', 'g?',    api.tree.toggle_help,           opts('Help'))
  vim.keymap.set('n', 'o',     api.node.open.no_window_picker, opts('Open: No Window Picker'))
  vim.keymap.set('n', 'q',     api.tree.close,                 opts('Close'))
  vim.keymap.set('n', 'r',     api.fs.rename,                  opts('Rename'))
  vim.keymap.set('n', 'R',     api.tree.reload,                opts('Refresh'))

  -- Custom mappings
  vim.keymap.set('n', 'h', nvim_tree_go_out, opts('Go out'))
  vim.keymap.set('n', 'l', nvim_tree_go_in,  opts('Go in'))
end
-- Setup plugin
nvim_tree.setup({
  on_attach = on_attach,
  hijack_cursor = true,
  update_focused_file = { enable = false },
  git = { enable = false },
  respect_buf_cwd = true,
  view = {
    width = 40,
  },
  renderer = {
    add_trailing = true,
    indent_markers = {
      enable = true,
      icons = { item = '├' },
    },
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
