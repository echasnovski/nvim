local null_ls = require('null-ls')

-- Set up null-ls server
-- NOTE: currently mappings for formatting with `vim.lsp.buf.formatting()` and
-- `vim.lsp.buf.range_formatting()` are set up for every buffer in
-- 'mappings-leader.vim'. This is done to make 'mini.clue' respect labels.
null_ls.setup({
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
