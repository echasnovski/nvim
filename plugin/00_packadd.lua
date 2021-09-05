local function packadd(plugin)
  vim.cmd(string.format([[packadd %s]], plugin))
end

-- More text objects
packadd('targets')

if vim.fn.exists('vscode') ~= 1 then
  -- Common dependency for Lua plugins
  packadd('plenary')

  -- Colorful icons
  packadd('nvim-web-devicons')

  -- Fuzzy finder
  packadd('telescope')

  -- Treesitter: advanced syntax parsing. Add highlighting and text objects.
  packadd('nvim-treesitter')
  packadd('nvim-treesitter-textobjects')

  -- Git integration
  packadd('gitsigns')

  -- Language server configurations
  packadd('nvim-lspconfig')

  -- File tree explorer
  packadd('nvim-tree')

  -- Usage of external actions (formatting, diagnostics, etc.)
  packadd('null-ls')

  -- Enhanced diagnostics lists
  packadd('trouble')

  -- Todo (and other notes) highlighting
  packadd('todo-comments')

  -- Display of text colors
  packadd('nvim-colorizer')
end

-- Do plugin hooks (find a better way to do this; maybe after custom update)
function _G.plugin_hooks()
  -- Ensure most recent help tags
  vim.cmd('helptags ALL')

  -- Ensure most recent treesitter parsers
  vim.cmd('silent TSUpdate')

  -- Destroy this function
  _G.plugin_hooks = nil
end

vim.cmd([[autocmd VimEnter * ++once lua vim.defer_fn(_G.plugin_hooks, 15)]])
