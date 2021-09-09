local function packadd(plugin)
  vim.cmd(string.format([[packadd %s]], plugin))
end

-- More text objects
packadd('targets')

-- Align text
packadd('vim-lion')

-- Wrap function arguments
packadd('vim-argwrap')

-- Swap function arguments (and define better 'argument' text object)
packadd('sideways')

-- Exchange regions
packadd('vim-exchange')

-- Pairs of handy bracket mappings
packadd('vim-unimpaired')

if vim.fn.exists('vscode') ~= 1 then
  -- Common dependency for Lua plugins
  packadd('plenary')

  -- Colorful icons
  packadd('nvim-web-devicons')

  -- Fuzzy finder
  packadd('telescope')

  -- Show keybindings
  packadd('which-key')

  -- Treesitter: advanced syntax parsing. Add highlighting and text objects.
  packadd('nvim-treesitter')
  packadd('nvim-treesitter-textobjects')

  -- Git integration
  ---- Interact with git
  packadd('vim-fugitive')

  ---- Interact with commits
  packadd('gv')

  ---- Interact with hunks
  packadd('gitsigns')

  -- Language server configurations
  packadd('nvim-lspconfig')

  -- File tree explorer
  packadd('nvim-tree')

  -- Start screen and session manager
  packadd('vim-startify')

  -- Updater of current working directory
  packadd('vim-rooter')

  -- Tweak Neovim's terminal to be more REPL-aware
  packadd('neoterm')

  -- Usage of external actions (formatting, diagnostics, etc.)
  packadd('null-ls')

  -- Enhanced diagnostics lists
  packadd('trouble')

  -- Todo (and other notes) highlighting
  packadd('todo-comments')

  -- Display of text colors
  packadd('nvim-colorizer')

  -- Visualize undo tree
  packadd('undotree')

  -- Snippets
  ---- Engine
  packadd('luasnip')

  ---- Collection
  packadd('friendly-snippets')
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
