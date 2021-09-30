local function packadd(plugin)
  -- Add plugin
  vim.cmd(string.format([[packadd %s]], plugin))

  -- Try execute its configuration
  -- NOTE: configuration file should have the same name as plugin directory
  pcall(require, 'ec.configs.' .. plugin)
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

  -- Snippets engine
  packadd('luasnip')

  -- Documentation generator
  ---- Disable mappings, should be run before adding package
  vim.g.doge_enable_mappings = 0
  packadd('vim-doge')

  -- Test runner
  packadd('vim-test')

  ---- Helper to populate quickfix list with test results
  packadd('vim-dispatch')

  -- Filetype: csv
  packadd('rainbow_csv')

  -- Filetype: pandoc and rmarkdown
  ---- This option should be set before loading plugin to take effect. See
  ---- https://github.com/vim-pandoc/vim-pandoc/issues/342
  vim.g['pandoc#filetypes#pandoc_markdown'] = 0
  -- vim.cmd([[let g:pandoc#filetypes#pandoc_markdown = 0]])
  packadd('vim-pandoc')
  packadd('vim-pandoc-syntax')
  packadd('vim-rmarkdown')

  -- Filetype: markdown
  packadd('vim-markdown')

  -- Markdown preview (has rather big disk size usage, around 50M)
  packadd('markdown-preview')
end

-- Do plugin hooks (find a better way to do this; maybe after custom update)
function _G.plugin_hooks()
  -- Ensure most recent help tags
  vim.cmd('helptags ALL')

  if vim.fn.exists('vscode') ~= 1 then
    -- Ensure most recent treesitter parsers
    vim.cmd('silent TSUpdate')

    -- -- Ensure most recent 'vim-doge'
    -- vim.cmd('silent call doge#install()')

    -- -- Ensure most recent markdown-preview
    -- -- NOTE: this worked before moving to 'pack/plugins/opt' structure.  After
    -- -- that, doing manual installation worked instead (`cd app | yarn
    -- -- install`, which needs `yarn` installed).
    -- vim.cmd('call mkdp#util#install()')
  end

  -- Destroy this function
  _G.plugin_hooks = nil
end

vim.cmd([[autocmd VimEnter * ++once lua vim.defer_fn(_G.plugin_hooks, 15)]])
