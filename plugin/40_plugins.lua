local add = vim.pack.add
local now_if_args, later = _G.Config.now_if_args, MiniDeps.later

-- Tree-sitter ================================================================
now_if_args(function()
  local ts_update = function() vim.cmd('TSUpdate') end
  _G.Config.on_packchanged('nvim-treesitter', { 'update' }, ts_update, 'Update tree-sitter parsers')
  add({
    'https://github.com/nvim-treesitter/nvim-treesitter',
    { src = 'https://github.com/nvim-treesitter/nvim-treesitter-textobjects', version = 'main' },
  })

  -- Ensure installed
  --stylua: ignore
  local ensure_languages = {
    'bash', 'c',          'cpp',  'css',   'diff', 'go',
    'html', 'javascript', 'json', 'julia', 'nu',   'php', 'python',
    'r',    'regex',      'rst',  'rust',  'toml', 'tsx', 'typescript', 'yaml',
  }
  local isnt_installed = function(lang) return #vim.api.nvim_get_runtime_file('parser/' .. lang .. '.*', false) == 0 end
  local to_install = vim.tbl_filter(isnt_installed, ensure_languages)
  if #to_install > 0 then require('nvim-treesitter').install(to_install) end

  -- Ensure enabled
  local filetypes = vim.iter(ensure_languages):map(vim.treesitter.language.get_filetypes):flatten():totable()
  vim.list_extend(filetypes, { 'markdown', 'quarto' })
  local ts_start = function(ev) vim.treesitter.start(ev.buf) end
  _G.Config.new_autocmd('FileType', filetypes, ts_start, 'Ensure enabled tree-sitter')

  -- Miscellaneous adjustments
  vim.treesitter.language.register('markdown', 'quarto')
  vim.filetype.add({
    extension = { qmd = 'quarto', Qmd = 'quarto' },
  })
end)

-- Install LSP/formatting/linter executables ==================================
later(function()
  add({ 'https://github.com/mason-org/mason.nvim' })
  require('mason').setup()
end)

-- Formatting =================================================================
later(function()
  add({ 'https://github.com/stevearc/conform.nvim' })

  require('conform').setup({
    -- Map of filetype to formatters
    formatters_by_ft = {
      javascript = { 'prettier' },
      json = { 'prettier' },
      lua = { 'stylua' },
      python = { 'black' },
      r = { 'air' },
    },
  })
end)

-- Language server configurations =============================================
later(function()
  -- Enable LSP only on Neovim>=0.11 as it introduced `vim.lsp.config`
  if vim.fn.has('nvim-0.11') == 0 then return end

  add({ 'https://github.com/neovim/nvim-lspconfig' })

  -- Do not enable R language server in Quarto files
  vim.lsp.config('r_language_server', { filetypes = { 'r', 'rmd' } })

  -- All language servers are expected to be installed with 'mason.nvim'
  vim.lsp.enable({
    -- 'air',
    'clangd',
    'emmet_ls',
    'gopls',
    'intelephense',
    'lua_ls',
    'nushell',
    'pyright',
    'r_language_server',
    'rust_analyzer',
    'ts_ls',
  })
end)

-- Better built-in terminal ===================================================
later(function()
  add({ 'https://github.com/kassio/neoterm' })

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
  vim.g.neoterm_shell = vim.fn.executable('nu') == 1 and 'nu' or (vim.fn.executable('zsh') == 1 and 'zsh' or 'bash')
end)

-- Snippet collection =========================================================
later(function() add({ 'https://github.com/rafamadriz/friendly-snippets' }) end)

-- Test runner ================================================================
later(function()
  add({
    'https://github.com/tpope/vim-dispatch',
    'https://github.com/vim-test/vim-test',
  })
  vim.cmd([[let test#strategy = 'neoterm']])
  vim.cmd([[let test#python#runner = 'pytest']])
end)

-- Filetype: markdown =========================================================
later(function()
  local build = function() vim.fn['mkdp#util#install']() end
  _G.Config.on_packchanged('markdown-preview.nvim', { 'install', 'update' }, build, 'Build markdown-preview')
  add({ 'https://github.com/iamcco/markdown-preview.nvim' })

  -- Do not close the preview tab when switching to other buffers
  vim.g.mkdp_auto_close = 0
end)

-- -- Popular color schemes for testing ==========================================
-- later(function()
--   add({
--     'https://github.com/folke/tokyonight.nvim',
--     { src = 'https://github.com/catppuccin/nvim', name = 'catppuccin-nvim' },
--     'https://github.com/rebelot/kanagawa.nvim',
--     'https://github.com/sainnhe/everforest',
--     { src = 'https://github.com/rose-pine/neovim', name = 'rose-pine' },
--     'https://github.com/bluz71/vim-moonfly-colors',
--     'https://github.com/ellisonleao/gruvbox.nvim',
--     'https://github.com/craftzdog/solarized-osaka.nvim',
--     'https://github.com/navarasu/onedark.nvim',
--     'https://github.com/projekt0n/github-nvim-theme',
--     'https://github.com/marko-cerovac/material.nvim',
--     'https://github.com/EdenEast/nightfox.nvim',
--     'https://github.com/scottmckendry/cyberdream.nvim',
--     'https://github.com/Shatur/neovim-ayu',
--     'https://github.com/NvChad/base46',
--   })
--   require('material').setup({ plugins = { 'mini' } })
-- end)
