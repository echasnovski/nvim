-- Clone 'mini.nvim' manually in a way that it gets managed with 'mini.deps'
local path_package = vim.fn.stdpath('data') .. '/site/'
local mini_path = path_package .. 'pack/deps/opt/mini.nvim'
if not vim.loop.fs_stat(mini_path) then
  vim.cmd('echo "Installing `mini.nvim`" | redraw')
  local clone_cmd = { 'git', 'clone', '--filter=blob:none', 'https://github.com/echasnovski/mini.nvim', mini_path }
  vim.fn.system(clone_cmd)
end

-- Make 'mini.nvim' reachable in current session
vim.cmd('packadd mini.nvim')

-- Set up 'mini.deps' (customize to your liking)
require('mini-dev.deps').setup({ path = { package = path_package } })

-- Use 'mini.deps'. `now()` and `later()` are helpers for a safe two-stage
-- startup and are optional.
local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later

-- Safely execute immediately
now(function()
  vim.o.termguicolors = true
  vim.cmd('colorscheme randomhue')
end)
now(function()
  require('mini.notify').setup()
  vim.notify = require('mini.notify').make_notify()
end)
now(function() require('mini.statusline').setup() end)

-- Safely execute later
later(function() require('mini.operators').setup() end)

-- Use external plugins with `add()`
now(function()
  -- Add to current session (install if absent)
  add('nvim-tree/nvim-web-devicons')
  require('nvim-web-devicons').setup()
end)

later(function()
  -- Supply dependencies near target plugin
  add({ source = 'neovim/nvim-lspconfig', depends = { 'williamboman/mason.nvim' } })
end)

-- Utilize plugin spec to install separate plugins based on Nvim version
later(function()
  local is_010 = vim.fn.has('nvim-0.10') == 1
  local name = is_010 and 'nvim-treesitter-main' or 'nvim-treesitter'
  local checkout = is_010 and 'main' or 'master'
  add({
    source = 'nvim-treesitter/nvim-treesitter',
    name = name,
    checkout = checkout,
    monitor = checkout,
    hooks = { post_checkout = function() vim.cmd('TSUpdate') end },
  })
end)
