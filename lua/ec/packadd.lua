-- Source plugin and its configuration immediately
-- @param plugin String with name of plugin as subdirectory in 'pack'
local packadd = function(plugin)
  -- Add plugin
  vim.cmd(string.format([[packadd %s]], plugin))

  -- Try execute its configuration
  -- NOTE: configuration file should have the same name as plugin directory
  pcall(require, 'ec.configs.' .. plugin)
end

-- Defer plugin source right after Vim is loaded
--
-- This reduces time before a fully functional start screen is shown. Use this
-- for plugins that are not directly related to startup process.
--
-- @param plugin String with name of plugin as subdirectory in 'pack'
local packadd_defer = function(plugin)
  vim.defer_fn(function() packadd(plugin) end, 0)
end

-- Collection of minimal and fast Lua modules
packadd('mini')

-- -- More text objects
-- packadd_defer('targets')

-- Align text
packadd_defer('vim-lion')

-- Wrap function arguments
packadd_defer('vim-argwrap')

-- Swap function arguments (and define better 'argument' text object)
packadd_defer('sideways')

-- Exchange regions
packadd_defer('vim-exchange')

-- Pairs of handy bracket mappings
packadd_defer('vim-unimpaired')

if vim.fn.exists('vscode') ~= 1 then
  -- Common dependency for Lua plugins
  packadd('plenary')

  -- Updater of current working directory
  packadd('vim-rooter')

  -- Colorful icons
  packadd('nvim-web-devicons')

  -- Treesitter: advanced syntax parsing. Add highlighting and text objects.
  -- NOTE: when opening file directly (`nvim <file>`) defered initialization
  -- results into highlighting change right after opening. If it bothers,
  -- change to `packadd()`.
  packadd_defer('nvim-treesitter')
  packadd_defer('nvim-treesitter-textobjects')

  -- Fuzzy finder
  packadd_defer('telescope')

  -- Show keybindings
  packadd_defer('which-key')

  -- Interact with git
  -- packadd_defer('vim-fugitive')

  -- Interact with commits
  -- packadd_defer('gv')

  -- Interact with hunks
  packadd_defer('gitsigns')

  -- Language server configurations
  packadd_defer('nvim-lspconfig')

  -- File tree explorer
  packadd_defer('nvim-tree')

  -- Tweak Neovim's terminal to be more REPL-aware
  packadd_defer('neoterm')

  -- Usage of external actions (formatting, diagnostics, etc.)
  packadd_defer('null-ls')

  -- Todo (and other notes) highlighting
  packadd_defer('todo-comments')

  -- Display of text colors
  packadd_defer('nvim-colorizer')

  -- Visualize undo tree
  packadd_defer('undotree')

  -- Snippets engine
  packadd_defer('luasnip')

  -- Documentation generator
  packadd_defer('neogen')

  -- Test runner
  packadd_defer('vim-test')

  -- Helper to populate quickfix list with test results
  packadd_defer('vim-dispatch')

  -- Filetype: csv
  packadd_defer('rainbow_csv')

  -- Filetype: pandoc and rmarkdown
  -- This option should be set before loading plugin to take effect. See
  -- https://github.com/vim-pandoc/vim-pandoc/issues/342
  vim.g['pandoc#filetypes#pandoc_markdown'] = 0
  -- vim.cmd([[let g:pandoc#filetypes#pandoc_markdown = 0]])
  packadd_defer('vim-pandoc')
  packadd_defer('vim-pandoc-syntax')
  packadd_defer('vim-rmarkdown')

  -- Markdown preview (has rather big disk size usage, around 50M)
  -- NOTE: this exact name is important to make plugin work
  packadd_defer('markdown-preview.nvim')
end

-- Do plugin hooks (find a better way to do this; maybe after custom update)
local plugin_hooks = function()
  -- Ensure most recent help tags
  vim.cmd('helptags ALL')

  if vim.fn.exists('vscode') ~= 1 then
    -- Ensure most recent treesitter parsers
    vim.cmd('silent TSUpdate')

    -- -- Ensure most recent markdown-preview
    -- -- NOTE: this worked before moving to 'pack/plugins/opt' structure.  After
    -- -- that, doing manual installation worked instead (`cd app | yarn
    -- -- install`, which needs `yarn` installed).
    -- vim.cmd('call mkdp#util#install()')
  end
end

vim.defer_fn(plugin_hooks, 0)
