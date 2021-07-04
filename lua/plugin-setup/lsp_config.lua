-- Currently used language servers:
-- - r_language_server for R
-- - pyright for Python
-- - sumneko_lua for Lua

local has_lspconfig, nvim_lsp = pcall(require, 'lspconfig')
if not has_lspconfig then return end

-- local has_completion, completion = pcall(require, 'completion')

local on_attach = function(client, bufnr)
  -- if has_completion then completion.on_attach() end

  local function buf_set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
  local function buf_set_option(...) vim.api.nvim_buf_set_option(bufnr, ...) end

  buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

  -- Mappings.
  local opts = { noremap=true, silent=true }
  buf_set_keymap('n', '<leader>lR', '<cmd>lua vim.lsp.buf.references()<CR>', opts)
  buf_set_keymap('n', '<leader>la', '<cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
  buf_set_keymap('n', '<leader>ld', '<cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>', opts)
  buf_set_keymap('n', '<leader>li', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)
  buf_set_keymap('n', '<leader>lj', '<cmd>lua vim.lsp.diagnostic.goto_next()<CR>', opts)
  buf_set_keymap('n', '<leader>lk', '<cmd>lua vim.lsp.diagnostic.goto_prev()<CR>', opts)
  buf_set_keymap('n', '<leader>lr', '<cmd>lua vim.lsp.buf.rename()<CR>', opts)
  buf_set_keymap('n', '<leader>ls', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
  -- buf_set_keymap('n', '<leader>lD', '<cmd>lua vim.lsp.diagnostic.set_loclist()<CR>', opts)
  -- buf_set_keymap('n', '<space>D', '<cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
  -- buf_set_keymap('n', '<space>wa', '<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>', opts)
  -- buf_set_keymap('n', '<space>wl', '<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>', opts)
  -- buf_set_keymap('n', '<space>wr', '<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>', opts)
  -- buf_set_keymap('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<CR>', opts)
  -- buf_set_keymap('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<CR>', opts)

  -- Currently formatting is handled with 'Neoformat' plugin
  -- -- Set some keybinds conditional on server capabilities
  -- if client.resolved_capabilities.document_formatting then
  --   buf_set_keymap('n', '<leader>lf', '<cmd>lua vim.lsp.buf.formatting()<CR>', opts)
  -- elseif client.resolved_capabilities.document_range_formatting then
  --   buf_set_keymap('n', '<leader>lF', '<cmd>lua vim.lsp.buf.formatting()<CR>', opts)
  -- end
end

vim.lsp.handlers['textDocument/publishDiagnostics'] = vim.lsp.with(
    vim.lsp.diagnostic.on_publish_diagnostics, {
      -- Show gutter sings
      signs = {
        -- With highest priority
        priority = 9999,
        -- Only for warnings and errors
        severity_limit = 'Warning'
      },
      -- Show virtual text only for errors
      virtual_text = { severity_limit = 'Error'},
      -- Don't update diagnostics when typing
      update_in_insert = false,
    }
  )

-- -- Disable diagnostics
-- vim.lsp.callbacks['textDocument/publishDiagnostics'] = function() end

-- Setup well-defined servers
local servers = {'pyright', 'r_language_server'}
for _, lsp in ipairs(servers) do
  -- Map buffer local keybindings when the language server attaches
  nvim_lsp[lsp].setup { on_attach = on_attach }
end

-- Lua language server
-- Should be buildtand run manually:
-- https://github.com/sumneko/lua-language-server/wiki/Build-and-Run-(Standalone)
-- Should be cloned into '.config/nvim' as 'lua-language-server' directory.
-- Code structure is taken from https://www.chrisatmachine.com/Neovim/28-neovim-lua-development/
local sumneko_root = vim.fn.expand('$HOME/.config/nvim/lua-language-server')
if vim.fn.isdirectory(sumneko_root) == 1 then
  local sumneko_binary = ''
  if vim.fn.has('mac') == 1 then
    sumneko_binary = sumneko_root .. '/bin/macOS/lua-language-server'
  elseif vim.fn.has('unix') == 1 then
    sumneko_binary = sumneko_root .. '/bin/Linux/lua-language-server'
  else
    print('Unsupported system for sumneko')
  end

  nvim_lsp.sumneko_lua.setup {
    cmd = {sumneko_binary, '-E', sumneko_root .. '/main.lua'},
    on_attach = on_attach,
    settings = {
      Lua = {
        runtime = {
          -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
          version = 'LuaJIT',
          -- Setup your lua path
          path = vim.split(package.path, ';')
        },
        diagnostics = {
          -- Get the language server to recognize the `vim` global
          globals = {'vim'}
        },
        workspace = {
          -- Make the server aware of Neovim runtime files
          library = {[vim.fn.expand('$VIMRUNTIME/lua')] = true, [vim.fn.expand('$VIMRUNTIME/lua/vim/lsp')] = true}
        }
      }
    }
  }
end
