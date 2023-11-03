-- Source plugin and its configuration immediately
-- @param plugin String with name of plugin as subdirectory in 'pack'
local packadd = function(plugin)
  -- Add plugin. Using `packadd!` during startup is better for initialization
  -- order (see `:h load-plugins`). Use `packadd` otherwise to also force
  -- 'plugin' scripts to be executed right away.
  -- local command = vim.v.vim_did_enter == 1 and 'packadd' or 'packadd!'
  local command = 'packadd'
  vim.cmd(string.format([[%s %s]], command, plugin))

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
local packadd_later = function(plugin)
  EC.later(function() packadd(plugin) end)
end

-- Collection of minimal and fast Lua modules
EC.now(function() packadd('mini') end)

if vim.fn.exists('vscode') ~= 1 then
  -- Colorful icons
  packadd('nvim-web-devicons')

  -- -- Common dependency for Lua plugins
  packadd_later('plenary')

  -- Treesitter: advanced syntax parsing. Add highlighting and text objects.
  -- NOTE: when opening file directly (`nvim <file>`) defered initialization
  -- results into highlighting change right after opening. If it bothers,
  -- change to `packadd()`.
  packadd_later('nvim-treesitter')
  packadd_later('nvim-treesitter-textobjects')

  -- Fuzzy finder
  packadd_later('telescope')

  -- Interact with hunks
  packadd_later('gitsigns')

  -- Language server configurations
  packadd_later('nvim-lspconfig')

  -- Tweak Neovim's terminal to be more REPL-aware
  packadd_later('neoterm')

  -- Usage of external actions (formatting, diagnostics, etc.)
  packadd_later('null-ls')

  -- Snippets engine
  packadd_later('luasnip')

  -- Documentation generator
  packadd_later('neogen')

  -- Test runner
  packadd_later('vim-test')

  -- Helper to populate quickfix list with test results
  packadd_later('vim-dispatch')

  -- Filetype: csv
  vim.g.disable_rainbow_csv_autodetect = true
  packadd_later('rainbow_csv')

  -- Filetype: pandoc and rmarkdown
  -- This option should be set before loading plugin to take effect. See
  -- https://github.com/vim-pandoc/vim-pandoc/issues/342
  vim.g['pandoc#filetypes#pandoc_markdown'] = 0
  -- vim.cmd([[let g:pandoc#filetypes#pandoc_markdown = 0]])
  packadd_later('vim-pandoc')
  packadd_later('vim-pandoc-syntax')
  packadd_later('vim-rmarkdown')

  -- Markdown preview (has rather big disk size usage, around 50M)
  -- NOTE: this exact name is important to make plugin work
  packadd_later('markdown-preview.nvim')
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

EC.later(plugin_hooks)
