-- All language servers are expected to be installed with 'mason.vnim'
-- Currently used ones:
-- - clangd for C/C++
-- - pyright for Python
-- - r_language_server for R
-- - LuaLS for Lua
-- - typescript-language-server for Typescript and Javascript
-- - gopls for Go

local lspconfig = require('lspconfig')

-- Preconfiguration ===========================================================
local custom_on_attach = function(client, buf_id)
  -- Set up 'mini.completion' LSP part of completion
  vim.bo[buf_id].omnifunc = 'v:lua.MiniCompletion.completefunc_lsp'

  -- Mappings are created globally with `<Leader>l` prefix (for simplicity)
end

-- R (r_language_server) ======================================================
lspconfig.r_language_server.setup({
  on_attach = custom_on_attach,
  -- Debounce "textDocument/didChange" notifications because they are slowly
  -- processed (seen when going through completion list with `<C-N>`)
  flags = { debounce_text_changes = 150 },
})

-- Python (pyright) ===========================================================
lspconfig.pyright.setup({ on_attach = custom_on_attach })

-- Lua (sumneko_lua) ==========================================================
lspconfig.lua_ls.setup({
  on_attach = function(client, bufnr)
    custom_on_attach(client, bufnr)

    -- Reduce unnecessarily long list of completion triggers for better
    -- 'mini.completion' experience
    client.server_capabilities.completionProvider.triggerCharacters = { '.', ':' }

    -- Override global "Go to source" mapping with dedicated buffer-local
    local opts = { buffer = bufnr, desc = 'Lua source definition' }
    vim.keymap.set('n', '<Leader>ls', Config.luals_unique_definition, opts)
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
        -- Get the language server to recognize common globals
        globals = { 'vim', 'describe', 'it', 'before_each', 'after_each' },
        disable = { 'need-check-nil' },
        -- Don't make workspace diagnostic, as it consumes too much CPU and RAM
        workspaceDelay = -1,
      },
      workspace = {
        -- Don't analyze code from submodules
        ignoreSubmodules = true,
      },
      -- Do not send telemetry data containing a randomized but unique identifier
      telemetry = {
        enable = false,
      },
    },
  },
})

-- C/C++ (clangd) =============================================================
lspconfig.clangd.setup({ on_attach = custom_on_attach })

-- Typescript (ts_ls) =========================================================
lspconfig.ts_ls.setup({ on_attach = custom_on_attach })

-- Go (gopls) =================================================================
lspconfig.gopls.setup({ on_attach = custom_on_attach })
