vim.lsp.config.lua_ls = {
  on_attach = function(client, buf_id)
    -- Reduce unnecessarily long list of completion triggers for better
    -- 'mini.completion' experience
    client.server_capabilities.completionProvider.triggerCharacters = { '.', ':', '#', '(' }

    -- Override global "Go to source" mapping with dedicated buffer-local
    local opts = { buffer = buf_id, desc = 'Lua source definition' }
    vim.keymap.set('n', '<Leader>ls', Config.luals_unique_definition, opts)
  end,
  settings = {
    Lua = {
      runtime = { version = 'LuaJIT', path = vim.split(package.path, ';') },
      diagnostics = {
        -- Don't analyze whole workspace, as it consumes too much CPU and RAM
        workspaceDelay = -1,
      },
      workspace = {
        -- Don't analyze code from submodules
        ignoreSubmodules = true,
        -- Add Neovim's methods for easier code writing
        library = { vim.env.VIMRUNTIME },
      },
      telemetry = { enable = false },
    },
  },
}
