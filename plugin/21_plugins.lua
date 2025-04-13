local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later
local now_if_args = vim.fn.argc(-1) > 0 and now or later

-- Tree-sitter (advanced syntax parsing, highlighting, textobjects) ===========
now_if_args(function()
  add({
    source = 'nvim-treesitter/nvim-treesitter',
    checkout = 'master',
    hooks = { post_checkout = function() vim.cmd('TSUpdate') end },
  })
  add('nvim-treesitter/nvim-treesitter-textobjects')

  --stylua: ignore
  local ensure_installed = {
    'bash',       'c',     'cpp',   'css',  'html',
    'javascript', 'json',  'julia', 'php',  'python',
    'r',          'regex', 'rst',   'rust', 'toml', 'tsx', 'yaml',
  }

  require('nvim-treesitter.configs').setup({
    ensure_installed = ensure_installed,
    highlight = { enable = true },
    incremental_selection = { enable = false },
    textobjects = { enable = false },
    indent = { enable = false },
  })

  -- Disable injections in 'lua' language
  local ts_query = require('vim.treesitter.query')
  local ts_query_set = vim.fn.has('nvim-0.9') == 1 and ts_query.set or ts_query.set_query
  ts_query_set('lua', 'injections', '')
end)

-- Install LSP/formatting/linter executables ==================================
later(function()
  add('williamboman/mason.nvim')
  require('mason').setup()
end)

-- Formatting =================================================================
later(function()
  add('stevearc/conform.nvim')

  require('conform').setup({
    -- Map of filetype to formatters
    formatters_by_ft = {
      javascript = { 'prettier' },
      json = { 'prettier' },
      lua = { 'stylua' },
      python = { 'black' },
      r = { 'my_styler' },
    },

    formatters = {
      my_styler = {
        command = 'R',
        -- A list of strings, or a function that returns a list of strings
        -- Return a single string instead of a list to run the command in a shell
        args = { '-s', '-e', 'styler::style_file(commandArgs(TRUE)[1])', '--args', '$FILENAME' },
        stdin = false,
      },
    },
  })
end)

-- Language server configurations =============================================
later(function()
  -- Enable LSP only on Neovim>=0.11 as it introduced `vim.lsp.config`
  if vim.fn.has('nvim-0.11') == 0 then return end

  add('neovim/nvim-lspconfig')

  -- All language servers are expected to be installed with 'mason.vnim'
  vim.lsp.enable({
    'clangd',
    'emmet_ls',
    'gopls',
    'intelephense',
    'lua_ls',
    'pyright',
    'r_language_server',
    'rust_analyzer',
    'ts_ls',
  })
end)

-- Better built-in terminal ===================================================
later(function()
  add('kassio/neoterm')

  -- Enable bracketed paste
  vim.g.neoterm_bracketed_paste = 1

  -- Default python REPL
  vim.g.neoterm_repl_python = 'ipython'

  -- Default R REPL
  vim.g.neoterm_repl_r = 'radian'

  -- Don't add extra call to REPL when sending
  vim.g.neoterm_direct_open_repl = 1

  -- Open terminal to the right by default
  vim.g.neoterm_default_mod = 'vertical'

  -- Go into insert mode when terminal is opened
  vim.g.neoterm_autoinsert = 1

  -- Scroll to recent command when it is executed
  vim.g.neoterm_autoscroll = 1

  -- Don't automap keys
  pcall(vim.keymap.del, 'n', ',tt')

  -- Change default shell to zsh (if it is installed)
  if vim.fn.executable('zsh') == 1 then vim.g.neoterm_shell = 'zsh' end
end)

-- Snippet collection =========================================================
later(function() add('rafamadriz/friendly-snippets') end)

-- Documentation generator ====================================================
later(function()
  add('danymat/neogen')
  require('neogen').setup({
    snippet_engine = 'mini',
    languages = {
      lua = { template = { annotation_convention = 'emmylua' } },
      python = { template = { annotation_convention = 'numpydoc' } },
    },
  })
end)

-- Test runner ================================================================
later(function()
  add({ source = 'vim-test/vim-test', depends = { 'tpope/vim-dispatch' } })
  vim.cmd([[let test#strategy = 'neoterm']])
  vim.cmd([[let test#python#runner = 'pytest']])
end)

-- Filetype: csv ==============================================================
later(function()
  vim.g.disable_rainbow_csv_autodetect = true
  add('mechatroner/rainbow_csv')
end)

-- Filetype: markdown =========================================================
later(function()
  local build = function() vim.fn['mkdp#util#install']() end
  add({
    source = 'iamcco/markdown-preview.nvim',
    hooks = {
      post_install = function() later(build) end,
      post_checkout = build,
    },
  })

  -- Do not close the preview tab when switching to other buffers
  vim.g.mkdp_auto_close = 0
end)

-- Filetype: rmarkdown ========================================================
later(function()
  -- This option should be set before loading plugin to take effect. See
  -- https://github.com/vim-pandoc/vim-pandoc/issues/342
  vim.g['pandoc#filetypes#pandoc_markdown'] = 0

  add({
    source = 'vim-pandoc/vim-rmarkdown',
    depends = { 'vim-pandoc/vim-pandoc', 'vim-pandoc/vim-pandoc-syntax' },
  })

  -- Show raw symbols
  vim.g['pandoc#syntax#conceal#use'] = 0

  -- Folding
  vim.g['pandoc#folding#fold_yaml'] = 1
  vim.g['pandoc#folding#fold_fenced_codeblocks'] = 1
  vim.g['pandoc#folding#fastfolds'] = 1
  vim.g['pandoc#folding#fdc'] = 0
end)

-- -- Popular color schemes for testing ==========================================
-- later(function()
--   add('folke/tokyonight.nvim')
--   add({ source = 'catppuccin/nvim', name = 'catppuccin-nvim' })
--   add('rebelot/kanagawa.nvim')
--   add('sainnhe/everforest')
--   add({ source = 'rose-pine/neovim', name = 'rose-pine' })
--   add('bluz71/vim-moonfly-colors')
--   add('ellisonleao/gruvbox.nvim')
--   add('craftzdog/solarized-osaka.nvim')
--   add('navarasu/onedark.nvim')
--   add('projekt0n/github-nvim-theme')
--   add('marko-cerovac/material.nvim')
--   require('material').setup({ plugins = { 'mini' } })
--   add('EdenEast/nightfox.nvim')
--   add('scottmckendry/cyberdream.nvim')
--   add('Shatur/neovim-ayu')
-- end)
