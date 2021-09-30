local has_null_ls, null_ls = pcall(require, 'null-ls')
local has_lspconfig, lspconfig = pcall(require, 'lspconfig')
if not (has_null_ls and has_lspconfig) then
  return
end

-- Configuring null-ls for other sources
null_ls.config({
  sources = {
    -- `black` should be set up as callable from command line (be in '$PATH')
    null_ls.builtins.formatting.black,
    -- `prettier` should be set up as callable from command line (be in '$PATH')
    null_ls.builtins.formatting.prettier,
    -- 'styler' package should be installed in library used by `R` command.
    null_ls.builtins.formatting.styler,
    -- `stylua` should be set up as callable from command line (be in '$PATH')
    null_ls.builtins.formatting.stylua,
  },
})

-- Set up null-ls server
-- NOTE: currently mappings for formatting with `vim.lsp.buf.formatting()` and
-- `vim.lsp.buf.range_formatting()` are set up for every buffer in
-- 'mappings-leader.vim'. This is done to make 'which-key' respect labels.
lspconfig['null-ls'].setup({})
