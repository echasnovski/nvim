-- Adjust semantic token highlighting:
-- - Don't extra highlight keywords, tree-sitter seems to do a better job
vim.api.nvim_set_hl(0, '@lsp.type.keyword.lua', { fg = 'NONE' })
-- - But still highlight special words in documentation (like ---@param).
vim.api.nvim_set_hl(0, '@lsp.mod.documentation.lua', { link = 'Statement' })

return {
  settings = {
    Lua = {
      diagnostics = {
        disable = { 'undefined-global' },
      },
      runtime = { version = 'LuaJIT' },
      semanticTokens = { enable = true },
      workspace = {
        -- Add Neovim's methods for easier code writing
        library = { vim.env.VIMRUNTIME },
        -- Add Neovim's methods for easier code writing
        ignoreDir = { 'dual', 'deps' },
      },
    },
  },
}
