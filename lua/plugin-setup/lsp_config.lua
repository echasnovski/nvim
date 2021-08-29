-- Currently used language servers:
-- - r_language_server for R
-- - pyright for Python
-- - sumneko_lua for Lua

local has_lspconfig, lspconfig = pcall(require, 'lspconfig')
if not has_lspconfig then
  return
end

-- Preconfiguration
local on_attach_custom = function(_, bufnr)
  local function buf_set_keymap(keys, action)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', keys, action, { noremap = true })
  end
  local function buf_set_option(name, value)
    vim.api.nvim_buf_set_option(bufnr, name, value)
  end

  buf_set_option('omnifunc', 'v:lua.MiniCompletion.completefunc_lsp')

  -- Mappings.
  buf_set_keymap('<leader>lR', '<cmd>lua vim.lsp.buf.references()<CR>')
  buf_set_keymap('<leader>la', '<cmd>lua vim.lsp.buf.signature_help()<CR>')
  buf_set_keymap('<leader>ld', '<cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>')
  buf_set_keymap('<leader>li', '<cmd>lua vim.lsp.buf.hover()<CR>')
  buf_set_keymap('<leader>lj', '<cmd>lua vim.lsp.diagnostic.goto_next()<CR>')
  buf_set_keymap('<leader>lk', '<cmd>lua vim.lsp.diagnostic.goto_prev()<CR>')
  buf_set_keymap('<leader>lr', '<cmd>lua vim.lsp.buf.rename()<CR>')
  buf_set_keymap('<leader>ls', '<cmd>lua vim.lsp.buf.definition()<CR>')
  -- buf_set_keymap('<leader>lD', '<cmd>lua vim.lsp.diagnostic.set_loclist()<CR>')
  -- buf_set_keymap('<space>D', '<cmd>lua vim.lsp.buf.type_definition()<CR>')
  -- buf_set_keymap('<space>wa', '<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>')
  -- buf_set_keymap('<space>wl', '<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>')
  -- buf_set_keymap('<space>wr', '<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>')
  -- buf_set_keymap('gD', '<cmd>lua vim.lsp.buf.declaration()<CR>')
  -- buf_set_keymap('gi', '<cmd>lua vim.lsp.buf.implementation()<CR>')

  -- Currently formatting is handled with 'Neoformat' plugin
  -- -- Set some keybinds conditional on server capabilities
  -- if client.resolved_capabilities.document_formatting then
  --   buf_set_keymap('<leader>lf', '<cmd>lua vim.lsp.buf.formatting()<CR>')
  -- end
  -- if client.resolved_capabilities.document_range_formatting then
  --   buf_set_keymap('<leader>lF', '<cmd>lua vim.lsp.buf.range_formatting()<CR>')
  -- end
end

vim.lsp.handlers['textDocument/publishDiagnostics'] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
  -- Show gutter sings
  signs = {
    -- With highest priority
    priority = 9999,
    -- Only for warnings and errors
    severity_limit = 'Warning',
  },
  -- Show virtual text only for errors
  virtual_text = { severity_limit = 'Error' },
  -- Don't update diagnostics when typing
  update_in_insert = false,
})

-- R (r_language_server)
lspconfig.r_language_server.setup({ on_attach = on_attach_custom })

-- Python (pyright)
lspconfig.pyright.setup({ on_attach = on_attach_custom })

-- Lua (sumneko_lua)
---- Should be built and run manually:
---- https://github.com/sumneko/lua-language-server/wiki/Build-and-Run-(Standalone)
---- Should be cloned into '.config/nvim' as 'lua-language-server' directory.
---- Code structure is taken from https://www.chrisatmachine.com/Neovim/28-neovim-lua-development/
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

  lspconfig.sumneko_lua.setup({
    cmd = { sumneko_binary, '-E', sumneko_root .. '/main.lua' },
    on_attach = function(client, bufnr)
      on_attach_custom(client, bufnr)
      -- Reduce unnecessarily long list of completion triggers for better
      -- `MiniCompletion` experience
      client.server_capabilities.completionProvider.triggerCharacters = { '.', ':' }
    end,
    root_dir = function(fname)
      return lspconfig.util.root_pattern('.git')(fname) or lspconfig.util.path.dirname(fname)
    end,
    settings = {
      Lua = {
        runtime = {
          -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
          version = 'LuaJIT',
          -- Setup your lua path
          path = vim.split(package.path, ';'),
        },
        diagnostics = {
          -- Get the language server to recognize the `vim` global
          globals = { 'vim' },
        },
        workspace = {
          -- Don't analyze code from submodules
          ignoreSubmodules = true,
          -- Don't analyze 'undo cache'
          ignoreDir = { 'undodir' },
          -- Make the server aware of Neovim runtime files
          library = { [vim.fn.expand('$VIMRUNTIME/lua')] = true, [vim.fn.expand('$VIMRUNTIME/lua/vim/lsp')] = true },
        },
      },
    },
  })
end
